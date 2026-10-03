#!/bin/sh
. /usr/lib/router-defaults/core.sh || return 1

set_option() {
    uci_set "$1"
}

commit_mode_configuration() {
    for selected_value in system network wireless dhcp firewall; do
        uci commit $selected_value
    done
}

reload_mode_services() {
    [ "${MX4200_NO_RELOAD:-0}" = 1 ] && return 0
    reload_config 2>/dev/null || true
    /etc/init.d/network restart
    sleep 3
    /etc/init.d/dnsmasq restart
    /etc/init.d/firewall restart
}
