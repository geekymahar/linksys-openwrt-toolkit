#!/bin/sh

if [ "${ROUTER_DEFAULTS_CORE_LOADED:-0}" = 1 ]; then
    return 0
fi
ROUTER_DEFAULTS_CONFIG=${ROUTER_DEFAULTS_CONFIG:-/etc/router-defaults/config}
if [ ! -r "$ROUTER_DEFAULTS_CONFIG" ]; then
    printf 'Cannot read %s\n' "$ROUTER_DEFAULTS_CONFIG" >&2
    return 1
fi
. "$ROUTER_DEFAULTS_CONFIG" || return 1
ROUTER_DEFAULTS_CORE_LOADED=1

log() {
    logger -t router-defaults -- "$*"
}

warn() {
    log "WARNING: $*"
    printf 'WARNING: %s\n' "$*" >&2
}

error() {
    log "ERROR: $*"
    printf 'ERROR: %s\n' "$*" >&2
    return 1
}

require_command() {
    command -v "$1" >/dev/null 2>&1 || error "Required command missing: $1"
}

require_target() {
    [ "$(cat /tmp/sysinfo/board_name 2>/dev/null)" = 'linksys,mx4200v2' ] ||
        error 'Only Linksys MX4200 V2 is supported'
}

uci_set() {
    uci -q set "$1" || error "Cannot set UCI option: ${1%%=*}"
}

uci_add_list() {
    uci -q del_list "$1" 2>/dev/null || true
    uci -q add_list "$1" || error "Cannot add UCI list: ${1%%=*}"
}

service_enable() {
    [ -x "/etc/init.d/$1" ] || return 0
    "/etc/init.d/$1" enable || error "Cannot enable service: $1"
}

service_restart() {
    [ -x "/etc/init.d/$1" ] || return 0
    "/etc/init.d/$1" restart || error "Cannot restart service: $1"
}

root_password_is_set() {
    awk -F: '$1 == "root" && $2 != "" && $2 !~ /^[!*]/ { found = 1 } END { exit !found }' /etc/shadow
}

require_root_password() {
    [ "$(id -u)" = 0 ] || return 0
    root_password_is_set && return 0
    printf '\nA root password is required before using this router.\n'
    passwd || return 1
    root_password_is_set || error 'Root password is still unset'
    log 'Root password set during interactive login'
}

# Shared by mode selection and LED diagnostics: prefer the lowest-metric
# non-VPN default route without making the status depend on a VPN tunnel.
non_vpn_default_device() {
    ip -4 route show default 2>/dev/null | awk '
        $1 == "default" {
            device = ""
            metric = 0
            for (field = 1; field <= NF; field++) {
                if ($field == "dev") device = $(field + 1)
                if ($field == "metric") metric = $(field + 1) + 0
            }
            if (device == "" || device ~ /^(tun|tap|wg|tailscale)/) next
            if (!found || metric < best) {
                found = 1
                best = metric
                selected = device
            }
        }
        END { print selected }
    '
}