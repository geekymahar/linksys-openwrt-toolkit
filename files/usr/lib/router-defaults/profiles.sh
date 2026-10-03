#!/bin/sh
. /usr/lib/router-defaults/core.sh || return 1

profile_exists() {
    profile_directory="$PROFILE_ROOT/$1"
    [ -f "$profile_directory/network" ] && [ -f "$profile_directory/wireless" ] && [ -f "$profile_directory/dhcp" ] && [ -f "$profile_directory/firewall" ]
}

save_profile() {
    profile_name="$1"
    profile_directory="$PROFILE_ROOT/$profile_name"
    mkdir -p "$profile_directory"
    chmod 700 "$profile_directory"
    for profile_file in $PROFILE_FILES; do
        [ -f "/etc/config/$profile_file" ] && cp "/etc/config/$profile_file" "$profile_directory/$profile_file"
    done
    date +%s >"$profile_directory/saved_at"
    chmod 600 "$profile_directory"/* 2>/dev/null || true
}

load_profile() {
    profile_name="$1"
    profile_directory="$PROFILE_ROOT/$profile_name"
    profile_exists "$profile_name" || return 1
    for profile_file in $PROFILE_FILES; do
        [ -f "$profile_directory/$profile_file" ] && cp "$profile_directory/$profile_file" "/etc/config/$profile_file"
    done
    profile_mode="$profile_name"
    [ "$profile_name" = router-baseline ] && profile_mode=router
    if [ "$profile_mode" = repeater ] && [ "$(uci -q get network.wan.proto)" = none ]; then
        bridge_wan_port || return 1
        uci commit network || return 1
        save_profile repeater
    fi
    if [ "$profile_mode" = ap ] && {
        [ "$(uci -q get wireless.mx_mgmt.network)" != mgmt ] || [ "$(uci -q get network.mgmt.ipaddr)" != "$MGMT_IP" ]
    }; then
        configure_management_network "$MGMT_IP" "$LAN_NETMASK" "$DHCP_START"
        set_option wireless.mx_mgmt.network=mgmt
        set_option wireless.mx_mgmt.isolate=1
        configure_management_firewall
        commit_mode_configuration
        save_profile ap
    fi
    if [ "$profile_mode" = wds ] && [ "$(uci -q get network.mgmt.ipaddr)" != "$MGMT_IP" ]; then
        set_option network.mgmt.ipaddr="$MGMT_IP"
        uci commit network
        save_profile wds
    fi
    echo "$profile_mode" >/etc/mx4200/mode
    reload_mode_services
}

current_mode() {
    cat /etc/mx4200/mode 2>/dev/null || echo router
}

save_current_profile() {
    profile_mode="$(current_mode)"
    case "$profile_mode" in router | wds | repeater | ap) save_profile "$profile_mode" ;; esac
}

prompt_auto_priority() {
    profile_file=/etc/mx4200/auto-priority
    previous_priority="$(awk -v m="$1" '$1==m{print $2}' "$profile_file" 2>/dev/null)"
    printf 'Auto priority for %s (1=first, 9=last, 0=manual) [%s]: ' "$1" "${previous_priority:-0}"
    read -r selected_priority || return 1
    selected_priority=${selected_priority:-${previous_priority:-0}}
    case "$selected_priority" in [0-9]) ;; *) return 1 ;; esac
    [ -f "$profile_file" ] || : >"$profile_file"
    grep -v "^$1 " "$profile_file" >"$profile_file.new"
    [ "$selected_priority" = 0 ] || echo "$1 $selected_priority" >>"$profile_file.new"
    mv "$profile_file.new" "$profile_file"
    chmod 600 "$profile_file"
    date +%s >/tmp/mxauto-manual
}

print_profile_summary() {
    profile_name=$1
    profile_directory=$PROFILE_ROOT/$profile_name
    profile_exists $profile_name || {
        echo 'No profile'
        return
    }
    echo "Profile: $profile_name"
    profile_lan_ip="$(uci -c "$profile_directory" -q get network.lan.ipaddr)"
    [ -n "$profile_lan_ip" ] && echo "LAN: $profile_lan_ip"
    upstream_ssid="$(uci -c "$profile_directory" -q get wireless.mx_primary.ssid)"
    [ -n "$upstream_ssid" ] && echo "Upstream: $upstream_ssid"
}
