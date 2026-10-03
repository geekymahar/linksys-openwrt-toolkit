#!/bin/sh
. /usr/lib/router-defaults/core.sh || return 1

find_firewall_zone() {
    for section in $(uci -q show firewall | awk -F= '$2=="zone" {sections[++count]=$1} END {for (position=count; position>0; position--) print sections[position]}'); do
        [ "$(uci -q get "$section.name")" = "$1" ] && {
            echo "$section"
            return
        }
    done
    return 1
}

delete_firewall_zone() {
    for section in $(uci -q show firewall | awk -F= '$2=="zone" {sections[++count]=$1} END {for (position=count; position>0; position--) print sections[position]}'); do
        [ "$(uci -q get "$section.name")" = "$1" ] && uci -q delete "$section"
    done
    for config_entry in $(uci -q show firewall | awk -F= '$2=="forwarding" {sections[++count]=$1} END {for (position=count; position>0; position--) print sections[position]}'); do
        [ "$(uci -q get "$config_entry.src")" = "$1" ] || [ "$(uci -q get "$config_entry.dest")" = "$1" ] && uci -q delete "$config_entry"
    done
}

delete_non_vpn_forwardings() {
    for section in $(uci -q show firewall | awk -F= '$2=="forwarding" {sections[++count]=$1} END {for (position=count; position>0; position--) print sections[position]}'); do
        [ "$(uci -q get "$section.src")" = "$1" ] || continue
        case "$(uci -q get "$section.dest")" in vpn | tailscale) ;; *) uci -q delete "$section" ;; esac
    done
}

ensure_lan_zone() {
    zone_section="$(find_firewall_zone lan)"
    [ -n "$zone_section" ] || {
        zone_section=firewall.mx_lan
        set_option "$zone_section=zone"
        set_option ${zone_section}.name=lan
    }
    set_option ${zone_section}.input=ACCEPT
    set_option ${zone_section}.output=ACCEPT
    set_option ${zone_section}.forward=ACCEPT
    uci -q del_list "${zone_section}.network=lan"
    uci add_list "${zone_section}.network=lan"
}

configure_wan_zone() {
    zone_section="$(find_firewall_zone wan)"
    [ -n "$zone_section" ] || return 1
    set_option ${zone_section}.masq=1
    set_option ${zone_section}.mtu_fix=1
}

ensure_forwarding() {
    for config_entry in $(uci show firewall 2>/dev/null | awk -F= '$2=="forwarding"{print $1}'); do
        [ "$(uci -q get "$config_entry.src")" = "$1" ] && [ "$(uci -q get "$config_entry.dest")" = "$2" ] && return
    done
    config_entry="mx_${1}_${2}"
    set_option "firewall.$config_entry=forwarding"
    set_option "firewall.$config_entry.src=$1"
    set_option "firewall.$config_entry.dest=$2"
}

configure_lan_to_wan() {
    delete_non_vpn_forwardings lan
    ensure_forwarding lan wan
}

create_firewall_zone() {
    zone_section="mx_$1"
    set_option "firewall.$zone_section=zone"
    set_option "firewall.$zone_section.name=$1"
    set_option "firewall.$zone_section.input=$2"
    set_option firewall.$zone_section.output=ACCEPT
    set_option "firewall.$zone_section.forward=$3"
}

configure_management_firewall() {
    delete_firewall_zone mgmt
    create_firewall_zone mgmt ACCEPT REJECT
    uci add_list "firewall.$zone_section.network=mgmt"
}

configure_uplink_zone() {
    delete_firewall_zone uplink
    create_firewall_zone uplink REJECT REJECT
    set_option firewall.$zone_section.masq=1
    set_option firewall.$zone_section.mtu_fix=1
    uci add_list "firewall.$zone_section.network=wwanp"
    uci -q get network.wwanb >/dev/null && uci add_list "firewall.$zone_section.network=wwanb"
    for iteration in vpn tailscale; do
        [ -n "$(find_firewall_zone "$iteration")" ] && ensure_forwarding "$iteration" uplink
    done
}

add_management_source_ranges() {
    section=$1
    for interface in $MANAGEMENT_SOURCE_RANGES; do
        uci add_list "firewall.$section.src_ip=$interface"
    done
}

configure_management_rule() {
    section=mx_mgmt_$1
    uci -q delete firewall.$section
    set_option firewall.$section=rule
    set_option firewall.$section.src="$1"
    add_management_source_ranges $section
    set_option firewall.$section.proto=tcp
    set_option "firewall.$section.dest_port=$MANAGEMENT_TCP_PORTS"
    set_option firewall.$section.target=ACCEPT
}

configure_vpn_zone() {
    iteration=$1
    shift
    delete_firewall_zone "$iteration"
    create_firewall_zone "$iteration" ACCEPT ACCEPT
    set_option firewall.$zone_section.masq=1
    set_option firewall.$zone_section.mtu_fix=1
    for device in "$@"; do
        uci add_list "firewall.$zone_section.device=$device"
    done
    ensure_forwarding lan "$iteration"
    ensure_forwarding "$iteration" lan
    ensure_forwarding "$iteration" wan
    [ -n "$(find_firewall_zone uplink)" ] && ensure_forwarding "$iteration" uplink
}
