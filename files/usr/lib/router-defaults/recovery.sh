#!/bin/sh
. /usr/lib/router-defaults/core.sh || exit 1

main() {
    log "Setting Linksys automatic recovery to $AUTO_RECOVERY"
    require_target || return 1
    require_command fw_printenv || return 1
    require_command fw_setenv || return 1
    fw_printenv auto_recovery >/dev/null 2>&1 || {
        error 'Cannot read auto_recovery; refusing an unverified boot environment write'
        return 1
    }
    if [ "$(fw_printenv -n auto_recovery)" != "$AUTO_RECOVERY" ]; then
        fw_setenv auto_recovery "$AUTO_RECOVERY" || return 1
    fi
    [ "$(fw_printenv -n auto_recovery)" = "$AUTO_RECOVERY" ] || return 1
    # Keep boot_part and maxpartialboots unchanged. LuCI selects slots manually.
}

main "$@"