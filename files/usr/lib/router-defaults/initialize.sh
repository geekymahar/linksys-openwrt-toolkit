#!/bin/sh
. /usr/lib/router-defaults/core.sh || exit 1

backup_configuration() {
    mkdir -p "$backup" || return 1
    for package in system network dhcp wireless firewall uhttpd tailscale; do
        if [ -f "/etc/config/$package" ]; then
            cp -p "/etc/config/$package" "$backup/$package" || return 1
        fi
    done
}

cleanup() {
    result=$?
    trap - EXIT HUP INT TERM
    if [ "$completed" != 1 ] && [ -d "$backup" ]; then
        warn 'Initialization failed; restoring UCI files for a later boot retry'
        for package in system network dhcp wireless firewall uhttpd tailscale; do
            uci -q revert "$package" || true
            [ ! -f "$backup/$package" ] || cp -p "$backup/$package" "/etc/config/$package"
        done
        rm -f /etc/router-defaults/applied-version
        if [ "$fresh_configuration" = 1 ]; then
            rm -f /etc/mx4200/mode /etc/mx4200/provisioned
        fi
    fi
    rm -rf "$lock"
    exit "$result"
}

main() {
    umask 077
    require_target || return 1
    lock=/tmp/router-defaults-initialize.lock
    mkdir "$lock" 2>/dev/null || { error 'Another initialization is running'; return 1; }
    backup=$lock/config
    completed=0
    fresh_configuration=0
    trap cleanup EXIT
    trap 'exit 1' HUP INT TERM
    log 'Beginning baked-in router configuration'
    /usr/lib/router-defaults/preflight.sh || return 1
    /usr/lib/router-defaults/migration.sh || return 1
    # Preserved settings must not be replaced with router-mode defaults.
    if [ -e /etc/mx4200/provisioned ] || [ -e /etc/mx4200/mode ]; then
        log 'Existing configuration retained; applying non-destructive migration only'
        /usr/lib/router-defaults/recovery.sh || return 1
        /usr/lib/router-defaults/services.sh || return 1
    else
        backup_configuration || return 1
        fresh_configuration=1
        for module in system network dhcp wireless firewall vpn samba recovery services; do
            log "Applying $module"
            "/usr/lib/router-defaults/$module.sh" || return 1
        done
        for package in system network dhcp wireless firewall uhttpd tailscale; do
            if [ -f "/etc/config/$package" ]; then uci -q commit "$package" || return 1; fi
        done
        mkdir -p "$PROFILE_ROOT/router" "$PROFILE_ROOT/router-baseline" || return 1
        for package in $PROFILE_FILES; do
            cp "/etc/config/$package" "$PROFILE_ROOT/router/$package" || return 1
            cp "/etc/config/$package" "$PROFILE_ROOT/router-baseline/$package" || return 1
        done
        chmod 700 /etc/mx4200 "$PROFILE_ROOT" "$PROFILE_ROOT/router" "$PROFILE_ROOT/router-baseline" || return 1
        chmod 600 "$PROFILE_ROOT/router/"* "$PROFILE_ROOT/router-baseline/"* || return 1
        date +%s > "$PROFILE_ROOT/router/saved_at" || return 1
        cp "$PROFILE_ROOT/router/saved_at" "$PROFILE_ROOT/router-baseline/saved_at" || return 1
        printf 'router\n' > /etc/mx4200/mode || return 1
        touch /etc/mx4200/provisioned || return 1
    fi
    printf '1\n' > /etc/router-defaults/applied-version || return 1
    completed=1
    log 'Baked-in router configuration completed'
}

main "$@"