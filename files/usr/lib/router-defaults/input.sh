#!/bin/sh
. /usr/lib/router-defaults/core.sh || return 1

valid_wifi_password() {
    [ "${#1}" -ge 8 ] && [ "${#1}" -le 63 ]
}

read_secret() {
    printf %s "$1"
    if IFS= read -r -s SECRET 2>/dev/null; then
        echo
    else
        IFS= read -r SECRET
    fi
}
