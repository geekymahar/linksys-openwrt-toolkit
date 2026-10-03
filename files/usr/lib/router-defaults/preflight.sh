#!/bin/sh
. /usr/lib/router-defaults/core.sh || exit 1

valid_ipv4() {
    printf '%s\n' "$1" | awk -F. 'NF != 4 {exit 1} {for (field=1;field<=4;field++) if ($field !~ /^[0-9]+$/ || $field>255) exit 1}'
}

main() {
    log 'Checking hardware, configuration and package dependencies'
    require_target || return 1
    for command in uci ubus ip iw iwinfo jsonfilter logger cp chmod mkdir fw_printenv fw_setenv; do
        require_command "$command" || return 1
    done
    [ -n "$ROUTER_HOSTNAME" ] && [ -n "$COUNTRY" ] || return 1
    for address in "$LAN_IP" "$LAN_NETMASK" "$MGMT_IP" $MGMT_FALLBACK_IPS; do
        valid_ipv4 "$address" || { error "Invalid IPv4 value: $address"; return 1; }
    done
    for number in "$DHCP_START" "$DHCP_LIMIT" "$MGMT_DHCP_LIMIT" "$CHANNEL_5G_HIGH"; do
        case "$number" in ''|*[!0-9]*) error 'Expected numeric configuration value'; return 1;; esac
    done
    for radio in "$RADIO_24" "$RADIO_5G" "$RADIO_5G_MAX"; do
        [ "$(uci -q get "wireless.$radio")" = wifi-device ] || {
            error "Missing generated radio: $radio; refusing partial wireless configuration"
            return 1
        }
    done
    [ "$RADIO_24:$RADIO_5G:$RADIO_5G_MAX" = 'radio1:radio0:radio2' ] || {
        error 'Radio mapping does not match MX4200 V2'
        return 1
    }
    for package in system network wireless dhcp firewall; do
        [ -s "/etc/config/$package" ] || { error "Missing UCI package: $package"; return 1; }
    done
    for service in network dnsmasq firewall mxauto mxroutehealth mxb mxd mxl; do
        [ -x "/etc/init.d/$service" ] || { error "Missing service: $service"; return 1; }
    done
    case "$AUTO_RECOVERY" in yes|no) ;; *) error 'AUTO_RECOVERY must be yes or no'; return 1;; esac
}

main "$@"