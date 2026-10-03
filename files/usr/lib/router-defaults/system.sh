#!/bin/sh
. /usr/lib/router-defaults/core.sh || exit 1

main() {
    log 'Configuring hostname and HTTPS redirection'
    uci_set "system.@system[0].hostname=$ROUTER_HOSTNAME" || return 1
    if uci -q get uhttpd.main >/dev/null 2>&1; then
        uci_set uhttpd.main.redirect_https=1 || return 1
    fi
}

main "$@"