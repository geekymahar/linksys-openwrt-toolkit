#!/bin/sh
. /usr/lib/router-defaults/core.sh || exit 1
. /usr/lib/router-defaults/network-functions.sh || exit 1

main() {
    log 'Configuring router LAN, WAN and Ethernet bridge'
    bridge_section=$(find_bridge_section br-lan) || return 1
    uci_set "$bridge_section.stp=1" || return 1
    uci -q delete "$bridge_section.ports" || true
    for port in $LAN_PORTS; do
        uci_add_list "$bridge_section.ports=$port" || return 1
    done
    uci_set network.lan=interface || return 1
    uci_set network.lan.device=br-lan || return 1
    uci_set network.lan.proto=static || return 1
    uci_set "network.lan.ipaddr=$LAN_IP" || return 1
    uci_set "network.lan.netmask=$LAN_NETMASK" || return 1
    uci_set network.lan.delegate=1 || return 1
    for option in metric gateway dns; do uci -q delete "network.lan.$option" || true; done
    for interface in br_mgmt mgmt wwan wwanp wwanb wdsp wdsb usbwan; do
        uci -q delete "network.$interface" || true
    done
    uci_set network.wan=interface || return 1
    uci_set "network.wan.device=$WAN_DEVICE" || return 1
    uci_set network.wan.proto=dhcp || return 1
    uci_set "network.wan.metric=$METRIC_WAN_DEFAULT" || return 1
    uci -q delete network.wan6.disabled || true
}

main "$@"