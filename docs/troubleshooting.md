# Troubleshooting

## Management SSH Comes First

Do not debug the campus interface until SSH management is stable.

Recommended topology:

- Management interface: static IP such as `192.168.137.2/24`.
- Management host: `192.168.137.1/24`.
- Campus interface: no IP before authentication.

Useful checks:

```bash
ip -br link
ip -br addr
ip route
ethtool enp1s0
ethtool enp2s0
```

## Confirm Interface Roles

The common failure is swapping the two Ethernet cables.

Expected shape:

```text
enp1s0 UP  campus wall port
enp2s0 UP  management link
```

The management route should remain direct:

```bash
ip route get 192.168.137.1
```

Expected:

```text
192.168.137.1 dev enp2s0 src 192.168.137.2
```

## Capture EAPOL

Use tcpdump on the campus interface:

```bash
sudo timeout 30 tcpdump -i enp1s0 -e -nn -vvv 'ether proto 0x888e'
```

Expected successful exchange:

```text
Request Identity
Response Identity
Request Type unknown (7)
Response Type unknown (7)
Success
```

If you only see `Failure`, check:

- The account is correct.
- The password is correct.
- The MAC address matches the account's wired binding.
- The campus interface is the one connected to the wall port.

## DHCP Does Not Get an Offer

If EAP succeeds but DHCP does not:

```bash
sudo journalctl -u sufe-8021x.service -u sufe-campus-dhcp.service -b --no-pager
sudo timeout 30 tcpdump -i enp1s0 -e -nn -vvv 'ether proto 0x888e or port 67 or port 68'
```

The DHCP service waits for `/run/sufe-8021x-authenticated` instead of sleeping for a fixed number of seconds. This state file is written only after `EAP Success`.

If DHCP fails, the route script exits without installing a campus default route. This keeps the management route usable for recovery.

## Periodic EAP Failure

The switch may send periodic identity checks. The responder should only send `EAPOL-Start` before initial success or after a failure. Sending `EAPOL-Start` on a fixed interval after success can create overlapping sessions and cause delayed failures.

## DNS Fails But IP Ping Works

Check systemd-resolved:

```bash
resolvectl status
resolvectl query github.com
```

The DHCP route script sets DNS on the campus interface and disables default-route DNS on the management interface when configured.

For 1Panel app downloads in mainland China, the expected app-store asset host is usually:

```text
apps-assets.fit2cloud.com
```

If 1Panel still tries `apps.1panel.pro`, switch 1Panel's app store region to China mainland and sync the app store again. If it already uses `apps-assets.fit2cloud.com` but fails with `127.0.0.53` DNS timeouts, debug DNS and routing first; changing proxy mode is usually only a symptom workaround.

## BBR Is Usually Not the Cause

BBR/BBR3 affects TCP congestion control after IP connectivity already exists. It does not decide whether EAPOL, DHCP, ARP, or DNS packets are allowed through the campus port.

Quick check:

```bash
sysctl net.ipv4.tcp_congestion_control net.ipv4.tcp_available_congestion_control net.core.default_qdisc
```

If DHCP has no Offer, or 802.1X keeps failing, investigate EAPOL/DHCP/MAC binding before blaming BBR.

## Campus Ingress Should Stay Closed

After the campus interface gets an IP, verify from another campus network host that sensitive ports are not reachable on the campus IP. On the server side, a typical UFW shape is:

```bash
sudo ufw allow in on enp1s0 proto udp from any port 67 to any port 68 comment 'allow campus DHCP replies'
sudo ufw deny in on enp1s0 comment 'block campus NIC ingress'
sudo ufw deny routed in on enp1s0 comment 'block campus NIC routed/docker ingress'
sudo ufw allow in on enp2s0 from 192.168.137.0/24 comment 'trusted management'
sudo ufw allow in on tailscale0 comment 'trusted Tailscale management'
```

Keep SSH, 1Panel, Jellyfin, Immich, Mihomo dashboards, and similar services behind a management network or Tailscale unless you intentionally publish them.

## Manual Recovery

## Reboot Verification

After installing the services:

```bash
sudo reboot
```

After SSH returns:

```bash
systemctl is-active sufe-8021x.service sufe-campus-dhcp.service
ip -br addr show
ip route
ping -c 2 223.5.5.5
resolvectl query github.com
```

If the rebooted server has no outbound network but SSH over the management link still works:

```bash
sudo systemctl restart sufe-8021x.service
sudo systemctl restart sufe-campus-dhcp.service
journalctl -b -u sufe-8021x.service -u sufe-campus-dhcp.service --no-pager -n 120
```

Expected network shape:

```text
enp1s0 10.x.x.x/xx
enp2s0 192.168.137.2/24
default via 10.64.0.1 dev enp1s0 metric 50
default via 192.168.137.1 dev enp2s0 metric 500
```
