#!/bin/sh
. /usr/lib/router-defaults/core.sh || exit 1

merge_legacy_defaults() {
    [ -f "$1" ] || return 0
    # Legacy installers emitted trusted shell assignments. Replace only keys
    # that already exist in the new schema; do not execute the legacy file.
    awk -F= '
        NR==FNR {if ($0 ~ /^[A-Z][A-Z0-9_]*=/) overrides[$1]=$0; next}
        /^[A-Z][A-Z0-9_]*=/ && $1 in overrides {print overrides[$1]; next}
        {print}
    ' "$1" /etc/router-defaults/config > /etc/router-defaults/config.new || return 1
    chmod 600 /etc/router-defaults/config.new || return 1
    mv /etc/router-defaults/config.new /etc/router-defaults/config || return 1
}

refresh_legacy_programs() {
    [ ! -e /etc/router-defaults/applied-version ] || return 0
    merge_legacy_defaults /etc/mx4200/base.conf || return 1
    merge_legacy_defaults /etc/mx4200/led.conf || return 1
    # Old sysupgrade backups included programs. Archive those known toolkit
    # paths and replace them with this firmware's code, not old overlay code.
    archive=/etc/mx4200/legacy-program-backup
    for relative in usr/lib/mxc usr/sbin/mxb usr/sbin/mxu usr/sbin/mxw usr/sbin/mxd usr/sbin/mxm usr/sbin/mxmod usr/sbin/mxauto usr/sbin/mxroutehealth usr/bin/mxls usr/bin/mxld root/mxr root/mxa root/mxwds etc/init.d/mxb etc/init.d/mxd etc/init.d/mxauto etc/init.d/mxroutehealth etc/init.d/mxl etc/profile.d/mx etc/hotplug.d/iface/95-mxmgmt usr/libexec/rpcd/mx.samba usr/share/rpcd/acl.d/mx-samba.json usr/share/luci/menu.d/mx-samba.json www/luci-static/resources/view/samba4/users.js etc/mx4200/base.conf etc/mx4200/led.conf; do
        [ -f "/rom/$relative" ] || continue
        if [ -f "/$relative" ] && ! cmp -s "/$relative" "/rom/$relative"; then
            mkdir -p "$archive/$(dirname "$relative")" || return 1
            cp -p "/$relative" "$archive/$relative" || return 1
            cp -p "/rom/$relative" "/$relative" || return 1
        fi
    done
}

main() {
    log 'Preparing settings preservation and retiring legacy automatic provisioning'
    for service in mxprovision mxmod; do
        if [ -x "/etc/init.d/$service" ]; then
            "/etc/init.d/$service" stop || true
            "/etc/init.d/$service" disable || true
        fi
    done
    # This exact listener belongs to the old toolkit. Never touch stock WPS.
    rm -f /etc/hotplug.d/button/95-mx-partition || return 1
    refresh_legacy_programs || return 1
    # Replace old backup rules that would shadow firmware-owned programs on
    # subsequent upgrades. Retain unrelated user backup entries.
    if [ -f /etc/sysupgrade.conf ]; then
        awk '
            /^\/usr\/lib\/mxc$/ || /^\/usr\/(sbin|bin)\/mx/ || /^\/etc\/init.d\/mx/ || /^\/root\/mx/ || /^\/etc\/profile.d\/mx/ || /^\/etc\/hotplug.d\/.*mx/ || /^\/www\/luci-static\/resources\/view\/samba4\/users.js$/ || /^\/usr\/libexec\/rpcd\/mx.samba$/ || /^\/usr\/share\/(luci\/menu.d|rpcd\/acl.d)\/mx-samba.json$/ || /^\/etc\/mx4200\/?$/ || /^\/etc\/mx4200\/(base|led).conf$/ || /^\/etc\/sysctl.d\/99-mx4200-vpn.conf$/ {next}
            {print}
        ' /etc/sysupgrade.conf > /etc/sysupgrade.conf.new || return 1
        mv /etc/sysupgrade.conf.new /etc/sysupgrade.conf || return 1
    else
        touch /etc/sysupgrade.conf || return 1
    fi
    for path in /etc/router-defaults/config /etc/router-defaults/applied-version /etc/mx4200/profiles/ /etc/mx4200/mode /etc/mx4200/provisioned /etc/mx4200/auto-priority /etc/mx4200/usb.conf /etc/mx4200/mwan3-repeater.backup /etc/mx4200/mwan3-repeater.state /etc/mx4200/samba-users/ /etc/mx4200/modules/; do
        grep -qxF "$path" /etc/sysupgrade.conf || printf '%s\n' "$path" >> /etc/sysupgrade.conf || return 1
    done
}

main "$@"