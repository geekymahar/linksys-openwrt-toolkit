#!/bin/sh
# Install the optional MX dashboard. The router modes stay in local core scripts.
case "$(cat /tmp/sysinfo/board_name 2>/dev/null)" in linksys,mx4200v2*) ;; *) echo 'MX4200 V2/P2 required' >&2; exit 1 ;; esac
set -e
[ -r /usr/share/libubox/jshn.sh ] && command -v jsonfilter >/dev/null 2>&1 && [ -x /usr/sbin/mxm ] || { echo 'MX core/LuCI dependencies are missing' >&2; exit 1; }
UI_ALREADY_INSTALLED=0
[ -x /usr/libexec/rpcd/mx.ui ] && UI_ALREADY_INSTALLED=1
mkdir -p /usr/libexec/rpcd /usr/share/rpcd/acl.d /usr/share/luci/menu.d /www/luci-static/resources/view/mx4200
cat > /usr/libexec/rpcd/mx.ui.new.$$ <<'EOF_RPC'
#!/bin/sh
. /usr/share/libubox/jshn.sh
. /usr/lib/mxc
PRIORITIES=/etc/mx4200/auto-priority
reply(){ json_init;json_add_boolean ok "$1";json_add_string message "$2";json_dump; }
run(){ OUT=$("$@" 2>&1);RC=$?;[ "$RC" = 0 ] && reply 1 "${OUT:-Done}" || reply 0 "${OUT:-Operation failed}"; }
field(){ printf '%s' "$1" | jsonfilter -e "$2" 2>/dev/null; }
uplink(){
    ID=$1;TITLE=$2;SECTION=$3
    DATA=$(ubus call "network.interface.$SECTION" status 2>/dev/null)
    UP=$(field "$DATA" '@.up');DEV=$(field "$DATA" '@.l3_device')
    [ -n "$DEV" ] || DEV=$(field "$DATA" '@.device')
    IP=$(field "$DATA" '@["ipv4-address"][0].address')
    DNS=$(field "$DATA" '@["dns-server"][*]' | tr '\n' ' ')
    PROTO=$(uci -q get "network.$SECTION.proto")
    BSSID='';SIGNAL=''
    case "$ID" in wifi5) STA_IFACE=$PRIMARY_IFACE;;wifi2)STA_IFACE=$BACKUP_IFACE;;*)STA_IFACE='';;esac
    if [ -n "$STA_IFACE" ];then
        LINK=$(iw dev "$STA_IFACE" link 2>/dev/null)
        BSSID=$(printf '%s\n' "$LINK" | awk '/^Connected to /{print $3;exit}')
        SIGNAL=$(printf '%s\n' "$LINK" | awk '/signal:/{print $2" "$3;exit}')
    fi
    METRIC=$(uci -q get "network.$SECTION.metric" 2>/dev/null)
    case "$METRIC" in ''|*[!0-9]*) METRIC=0 ;; esac
    case "$ID" in
        wifi5) [ "$PRIMARY_LINK" = 1 ] && UP=true || UP=false ;;
        wifi2) [ "$BACKUP_LINK" = 1 ] && UP=true || UP=false ;;
        ethernet)
            if [ "$MODE" = ap ];then TITLE='Ethernet bridge';DEV=br-lan;IP=$(ip -4 addr show dev br-lan 2>/dev/null | awk '/inet /{sub(/\/.*/,"",$2);print $2;exit}');[ "$ROUTE_DEV" = br-lan ] && UP=true || UP=false
            fi ;;
    esac
    [ "$UP" = true ] && LIVE=1 || LIVE=0
    [ -n "$DEV" ] && [ "$DEV" = "$ROUTE_DEV" ] && SELECTED=1 || SELECTED=0
    case "$MODE:$ID:$ACTIVE_BACKHAUL" in wds:wifi5:primary|wds:wifi2:backup) [ "$ROUTE_DEV" = br-lan ] && SELECTED=1 ;; esac
    json_add_object ''
    json_add_string id "$ID";json_add_string label "$TITLE"
    json_add_string device "$DEV";json_add_string address "$IP"
    json_add_string protocol "$PROTO";json_add_string dns "$DNS"
    json_add_string bssid "$BSSID";json_add_string signal "$SIGNAL"
    json_add_string rx_bytes "$(cat "/sys/class/net/$DEV/statistics/rx_bytes" 2>/dev/null)"
    json_add_string tx_bytes "$(cat "/sys/class/net/$DEV/statistics/tx_bytes" 2>/dev/null)"
    json_add_int metric "$METRIC";json_add_int up "$LIVE";json_add_int selected "$SELECTED"
    json_close_object
}
wifi_link(){
    for INDEX in 0 1 2 3;do
        [ "$(field "$WIRELESS" "@.$1.interfaces[$INDEX].section")" = "$2" ] || continue
        IFACE=$(field "$WIRELESS" "@.$1.interfaces[$INDEX].ifname")
        [ -n "$IFACE" ] && iw dev "$IFACE" link 2>/dev/null | grep -q '^Connected to ' && return 0
    done
    return 1
}
case "$1" in
list) printf '{"status":{},"profiles":{},"overview":{},"logs":{"source":""},"scan_status":{"band":""},"setup":{"config":{}},"setup_status":{},"action":{"name":""},"priority":{"mode":"","value":0}}\n';exit 0 ;;
call) ;;
*) exit 1 ;;
esac
case "$2" in
overview)
    MODE=$(mode)
    ROUTE=$(ip -4 route show default 2>/dev/null | awk '$1=="default"{print;exit}')
    ROUTE_DEV=$(printf '%s\n' "$ROUTE" | awk '{for(i=1;i<=NF;i++)if($i=="dev"){print $(i+1);exit}}')
    GATEWAY=$(printf '%s\n' "$ROUTE" | awk '{for(i=1;i<=NF;i++)if($i=="via"){print $(i+1);exit}}')
    INTERNET=0;[ -n "$ROUTE_DEV" ] && { ping -I "$ROUTE_DEV" -c 1 -W 1 "$DNS_FALLBACK_1" >/dev/null 2>&1 || ping -I "$ROUTE_DEV" -c 1 -W 1 "$DNS_FALLBACK_2" >/dev/null 2>&1; } && INTERNET=1
    ACTIVE_BACKHAUL=$(cat /tmp/mx4200-backhaul-active 2>/dev/null)
    WIRELESS=$(ubus call network.wireless status 2>/dev/null)
    PRIMARY_LINK=0;BACKUP_LINK=0
    wifi_link radio2 mx_primary && { PRIMARY_LINK=1;PRIMARY_IFACE=$IFACE; }
    wifi_link radio1 mx_backup && { BACKUP_LINK=1;BACKUP_IFACE=$IFACE; }
    BOARD=$(ubus call system board 2>/dev/null)
    TS=$(tailscale status --json 2>/dev/null)
    json_init
    json_add_string mode "$MODE"
    json_add_string hostname "$(uci -q get system.@system[0].hostname)"
    json_add_string model "$(field "$BOARD" '@.model')"
    json_add_string release "$(field "$BOARD" '@.release.description')"
    json_add_string gateway "$GATEWAY"
    json_add_string route_device "$ROUTE_DEV"
    json_add_string wan_socket "$(uci -q get network.wan.proto)"
    json_add_string wan_preference "$(uci -q get network.wan.mx_priority)"
    json_add_int internet_probe "$INTERNET"
    json_add_string lan_address "$(ip -4 addr show dev br-lan 2>/dev/null | awk '/inet /{print $2;exit}')"
    json_add_string management_address "$(uci -q get network.mgmt.ipaddr)"
    json_add_string backhaul "$ACTIVE_BACKHAUL"
    json_add_string led_state "$(sed -n "s/^STATE='\([^']*\)'.*/\1/p" /tmp/mx4200-led-state 2>/dev/null | head -1)"
    json_add_string tailscale_state "$(field "$TS" '@.BackendState')"
    json_add_string tailscale_ip "$(field "$TS" '@.Self.TailscaleIPs[0]')"
    json_add_string wireguard "$(wg show interfaces 2>/dev/null)"
    pgrep openvpn >/dev/null 2>&1 && VPN=1 || VPN=0;json_add_int openvpn "$VPN"
    json_add_string uptime "$(awk '{print int($1)}' /proc/uptime 2>/dev/null)"
    json_add_string load "$(awk '{print $1" "$2" "$3}' /proc/loadavg 2>/dev/null)"
    json_add_string kernel "$(uname -r)"
    json_add_string cpu_cores "$(grep -c '^processor' /proc/cpuinfo 2>/dev/null)"
    json_add_string ssh_port "$(uci -q get dropbear.@dropbear[0].Port)"
    json_add_string http_listen "$(uci -q get uhttpd.main.listen_http)"
    json_add_string https_listen "$(uci -q get uhttpd.main.listen_https)"
    json_add_string memory_total "$(awk '$1=="MemTotal:"{print $2}' /proc/meminfo 2>/dev/null)"
    json_add_string memory_available "$(awk '$1=="MemAvailable:"{print $2}' /proc/meminfo 2>/dev/null)"
    json_add_string flash "$(df -k /overlay 2>/dev/null | awk 'NR==2{print $2" "$3" "$4}')"
    TEMP=$(cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null);case "$TEMP" in ''|*[!0-9]*) TEMP=0 ;; esac;json_add_int temperature "$TEMP"
    json_add_object wifi
    for N in mx_ap2 mx_ap5 mx_ap_high mx_primary mx_backup mx_mgmt;do json_add_string "$N" "$(uci -q get "wireless.$N.ssid")";done
    json_close_object
    json_add_array uplinks
    if [ "$MODE" = ap ] || [ "$(uci -q get network.wan.proto)" != none ];then uplink ethernet 'Ethernet WAN' wan;fi
    if [ "$MODE" = wds ];then P=wdsp;B=wdsb;else P=wwanp;B=wwanb;fi
    uplink wifi5 '5 GHz backhaul' "$P"
    uplink wifi2 '2.4 GHz backup' "$B"
    uplink usb 'USB tether' usbwan
    json_close_array
    json_add_array clients
    COUNT=0
    if [ -r /tmp/dhcp.leases ];then
        while read -r EXP MAC IP NAME _;do
            [ "$COUNT" -lt 64 ] || break
            case "$IP" in *.*.*.*) ;; *) continue ;; esac
            json_add_object ''
            json_add_string name "$NAME";json_add_string address "$IP";json_add_string mac "$MAC"
            json_close_object;COUNT=$((COUNT+1))
        done < /tmp/dhcp.leases
    fi
    json_close_array
    json_add_int client_count "$COUNT"
    json_dump;exit 0 ;;
logs)
    SOURCE=$(cat | jsonfilter -e '@.source' 2>/dev/null)
    json_init
    case "$SOURCE" in kernel) json_add_string lines "$(dmesg 2>/dev/null | tail -n 120)" ;; *) json_add_string lines "$(logread 2>/dev/null | tail -n 120)" ;; esac
    json_dump;exit 0 ;;
scan_status)
    BAND=$(cat | jsonfilter -e '@.band' 2>/dev/null)
    case "$BAND" in radio1|radio2) ;; *) reply 0 'Invalid band';exit 0 ;; esac
    BASE=/tmp/mxui-scan-$BAND
    json_init;json_add_string state "$(cat "$BASE.state" 2>/dev/null)";json_add_array networks
    if [ -r "$BASE.results" ];then
        TAB=$(printf '\t')
        while IFS="$TAB" read -r SSID CHANNEL SIGNAL SECURITY BSSID;do
            [ -n "$SSID" ] || continue
            json_add_object ''
            json_add_string ssid "$SSID";json_add_string channel "$CHANNEL"
            json_add_string signal "$SIGNAL";json_add_string security "$SECURITY"
            json_add_string bssid "$BSSID";json_close_object
        done < "$BASE.results"
    fi
    json_close_array;json_dump;exit 0 ;;
setup) exec /usr/sbin/mxsetup-ui submit ;;
setup_status) exec /usr/sbin/mxsetup-ui status ;;
status)
    json_init
    json_add_string mode "$(mode)"
    json_add_string summary "$(/usr/sbin/mxm status 2>&1)"
    json_add_string backhaul "$(cat /tmp/mx4200-backhaul-active 2>/dev/null || echo unknown)"
    json_add_string led "$(cat /tmp/mx4200-led-state 2>/dev/null || echo 'LED module pending')"
    json_add_string auto "$(/usr/sbin/mxmod auto-status 2>&1)"
    json_dump
    exit 0 ;;
profiles)
    json_init;json_add_string current "$(mode)";json_add_object profiles
    for M in router router-baseline repeater wds ap; do
        json_add_object "$M"
        [ -f "/etc/mx4200/profiles/$M/network" ] && SAVED=1 || SAVED=0
        P=$(awk -v m="$M" '$1==m{print $2;exit}' "$PRIORITIES" 2>/dev/null)
        case "$P" in [1-9]) ;; *) P=0 ;; esac
        json_add_int saved "$SAVED";json_add_int priority "$P"
        json_close_object
    done
    json_close_object;json_dump;exit 0 ;;
action|priority) ;;
*) reply 0 'Unsupported method';exit 0 ;;
esac
REQUEST=$(cat)
if [ "$2" = priority ]; then
    M=$(printf '%s' "$REQUEST" | jsonfilter -e '@.mode' 2>/dev/null)
    P=$(printf '%s' "$REQUEST" | jsonfilter -e '@.value' 2>/dev/null)
    case "$M" in router|repeater|wds|ap) ;; *) reply 0 'Invalid mode';exit 0 ;; esac
    case "$P" in [0-9]) ;; *) reply 0 'Priority must be 0–9';exit 0 ;; esac
    [ -f "/etc/mx4200/profiles/$M/network" ] || { reply 0 'Save this mode before setting priority';exit 0; }
    mkdir -p /etc/mx4200
    [ -f "$PRIORITIES" ] || : > "$PRIORITIES"
    awk -v m="$M" '$1!=m {print}' "$PRIORITIES" > "$PRIORITIES.new" || { reply 0 'Could not update priorities';exit 0; }
    [ "$P" = 0 ] || printf '%s %s\n' "$M" "$P" >> "$PRIORITIES.new"
    chmod 600 "$PRIORITIES.new";mv "$PRIORITIES.new" "$PRIORITIES"
    date +%s > /tmp/mxauto-manual
    reply 1 'Priority saved';exit 0
fi
A=$(printf '%s' "$REQUEST" | jsonfilter -e '@.name' 2>/dev/null)
case "$A" in
refresh) run /usr/sbin/mxm status ;;
usb_detect) run /usr/sbin/mxu detect ;;
usb_primary) run /usr/sbin/mxu primary ;;
usb_backup) run /usr/sbin/mxu backup ;;
usb_off) run /usr/sbin/mxu off ;;
scan_5g) run /usr/sbin/mxscan-ui start radio2 ;;
scan_2g) run /usr/sbin/mxscan-ui start radio1 ;;
backhaul_auto|backhaul_primary|backhaul_backup)
    case "$(mode)" in wds|repeater) ;; *) reply 0 'Backhaul controls require WDS or routed repeater';exit 0 ;; esac
    run /usr/sbin/mxb "${A#backhaul_}" ;;
wds_test) run /root/mxwds ;;
auto_status) [ -x /usr/sbin/mxauto ] && run /usr/sbin/mxauto status || reply 0 'Automatic mode module is pending' ;;
auto_once) [ -x /usr/sbin/mxauto ] && run /usr/sbin/mxauto once || reply 0 'Automatic mode module is pending' ;;
led_install) run /usr/sbin/mxmod once ;;
ui_update) MX_UI_RPC_UPDATE=1;export MX_UI_RPC_UPDATE;run /usr/sbin/mxmod ui-once ;;
led_detect) [ -x /usr/bin/mxls ] && run /usr/bin/mxls detect || reply 0 'LED module is pending' ;;
led_state) [ -f /tmp/mx4200-led-state ] && run cat /tmp/mx4200-led-state || reply 0 'No LED state yet' ;;
led_auto) [ -x /etc/init.d/mxl ] || { reply 0 'LED module is pending';exit 0; }; /etc/init.d/mxl enable >/dev/null 2>&1;run /etc/init.d/mxl restart ;;
led_red|led_green|led_blue|led_purple|led_orange|led_yellow|led_teal|led_white|led_off)
    [ -x /usr/bin/mxls ] || { reply 0 'LED module is pending';exit 0; }
    /etc/init.d/mxl stop >/dev/null 2>&1
    run /usr/bin/mxls "${A#led_}" ;;
profile_router|profile_router_baseline|profile_repeater|profile_wds|profile_ap)
    M=${A#profile_};[ "$M" = router_baseline ] && M=router-baseline
    pex "$M" || { reply 0 'Saved profile is missing';exit 0; }
    CUR=$(mode);TARGET=$M;[ "$TARGET" = router-baseline ] && TARGET=router
    date +%s > /tmp/mxauto-manual
    if uci -q get network.usbwan >/dev/null 2>&1;then /usr/sbin/mxu off-quiet || { reply 0 'Could not disable USB uplink';exit 0; };fi
    if [ "$CUR" != "$TARGET" ];then savecur;elif [ "$M" = router-baseline ];then psave router;fi
    run pload "$M" ;;
save_current) CUR=$(mode);case "$CUR" in router|repeater|wds|ap) psave "$CUR";reply 1 "Saved $CUR profile";;*) reply 0 'Unknown mode';;esac ;;
*) reply 0 'Unsupported action' ;;
esac
EOF_RPC
chmod 755 /usr/libexec/rpcd/mx.ui.new.$$
mv -f /usr/libexec/rpcd/mx.ui.new.$$ /usr/libexec/rpcd/mx.ui
cat > /usr/sbin/mxscan-ui <<'EOF_SCAN'
#!/bin/sh
case "$2" in radio1|radio2) BAND=$2 ;; *) exit 1 ;; esac
BASE=/tmp/mxui-scan-$BAND
case "$1" in
start)
    mkdir "$BASE.lock" 2>/dev/null || { echo 'Scan already running';exit 1; }
    echo running > "$BASE.state";rm -f "$BASE.results"
    (/usr/sbin/mxscan-ui run "$BAND" </dev/null >/dev/null 2>&1 &)
    echo 'Scan started; results will appear here when ready.' ;;
run)
    trap 'rm -f "$BASE.new";rmdir "$BASE.lock" 2>/dev/null' EXIT
    . /usr/lib/mxc
    if sr "$BAND" "$BASE.new" 120;then mv "$BASE.new" "$BASE.results";echo ready > "$BASE.state"
    else echo failed > "$BASE.state";fi ;;
*) exit 1 ;;
esac
EOF_SCAN
chmod 755 /usr/sbin/mxscan-ui
cat > /usr/sbin/mxsetup-ui <<'EOF_SETUP'
#!/bin/sh
. /usr/share/libubox/jshn.sh
. /usr/lib/mxc
uci(){ CMD=$1;[ "$CMD" = -q ] && CMD=$2;command uci "$@";RC=$?;case "$CMD" in set|add|add_list|commit) [ "$RC" = 0 ] || exit 1;;esac;return "$RC"; }
u(){ uci set "$1" || exit 1; }
LOCK=/tmp/mxui-setup.lock
STATE=/tmp/mxui-setup.state
field(){ cat "$INPUT" | jsonfilter -e "@.config.$1" 2>/dev/null; }
reply(){ json_init;json_add_boolean ok "$1";json_add_string message "$2";json_dump; }
bad(){ ERROR="$1";return 1; }
bytes(){ printf %s "$1" | LC_ALL=C wc -c | tr -d ' '; }
clean(){ [ -n "$1" ] && [ "$(bytes "$1")" -le "$2" ] && ! printf %s "$1" | LC_ALL=C grep -q '[[:cntrl:]]'; }
secret(){ [ "$(bytes "$1")" -ge 8 ] && [ "$(bytes "$1")" -le 63 ] && ! printf %s "$1" | LC_ALL=C grep -q '[[:cntrl:]]'; }
lookup(){
    [ -r "/tmp/mxui-scan-$1.results" ] || return 1
    WANT=$(printf %s "$2" | tr A-F a-f)
    printf %s "$WANT" | grep -Eq '^([0-9a-f]{2}:){5}[0-9a-f]{2}$' || return 1
    SELF=$(iw dev 2>/dev/null | awk '/addr/{printf " %s ",tolower($2)}')
    case "$SELF" in *" $WANT "*) return 1 ;; esac
    FOUND_SSID='';TAB=$(printf '\t')
    while IFS="$TAB" read -r S C G E B;do
        [ "$(printf %s "$B" | tr A-F a-f)" = "$WANT" ] || continue
        FOUND_SSID=$S;FOUND_CHANNEL=$C;FOUND_ENC=$(e2u "$E");FOUND_BSSID=$WANT
        break
    done < "/tmp/mxui-scan-$1.results"
    [ -n "$FOUND_SSID" ] && clean "$FOUND_SSID" 32 || return 1
    case "$FOUND_CHANNEL" in ''|*[!0-9]*) return 1;;esac
    [ "$FOUND_ENC" != unsupported ]
}
resolve_security(){
    SCANNED=$1;CHOSEN=$2
    case "$SCANNED:$CHOSEN" in
        psk:psk|psk:psk2) printf %s "$CHOSEN" ;;
        psk:auto) return 1 ;;
        *:auto) printf %s "$SCANNED" ;;
        *) [ "$SCANNED" = "$CHOSEN" ] && printf %s "$SCANNED" || return 1 ;;
    esac
}
validate(){
    MODE=$(field mode);PRIORITY=$(field priority)
    case "$MODE" in router|repeater|wds|ap) ;; *) bad 'Choose a router mode';return 1;;esac
    case "$PRIORITY" in [0-9]) ;; *) bad 'Priority must be 0–9';return 1;;esac
    case "$MODE" in
    router|ap)
        AP_SSID=$(field ap_ssid);AP_SECURITY=$(field ap_security);AP_PASS=$(field ap_password)
        MAX=21;[ "$MODE" = router ] && MAX=27
        clean "$AP_SSID" "$MAX" || { bad "Wi-Fi name must be 1–$MAX bytes";return 1; }
        case "$AP_SECURITY" in none|psk2|sae|sae-mixed) ;; *) bad 'Unsupported Wi-Fi security';return 1;;esac
        [ "$AP_SECURITY" = none ] || secret "$AP_PASS" || { bad 'Wi-Fi password must be 8–63 bytes';return 1; }
        if [ "$MODE" = ap ];then
            MGMT_PASS=$(field management_password)
            secret "$MGMT_PASS" || { bad 'Management password must be 8–63 bytes';return 1; }
        fi ;;
    repeater|wds)
        PRIMARY_BSSID=$(field primary_bssid);PRIMARY_CHOICE=$(field primary_security);PRIMARY_PASS=$(field primary_password)
        lookup radio2 "$PRIMARY_BSSID" || { bad 'Choose a fresh 5 GHz scan result';return 1; }
        PSSID=$FOUND_SSID;PCHAN=$FOUND_CHANNEL;PENC=$(resolve_security "$FOUND_ENC" "$PRIMARY_CHOICE") || { bad 'Confirm WPA1 or WPA2 for the 5 GHz network';return 1; }
        nk "$PENC" && { secret "$PRIMARY_PASS" || { bad '5 GHz password must be 8–63 bytes';return 1; }; }
        CLIENT_SSID=$(field client_ssid);CLIENT_PASS=$(field client_password)
        MAX=25;[ "$MODE" = wds ] && MAX=21
        clean "$CLIENT_SSID" "$MAX" || { bad "Client Wi-Fi name must be 1–$MAX bytes";return 1; }
        nk "$PENC" && { secret "$CLIENT_PASS" || { bad 'Client Wi-Fi password must be 8–63 bytes';return 1; }; }
        BACKUP_BSSID=$(field backup_bssid);BACKUP_CHOICE=$(field backup_security);BACKUP_PASS=$(field backup_password);BACKUP_SAME=$(field backup_same)
        if [ -n "$BACKUP_BSSID" ];then
            lookup radio1 "$BACKUP_BSSID" || { bad 'Choose a fresh 2.4 GHz scan result';return 1; }
            BSSID=$FOUND_SSID;BCHAN=$FOUND_CHANNEL;BENC=$(resolve_security "$FOUND_ENC" "$BACKUP_CHOICE") || { bad 'Confirm WPA1 or WPA2 for the backup';return 1; }
            if [ "$BACKUP_SAME" = 1 ];then
                [ "$BSSID" = "$PSSID" ] || { bad 'Same-credential backup needs the same SSID';return 1; }
                if nk "$PENC";then nk "$BENC" || { bad 'Backup security differs from the primary';return 1; }
                else nk "$BENC" && { bad 'Backup security differs from the primary';return 1; };fi
                BACKUP_PASS=$PRIMARY_PASS
            fi
            nk "$BENC" && { secret "$BACKUP_PASS" || { bad 'Backup password must be 8–63 bytes';return 1; }; }
        fi
        if [ "$MODE" = wds ];then
            MGMT_PASS=$(field management_password)
            secret "$MGMT_PASS" || { bad 'Management password must be 8–63 bytes';return 1; }
        else
            WAN_PORT=$(field wan_port);WAN_PREF=$(field wan_preference)
            case "$WAN_PORT" in lan|wan) ;; *) bad 'Choose a WAN socket role';return 1;;esac
            case "$WAN_PREF" in wifi|wan) ;; *) bad 'Choose a wired or Wi-Fi preference';return 1;;esac
            [ "$WAN_PORT" = wan ] || WAN_PREF=wifi
        fi ;;
    esac
    ds br-lan >/dev/null || { bad 'br-lan is missing';return 1; }
    zs wan >/dev/null || { bad 'WAN firewall zone is missing';return 1; }
    [ "$MODE" != router ] || pex router-baseline || { bad 'Router baseline profile is missing';return 1; }
    return 0
}
priority_save(){
    F=/etc/mx4200/auto-priority
    [ -f "$F" ] || : > "$F"
    awk -v m="$MODE" '$1!=m{print}' "$F" > "$F.new"
    [ "$PRIORITY" = 0 ] || printf '%s %s\n' "$MODE" "$PRIORITY" >> "$F.new"
    chmod 600 "$F.new";mv "$F.new" "$F"
}
commit_all(){ for F in $PROFILE_FILES;do uci commit "$F" || return 1;done; }
sta(){
    S=$1;R=$2;N=$3;Q=$4;A=$5;E=$6;K=$7
    u wireless.$S=wifi-iface;u wireless.$S.device="$R";u wireless.$S.mode=sta;u wireless.$S.network="$N"
    u wireless.$S.ssid="$Q";u wireless.$S.bssid="$A";u wireless.$S.encryption="$E"
    nk "$E" && u wireless.$S.key="$K"
    [ "$MODE" = wds ] && u wireless.$S.wds=1
    u wireless.$S.disabled=0
}
router_setup(){
    MX4200_NO_RELOAD=1 pload router-baseline
    wifi_clear;rb
    ap mx_ap2 radio1 lan "$AP_SSID" "$AP_PASS" "$AP_SECURITY"
    ap mx_ap5 radio0 lan "${AP_SSID}-5GHz" "$AP_PASS" "$AP_SECURITY"
    ap mx_ap_high radio2 lan "${AP_SSID}-Max" "$AP_PASS" "$AP_SECURITY"
    return 0
}
ap_setup(){
    wifi_clear;rb
    BR=$(ds br-lan);uci -q delete "${BR}.ports"
    for I in lan1 lan2 lan3;do uci add_list "${BR}.ports=$I";done
    rwan;ld
    for I in wwanp wwanb wdsp wdsb usbwan;do uci -q delete "network.$I";done
    mc "$MGMT_IP" "$LAN_NETMASK" "$DHCP_START"
    ap mx_ap2 radio1 lan "$AP_SSID" "$AP_PASS" "$AP_SECURITY"
    ap mx_ap5 radio0 lan "$AP_SSID" "$AP_PASS" "$AP_SECURITY"
    ap mx_ap_high radio2 lan "$AP_SSID" "$AP_PASS" "$AP_SECURITY"
    ap mx_mgmt radio1 mgmt "${AP_SSID}-Management" "$MGMT_PASS"
    u wireless.mx_mgmt.isolate=1
    dz uplink;lz;df lan;mf
    Z=$(zs wan);for I in lan wwanp wwanb usbwan;do uci -q del_list "${Z}.network=$I";done
    return 0
}
repeater_setup(){
    wifi_clear;rb
    BR=$(ds br-lan);u "${BR}.stp=1";uci -q delete "${BR}.ports"
    if [ "$MODE" = wds ];then
        uci add_list "${BR}.ports=lan2";uci add_list "${BR}.ports=lan3"
        ld;u network.lan.metric=5;mc "$MGMT_IP" "$LAN_NETMASK" "$DHCP_START" lan1
    else
        for I in lan1 lan2 lan3;do uci add_list "${BR}.ports=$I";done
        RD="$PROFILE_ROOT/router"
        LIP=$(uci -c "$RD" -q get network.lan.ipaddr 2>/dev/null);LIP=${LIP:-$LAN_IP}
        LNET=$(uci -c "$RD" -q get network.lan.netmask 2>/dev/null);LNET=${LNET:-$LAN_NETMASK}
        START=$(uci -c "$RD" -q get dhcp.lan.start 2>/dev/null);START=${START:-$DHCP_START}
        LIMIT=$(uci -c "$RD" -q get dhcp.lan.limit 2>/dev/null);LIMIT=${LIMIT:-$DHCP_LIMIT}
        LEASE=$(uci -c "$RD" -q get dhcp.lan.leasetime 2>/dev/null);LEASE=${LEASE:-$DHCP_LEASETIME}
        sl "$LIP" "$LNET" "$START" "$LIMIT" "$LEASE"
        uci -q delete network.br_mgmt;uci -q delete network.mgmt;uci -q delete dhcp.mgmt
    fi
    uci -q delete network.usbwan
    if [ "$MODE" = repeater ];then
        if [ "$WAN_PORT" = lan ];then rwan;else u network.wan.device=wan;u network.wan.proto=dhcp;uci -q delete network.wan6.disabled;fi
        u network.wan.mx_priority="$WAN_PREF"
        for X in wwanp wwanb;do u network.$X=interface;u network.$X.proto=dhcp;done
        u network.wwanp.metric=5;u network.wwanb.metric=15
        [ "$WAN_PREF" = wan ] && u network.wan.metric=3 || u network.wan.metric=20
        uci -q delete network.wdsp;uci -q delete network.wdsb
    else
        u network.wan.device=wan;u network.wan.proto=dhcp;uci -q delete network.wan.mx_priority
        uci -q delete network.wan6.disabled
        for X in wdsp wdsb;do u network.$X=interface;u network.$X.proto=none;done
        uci -q delete network.wwanp;uci -q delete network.wwanb;u network.wan.metric=10
    fi
    u wireless.radio2.channel="$PCHAN"
    [ "$MODE" = wds ] && NET=wdsp || NET=wwanp
    sta mx_primary radio2 "$NET" "$PSSID" "$PRIMARY_BSSID" "$PENC" "$PRIMARY_PASS"
    if [ -n "$BACKUP_BSSID" ];then
        u wireless.radio1.channel="$BCHAN"
        [ "$MODE" = wds ] && NET=wdsb || NET=wwanb
        sta mx_backup radio1 "$NET" "$BSSID" "$BACKUP_BSSID" "$BENC" "$BACKUP_PASS"
    else
        uci -q delete wireless.mx_backup;uci -q delete network.wwanb;uci -q delete network.wdsb
    fi
    ap mx_ap5 radio0 lan "${CLIENT_SSID}-RPT-5G" "$CLIENT_PASS" "$PENC"
    ap mx_ap2 radio1 lan "${CLIENT_SSID}-RPT-2G" "$CLIENT_PASS" "$PENC"
    if [ "$MODE" = wds ];then ap mx_mgmt radio1 mgmt "${CLIENT_SSID}-Management" "$MGMT_PASS";else uci -q delete wireless.mx_mgmt;fi
    dz mgmt;dz uplink;lz;wz
    Z=$(zs wan)
    for N in wan lan wwan wwanp wwanb usbwan;do uci -q del_list "${Z}.network=$N";done
    uci add_list "${Z}.network=wan"
    [ "$MODE" = wds ] && uci add_list "${Z}.network=lan"
    uci -q delete firewall.mx_wan_lan
    if [ "$MODE" = wds ];then dz lan;uci -q delete firewall.mx_mgmt_wan;mf;fw mgmt wan
    else uz;df lan;df uplink;fw lan uplink;fw lan wan;mr wan;mr uplink;fi
    return 0
}
rollback(){
    [ -f "$SAVE/snapshot-ready" ] || return
    for F in $PROFILE_FILES;do [ -f "$SAVE/$F" ] && cp "$SAVE/$F" "/etc/config/$F";uci -q revert "$F" 2>/dev/null || true;done
    [ -f "$SAVE/mode" ] && cp "$SAVE/mode" /etc/mx4200/mode
    if [ -d "$SAVE/profiles" ];then rm -rf "$PROFILE_ROOT";cp -R "$SAVE/profiles" "$PROFILE_ROOT";fi
    if [ -f "$SAVE/priority" ];then cp "$SAVE/priority" /etc/mx4200/auto-priority
    else rm -f /etc/mx4200/auto-priority;fi
    ra >/dev/null 2>&1 || true
}
finish(){
    RC=$?;trap - EXIT;set +e
    if [ "$RC" = 0 ];then echo ready > "$STATE";else rollback;echo failed > "$STATE";fi
    rm -f "$INPUT";rm -rf "$SAVE" "$LOCK"
    exit "$RC"
}
case "$1" in
submit)
    umask 077
    mkdir "$LOCK" 2>/dev/null || { reply 0 'Another setup is running';exit 0; }
    INPUT="$LOCK/request.json"
    cat > "$INPUT" || { rmdir "$LOCK";reply 0 'Could not read setup';exit 0; }
    [ "$(wc -c < "$INPUT")" -le 8192 ] || { rm -f "$INPUT";rmdir "$LOCK";reply 0 'Setup request is too large';exit 0; }
    if ! validate;then rm -f "$INPUT";rmdir "$LOCK";reply 0 "$ERROR";exit 0;fi
    echo running > "$STATE"
    (/usr/sbin/mxsetup-ui run "$INPUT" </dev/null >/dev/null 2>&1 &)
    reply 1 'Applying setup. This page may disconnect while the network restarts.' ;;
status)
    json_init;json_add_string state "$(cat "$STATE" 2>/dev/null)";json_dump ;;
run)
    INPUT=$2;SAVE="$LOCK/rollback";umask 077
    trap finish EXIT
    mkdir "$SAVE" || exit 1
    validate || exit 1
    for F in $PROFILE_FILES;do [ -f "/etc/config/$F" ] && cp "/etc/config/$F" "$SAVE/$F" || exit 1;done
    cp -R "$PROFILE_ROOT" "$SAVE/profiles" || exit 1
    [ ! -f /etc/mx4200/mode ] || cp /etc/mx4200/mode "$SAVE/mode" || exit 1
    [ ! -f /etc/mx4200/auto-priority ] || cp /etc/mx4200/auto-priority "$SAVE/priority" || exit 1
    touch "$SAVE/snapshot-ready" || exit 1
    date +%s > /tmp/mxauto-manual
    savecur
    case "$MODE" in router) router_setup;;ap) ap_setup;;repeater|wds) repeater_setup;;esac || exit 1
    commit_all || exit 1
    echo "$MODE" > /etc/mx4200/mode || exit 1
    psave "$MODE" || exit 1
    priority_save || exit 1
    ra || exit 1
    ;;
*) exit 1 ;;
esac
EOF_SETUP
chmod 755 /usr/sbin/mxsetup-ui
cat > /usr/share/rpcd/acl.d/mx-ui.json <<'EOF_ACL'
{
  "mx-ui": {
    "description": "View and manage MX4200 modes through dedicated actions",
    "read": { "ubus": { "mx.ui": [ "status", "profiles", "overview", "logs", "scan_status", "setup_status" ] } },
    "write": { "ubus": { "mx.ui": [ "action", "priority", "setup" ] } }
  }
}
EOF_ACL
cat > /usr/share/luci/menu.d/mx-ui.json <<'EOF_MENU'
{
  "admin/mx4200": {
    "title": "MX Dashboard",
    "order": 1,
    "action": { "type": "view", "path": "mx4200/dashboard" },
    "depends": { "acl": [ "mx-ui" ] }
  },
  "admin/services/mx4200": {
    "title": "MX4200 Manager",
    "order": 40,
    "action": { "type": "view", "path": "mx4200/manager" },
    "depends": { "acl": [ "mx-ui" ] }
  }
}
EOF_MENU
cat > /www/luci-static/resources/view/mx4200/manager.js <<'EOF_JS'
'use strict';
'require rpc';
'require view';
'require ui';

var getStatus = rpc.declare({ object: 'mx.ui', method: 'status' });
var getProfiles = rpc.declare({ object: 'mx.ui', method: 'profiles' });
var doAction = rpc.declare({ object: 'mx.ui', method: 'action', params: [ 'name' ] });
var setPriority = rpc.declare({ object: 'mx.ui', method: 'priority', params: [ 'mode', 'value' ] });

function button(label, fn) { return E('button', { 'class': 'btn', 'click': fn }, label); }
function section(title, description, content) { return E('div', { 'class': 'cbi-section' }, [ E('h3', {}, title), E('p', {}, description), content ]); }
function terminalLink() { return E('a', { 'href': L.url('admin/services/ttyd/ttyd'), 'target': '_blank', 'rel': 'noopener noreferrer' }, _('Open browser terminal')); }

return view.extend({
	load: function() { return Promise.all([ getStatus(), getProfiles() ]); },
	render: function(data) {
		var status = E('pre', {}, data[0] && data[0].summary || _('Status unavailable'));
		var profileTable = E('table', { 'class': 'table' });
		var result = E('pre', {}, '');
		var currentMode = data[0] && data[0].mode || 'router';
		function refresh() {
			return Promise.all([ getStatus(), getProfiles() ]).then(function(values) {
				status.textContent = values[0] && values[0].summary || _('Status unavailable');
				currentMode = values[0] && values[0].mode || currentMode;
				drawProfiles(values[1]);
			});
		}
		function execute(name, disruptive) {
			if (disruptive && !window.confirm(_('This may disconnect your browser while the router changes network mode or uplink. Continue?'))) return;
			result.textContent = _('Working…');
			return doAction(name).then(function(response) {
				result.textContent = response && response.message || _('No response');
				if (response && response.ok) return refresh();
			}).catch(function(error) {
				result.textContent = _('Connection changed or action failed. Reconnect and refresh if needed.') + '\n' + String(error);
			});
		}
		function priority(mode, value) {
			return setPriority(mode, Number(value)).then(function(response) {
				result.textContent = response && response.message || _('No response');
				if (response && response.ok) return refresh();
			});
		}
		function drawProfiles(info) {
			profileTable.replaceChildren(E('tr', { 'class': 'tr table-titles' }, [
				E('th', { 'class': 'th' }, _('Mode')), E('th', { 'class': 'th' }, _('Saved')), E('th', { 'class': 'th' }, _('Auto priority')), E('th', { 'class': 'th' }, _('Action'))
			]));
			[ [ 'router', _('Router') ], [ 'router-baseline', _('First-boot router baseline') ], [ 'repeater', _('Routed repeater') ], [ 'wds', _('WDS repeater') ], [ 'ap', _('Wired AP') ] ].forEach(function(item) {
				var name = item[0], profile = info && info.profiles && info.profiles[name] || {}, saved = profile.saved === 1;
				var actions = [];
				if (saved) actions.push(button(_('Restore'), function() { execute('profile_' + name.replace('-', '_'), true); }));
				var rank = E('select');
				for (var n = 0; n <= 9; n++) rank.appendChild(E('option', { 'value': String(n) }, String(n)));
				rank.value = String(profile.priority || 0);
				var rankCell = name === 'router-baseline' ? E('span', {}, '—') : E('span', {}, [ rank, button(_('Save'), function() { priority(name, rank.value); }) ]);
				profileTable.appendChild(E('tr', { 'class': 'tr' }, [
					E('td', { 'class': 'td' }, item[1] + (name === currentMode ? ' (' + _('active') + ')' : '')),
					E('td', { 'class': 'td' }, saved ? _('Yes') : _('No')),
					E('td', { 'class': 'td' }, rankCell),
					E('td', { 'class': 'td' }, actions)
				]));
			});
		}
		function controls(items) { return E('div', {}, items.map(function(item) { return button(item[0], function() { execute(item[1], item[2]); }); })); }
		var page = E('div', { 'class': 'cbi-map' }, [
			E('h2', {}, _('MX4200 Manager')),
			E('p', {}, _('View status and control saved modes, USB tethering, backhaul and LEDs. The original mx menu remains available in the browser terminal.')),
			section(_('Current status'), _('Refresh after an uplink or mode change.'), E('div', {}, [ status, button(_('Refresh'), refresh) ])),
			section(_('Mode profiles'), _('Priority 1 is highest; 0 disables automatic switching. Restoring a profile may change this page’s IP address.'), E('div', {}, [ profileTable, button(_('Save current mode'), function() { execute('save_current'); }) ])),
			section(_('Guided setup'), _('The MX Dashboard has native setup forms for router, WDS, routed repeater and wired AP. The offline mx menu remains available in the browser terminal.'), E('div', {}, [ E('a', { 'href': L.url('admin/mx4200') }, _('Open MX Dashboard')), E('p', {}, [ terminalLink(), ' · Run: mx, mxrepeater, mxap, mxusb, or mxhelp' ]) ])),
			section(_('USB tethering'), _('The connected phone supplies addressing by DHCP. Primary and backup change route metrics.'), controls([ [ _('Detect USB'), 'usb_detect' ], [ _('Primary'), 'usb_primary', true ], [ _('Backup'), 'usb_backup', true ], [ _('Off'), 'usb_off', true ] ])),
			section(_('Wi-Fi backhaul'), _('Repeater modes use radio2 5 GHz as primary and optional radio1 2.4 GHz as backup.'), controls([ [ _('Automatic'), 'backhaul_auto', true ], [ _('5 GHz only'), 'backhaul_primary', true ], [ _('2.4 GHz only'), 'backhaul_backup', true ] ])),
			section(_('Automatic mode switching'), _('Saved priorities can fail over and fail back; a manual trial may interrupt clients.'), controls([ [ _('Show priorities'), 'auto_status' ], [ _('Run one decision'), 'auto_once', true ] ])),
			section(_('Diagnostics'), _('Inspect WDS/DNS and current LED state.'), controls([ [ _('WDS/DNS test'), 'wds_test' ], [ _('LED state'), 'led_state' ], [ _('Detect LED'), 'led_detect' ] ])),
			section(_('LED control'), _('Install the optional module when Internet is available, or return to automatic color control.'), controls([ [ _('Install LED'), 'led_install' ], [ _('Automatic'), 'led_auto' ], [ _('Red'), 'led_red' ], [ _('Green'), 'led_green' ], [ _('Blue'), 'led_blue' ], [ _('Purple'), 'led_purple' ], [ _('Orange'), 'led_orange' ], [ _('Yellow'), 'led_yellow' ], [ _('Teal'), 'led_teal' ], [ _('White'), 'led_white' ], [ _('Off'), 'led_off' ] ])),
			section(_('Result'), _('Messages from the last action appear here.'), result)
		]);
		drawProfiles(data[1]);
		return page;
	},
	handleSave: null,
	handleSaveApply: null,
	handleReset: null
});
EOF_JS
cat > /www/luci-static/resources/view/mx4200/dashboard.js <<'EOF_DASH'
'use strict';
'require rpc';
'require view';

var overview = rpc.declare({ object: 'mx.ui', method: 'overview' });
var profiles = rpc.declare({ object: 'mx.ui', method: 'profiles' });
var logs = rpc.declare({ object: 'mx.ui', method: 'logs', params: [ 'source' ] });
var scanStatus = rpc.declare({ object: 'mx.ui', method: 'scan_status', params: [ 'band' ] });
var submitSetup = rpc.declare({ object: 'mx.ui', method: 'setup', params: [ 'config' ] });
var setupStatus = rpc.declare({ object: 'mx.ui', method: 'setup_status' });
var action = rpc.declare({ object: 'mx.ui', method: 'action', params: [ 'name' ] });
var priority = rpc.declare({ object: 'mx.ui', method: 'priority', params: [ 'mode', 'value' ] });
var names = { overview: 'Overview', setup: 'Set up Internet', internet: 'Internet', wireless: 'Wireless', clients: 'Clients', vpn: 'VPN', led: 'LED', logs: 'Logs', system: 'Advanced settings', controls: 'Controls' };
var loadError = false;
function loadStylesheet() {
	if (document.getElementById('mx-dashboard-style')) return;
	var link = document.createElement('link');
	link.id = 'mx-dashboard-style';
	link.rel = 'stylesheet';
	link.href = L.resource('mx4200/dashboard.css') + '?v=5';
	link.onerror = function() {
		var fallback = document.createElement('style');
		fallback.textContent = '.mx-dashboard{display:grid;grid-template-areas:"top top" "side main";grid-template-columns:205px minmax(0,1fr);max-width:1600px;margin:0 auto;background:#eef0f7;color:#252b52;font:14px sans-serif}.mx-global{grid-area:top;background:white;padding:12px;display:flex;justify-content:space-between}.mx-side{grid-area:side;background:#13172d;color:white;padding:20px}.mx-side nav{display:grid;gap:8px}.mx-nav{padding:10px}.mx-main{grid-area:main;padding:24px}.mx-grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(220px,1fr));gap:16px}.mx-card{background:white;padding:16px;margin:12px 0;border-radius:8px}.mx-card-head{font-weight:bold}.mx-table{width:100%}.mx-hero{background:#201861;color:white;padding:30px;display:flex;justify-content:space-around}@media(max-width:700px){.mx-dashboard{grid-template-areas:"top" "side" "main";grid-template-columns:1fr}}';
		document.head.appendChild(fallback);
	};
	document.head.appendChild(link);
}

function value(v, fallback) { return v === undefined || v === null || v === '' ? (fallback || '—') : String(v); }
function chip(label, state) { return E('span', { 'class': 'mx-chip ' + (state || '') }, label); }
function button(label, callback, style) { return E('button', { 'class': 'mx-btn ' + (style || ''), 'type': 'button', 'click': callback }, label); }
function link(label, path) { return E('a', { 'href': L.url.apply(L, path.split('/')) }, label); }
function card(title, body, extra) { return E('section', { 'class': 'mx-card' }, [ E('div', { 'class': 'mx-card-head' }, [ E('h3', {}, title), extra || '' ]), E('div', { 'class': 'mx-card-body' }, body) ]); }
function pair(label, data) { return E('div', { 'class': 'mx-kv' }, [ E('span', {}, label), E('strong', {}, value(data)) ]); }
function table(headers, rows) { return E('div', { 'class': 'mx-table-wrap' }, E('table', { 'class': 'mx-table' }, [ E('thead', {}, E('tr', {}, headers.map(function(h) { return E('th', {}, h); }))), E('tbody', {}, rows.length ? rows.map(function(row) { return E('tr', {}, row.map(function(cell) { return E('td', {}, cell); })); }) : E('tr', {}, E('td', { 'colspan': String(headers.length), 'class': 'mx-empty' }, _('No data reported.')))) ])); }
function percent(n) { return Math.max(0, Math.min(100, n)); }
function usage(label, used, total) { var p = total > 0 ? percent(Math.round(100 * used / total)) : 0; return E('div', {}, [ pair(label, p + '%'), E('div', { 'class': 'mx-meter' }, E('i', { 'style': 'width:' + p + '%' })) ]); }
function stat(label, main, detail, state) { return E('div', { 'class': 'mx-card mx-stat' }, [ E('div', { 'class': 'mx-stat-label' }, label), E('div', { 'class': 'mx-stat-value' }, main), E('div', { 'class': 'mx-stat-detail' }, [ state ? E('span', { 'class': 'mx-dot ' + state }) : '', detail ]) ]); }
function sectionTitle(title) { return E('h3', { 'class': 'mx-section-title' }, title); }
function terminalLink() { return E('a', { 'href': L.url('admin/services/ttyd/ttyd'), 'target': '_blank', 'rel': 'noopener noreferrer' }, _('Open browser terminal')); }
function formatUptime(seconds) { var s = Number(seconds) || 0; return Math.floor(s / 86400) + 'd ' + Math.floor(s % 86400 / 3600) + 'h ' + Math.floor(s % 3600 / 60) + 'm'; }
function formatBytes(bytes) { var n = Number(bytes); if (!isFinite(n) || n < 0) return '—'; var u = [ 'B', 'KiB', 'MiB', 'GiB', 'TiB' ], i = 0; while (n >= 1024 && i < u.length - 1) { n /= 1024; i++; } return n.toFixed(i ? 1 : 0) + ' ' + u[i]; }
function regularLuciLink() { return E('a', { 'class': 'mx-btn primary', 'href': L.url('admin/status/overview'), 'target': '_blank', 'rel': 'noopener noreferrer' }, _('Open in LuCI')); }
function logoutLink() { return E('a', { 'class': 'mx-btn', 'href': L.url('admin/logout') }, _('Log out')); }

return view.extend({
	load: function() {
		loadStylesheet();
		return Promise.all([ overview().catch(function() { loadError = true; return {}; }), profiles().catch(function() { loadError = true; return {}; }) ]);
	},
	render: function(initial) {
		var data = initial[0] || {}, saved = initial[1] || {}, selected = 'overview', busy = false;
		var scans = { radio1: {}, radio2: {} }, logSource = 'system';
		var setupData = { mode: data.mode || 'router', priority: '0', wan_port: 'lan', wan_preference: 'wifi', primary_bssid: '', primary_security: 'auto', primary_password: '', backup_bssid: '', backup_security: 'auto', backup_password: '', backup_same: false, client_ssid: '', client_password: '', ap_ssid: 'LS-MX4200v2', ap_security: 'none', ap_password: '', management_password: '' };
		var content = E('div'), nav = E('nav'), result = E('div', { 'class': 'mx-result', 'hidden': true });
		var subtitle = E('p', { 'class': 'mx-sub' }, _('Live status and controls for your MX4200 V2/P2.'));
		var title = E('h2', {}, _('Overview'));
		var refreshButton = button(_('Refresh'), refresh);
		var page = E('div', { 'class': 'mx-dashboard' }, [
			E('header', { 'class': 'mx-global' }, [ E('div', { 'class': 'mx-global-brand' }, [ E('strong', {}, 'MX4200'), E('span', {}, '|'), E('span', {}, _('OpenWrt Dashboard')) ]), E('div', { 'class': 'mx-global-actions' }, [ chip(_('Local dashboard'), 'info'), refreshButton, regularLuciLink(), logoutLink() ]) ]),
			E('aside', { 'class': 'mx-side' }, [ nav, E('div', { 'class': 'mx-side-note' }, _('Core modes work without Internet.')) ]),
			E('main', { 'class': 'mx-main' }, [ E('header', { 'class': 'mx-head' }, [ title, subtitle ]), content, result ])
		]);

		function notice(message, ok) { result.hidden = false; result.textContent = message; result.style.borderColor = ok ? '#9cdece' : '#e2a5b2'; }
		function run(name, disruptive) {
			if (busy || disruptive && !window.confirm(_('This may interrupt clients or change the router address. Continue?'))) return;
			busy = true; notice(_('Working…'), true);
			return action(name).then(function(response) {
				notice(value(response.message, _('No response.')), !!response.ok);
				if (name === 'ui_update' && response.ok) { window.location.reload(); return; }
				if (response.ok) return refresh();
			}).catch(function(error) { notice(_('Action failed or connection changed. Reconnect and refresh if needed.') + '\n' + String(error), false); }).finally(function() { busy = false; });
		}
		function refresh() {
			refreshButton.disabled = true;
			return Promise.all([ overview(), profiles() ]).then(function(values) {
				data = values[0] || {}; saved = values[1] || {}; draw();
			}).catch(function(error) { notice(_('Could not refresh status: ') + String(error), false); }).finally(function() { refreshButton.disabled = false; });
		}
		function navItem(key) { return E('button', { 'class': 'mx-nav' + (key === selected ? ' active' : ''), 'type': 'button', 'click': function() { selected = key; draw(); if (key === 'wireless' || key === 'setup') { loadScan('radio2'); loadScan('radio1'); } } }, names[key]); }
		function loadScan(band) { return scanStatus(band).then(function(response) { scans[band] = response || {}; if (selected === 'wireless' || selected === 'setup') draw(); if ((selected === 'wireless' || selected === 'setup') && response && response.state === 'running') window.setTimeout(function() { if (selected === 'wireless' || selected === 'setup') loadScan(band); }, 5000); }).catch(function(error) { notice(_('Scan status unavailable: ') + String(error), false); }); }
		function startScan(band) { if (!window.confirm(_('Scanning can briefly interrupt an active Wi-Fi backhaul. Continue?'))) return; var task = run(band === 'radio2' ? 'scan_5g' : 'scan_2g'); if (task) return task.then(function() { loadScan(band); }); }
		function uplinkRows() { return (data.uplinks || []).map(function(u) {
			var status = u.up ? chip(_('Connected'), 'ok') : chip(_('Unavailable'), 'bad');
			return [ E('span', {}, [ E('span', { 'class': 'mx-dot ' + (u.selected ? 'active' : u.up ? 'up' : 'down') }), u.label ]), status, value(u.address), value(u.protocol), value(u.signal), u.metric ? String(u.metric) : '—', u.selected ? chip(_('Active route'), 'info') : '—' ];
		}); }
		function uplinkTable() { return table([ _('Uplink'), _('Link'), _('IPv4'), _('Protocol'), _('Signal'), _('Metric'), _('Route') ], uplinkRows()); }
		function uplinkDetails() { return E('div', { 'class': 'mx-grid' }, (data.uplinks || []).map(function(u) { return card(u.label, [ pair(_('Link'), u.up ? _('Connected') : _('Unavailable')), pair(_('IPv4'), u.address), pair(_('Device'), u.device), pair(_('DNS'), u.dns), pair(_('BSSID'), u.bssid), pair(_('Signal'), u.signal), pair(_('Received'), formatBytes(u.rx_bytes)), pair(_('Sent'), formatBytes(u.tx_bytes)) ]); })); }
		function findUplink(id) { return (data.uplinks || []).filter(function(u) { return u.id === id; })[0] || null; }
		function openSetup() { selected = 'setup'; draw(); loadScan('radio2'); loadScan('radio1'); }
		function overviewHero() {
			var sources = [ [ 'ethernet', _('Ethernet WAN') ], [ 'wifi5', _('5 GHz repeater') ], [ 'wifi2', _('2.4 GHz backup') ], [ 'usb', _('USB tethering') ] ];
			return E('section', { 'class': 'mx-hero' }, [
				E('div', { 'class': 'mx-hero-sources' }, sources.map(function(item) { var u = findUplink(item[0]); return E('div', { 'class': 'mx-hero-source' + (u && u.up ? ' online' : '') + (u && u.selected ? ' chosen' : '') }, [ E('span', { 'class': 'mx-hero-light' }), E('span', {}, item[1]), E('span', { 'class': 'mx-hero-rule' }) ]); })),
				E('div', { 'class': 'mx-hero-center' }, [ E('div', { 'class': 'mx-router-art' }, [ E('div', { 'class': 'mx-router-top' }), E('div', { 'class': 'mx-router-face' }, [ E('span', {}, 'MX'), E('i') ]) ]), E('strong', {}, value(data.hostname, 'MX4200')), E('small', {}, _('Linksys MX4200 V2/P2') + ' · ' + value(data.mode)), E('div', { 'class': 'mx-hero-badges' }, [ E('span', {}, data.internet_probe ? _('● Internet online') : _('● Internet check failed')), E('span', {}, _('↔ ') + value(data.backhaul, _('Automatic backhaul'))) ]) ]),
				E('div', { 'class': 'mx-hero-clients' }, [ E('div', { 'class': 'mx-hero-client' }, [ E('strong', {}, String(data.client_count || 0)), E('span', {}, _('Local DHCP clients')) ]), E('div', { 'class': 'mx-hero-client' }, [ E('strong', {}, value(data.lan_address, '—')), E('span', {}, _('LAN address')) ]), E('small', {}, _('AP/WDS clients using upstream DHCP may not appear here.')) ])
			]);
		}
		function overviewLinkCard(title, u, kind, actionLabel, actionFn) {
			var online = !!(u && u.up), details = [ pair(_('Status'), online ? _('Connected') : _('Unavailable')), pair(_('Protocol'), u && u.protocol), pair(_('IP address'), u && u.address) ];
			if (kind === 'wifi') details.push(pair(_('BSSID'), u && u.bssid), pair(_('Signal'), u && u.signal));
			else details.push(pair(_('Gateway'), data.gateway));
			if (u && u.dns) details.push(pair(_('DNS server'), u.dns));
			return E('section', { 'class': 'mx-card mx-link-card' }, [ E('div', { 'class': 'mx-card-head' }, [ E('h3', {}, [ E('span', { 'class': 'mx-dot ' + (online ? 'active' : 'down') }), title ]), chip(u && u.selected ? _('Active route') : online ? _('Connected') : _('Unavailable'), online ? 'ok' : 'bad') ]), E('div', { 'class': 'mx-link-body' }, [ E('div', { 'class': 'mx-link-details' }, [ E('div', { 'class': 'mx-link-pairs' }, details), E('div', { 'class': 'mx-link-actions' }, button(actionLabel, actionFn)) ]), E('div', { 'class': 'mx-link-symbol ' + kind }, kind === 'wifi' ? 'Wi-Fi' : kind === 'usb' ? 'USB' : '↔') ]) ]);
		}
		function overviewPage() {
			var wan = findUplink('ethernet'), primary = findUplink('wifi5'), backup = findUplink('wifi2'), usb = findUplink('usb');
			var mtotal = Number(data.memory_total) || 0, mavail = Number(data.memory_available) || 0;
			var temp = Number(data.temperature) || 0;
			return [ overviewHero(), E('div', { 'class': 'mx-overview-content' }, [
				overviewLinkCard(_('Ethernet WAN'), wan, 'ethernet', _('Configure Internet'), openSetup),
				overviewLinkCard(_('5 GHz repeater · radio2'), primary, 'wifi', _('Choose Wi-Fi network'), openSetup),
				E('div', { 'class': 'mx-grid' }, [ overviewLinkCard(_('2.4 GHz backup · radio1'), backup, 'wifi', _('Backhaul settings'), function() { selected = 'wireless'; draw(); }), overviewLinkCard(_('USB tethering'), usb, 'usb', _('USB controls'), function() { selected = 'controls'; draw(); }) ]),
				E('div', { 'class': 'mx-grid' }, [ card(_('Router health'), [ pair(_('Uptime'), formatUptime(data.uptime)), pair(_('CPU load · 1 / 5 / 15 min'), data.load), pair(_('Temperature'), temp ? (temp / 1000).toFixed(1) + ' °C' : '—'), pair(_('LED'), data.led_state) ]), card(_('Memory and access'), [ usage(_('Memory used'), mtotal - mavail, mtotal), pair(_('Mode'), data.mode), pair(_('OpenWrt'), data.release), E('div', { 'class': 'mx-space' }), regularLuciLink() ]) ])
			]) ];
		}
		function setupRow(label, control, hint) { return E('div', { 'class': 'mx-form-row' }, [ E('label', {}, label), E('div', {}, [ control, hint ? E('small', { 'class': 'mx-muted' }, hint) : '' ]) ]); }
		function setupInput(label, key, type, hint) {
			return setupRow(label, E('input', { 'class': 'mx-search', 'type': type || 'text', 'value': setupData[key] || '', 'autocomplete': type === 'password' ? 'new-password' : 'off', 'input': function(ev) { setupData[key] = ev.target.value; } }), hint);
		}
		function setupSelect(label, key, choices, hint) {
			var el = E('select', { 'class': 'mx-search', 'change': function(ev) { setupData[key] = ev.target.value; draw(); } }, choices.map(function(pair) { return E('option', { 'value': pair[0] }, pair[1]); }));
			el.value = String(setupData[key] || '');
			return setupRow(label, el, hint);
		}
		function setupScan(band, key, label) {
			var s = scans[band] || {}, choices = [ [ '', _('Choose a scanned network') ] ];
			(s.networks || []).forEach(function(n) { choices.push([ n.bssid, n.ssid + ' · ch ' + n.channel + ' · ' + n.signal + ' dBm · ' + n.security ]); });
			return card(label, [ setupSelect(_('Network'), key, choices, _('The BSSID and channel come from this router’s scan; your router’s own BSSIDs are excluded.')), E('div', { 'class': 'mx-controls' }, [ button(_('Scan'), function() { startScan(band); }, 'primary'), chip(value(s.state, _('Not scanned')), s.state === 'ready' ? 'ok' : 'info') ]) ]);
		}
		function setupSecurity(key, label) { return setupSelect(label, key, [ [ 'auto', _('Use scan result') ], [ 'psk2', _('WPA2-PSK (confirm ambiguous WPA scan)') ], [ 'psk', _('Legacy WPA1-PSK') ] ], _('If the scan says only “WPA PSK”, confirm WPA1 or WPA2 explicitly.')); }
		function pollSetup() {
			return setupStatus().then(function(s) {
				if (s.state === 'running') { notice(_('Applying setup; the router may change address. Reconnect if this page stops responding.'), true); window.setTimeout(pollSetup, 4000); }
				else if (s.state === 'ready') { notice(_('Setup applied. Refresh or reconnect at the router’s new address.'), true); refresh(); }
				else notice(_('Setup failed; the previous configuration was restored.'), false);
			}).catch(function() { notice(_('Connection changed. Reconnect and check MX status.'), false); });
		}
		function applySetup() {
			if (busy || !window.confirm(_('Apply this network setup? Clients may disconnect, and the router address may change.'))) return;
			busy = true;notice(_('Validating setup…'), true);
			var config = Object.assign({}, setupData, { backup_same: setupData.backup_same ? '1' : '0' });
			return submitSetup(config).then(function(reply) {
				notice(value(reply.message), !!reply.ok);
				if (reply.ok) { setupData.primary_password = setupData.backup_password = setupData.client_password = setupData.ap_password = setupData.management_password = ''; draw(); pollSetup(); }
			}).catch(function(error) { notice(_('Setup request failed: ') + String(error), false); }).finally(function() { busy = false; });
		}
		function setupPage() {
			var mode = setupData.mode, fields = [ setupSelect(_('Device mode'), 'mode', [ [ 'router', _('Router — own DHCP and NAT') ], [ 'repeater', _('Routed repeater — Wi-Fi uplink, own DHCP') ], [ 'wds', _('WDS repeater — upstream DHCP') ], [ 'ap', _('Wired AP — Ethernet uplink, upstream DHCP') ] ], _('The router, repeater, WDS, and wired-AP paths remain available offline through mx.')) ];
			if (mode === 'router' || mode === 'ap') {
				fields.push(setupInput(_('Wi-Fi name'), 'ap_ssid', 'text', _('One name across the radios. Router mode adds -5GHz and -Max.')));
				fields.push(setupSelect(_('Wi-Fi security'), 'ap_security', [ [ 'none', _('Open') ], [ 'psk2', _('WPA2-PSK') ], [ 'sae-mixed', _('WPA2/WPA3 mixed') ], [ 'sae', _('WPA3-SAE') ] ]));
				if (setupData.ap_security !== 'none') fields.push(setupInput(_('Wi-Fi password'), 'ap_password', 'password', _('8–63 bytes; entered only on this router.')));
				if (mode === 'ap') fields.push(setupInput(_('Management Wi-Fi password'), 'management_password', 'password', _('Separate isolated Management SSID; all Ethernet sockets, including WAN, become LAN.')));
				else fields.push(E('p', { 'class': 'mx-note' }, _('Router mode uses WAN DHCP, LAN 192.168.40.1/24, and this router’s DHCP server.')));
			} else {
				fields.push(E('div', { 'class': 'mx-grid' }, [ setupScan('radio2', 'primary_bssid', _('Primary · 5 GHz radio2')), setupScan('radio1', 'backup_bssid', _('Optional backup · 2.4 GHz radio1')) ]));
				fields.push(setupSecurity('primary_security', _('5 GHz security')));
				fields.push(setupInput(_('5 GHz upstream password'), 'primary_password', 'password', _('Leave empty only for an open or OWE network.')));
				if (setupData.backup_bssid) {
					fields.push(setupSecurity('backup_security', _('Backup security')));
					var samePassword = E('input', { 'type': 'checkbox', 'change': function(ev) { setupData.backup_same = ev.target.checked; draw(); } });
					samePassword.checked = setupData.backup_same;
					fields.push(setupRow(_('Use same upstream password'), samePassword, _('Available when both bands use the same SSID.')));
					if (!setupData.backup_same) fields.push(setupInput(_('2.4 GHz upstream password'), 'backup_password', 'password'));
				}
				fields.push(setupInput(_('Client Wi-Fi name'), 'client_ssid', 'text', _('The router broadcasts this name with -RPT-5G and -RPT-2G.')));
				fields.push(setupInput(_('Client Wi-Fi password'), 'client_password', 'password', _('Client security matches the selected upstream security. Leave empty only for an open/OWE upstream.')));
				if (mode === 'wds') {
					fields.push(setupInput(_('Management Wi-Fi password'), 'management_password', 'password', _('Management uses a separate local address and DHCP server. WDS requires upstream 4-address support.')));
				} else {
					fields.push(setupSelect(_('WAN socket'), 'wan_port', [ [ 'lan', _('Client LAN port') ], [ 'wan', _('Wired WAN uplink') ] ]));
					if (setupData.wan_port === 'wan') fields.push(setupSelect(_('Preferred uplink'), 'wan_preference', [ [ 'wifi', _('Wi-Fi repeater first') ], [ 'wan', _('Wired WAN first') ] ], _('The other uplink remains available for failover.')));
				}
			}
			var ranks = [ [ '0', _('0 · manual only') ] ];
			for (var i = 1; i <= 9; i++) ranks.push([ String(i), String(i) + (i === 1 ? _(' · highest') : '') ]);
			fields.push(setupSelect(_('Automatic mode priority'), 'priority', ranks, _('Priority 1 is highest; 0 excludes this saved mode from automatic switching.')));
			fields.push(E('div', { 'class': 'mx-controls' }, [ button(_('Apply setup'), applySetup, 'primary'), terminalLink() ]));
			return [ card(_('Native MX4200 setup'), [ E('p', { 'class': 'mx-note' }, _('Configure this MX4200 directly. Network addresses for wired, Wi-Fi, and USB uplinks come from DHCP; no upstream subnet is assumed. Use HTTPS when entering passwords.')), E('div', { 'class': 'mx-space' }) ].concat(fields)), E('p', { 'class': 'mx-sub' }, _('If configuration commands fail, the previous settings are restored. Wrong upstream credentials or unsupported WDS may still leave the new mode without Internet; use Management Wi-Fi or mx to recover.')) ];
		}
		function internetPage() { return [ card(_('Interface status'), [ E('p', { 'class': 'mx-note' }, _('These are the existing MX uplinks. The firmware selects one route by priority and health; it does not load-balance traffic.')), E('div', { 'class': 'mx-space' }), uplinkTable() ]), sectionTitle(_('Interface details')), uplinkDetails(), sectionTitle(_('Routing')), E('div', { 'class': 'mx-grid' }, [ card(_('Active IPv4 route'), [ pair(_('Device'), data.route_device), pair(_('Gateway'), data.gateway), pair(_('Internet probe'), data.internet_probe ? _('Passed') : _('No response')) ]), card(_('WAN socket and management'), [ pair(_('WAN socket'), data.wan_socket === 'none' ? _('Client LAN port') : _('Wired uplink')), pair(_('Repeater preference'), data.wan_preference), pair(_('LAN address'), data.lan_address), pair(_('Isolated management'), data.management_address) ]) ]), sectionTitle(_('Saved mode priorities')), profileTable(), E('p', { 'class': 'mx-sub' }, _('Priority 1 is highest; 0 excludes a saved mode from automatic switching. Changing modes can disconnect this browser.')) ]; }
		function profileTable() {
			var p = saved.profiles || {};
			return card(_('Failover and failback'), table([ _('Mode'), _('Saved'), _('Priority'), _('Action') ], [ [ 'router', _('Router') ], [ 'router-baseline', _('First-boot router baseline') ], [ 'repeater', _('Routed repeater') ], [ 'wds', _('WDS repeater') ], [ 'ap', _('Wired AP') ] ].map(function(entry) {
				var key = entry[0], item = p[key] || {}, rank = E('select', { 'class': 'mx-search' });
				for (var n = 0; n <= 9; n++) rank.appendChild(E('option', { 'value': String(n) }, String(n)));
				rank.value = String(item.priority || 0);
				var priorityCell = key === 'router-baseline' ? '—' : E('div', { 'class': 'mx-controls' }, [ rank, button(_('Save'), function() { priority(key, Number(rank.value)).then(function(reply) { notice(value(reply.message), !!reply.ok); if (reply.ok) refresh(); }).catch(function(e) { notice(String(e), false); }); }) ]);
				return [ entry[1] + (data.mode === key ? ' · ' + _('active') : ''), item.saved ? _('Yes') : _('No'), priorityCell, item.saved ? button(_('Restore'), function() { run('profile_' + key.replace('-', '_'), true); }) : '—' ];
			})), E('div', { 'class': 'mx-controls' }, [ button(_('Save current mode'), function() { run('save_current'); }), link(_('Full manager'), 'admin/services/mx4200') ]));
		}
		function scanCard(band, label) {
			var s = scans[band] || {}, rows = (s.networks || []).map(function(n) { return [ n.ssid, n.channel, n.signal + ' dBm', n.security, n.bssid ]; });
			return card(label, [ E('div', { 'class': 'mx-controls' }, [ button(_('Scan now'), function() { startScan(band); }, 'primary'), button(_('Refresh results'), function() { loadScan(band); }), chip(value(s.state, _('Not scanned')), s.state === 'ready' ? 'ok' : 'info') ]), E('div', { 'class': 'mx-space' }), s.state === 'running' ? E('p', {}, _('Scanning; DFS channels can take longer.')) : '', table([ _('SSID'), _('Channel'), _('Signal'), _('Security'), _('BSSID') ], rows) ]);
		}
		function wirelessPage() {
			var w = data.wifi || {};
			return [ card(_('Backhaul'), [ pair(_('5 GHz · radio2 · 4×4'), value(w.mx_primary, _('Not configured'))), pair(_('2.4 GHz · radio1 · backup'), value(w.mx_backup, _('Not configured'))), pair(_('Current backhaul'), data.backhaul), E('div', { 'class': 'mx-space' }), E('div', { 'class': 'mx-controls' }, [ button(_('Automatic'), function() { run('backhaul_auto', true); }), button(_('5 GHz only'), function() { run('backhaul_primary', true); }), button(_('2.4 GHz only'), function() { run('backhaul_backup', true); }) ]) ]), sectionTitle(_('Broadcast networks')), E('div', { 'class': 'mx-grid' }, [ card(_('2.4 GHz'), [ pair(_('SSID'), w.mx_ap2), pair(_('Management SSID'), w.mx_mgmt) ]), card(_('5 GHz'), [ pair(_('5 GHz 2×2'), w.mx_ap5), pair(_('5 GHz 4×4'), w.mx_ap_high) ]) ]), sectionTitle(_('Nearby networks')), E('p', { 'class': 'mx-sub' }, _('Scans reuse the offline MX scanner and exclude this router’s own BSSIDs. Scanning may briefly affect an active Wi-Fi backhaul.')), E('div', { 'class': 'mx-grid' }, [ scanCard('radio2', _('5 GHz · radio2')), scanCard('radio1', _('2.4 GHz · radio1')) ]), sectionTitle(_('Join Wi-Fi')), card(_('Native repeater setup'), [ E('p', {}, _('Use Set up Internet to choose an upstream network and configure WDS or routed repeater.')), E('div', { 'class': 'mx-space' }), E('div', { 'class': 'mx-controls' }, [ button(_('Open setup'), function() { selected = 'setup';draw();loadScan('radio2');loadScan('radio1'); }, 'primary'), terminalLink() ]) ]) ];
		}
		function clientsPage() { return [ card(_('Local DHCP leases'), [ E('p', { 'class': 'mx-note' }, _('Only clients receiving a lease from this router appear here. In wired AP and WDS modes, the upstream router manages DHCP leases.')), E('div', { 'class': 'mx-space' }), table([ _('Name'), _('IPv4'), _('MAC') ], (data.clients || []).map(function(c) { return [ value(c.name, _('Unknown')), c.address, c.mac ]; })) ]) ]; }
		function vpnPage() { return [ E('div', { 'class': 'mx-grid' }, [ card(_('Tailscale'), [ pair(_('State'), data.tailscale_state), pair(_('Router IP'), data.tailscale_ip), E('div', { 'class': 'mx-space' }), link(_('Open Tailscale settings'), 'admin/vpn/tailscale') ]), card(_('WireGuard and OpenVPN'), [ pair(_('WireGuard interfaces'), data.wireguard), pair(_('OpenVPN process'), data.openvpn ? _('Running') : _('Not running')), E('div', { 'class': 'mx-space' }), link(_('Open VPN settings'), 'admin/vpn') ]) ]) ]; }
		function ledPage() { return [ card(_('LED control'), [ pair(_('Current state'), data.led_state), E('p', { 'class': 'mx-muted' }, _('Advanced LED control is an optional module. Once installed, it runs locally on every boot.')), E('div', { 'class': 'mx-space' }), E('div', { 'class': 'mx-controls' }, [ button(_('Install module'), function() { run('led_install'); }, 'primary'), button(_('Automatic'), function() { run('led_auto'); }, 'accent') ].concat([ 'red', 'green', 'blue', 'purple', 'orange', 'yellow', 'teal', 'white', 'off' ].map(function(color) { return button(color.charAt(0).toUpperCase() + color.slice(1), function() { run('led_' + color); }); }))) ]) ]; }
		function logsPage() {
			var text = E('div', { 'class': 'mx-log' }, _('Loading…'));
			var search = E('input', { 'class': 'mx-search', 'type': 'search', 'placeholder': _('Filter displayed log lines') });
			var raw = '';
			function filter() { var q = search.value.toLowerCase(); text.textContent = raw.split('\n').filter(function(line) { return line.toLowerCase().indexOf(q) >= 0; }).join('\n') || _('No matching lines.'); }
			search.addEventListener('input', filter);
			function reload() { return logs(logSource).then(function(reply) { raw = reply && reply.lines || ''; filter(); }).catch(function(error) { text.textContent = String(error); }); }
			reload();
			return [ card(_('Recent logs · last 120 lines'), [ E('div', { 'class': 'mx-controls' }, [ button(_('System'), function() { logSource = 'system'; draw(); }, logSource === 'system' ? 'primary' : ''), button(_('Kernel'), function() { logSource = 'kernel'; draw(); }, logSource === 'kernel' ? 'primary' : ''), search, button(_('Refresh logs'), reload) ]), E('div', { 'class': 'mx-space' }), text ]) ];
		}
		function systemPage() { return [ card(_('Regular OpenWrt settings'), [ E('p', {}, _('Open the standard LuCI interface in a new tab. Both views use the same router settings.')), E('div', { 'class': 'mx-space' }), regularLuciLink(), E('div', { 'class': 'mx-space' }), button(_('Update MX dashboard'), function() { run('ui_update'); }, 'primary'), E('p', { 'class': 'mx-muted' }, _('Checks the signed release. Reload this page after a successful update.')) ]), sectionTitle(_('Device and access')), E('div', { 'class': 'mx-grid' }, [ card(_('Device'), [ pair(_('Hostname'), data.hostname), pair(_('Model'), data.model), pair(_('OpenWrt'), data.release), pair(_('Kernel'), data.kernel), pair(_('CPU cores'), data.cpu_cores), pair(_('Mode'), data.mode), pair(_('Uptime'), formatUptime(data.uptime)) ]), card(_('Admin access'), [ pair(_('SSH port'), value(data.ssh_port, '22')), pair(_('HTTP listener'), data.http_listen), pair(_('HTTPS listener'), data.https_listen), E('p', { 'class': 'mx-muted' }, _('Firewall rules determine whether access is allowed from an uplink.')) ]) ]) ]; }
		function controlsPage() { return [ card(_('MX mode controls'), [ E('p', {}, _('Use Set up Internet for a new router, WDS, routed repeater, or wired AP configuration. The SSH mx menu remains available offline.')), E('div', { 'class': 'mx-space' }), E('div', { 'class': 'mx-controls' }, [ button(_('Open native setup'), function() { selected = 'setup';draw();loadScan('radio2');loadScan('radio1'); }, 'primary'), link(_('Open MX Manager'), 'admin/services/mx4200'), terminalLink() ]) ]), sectionTitle(_('USB tethering')), card(_('Connected phone'), E('div', { 'class': 'mx-controls' }, [ button(_('Detect USB'), function() { run('usb_detect'); }), button(_('Primary'), function() { run('usb_primary', true); }), button(_('Backup'), function() { run('usb_backup', true); }), button(_('Off'), function() { run('usb_off', true); }) ])), sectionTitle(_('Diagnostics')), card(_('Local checks'), E('div', { 'class': 'mx-controls' }, [ button(_('WDS/DNS test'), function() { run('wds_test'); }), button(_('Auto priorities'), function() { run('auto_status'); }), button(_('One mode decision'), function() { run('auto_once', true); }) ])) ]; }
		function draw() {
			page.className = 'mx-dashboard mx-page-' + selected;
			nav.replaceChildren.apply(nav, Object.keys(names).map(navItem));
			title.textContent = _(names[selected]);
			var views = { overview: overviewPage, setup: setupPage, internet: internetPage, wireless: wirelessPage, clients: clientsPage, vpn: vpnPage, led: ledPage, logs: logsPage, system: systemPage, controls: controlsPage };
			content.replaceChildren.apply(content, views[selected]());
		}
		draw();
		if (loadError) notice(_('MX status is temporarily unavailable. Check that rpcd is running, then refresh this page.'), false);
		return page;
	},
	handleSave: null,
	handleSaveApply: null,
	handleReset: null
});
EOF_DASH
mkdir -p /www/luci-static/resources/mx4200
cat > /www/luci-static/resources/mx4200/dashboard.css <<'EOF_CSS'
body:has(.mx-dashboard){padding:0!important;margin:0!important;background:#eef0f7}body:has(.mx-dashboard)>header,body:has(.mx-dashboard)>footer,body:has(.mx-dashboard) #tabmenu{display:none!important}body:has(.mx-dashboard) #maincontent{width:100%;max-width:none;margin:0;padding:0}body:has(.mx-dashboard) .mx-dashboard{min-height:100vh;max-width:1600px;margin:0 auto;border-radius:0;box-shadow:none}
.mx-dashboard{--mx-ink:#252b52;--mx-muted:#68708c;--mx-cyan:#00b9cd;--mx-blue:#5672ed;--mx-card:#fff;--mx-bg:#eef0f7;--mx-line:#dfe3ee;color:var(--mx-ink);background:var(--mx-bg);font:14px/1.45 -apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif;min-height:calc(100vh - 8rem);border-radius:14px;overflow:hidden;display:grid;grid-template-columns:205px minmax(0,1fr);box-shadow:0 12px 35px rgba(16,22,58,.12)}
.mx-dashboard *{box-sizing:border-box}.mx-dashboard a{color:#3061d4}.mx-dashboard button{cursor:pointer;font:inherit}.mx-dashboard h2,.mx-dashboard h3,.mx-dashboard h4,.mx-dashboard p{margin:0}.mx-dashboard h2{font-size:23px}.mx-dashboard h3{font-size:17px}.mx-dashboard h4{font-size:14px}
.mx-side{background:#13172d;color:#dce3f8;padding:22px 13px;display:flex;flex-direction:column;gap:22px}.mx-brand{font-weight:750;font-size:17px;letter-spacing:.025em;padding:0 13px}.mx-brand small{display:block;font-size:11px;font-weight:500;color:#8e99bc;letter-spacing:.08em;margin-top:3px}.mx-side nav{display:flex;flex-direction:column;gap:4px}.mx-nav{border:0;background:transparent;color:#c8d0e8;text-align:left;border-radius:9px;padding:11px 13px;width:100%;display:flex;align-items:center;gap:11px}.mx-nav:hover,.mx-nav.active{background:#242b4a;color:#fff}.mx-nav.active:before{content:"";width:5px;height:20px;background:var(--mx-cyan);border-radius:4px;margin-left:-13px;margin-right:8px}.mx-side-note{font-size:11px;color:#9aa5c6;padding:0 13px;margin-top:auto}
.mx-main{min-width:0;padding:25px clamp(17px,3vw,35px) 40px}.mx-head{display:flex;align-items:flex-start;justify-content:space-between;gap:15px;margin-bottom:23px}.mx-sub{color:var(--mx-muted);margin-top:5px!important}.mx-actions{display:flex;align-items:center;gap:8px;flex-wrap:wrap}.mx-btn{border:1px solid #cdd5ea;background:#fff;color:#283767;border-radius:8px;padding:8px 13px;min-height:36px}.mx-btn:hover{border-color:var(--mx-blue);color:var(--mx-blue)}.mx-btn.primary{background:var(--mx-blue);border-color:var(--mx-blue);color:#fff}.mx-btn.accent{background:var(--mx-cyan);border-color:var(--mx-cyan);color:#fff}.mx-btn.warn{color:#ab3450}.mx-chip{display:inline-flex;align-items:center;gap:6px;border-radius:99px;padding:4px 9px;background:#e5ebf8;color:#34446f;font-size:11px;font-weight:650}.mx-chip.ok{background:#def6f0;color:#147968}.mx-chip.bad{background:#fde8eb;color:#a3304c}.mx-chip.info{background:#e2f5fb;color:#08778a}
.mx-view[hidden]{display:none!important}.mx-grid{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:16px}.mx-grid.four{grid-template-columns:repeat(4,minmax(0,1fr))}.mx-card{background:var(--mx-card);border-radius:10px;box-shadow:0 4px 18px rgba(31,43,79,.06);border:1px solid rgba(160,171,198,.18);overflow:hidden}.mx-card-head{background:#f6f7fb;border-bottom:1px solid var(--mx-line);padding:13px 18px;display:flex;justify-content:space-between;align-items:center;gap:10px}.mx-card-body{padding:18px}.mx-card-body p{color:var(--mx-muted)}.mx-stat{padding:17px 18px}.mx-stat-label{color:var(--mx-muted);font-size:12px;font-weight:600}.mx-stat-value{font-size:23px;font-weight:750;line-height:1.25;margin:6px 0}.mx-stat-detail{color:var(--mx-muted);font-size:11px}.mx-section-title{margin:24px 0 12px!important}.mx-section-title:first-child{margin-top:0!important}.mx-muted{color:var(--mx-muted)}.mx-empty{color:var(--mx-muted);font-style:italic}
.mx-topology{display:grid;grid-template-columns:1fr auto 1fr auto 1fr;align-items:center;gap:12px;text-align:center}.mx-node{border:1px solid var(--mx-line);border-radius:10px;padding:16px 10px;min-width:0}.mx-node strong{display:block;font-size:15px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}.mx-node small{display:block;color:var(--mx-muted);margin-top:4px}.mx-connector{height:2px;width:28px;background:#9caadd}.mx-dot{width:9px;height:9px;border-radius:50%;background:#c3c8d2;display:inline-block;margin-right:8px;vertical-align:middle}.mx-dot.up{background:var(--mx-cyan)}.mx-dot.active{background:#27b98e;box-shadow:0 0 0 4px #dff8ee}.mx-dot.down{background:#e05a70}
.mx-form-row{display:grid;grid-template-columns:minmax(130px,34%) minmax(0,1fr);gap:16px;align-items:start;padding:12px 0;border-bottom:1px solid var(--mx-line)}.mx-form-row>label{font-weight:600;padding-top:7px}.mx-form-row>div{display:flex;flex-direction:column;gap:5px}.mx-form-row .mx-search{width:100%;max-width:520px}.mx-form-row input[type=checkbox]{width:18px;height:18px;accent-color:var(--mx-blue);margin:8px 0}.mx-form-row small{line-height:1.4}
.mx-table-wrap{overflow:auto}.mx-table{width:100%;border-collapse:collapse;min-width:520px}.mx-table th{text-align:left;background:#f7f8fb;color:#69718c;font-size:12px;font-weight:700}.mx-table th,.mx-table td{padding:12px 15px;border-bottom:1px solid var(--mx-line)}.mx-table tr:last-child td{border-bottom:0}.mx-table td small{display:block;color:var(--mx-muted)}.mx-two-col{display:grid;grid-template-columns:1fr 1fr;gap:16px}.mx-kv{display:grid;grid-template-columns:minmax(90px,42%) minmax(0,1fr);gap:12px;border-bottom:1px solid var(--mx-line);padding:9px 0}.mx-kv:last-child{border-bottom:0}.mx-kv span:first-child{color:var(--mx-muted)}.mx-kv strong{font-weight:600;overflow-wrap:anywhere}.mx-meter{height:8px;background:#e8ebf4;border-radius:99px;overflow:hidden;margin:8px 0}.mx-meter>i{display:block;height:100%;background:linear-gradient(90deg,var(--mx-cyan),var(--mx-blue));border-radius:99px}.mx-result{white-space:pre-wrap;word-break:break-word;background:#f7f8fb;color:#35405e;border:1px solid var(--mx-line);border-radius:8px;padding:12px;margin-top:14px;max-height:220px;overflow:auto;font:12px/1.5 ui-monospace,SFMono-Regular,Consolas,monospace}.mx-log{height:min(60vh,550px);overflow:auto;white-space:pre-wrap;background:#141b30;color:#d7e2ff;padding:17px;border-radius:8px;font:12px/1.5 ui-monospace,SFMono-Regular,Consolas,monospace}.mx-search{border:1px solid var(--mx-line);border-radius:7px;padding:8px 10px;min-height:36px;background:#fff;color:var(--mx-ink)}.mx-controls{display:flex;gap:8px;flex-wrap:wrap}.mx-space{height:16px}.mx-note{background:#e9efff;border-left:3px solid var(--mx-blue);padding:12px 15px;border-radius:5px;color:#33406c}
@media(max-width:1100px){.mx-grid.four{grid-template-columns:repeat(2,minmax(0,1fr))}}@media(max-width:850px){.mx-dashboard{grid-template-columns:1fr}.mx-side{padding:12px 14px;gap:8px}.mx-brand small,.mx-side-note{display:none}.mx-side nav{flex-direction:row;overflow:auto}.mx-nav{white-space:nowrap;width:auto;padding:8px 12px}.mx-nav.active:before{display:none}.mx-main{padding:20px}.mx-topology{grid-template-columns:1fr;gap:7px}.mx-connector{width:2px;height:14px;margin:auto}.mx-two-col{grid-template-columns:1fr}}@media(max-width:600px){.mx-grid,.mx-grid.four{grid-template-columns:1fr}.mx-head{flex-direction:column}.mx-stat-value{font-size:20px}.mx-form-row{grid-template-columns:1fr;gap:4px}}
.mx-dashboard{grid-template-areas:'top top' 'side main';grid-template-rows:46px minmax(0,1fr);grid-template-columns:225px minmax(0,1fr);background:#e9eaf0;border-radius:0}
.mx-global{grid-area:top;display:flex;align-items:center;justify-content:space-between;background:#fff;color:#262a38;padding:0 23px;border-bottom:1px solid #e1e2e9;gap:16px;min-width:0}.mx-global-brand{display:flex;align-items:center;gap:17px;white-space:nowrap;font-size:16px}.mx-global-brand strong{font-weight:750;letter-spacing:.025em}.mx-global-brand>span:nth-child(2){color:#777c89}.mx-global-actions{display:flex;gap:9px;align-items:center;white-space:nowrap}.mx-global-actions .mx-btn{border:0;background:transparent;min-height:30px;padding:4px 8px;color:#4a4f67}.mx-global-actions .mx-btn.primary{background:transparent;color:#4a4f67}.mx-global-actions .mx-btn:hover{color:#00aebe;background:#eef9fb}
.mx-side{grid-area:side;background:#141427;padding:12px 0 20px;gap:0}.mx-side nav{gap:0}.mx-nav{border-radius:0;padding:16px 20px;color:#c9c9d9;text-transform:uppercase;font-size:12px;font-weight:650;letter-spacing:.035em}.mx-nav:before{content:'◌';display:inline-block;width:19px;text-align:center;color:#b6b9d0;font-size:17px;margin-right:7px}.mx-nav:nth-child(2):before{content:'✦'}.mx-nav:nth-child(3):before{content:'↔'}.mx-nav:nth-child(4):before{content:'◉'}.mx-nav:nth-child(5):before{content:'▣'}.mx-nav:nth-child(6):before{content:'⬡'}.mx-nav:nth-child(7):before{content:'◐'}.mx-nav:nth-child(8):before{content:'☷'}.mx-nav:nth-child(9):before{content:'⚙'}.mx-nav:nth-child(10):before{content:'◇'}.mx-nav:hover,.mx-nav.active{background:#0c0c1b;color:#22d8dc}.mx-nav.active:before{content:'◌';width:19px;height:auto;background:none;border-radius:0;margin:0 7px 0 0;color:#22d8dc}.mx-nav.active:nth-child(2):before{content:'✦'}.mx-nav.active:nth-child(3):before{content:'↔'}.mx-nav.active:nth-child(4):before{content:'◉'}.mx-nav.active:nth-child(5):before{content:'▣'}.mx-nav.active:nth-child(6):before{content:'⬡'}.mx-nav.active:nth-child(7):before{content:'◐'}.mx-nav.active:nth-child(8):before{content:'☷'}.mx-nav.active:nth-child(9):before{content:'⚙'}.mx-nav.active:nth-child(10):before{content:'◇'}.mx-side-note{padding:20px;margin-top:auto}
.mx-main{grid-area:main;background:#e9eaf0;padding:24px;min-width:0}.mx-head{display:block;margin:0 0 18px}.mx-head .mx-sub{margin-top:2px!important}.mx-page-overview .mx-main{padding:0 0 34px}.mx-page-overview .mx-head{display:none}.mx-page-overview .mx-result{margin:20px}.mx-overview-content{padding:20px;display:grid;gap:20px}
.mx-hero{background:radial-gradient(circle at 54% 35%,#33299a 0,#17104f 45%,#2b238a 100%);color:#fff;min-height:345px;display:grid;grid-template-columns:minmax(180px,1fr) minmax(220px,1.25fr) minmax(170px,1fr);align-items:center;gap:18px;padding:30px clamp(22px,5vw,75px);overflow:hidden}.mx-hero-sources{display:grid;gap:15px}.mx-hero-source{display:flex;align-items:center;gap:9px;color:#9698ca;font-size:13px;white-space:nowrap}.mx-hero-source.online{color:#e6e8ff}.mx-hero-source.chosen{color:#28e0de}.mx-hero-light{display:inline-block;width:8px;height:8px;border-radius:50%;background:#666a9c;flex:none}.mx-hero-source.online .mx-hero-light{background:#21ccbd}.mx-hero-rule{height:1px;flex:1;border-top:1px dashed #7e81bd;margin-left:10px}.mx-hero-source.chosen .mx-hero-rule{border-top:1px solid #23d8de}.mx-hero-center{text-align:center;display:flex;flex-direction:column;align-items:center;justify-content:center;gap:8px;min-width:0}.mx-hero-center>strong{font-size:17px;color:#28dedb}.mx-hero-center>small{color:#a8a9dc}.mx-hero-badges{display:flex;gap:7px;flex-wrap:wrap;justify-content:center;margin-top:8px}.mx-hero-badges span{background:#18144e;color:#d4d9ff;border:1px solid #514da1;border-radius:7px;padding:6px 8px;font-size:11px}.mx-router-art{height:108px;width:115px;position:relative;margin:3px 0 8px;filter:drop-shadow(0 10px 15px #08073c)}.mx-router-top{position:absolute;left:18px;top:1px;width:80px;height:23px;border:2px solid #27dcd8;border-radius:50%;background:#1f1a68}.mx-router-face{position:absolute;left:18px;top:12px;width:80px;height:84px;border:2px solid #27dcd8;border-top:0;border-radius:0 0 34px 34px;background:linear-gradient(100deg,#171252,#34309a 48%,#15104c);display:flex;align-items:center;justify-content:center;flex-direction:column;gap:15px;color:#65e6eb;letter-spacing:.2em}.mx-router-face i{height:4px;width:4px;background:#26e3d6;border-radius:50%;box-shadow:10px 0 #26e3d6,-10px 0 #26e3d6}.mx-hero-clients{border-left:1px solid #4b48a8;padding-left:26px;display:grid;gap:19px}.mx-hero-client{display:flex;align-items:center;gap:11px;color:#29dfdc}.mx-hero-client strong{border:1px solid #31d9da;border-radius:50px;min-width:35px;min-height:35px;padding:6px;text-align:center;font-size:13px}.mx-hero-client span{font-size:13px}.mx-hero-clients small{color:#a8a9d5;line-height:1.35}
.mx-link-card{border-radius:6px;box-shadow:0 5px 18px rgba(22,25,58,.11)}.mx-link-card .mx-card-head{background:#f4f4f8;padding:16px 20px}.mx-link-card .mx-card-head h3{font-weight:500}.mx-link-body{display:grid;grid-template-columns:minmax(0,1fr) 190px;gap:24px;align-items:center;padding:18px 20px 21px}.mx-link-details{min-width:0}.mx-link-pairs .mx-kv{grid-template-columns:minmax(125px,40%) minmax(0,1fr);padding:11px 10px}.mx-link-pairs .mx-kv strong{text-align:right;font-weight:500}.mx-link-actions{display:flex;justify-content:center;padding-top:16px}.mx-link-actions .mx-btn{border-radius:30px;padding:7px 22px;min-width:125px}.mx-link-symbol{width:130px;height:130px;border-radius:50%;background:#f0f1f7;color:#333876;display:grid;place-items:center;margin:auto;font-size:54px;font-weight:500}.mx-link-symbol.wifi{font-size:25px;font-weight:750;letter-spacing:-.05em}.mx-link-symbol.usb{font-size:24px;font-weight:750}.mx-overview-content>.mx-grid .mx-link-body{grid-template-columns:minmax(0,1fr)}.mx-overview-content>.mx-grid .mx-link-symbol{display:none}.mx-overview-content>.mx-grid .mx-card{min-width:0}
@media(max-width:1050px){.mx-hero{padding:24px;grid-template-columns:1fr 1.1fr}.mx-hero-clients{grid-column:1/-1;border-left:0;border-top:1px solid #4b48a8;padding:15px 0 0;display:flex;align-items:center;justify-content:space-between}.mx-hero-clients small{max-width:220px}.mx-link-body{grid-template-columns:minmax(0,1fr) 130px}.mx-link-symbol{width:105px;height:105px}}
@media(max-width:850px){.mx-dashboard{grid-template-areas:'top' 'side' 'main';grid-template-rows:auto auto minmax(0,1fr);grid-template-columns:minmax(0,1fr)}.mx-global{min-height:48px}.mx-side{padding:0;overflow:auto}.mx-side nav{flex-direction:row}.mx-side-note{display:none}.mx-nav{padding:12px;white-space:nowrap;width:auto}.mx-nav.active:before{display:inline-block}.mx-main{padding:18px}.mx-page-overview .mx-main{padding:0 0 25px}.mx-overview-content{padding:16px}}
@media(max-width:600px){.mx-global{padding:8px 12px;flex-wrap:wrap}.mx-global-brand{font-size:14px}.mx-global-actions{gap:3px;flex-wrap:wrap}.mx-global-actions .mx-chip{display:none}.mx-hero{grid-template-columns:1fr;gap:24px;text-align:center}.mx-hero-sources{order:2}.mx-hero-center{order:1}.mx-hero-clients{order:3;display:grid;text-align:left}.mx-hero-source{justify-content:center}.mx-hero-rule{max-width:45px}.mx-link-body{grid-template-columns:1fr}.mx-link-symbol{display:none}.mx-link-pairs .mx-kv{grid-template-columns:1fr 1fr}.mx-overview-content>.mx-grid{grid-template-columns:1fr}}
EOF_CSS
touch /etc/sysupgrade.conf
for F in /usr/libexec/rpcd/mx.ui /usr/sbin/mxscan-ui /usr/sbin/mxsetup-ui /usr/share/rpcd/acl.d/mx-ui.json /usr/share/luci/menu.d/mx-ui.json /www/luci-static/resources/view/mx4200/manager.js /www/luci-static/resources/view/mx4200/dashboard.js /www/luci-static/resources/mx4200/dashboard.css; do
    grep -qxF "$F" /etc/sysupgrade.conf || printf '%s\n' "$F" >> /etc/sysupgrade.conf
done
rm -f /tmp/luci-indexcache.*.json
if [ "$UI_ALREADY_INSTALLED" != 1 ] && [ "${MX_UI_RPC_UPDATE:-0}" != 1 ];then
    /etc/init.d/rpcd reload >/dev/null 2>&1 || /etc/init.d/rpcd restart >/dev/null 2>&1 || true
    (sleep 3; /etc/init.d/uhttpd restart >/dev/null 2>&1) </dev/null >/dev/null 2>&1 &
fi
