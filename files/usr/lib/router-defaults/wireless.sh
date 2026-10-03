#!/bin/sh
. /usr/lib/router-defaults/core.sh || exit 1

configure_radio() {
    uci_set "wireless.$1.country=$COUNTRY" || return 1
    uci_set "wireless.$1.disabled=0" || return 1
    uci_set "wireless.$1.band=$2" || return 1
    uci_set "wireless.$1.htmode=$3" || return 1
}

configure_initial_ap() {
    section=$1
    radio=$2
    ssid=$3
    encryption=$4
    password=$5
    [ -n "$ssid" ] && [ "$(printf '%s' "$ssid" | wc -c)" -le 32 ] || {
        error 'SSID must contain 1-32 bytes'
        return 1
    }
    case "$encryption" in
        none|owe) ;;
        psk2|sae|sae-mixed)
            [ "${#password}" -ge 8 ] && [ "${#password}" -le 63 ] || {
                error 'Configured Wi-Fi password must contain 8-63 characters'
                return 1
            } ;;
        *) error "Unsupported initial AP encryption: $encryption"; return 1 ;;
    esac
    uci_set "wireless.$section=wifi-iface" || return 1
    uci_set "wireless.$section.device=$radio" || return 1
    uci_set "wireless.$section.network=lan" || return 1
    uci_set "wireless.$section.mode=ap" || return 1
    uci_set "wireless.$section.ssid=$ssid" || return 1
    uci_set "wireless.$section.encryption=$encryption" || return 1
    if [ "$encryption" = none ] || [ "$encryption" = owe ]; then
        uci -q delete "wireless.$section.key" || true
    else
        uci_set "wireless.$section.key=$password" || return 1
    fi
    uci_set "wireless.$section.disabled=0" || return 1
}

main() {
    log 'Configuring the three MX4200 V2 radios and initial APs'
    # Delete anonymous interfaces backwards so their indexes do not shift.
    for section in $(uci -q show wireless | awk -F= '$2=="wifi-iface" {sections[++count]=$1} END {for (position=count; position>0; position--) print sections[position]}'); do
        uci -q delete "$section" || return 1
    done
    configure_radio "$RADIO_24" 2g "$MODE_2G" || return 1
    configure_radio "$RADIO_5G" 5g "$MODE_5G" || return 1
    configure_radio "$RADIO_5G_MAX" 5g "$MODE_5G_HIGH" || return 1
    uci_set "wireless.$RADIO_5G_MAX.channel=$CHANNEL_5G_HIGH" || return 1
    configure_initial_ap default_radio1 "$RADIO_24" "$SSID_2G" "$WIFI_24_ENCRYPTION" "$WIFI_24_PASSWORD" || return 1
    configure_initial_ap default_radio0 "$RADIO_5G" "$SSID_5G" "$WIFI_5G_ENCRYPTION" "$WIFI_5G_PASSWORD" || return 1
    configure_initial_ap default_radio2 "$RADIO_5G_MAX" "$SSID_5G_HIGH" "$WIFI_5G_MAX_ENCRYPTION" "$WIFI_5G_MAX_PASSWORD"
}

main "$@"