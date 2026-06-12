#!/bin/sh
set -eu

. /etc/sufe-8021x/sufe-8021x.env

ip link set dev "$SUFE_IFACE" down
ip link set dev "$SUFE_IFACE" address "$SUFE_MAC"
ip addr flush dev "$SUFE_IFACE" || true
ip link set dev "$SUFE_IFACE" up

# Give the switch a moment after link/MAC change.
sleep 3
