#!/bin/sh
. /usr/lib/router-defaults/core.sh || exit 1

main() {
    log 'Enabling baked-in services without interrupting first-boot networking'
    for service in mxb mxd mxauto mxroutehealth tailscale openvpn; do
        service_enable "$service" || return 1
    done
    if [ "$LED_AUTO_INSTALL" = 1 ]; then
        service_enable mxl || return 1
    else
        /etc/init.d/mxl disable || return 1
    fi
    # OpenWrt starts enabled services after uci-defaults has completed. Runtime
    # profile changes retain their explicit network/firewall reload operations.
}

main "$@"