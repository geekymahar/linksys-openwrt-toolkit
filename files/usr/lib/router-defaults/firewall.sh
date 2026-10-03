#!/bin/sh
. /usr/lib/router-defaults/core.sh || exit 1

delete_zone() {
    for section in $(uci -q show firewall | awk -F= '$2=="zone" {sections[++count]=$1} END {for (position=count; position>0; position--) print sections[position]}'); do
        [ "$(uci -q get "$section.name")" != "$1" ] || uci -q delete "$section" || return 1
    done
    for section in $(uci -q show firewall | awk -F= '$2=="forwarding" {sections[++count]=$1} END {for (position=count; position>0; position--) print sections[position]}'); do
        if [ "$(uci -q get "$section.src")" = "$1" ] || [ "$(uci -q get "$section.dest")" = "$1" ]; then
            uci -q delete "$section" || return 1
        fi
    done
}

configure_zone() {
    uci_set "firewall.$1=zone" || return 1
    uci_set "firewall.$1.name=$2" || return 1
    uci_set "firewall.$1.input=$3" || return 1
    uci_set "firewall.$1.output=ACCEPT" || return 1
    uci_set "firewall.$1.forward=$4"
}

configure_forwarding() {
    uci_set "firewall.$1=forwarding" || return 1
    uci_set "firewall.$1.src=$2" || return 1
    uci_set "firewall.$1.dest=$3"
}

main() {
    log 'Configuring deterministic router, management and VPN firewall rules'
    for zone in mgmt uplink lan wan vpn tailscale; do delete_zone "$zone" || return 1; done
    configure_zone mx_lan lan ACCEPT ACCEPT || return 1
    uci_set firewall.mx_lan.network=lan || return 1
    configure_zone mx_wan wan REJECT REJECT || return 1
    uci_set 'firewall.mx_wan.network=wan wan6' || return 1
    uci_set firewall.mx_wan.masq=1 || return 1
    uci_set firewall.mx_wan.mtu_fix=1 || return 1
    configure_forwarding mx_lan_wan lan wan || return 1
    uci -q delete firewall.allow_luci_from_wan || true
    uci -q delete firewall.mx_mgmt_wan || true
    uci_set firewall.mx_mgmt_wan=rule || return 1
    uci_set firewall.mx_mgmt_wan.src=wan || return 1
    for range in $MANAGEMENT_SOURCE_RANGES; do
        uci_add_list "firewall.mx_mgmt_wan.src_ip=$range" || return 1
    done
    uci_set firewall.mx_mgmt_wan.proto=tcp || return 1
    uci_set "firewall.mx_mgmt_wan.dest_port=$MANAGEMENT_TCP_PORTS" || return 1
    uci_set firewall.mx_mgmt_wan.target=ACCEPT || return 1
    for zone in vpn tailscale; do
        configure_zone "mx_$zone" "$zone" ACCEPT ACCEPT || return 1
        uci_set "firewall.mx_$zone.masq=1" || return 1
        uci_set "firewall.mx_$zone.mtu_fix=1" || return 1
        configure_forwarding "mx_lan_$zone" lan "$zone" || return 1
        configure_forwarding "mx_${zone}_lan" "$zone" lan || return 1
        configure_forwarding "mx_${zone}_wan" "$zone" wan || return 1
    done
    uci_add_list 'firewall.mx_vpn.device=tun+' || return 1
    uci_add_list 'firewall.mx_vpn.device=wg+' || return 1
    uci_add_list 'firewall.mx_tailscale.device=tailscale0' || return 1
    uci -q delete firewall.mx_vpn_in || true
    uci_set firewall.mx_vpn_in=rule || return 1
    uci_set firewall.mx_vpn_in.src=wan || return 1
    uci_set 'firewall.mx_vpn_in.proto=tcp udp' || return 1
    uci_set "firewall.mx_vpn_in.dest_port=$VPN_INBOUND_PORTS" || return 1
    uci_set firewall.mx_vpn_in.target=ACCEPT
}

main "$@"