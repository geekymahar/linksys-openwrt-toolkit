#!/bin/sh
. /usr/lib/router-defaults/core.sh || exit 1

main() {
    log 'Preparing VPN forwarding and Tailscale firewall integration'
    # No login, private key, peer, OpenVPN connection or PBR policy is created.
    sysctl -w net.ipv4.ip_forward=1 net.ipv6.conf.all.forwarding=1 >/dev/null || return 1
    if [ -x /etc/init.d/tailscale ]; then
        uci_set "tailscale.settings.fw_mode=$TAILSCALE_FIREWALL_MODE" || return 1
    fi
}

main "$@"