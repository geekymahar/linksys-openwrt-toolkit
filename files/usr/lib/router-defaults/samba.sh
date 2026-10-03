#!/bin/sh
. /usr/lib/router-defaults/core.sh || exit 1

main() {
    log 'Preparing the existing Samba-only account manager'
    for command in useradd userdel smbpasswd jsonfilter; do require_command "$command" || return 1; done
    mkdir -p "$SAMBA_USER_STORE" || return 1
    chmod 700 "$SAMBA_USER_STORE" || return 1
    # Accounts and shares are user-managed; first boot creates neither.
}

main "$@"