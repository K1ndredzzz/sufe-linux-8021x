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

The service intentionally waits before DHCP so the switch has time to authorize the port.

## Periodic EAP Failure

The switch may send periodic identity checks. The responder should only send `EAPOL-Start` before initial success or after a failure. Sending `EAPOL-Start` on a fixed interval after success can create overlapping sessions and cause delayed failures.

## DNS Fails But IP Ping Works

Check systemd-resolved:

```bash
resolvectl status
resolvectl query github.com
```

The DHCP route script sets DNS on the campus interface and disables default-route DNS on the management interface when configured.

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
