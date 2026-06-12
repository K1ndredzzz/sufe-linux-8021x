#!/usr/bin/env python3
import argparse
import os
import socket
import struct
import sys
import time


ETH_P_EAPOL = 0x888E
EAPOL_VERSION = 1
EAPOL_PACKET = 0
EAPOL_START = 1
PAE_GROUP = bytes.fromhex("0180c2000003")


def parse_env_file(path):
    values = {}
    if not path:
        return values
    with open(path, "r", encoding="utf-8") as handle:
        for raw_line in handle:
            line = raw_line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            key, value = line.split("=", 1)
            values[key.strip()] = value.strip().strip('"').strip("'")
    return values


def mac_bytes_from_sysfs(iface):
    with open(f"/sys/class/net/{iface}/address", "r", encoding="ascii") as handle:
        return bytes.fromhex(handle.read().strip().replace(":", ""))


def format_mac(raw):
    return ":".join(f"{byte:02x}" for byte in raw)


def send_eapol_start(sock, src_mac):
    frame = PAE_GROUP + src_mac + struct.pack("!HBBH", ETH_P_EAPOL, EAPOL_VERSION, EAPOL_START, 0)
    sock.send(frame)


def send_eap_response(sock, src_mac, dst_mac, eap_id, eap_type, payload):
    eap_len = 5 + len(payload)
    eap = struct.pack("!BBHB", 2, eap_id, eap_len, eap_type) + payload
    frame = dst_mac + src_mac + struct.pack("!HBBH", ETH_P_EAPOL, EAPOL_VERSION, EAPOL_PACKET, len(eap)) + eap
    sock.send(frame)


def describe_request(eap_type):
    if eap_type == 1:
        return "Identity"
    if eap_type == 7:
        return "Type7"
    return f"Type{eap_type}"


def main():
    parser = argparse.ArgumentParser(description="Minimal SUFE/H3C iNode-style 802.1X responder")
    parser.add_argument("--env-file", default=None)
    parser.add_argument("--iface", default=None)
    parser.add_argument("--username", default=None)
    parser.add_argument("--password", default=None)
    parser.add_argument("--once", action="store_true", help="exit after first EAP Success")
    parser.add_argument("--start-interval", type=float, default=5.0)
    parser.add_argument("--listen-timeout", type=float, default=1.0)
    args = parser.parse_args()

    cfg = parse_env_file(args.env_file)
    iface = args.iface or cfg.get("SUFE_IFACE") or os.environ.get("SUFE_IFACE")
    username = args.username or cfg.get("SUFE_USERNAME") or os.environ.get("SUFE_USERNAME")
    password = args.password or cfg.get("SUFE_PASSWORD") or os.environ.get("SUFE_PASSWORD")

    if not iface or not username or not password:
        print("missing iface, username, or password", file=sys.stderr)
        return 2

    username_bytes = username.encode("ascii")
    password_bytes = password.encode("ascii")
    if len(password_bytes) > 255:
        print("password too long for Type 7 length byte", file=sys.stderr)
        return 2

    src_mac = mac_bytes_from_sysfs(iface)
    sock = socket.socket(socket.AF_PACKET, socket.SOCK_RAW, socket.htons(ETH_P_EAPOL))
    sock.bind((iface, 0))
    sock.settimeout(args.listen_timeout)

    print(f"iface={iface} mac={format_mac(src_mac)} identity_len={len(username_bytes)} password_len={len(password_bytes)}")
    send_eapol_start(sock, src_mac)
    last_start = time.monotonic()
    success_count = 0

    while True:
        now = time.monotonic()
        if success_count == 0 and args.start_interval > 0 and now - last_start >= args.start_interval:
            send_eapol_start(sock, src_mac)
            last_start = now
            print("sent EAPOL-Start")

        try:
            packet = sock.recv(2048)
        except socket.timeout:
            continue

        if len(packet) < 23:
            continue
        peer_mac = packet[6:12]
        ethertype = struct.unpack("!H", packet[12:14])[0]
        if ethertype != ETH_P_EAPOL:
            continue

        _version, packet_type, eapol_len = struct.unpack("!BBH", packet[14:18])
        if packet_type != EAPOL_PACKET or eapol_len < 4:
            continue
        eap = packet[18:18 + eapol_len]
        if len(eap) < 4:
            continue
        eap_code, eap_id, _eap_len = struct.unpack("!BBH", eap[:4])

        if eap_code == 1 and len(eap) >= 5:
            eap_type = eap[4]
            if eap_type == 1:
                send_eap_response(sock, src_mac, peer_mac, eap_id, 1, username_bytes)
                print(f"request={describe_request(eap_type)} id={eap_id} -> response identity_len={len(username_bytes)}")
            elif eap_type == 7:
                payload = bytes([len(password_bytes)]) + password_bytes + username_bytes
                send_eap_response(sock, src_mac, peer_mac, eap_id, 7, payload)
                print(f"request={describe_request(eap_type)} id={eap_id} -> response payload_len={len(payload)}")
            else:
                print(f"request={describe_request(eap_type)} id={eap_id} ignored")
        elif eap_code == 3:
            success_count += 1
            print(f"EAP Success id={eap_id} count={success_count}")
            if args.once:
                return 0
        elif eap_code == 4:
            print(f"EAP Failure id={eap_id}", file=sys.stderr)
            if args.once:
                return 1
            success_count = 0
            send_eapol_start(sock, src_mac)
            last_start = time.monotonic()


if __name__ == "__main__":
    raise SystemExit(main())
