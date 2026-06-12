#!/bin/sh
set -eu

. /etc/sufe-8021x/sufe-8021x.env

AUTH_STATE=${SUFE_AUTH_STATE:-/run/sufe-8021x-authenticated}
MGMT_IFACE=${SUFE_MGMT_IFACE:-}
MGMT_GATEWAY=${SUFE_MGMT_GATEWAY:-}
CAMPUS_METRIC=${SUFE_CAMPUS_METRIC:-50}
MGMT_METRIC=${SUFE_MGMT_METRIC:-500}
SUFE_GATEWAY=${SUFE_GATEWAY:-10.64.0.1}
SUFE_DNS1=${SUFE_DNS1:-211.136.150.66}
SUFE_DNS2=${SUFE_DNS2:-211.136.112.50}
LEASE_FILE=${SUFE_LEASE_FILE:-/var/lib/dhcp/dhclient.$SUFE_IFACE.leases}
PID_FILE=${SUFE_PID_FILE:-/run/dhclient-$SUFE_IFACE.pid}
WAIT_SECONDS=${SUFE_AUTH_WAIT_SECONDS:-75}

echo "waiting for 802.1X state file $AUTH_STATE"
i=0
while [ ! -s "$AUTH_STATE" ]; do
  if [ "$i" -ge "$WAIT_SECONDS" ]; then
    echo "802.1X did not report success within ${WAIT_SECONDS}s" >&2
    exit 1
  fi
  i=$((i + 1))
  sleep 1
done

echo "802.1X authenticated; requesting DHCP on $SUFE_IFACE"
if [ -s "$PID_FILE" ]; then
  old_pid=$(cat "$PID_FILE" 2>/dev/null || true)
  if [ -n "$old_pid" ]; then
    kill "$old_pid" 2>/dev/null || true
  fi
fi
rm -f "$PID_FILE"
mkdir -p "$(dirname "$LEASE_FILE")"
: > "$LEASE_FILE"

ip addr flush dev "$SUFE_IFACE" scope global || true
while ip route del default dev "$SUFE_IFACE" 2>/dev/null; do :; done
ip route flush dev "$SUFE_IFACE" proto dhcp 2>/dev/null || true

if ! dhclient -4 -v -1 -pf "$PID_FILE" -lf "$LEASE_FILE" "$SUFE_IFACE"; then
  echo "dhclient failed on $SUFE_IFACE; keeping management route untouched" >&2
  exit 1
fi

if ! ip -4 -o addr show dev "$SUFE_IFACE" scope global | grep -q ' inet '; then
  echo "dhclient exited without a global IPv4 address on $SUFE_IFACE" >&2
  exit 1
fi

addr=$(ip -4 -o addr show dev "$SUFE_IFACE" scope global | awk '{print $4}' | head -n 1)
echo "campus address: $addr"

# dhclient may add an unmetric default route; normalize routes explicitly.
while ip route del default via "$SUFE_GATEWAY" dev "$SUFE_IFACE" 2>/dev/null; do :; done
ip route replace default via "$SUFE_GATEWAY" dev "$SUFE_IFACE" metric "$CAMPUS_METRIC"

if [ -n "$MGMT_IFACE" ] && [ -n "$MGMT_GATEWAY" ]; then
  while ip route del default via "$MGMT_GATEWAY" dev "$MGMT_IFACE" 2>/dev/null; do :; done
  ip route replace default via "$MGMT_GATEWAY" dev "$MGMT_IFACE" metric "$MGMT_METRIC" || true
fi

resolvectl dns "$SUFE_IFACE" "$SUFE_DNS1" "$SUFE_DNS2" || true
resolvectl default-route "$SUFE_IFACE" yes || true

if [ -n "$MGMT_IFACE" ]; then
  resolvectl default-route "$MGMT_IFACE" no || true
fi
