# Packet Analysis Notes

This document summarizes the packet-level observations that motivated the implementation.

## Protocol Shape

The wired network uses 802.1X over EAPOL.

The useful successful exchange looked like this:

```text
EAP Request Identity
EAP Response Identity
EAP Request Type 7
EAP Response Type 7
EAP Success
DHCP Discover
DHCP Offer
DHCP Request
DHCP ACK
```

## Type 7 Payload

The Type 7 response observed from the Windows iNode client had this minimal shape:

```text
1 byte password length
password bytes
identity bytes
```

For example, if the password length is 10 and the identity is 16 bytes, the EAP Type 7 payload length is:

```text
1 + 10 + 16 = 27 bytes
```

The EAP length includes the EAP header and type byte:

```text
4 byte EAP header + 1 byte EAP type + 27 byte Type 7 payload = 32 bytes
```

## MAC Binding

Failure at EAP stage can be caused by MAC binding, even if the EAP payload format is otherwise correct.

Useful signal:

- Same Type 7 structure.
- Immediate `EAP Failure`.
- Windows iNode logs or portal page indicate MAC mismatch or changed MAC.

## Keepalive Behavior

After initial success, the switch periodically sends identity requests. A stable client should respond to those requests. It should not keep sending unsolicited `EAPOL-Start` after success, because that may create overlapping authentication sessions and delayed `EAP Failure`.

The script therefore:

- Sends `EAPOL-Start` at startup.
- Retries `EAPOL-Start` while unauthenticated.
- Stops unsolicited starts after success.
- Resets to unauthenticated state if an `EAP Failure` arrives.
