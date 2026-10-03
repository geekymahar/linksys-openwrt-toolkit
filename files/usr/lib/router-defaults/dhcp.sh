#!/bin/sh
. /usr/lib/router-defaults/core.sh || exit 1

main() {
    log 'Configuring the router LAN DHCP pool'
    uci_set dhcp.lan=dhcp || return 1
    uci_set dhcp.lan.interface=lan || return 1
    uci_set "dhcp.lan.start=$DHCP_START" || return 1
    uci_set "dhcp.lan.limit=$DHCP_LIMIT" || return 1
    uci_set "dhcp.lan.leasetime=$DHCP_LEASETIME" || return 1
    uci_set dhcp.lan.ignore=0 || return 1
    uci -q delete dhcp.mgmt || true
}

main "$@"