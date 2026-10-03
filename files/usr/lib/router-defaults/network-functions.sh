#!/bin/sh
. /usr/lib/router-defaults/core.sh || return 1

find_bridge_section() {
    for section in $(uci show network 2>/dev/null | awk -F= '$2=="device"{print $1}'); do
        [ "$(uci -q get "$section.name")" = "$1" ] && {
            echo "$section"
            return
        }
    done
    return 1
}

bridge_wan_port() {
    bridge_section="$(find_bridge_section br-lan)"
    [ -n "$bridge_section" ] || return 1
    uci -q del_list "${bridge_section}.ports=wan"
    uci add_list "${bridge_section}.ports=wan" || return 1
    uci -q delete network.wan.device
    set_option network.wan.proto=none || return 1
    if uci -q get network.wan6 >/dev/null 2>&1; then
        set_option network.wan6.disabled=1 || return 1
    fi
}

configure_repeater_wan() {
    bridge_section="$(find_bridge_section br-lan)"
    [ -n "$bridge_section" ] || return 1
    uci -q delete "${bridge_section}.ports" || return 1
    for lan_port in $LAN_PORTS; do
        uci add_list "${bridge_section}.ports=$lan_port" || return 1
    done
    set_option "network.wan.device=$WAN_DEVICE" || return 1
    set_option network.wan.proto=dhcp || return 1
    uci -q delete network.wan6.disabled || true

    case "$(uci -q get network.wan.mx_priority)" in
        wan)
            set_option "network.wan.metric=$METRIC_WAN_PREFERRED"
            ;;
        *)
            set_option network.wan.mx_priority=wifi || return 1
            set_option "network.wan.metric=$METRIC_WAN_BACKUP"
            ;;
    esac
}

configure_bridge_dhcp_client() {
    set_option network.lan=interface
    set_option network.lan.device=br-lan
    set_option network.lan.proto=dhcp
    set_option network.lan.delegate=0
    for option in ipaddr netmask gateway dns ip6assign ip6hint ip6class metric; do
        uci -q delete "network.lan.$option"
    done
    set_option dhcp.lan=dhcp
    set_option dhcp.lan.interface=lan
    set_option dhcp.lan.ignore=1
    set_option dhcp.lan.ra=disabled
    set_option dhcp.lan.dhcpv6=disabled
    set_option dhcp.lan.ndp=disabled
}

configure_static_lan() {
    set_option network.lan=interface
    set_option network.lan.device=br-lan
    set_option network.lan.proto=static
    set_option network.lan.ipaddr="$1"
    set_option network.lan.netmask="$2"
    set_option network.lan.delegate=1
    for option in metric gateway dns; do
        uci -q delete "network.lan.$option"
    done
    set_option dhcp.lan=dhcp
    set_option dhcp.lan.interface=lan
    set_option dhcp.lan.start="$3"
    set_option dhcp.lan.limit="$4"
    set_option dhcp.lan.leasetime="$5"
    set_option dhcp.lan.ignore=0
}

configure_management_network() {
    uci -q delete network.br_mgmt
    set_option network.br_mgmt=device
    set_option network.br_mgmt.name=br-mgmt
    set_option network.br_mgmt.type=bridge
    set_option network.br_mgmt.bridge_empty=1
    [ "$4" = lan1 ] && uci add_list network.br_mgmt.ports=lan1
    uci -q delete network.mgmt
    set_option network.mgmt=interface
    set_option network.mgmt.device=br-mgmt
    set_option network.mgmt.proto=static
    set_option network.mgmt.ipaddr="$1"
    set_option network.mgmt.netmask="$2"
    set_option network.mgmt.delegate=0
    uci -q delete dhcp.mgmt
    set_option dhcp.mgmt=dhcp
    set_option dhcp.mgmt.interface=mgmt
    set_option dhcp.mgmt.start="$3"
    set_option "dhcp.mgmt.limit=$MGMT_DHCP_LIMIT"
    set_option dhcp.mgmt.leasetime="${5:-$DHCP_LEASETIME}"
    set_option dhcp.mgmt.ignore=0
    set_option dhcp.mgmt.ra=disabled
    set_option dhcp.mgmt.dhcpv6=disabled
    set_option dhcp.mgmt.ndp=disabled
}
