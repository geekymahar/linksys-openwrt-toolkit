#!/bin/sh
. /usr/lib/router-defaults/core.sh || return 1

wifi_clear() {
    for section in $(uci -q show wireless | awk -F= '$2=="wifi-iface" {sections[++count]=$1} END {for (position=count; position>0; position--) print sections[position]}'); do
        uci -q delete "$section"
    done
}

configure_radio_defaults() {
    for radio in "$RADIO_5G" "$RADIO_24" "$RADIO_5G_MAX"; do
        set_option wireless.$radio.country="$COUNTRY"
        set_option wireless.$radio.disabled=0
    done
    set_option "wireless.$RADIO_24.band=2g"
    set_option "wireless.$RADIO_24.htmode=$MODE_2G"
    set_option "wireless.$RADIO_5G.band=5g"
    set_option "wireless.$RADIO_5G.htmode=$MODE_5G"
    set_option "wireless.$RADIO_5G_MAX.band=5g"
    set_option "wireless.$RADIO_5G_MAX.htmode=$MODE_5G_HIGH"
    set_option "wireless.$RADIO_5G_MAX.channel=$CHANNEL_5G_HIGH"
}

configure_access_point() {
    local section=$1 encryption=${6:-$CLIENT_AP_ENCRYPTION}
    set_option wireless.$section=wifi-iface
    set_option wireless.$section.device="$2"
    set_option wireless.$section.mode=ap
    set_option wireless.$section.network="$3"
    set_option wireless.$section.ssid="$4"
    set_option wireless.$section.encryption="$encryption"
    if encryption_needs_key "$encryption"; then
        set_option "wireless.$section.key=$5" || return 1
    else
        uci -q delete "wireless.$section.key" || true
    fi
    set_option wireless.$section.disabled=0
}

wireless_status() {
    ubus call network.wireless status 2>/dev/null
}

radio_interface() {
    wireless_status | jsonfilter -e "@.$1.interfaces[0].ifname" 2>/dev/null
}

scan_radio() {
    radio=$1
    scan_output=$2
    WAIT_MAX=${3:-$SCAN_WAIT_MAX}
    scan_buffer=/tmp/mxscan.$$
    scan_pass_file=$scan_buffer.p
    : >"$scan_buffer"
    local_bssids="$(iw dev 2>/dev/null | awk '/addr/{printf "%s ",tolower($2)}')"
    scan_pass=1
    scan_delay=3
    if [ "$radio" = "$RADIO_5G_MAX" ]; then
        scan_delay=8
        wait_elapsed=0
        while [ "$(wireless_status | jsonfilter -e "@.$radio.pending" 2>/dev/null)" = true ] && [ $wait_elapsed -lt "$WAIT_MAX" ]; do
            [ $wait_elapsed = 0 ] && echo 'Waiting for 5GHz radio/DFS...' >&2
            sleep 2
            wait_elapsed=$((wait_elapsed + 2))
        done
    fi
    while [ $scan_pass -le 4 ]; do
        echo "Scan pass $scan_pass/4..." >&2
        : >"$scan_pass_file"
        iwinfo "$radio" scan >"$scan_pass_file" 2>/dev/null
        if [ ! -s "$scan_pass_file" ]; then
            interface="$(radio_interface "$radio")"
            [ -n "$interface" ] && iwinfo "$interface" scan >"$scan_pass_file" 2>/dev/null
        fi
        if [ ! -s "$scan_pass_file" ]; then
            phy_name="$(iwinfo "$radio" info 2>/dev/null | sed -n 's/.*PHY name: //p' | tail -1)"
            [ -n "$phy_name" ] || phy_name=phy${radio#radio}
            SCAN_IF=m$$
            iw phy "$phy_name" interface add "$SCAN_IF" type managed >/dev/null 2>&1 && {
                ip link set "$SCAN_IF" up
                sleep 2
                iwinfo "$SCAN_IF" scan >"$scan_pass_file" 2>/dev/null
                iw dev "$SCAN_IF" del >/dev/null 2>&1
            }
        fi
        [ -s "$scan_pass_file" ] && cat "$scan_pass_file" >>"$scan_buffer"
        scan_pass=$((scan_pass + 1))
        [ $scan_pass -le 4 ] && sleep "$scan_delay"
    done
    # Ignore our own BSSIDs and retain the strongest scanned AP for each SSID.
    awk -v local_addresses="$local_bssids" '
        BEGIN {
            count = split(local_addresses, addresses, " ")
            for (position = 1; position <= count; position++) {
                own_address[addresses[position]] = 1
            }
        }
        function save_cell() {
            if (ssid != "" && !own_address[tolower(bssid)]) {
                strength = signal + 0
                if (!(ssid in strongest) || strength > strongest[ssid]) {
                    strongest[ssid] = strength
                    result[ssid] = ssid "\t" channel "\t" signal "\t" encryption "\t" bssid
                }
            }
        }
        /^Cell / {
            save_cell()
            ssid = channel = signal = encryption = ""
            bssid = $5
            next
        }
        /ESSID:/ {
            ssid = $0
            sub(/.*ESSID: "/, "", ssid)
            sub(/"[[:space:]]*$/, "", ssid)
        }
        /Channel:/ {
            for (field = 1; field <= NF; field++) {
                if ($field == "Channel:") { channel = $(field + 1); break }
            }
        }
        /Signal:/ {
            for (field = 1; field <= NF; field++) {
                if ($field == "Signal:") { signal = $(field + 1); break }
            }
        }
        /Encryption:/ {
            encryption = $0
            sub(/^[[:space:]]*Encryption:[[:space:]]*/, "", encryption)
        }
        END {
            save_cell()
            for (name in result) print result[name]
        }
    ' "$scan_buffer" >"$scan_output"
    rm -f "$scan_buffer" "$scan_pass_file"
    [ -s "$scan_output" ]
}

scan_encryption_to_uci() {
    encryption="$(echo "$1" | tr A-Z a-z)"
    case "$encryption" in *owe*) echo owe ;; *sae*psk* | *psk*sae* | *sae*wpa2* | *wpa2*sae*) echo sae-mixed ;; *sae*) echo sae ;; *mix*wpa*psk* | *wpa*wpa2*psk*) echo psk-mixed ;; *wpa2*psk* | *psk*wpa2*) echo psk2 ;; *wpa*psk* | *psk*wpa*) echo psk ;; *none* | *open*) echo none ;; *) echo unsupported ;; esac
}

encryption_needs_key() {
    case "$1" in none | owe) return 1 ;; *) return 0 ;; esac
}
