#!/bin/sh
set -eu

. /etc/sufe-8021x/sufe-8021x.env

rm -f "/run/dhclient-$SUFE_IFACE.pid"
dhclient -4 -v -1 -pf "/run/dhclient-$SUFE_IFACE.pid" -lf "/var/lib/dhcp/dhclient.$SUFE_IFACE.leases" "$SUFE_IFACE"

# dhclient may add an unmetric default route; normalize routes explicitly.
while ip route del default via "$SUFE_GATEWAY" dev "$SUFE_IFACE" 2>/dev/null; do :; done
ip route replace default via "$SUFE_GATEWAY" dev "$SUFE_IFACE" metric "$SUFE_CAMPUS_METRIC"

if [ -n "${SUFE_MGMT_IFACE:-}" ] && [ -n "${SUFE_MGMT_GATEWAY:-}" ]; then
  while ip route del default via "$SUFE_MGMT_GATEWAY" dev "$SUFE_MGMT_IFACE" 2>/dev/null; do :; done
  ip route replace default via "$SUFE_MGMT_GATEWAY" dev "$SUFE_MGMT_IFACE" metric "$SUFE_MGMT_METRIC" || true
fi

resolvectl dns "$SUFE_IFACE" "$SUFE_DNS1" "$SUFE_DNS2" || true
resolvectl default-route "$SUFE_IFACE" yes || true

if [ -n "${SUFE_MGMT_IFACE:-}" ]; then
  resolvectl default-route "$SUFE_MGMT_IFACE" no || true
fi
