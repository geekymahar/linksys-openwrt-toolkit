#!/bin/sh
# Install LED module revision 3 locally for offline boots on MX4200 V2/P2.
case "$(cat /tmp/sysinfo/board_name 2>/dev/null)" in linksys,mx4200v2*) ;; *) echo 'MX4200 V2/P2 required' >&2; exit 1 ;; esac
set -e
[ ! -x /etc/init.d/mxl ] || /etc/init.d/mxl stop >/dev/null 2>&1 || true
mkdir -p /etc/mx4200
cat > /etc/mx4200/led.conf <<'EOF_LED_CONF'
LED_TEST_IP1='1.1.1.1'
LED_TEST_IP2='8.8.8.8'
LED_INTERVAL='1'
LED_IDLE_THRESHOLD='4096'
LED_LIGHT_THRESHOLD='32768'
LED_MEDIUM_THRESHOLD='262144'
EOF_LED_CONF
chmod 600 /etc/mx4200/led.conf
cat > /usr/bin/mxls <<'EOF_LED_SET'
#!/bin/sh
fl(){ C=$1;for P in "/sys/class/leds/${C}:indicator" "/sys/class/leds/${C}:status" "/sys/class/leds/${C}" /sys/class/leds/*$C*;do [ -e "$P/brightness" ]&&{ echo "$P";return;};done;}
R="$(fl red)";G="$(fl green)";B="$(fl blue)"
rb(){ case "$(cat /tmp/sysinfo/board_name 2>/dev/null)" in linksys,mx4200v2*) ;; *) return ;; esac;[ -f /tmp/mxlb ]&&{ cat /tmp/mxlb;return;};command -v i2cget >/dev/null||return;for D in /dev/i2c-*;do [ -e "$D" ]||continue;N=${D##*-};i2cget -y "$N" 0x58 0x00 >/dev/null 2>&1&&{ echo "$N">/tmp/mxlb;echo "$N";return;};done;}
IB="$(rb)";BK=sysfs;case "$R$G$B" in *st1202*) IB='';;*) [ -n "$IB" ]&&BK=st1202;;esac
sc(){ P=$1;V=$2;[ -n "$P" ]&&[ -e "$P/brightness" ]||return;[ -w "$P/trigger" ]&&echo none>"$P/trigger" 2>/dev/null;M="$(cat "$P/max_brightness" 2>/dev/null)";case "$M" in ''|*[!0-9]*)M=255;;esac;echo $((V*M/255))>"$P/brightness";}
si(){ [ -e /tmp/mxli ]&&return;i2cset -y "$IB" 0x58 0x01 0x80 >/dev/null 2>&1||return 1;sleep .02;i2cset -y "$IB" 0x58 0x04 0x08;i2cset -y "$IB" 0x58 0x01 0x01;sleep .02;i2cset -y "$IB" 0x58 0x02 0x07;i2cset -y "$IB" 0x58 0x03 0x00;i2cset -y "$IB" 0x58 0x04 0x08;touch /tmp/mxli;}
rgb(){ X=$1;Y=$2;Z=$3;if [ "$BK" = st1202 ];then si||return;GH=$(printf '0x%02x' "$Y");RH=$(printf '0x%02x' "$X");BH=$(printf '0x%02x' "$Z");if command -v i2ctransfer >/dev/null;then i2ctransfer -y "$IB" w4@0x58 0x09 "$GH" "$RH" "$BH" >/dev/null 2>&1;else i2cset -y "$IB" 0x58 0x09 "$GH";i2cset -y "$IB" 0x58 0x0a "$RH";i2cset -y "$IB" 0x58 0x0b "$BH";fi;else sc "$R" "$X";sc "$G" "$Y";sc "$B" "$Z";fi;}
case "$1" in
rgb)rgb "${2:-0}" "${3:-0}" "${4:-0}";;red)rgb 255 0 0;;green)rgb 0 255 0;;blue)rgb 0 0 255;;purple)rgb 255 0 255;;orange)rgb 255 70 0;;yellow)rgb 255 220 0;;teal)rgb 0 180 120;;white)rgb 255 255 255;;dimred)rgb 15 0 0;;dimgreen)rgb 0 15 0;;dimblue)rgb 0 0 15;;dimpurple)rgb 15 0 15;;dimorange)rgb 15 4 0;;standby|dimwhite)rgb 15 15 15;;off)rgb 0 0 0;;
detect)echo "LED: $BK bus=${IB:-none} R=${R:-none} G=${G:-none} B=${B:-none}";[ "$BK" = st1202 ]||{ [ -n "$R$G$B" ]&&echo 'RGB: READY'||echo 'RGB: NOT READY';};;*)exit 1;;esac
EOF_LED_SET
chmod 755 /usr/bin/mxls
cat > /usr/bin/mxld <<'EOF_LED_STATUS'
#!/bin/sh
. /etc/mx4200/base.conf
. /etc/mx4200/led.conf
LED=/usr/bin/mxls
SF=/tmp/mx4200-led-state
ST=/tmp/mx4200-led-state.new
CURVE='15 20 30 45 65 90 120 150 180 205 220 205 180 150 120 90 65 45 30 20 15'
D0=.095; D1=.060; D2=.036; D3=.019; DF=.080
load(){ STATE=online; LEVEL=0; TS_ACTIVE=0; WG_ACTIVE=0; OVPN_ACTIVE=0; UPLINK=primary; [ -f "$SF" ] && . "$SF"; }
delay(){ case "$1" in 0) echo "$D0";; 1) echo "$D1";; 2) echo "$D2";; *) echo "$D3";; esac; }
show(){ C="$1"; V="$2"; case "$C" in green) "$LED" rgb 0 "$V" 0;; blue) "$LED" rgb 0 0 "$V";; purple) "$LED" rgb "$V" 0 "$V";; orange) O=$((V*70/255)); [ "$O" -lt 1 ] && O=1; "$LED" rgb "$V" "$O" 0;; yellow) O=$((V*220/255)); "$LED" rgb "$V" "$O" 0;; red) "$LED" rgb "$V" 0 0;; teal) O=$((V*180/255)); P=$((V*120/255)); "$LED" rgb 0 "$O" "$P";; white) "$LED" rgb "$V" "$V" "$V";; esac; }
breathe(){ C="$1"; EXPECT="$2"; for V in $CURVE; do load; [ "$STATE" = "$EXPECT" ] || return; show "$C" "$V"; sleep "$(delay "$LEVEL")"; done; }
beat(){ C="$1"; EXPECT="$2"; for V in 220 35 220 15; do load; [ "$STATE" = "$EXPECT" ] || return; show "$C" "$V"; sleep "$DF"; done; sleep .35; }
dfs_blink(){ for V in 220 0 220 0; do load; [ "$STATE" = dfs_wait ] || return; show purple "$V"; sleep .15; done; sleep .65; }
boot_ready(){ M="$(cat /etc/mx4200/mode 2>/dev/null || echo router)"; case "$M" in wds|ap)DEV=br-mgmt;IP="$(uci -q get network.mgmt.ipaddr)";;*)DEV=br-lan;IP="$(uci -q get network.lan.ipaddr)";;esac; [ -n "$IP" ]||return 1;ip link show "$DEV" >/dev/null 2>&1||return 1;ip -4 addr show dev "$DEV" 2>/dev/null|grep -q " $IP/"||return 1;pgrep dnsmasq >/dev/null 2>&1||return 1;[ ! -x /etc/init.d/uhttpd ] || pgrep uhttpd >/dev/null 2>&1; }
N=0
while ! boot_ready && [ "$N" -lt 24 ]; do for C in red green blue yellow purple teal; do case "$C" in red) "$LED" rgb 180 0 0;; green) "$LED" rgb 0 180 0;; blue) "$LED" rgb 0 0 180;; yellow) "$LED" rgb 180 155 0;; purple) "$LED" rgb 180 0 180;; teal) "$LED" rgb 0 150 100;; esac; sleep .18; boot_ready && break; done; N=$((N+1)); done
bytes(){ [ -r "/sys/class/net/$1/statistics/rx_bytes" ] || { echo 0; return; }; A="$(cat "/sys/class/net/$1/statistics/rx_bytes")"; Z="$(cat "/sys/class/net/$1/statistics/tx_bytes")"; echo $((${A:-0}+${Z:-0})); }
wgifs(){ command -v wg >/dev/null 2>&1 && wg show interfaces 2>/dev/null; }
wgup(){ for I in $(wgifs); do wg show "$I" latest-handshakes 2>/dev/null | awk '$2>0{x=1}END{exit !x}' && return 0; done; return 1; }
wgbytes(){ X=0; for I in $(wgifs); do V="$(bytes "$I")"; X=$((X+V)); done; echo "$X"; }
ovpnifs(){ for P in /sys/class/net/tun* /sys/class/net/tap*; do [ -e "$P" ] && basename "$P"; done; }
ovpnup(){ pidof openvpn >/dev/null 2>&1 && [ -n "$(ovpnifs)" ]; }
ovpnbytes(){ X=0; for I in $(ovpnifs); do V="$(bytes "$I")"; X=$((X+V)); done; echo "$X"; }
wdssta(){ for I in $(iw dev 2>/dev/null|awk '/Interface/{i=$2}/type managed/{print i}');do [ -e "/sys/class/net/br-lan/brif/$I" ]&&iw dev "$I" link 2>/dev/null|grep -q '^Connected to '&&{ echo "$I";return;};done;}
staif(){ S="$1"; R="$(uci -q get wireless.$S.device)"; [ -n "$R" ] || return; J="$(ubus call network.wireless status 2>/dev/null)"; for N in 0 1 2 3; do [ "$(printf '%s\n' "$J" | jsonfilter -e "@.$R.interfaces[$N].section" 2>/dev/null)" = "$S" ] && { printf '%s\n' "$J" | jsonfilter -e "@.$R.interfaces[$N].ifname" 2>/dev/null; return; }; done; }
staup(){ I="$(staif "$1")"; [ -n "$I" ] && iw dev "$I" link 2>/dev/null | grep -q '^Connected to '; }
route_dev(){ ip -4 route show default 2>/dev/null | awk '$1=="default"{d="";m=0;for(i=1;i<=NF;i++){if($i=="dev")d=$(i+1);if($i=="metric")m=$(i+1)+0}if(d==""||d~/^(tun|tap|wg|tailscale)/)next;if(!found||m<best){found=1;best=m;chosen=d}}END{print chosen}'; }
iface_dev(){ ubus call "network.interface.$1" status 2>/dev/null | jsonfilter -e '@.l3_device' 2>/dev/null; }
uplink_kind(){
DEV="$2"; [ -n "$DEV" ] || { echo none; return; }
USB_DEV="$(iface_dev usbwan)"
[ -n "$USB_DEV" ] && [ "$DEV" = "$USB_DEV" ] && { echo usb; return; }
if [ "$1" = wds ] && [ "$DEV" = br-lan ]; then
case "$(cat /tmp/mx4200-backhaul-active 2>/dev/null)" in backup) echo backup;; *) echo primary;; esac
return
fi
BACKUP_DEV="$(iface_dev wwanb)"
[ -n "$BACKUP_DEV" ] && [ "$DEV" = "$BACKUP_DEV" ] && echo backup || echo primary
}
wds_health(){ case "$1" in GREEN) STATE=online;; RED) STATE=link_down;; YELLOW) STATE=dns_fail;; *) STATE=no_internet;; esac; }
dfs_wait(){
J="$(ubus call network.wireless status 2>/dev/null)" || return 1
for AP in $(printf '%s\n' "$J" | jsonfilter -e '@.radio2.interfaces[*].ifname' 2>/dev/null); do
[ "$(ubus call "hostapd.$AP" get_status 2>/dev/null | jsonfilter -e '@.status' 2>/dev/null)" = DFS ] && return 0
done
return 1
}
uplink_cue(){ case "$UPLINK" in backup) show teal 160;; usb) show white 160;; *) return;; esac; sleep .18; }
level(){ V="$1"; if [ "$V" -lt "${LED_IDLE_THRESHOLD:-4096}" ]; then echo 0; elif [ "$V" -lt "${LED_LIGHT_THRESHOLD:-32768}" ]; then echo 1; elif [ "$V" -lt "${LED_MEDIUM_THRESHOLD:-262144}" ]; then echo 2; else echo 3; fi; }
write(){ printf "STATE='%s'\nLEVEL='%s'\nTS_ACTIVE='%s'\nWG_ACTIVE='%s'\nOVPN_ACTIVE='%s'\nUPLINK='%s'\n" "$1" "$2" "$3" "$4" "$5" "$6" > "$ST"; mv "$ST" "$SF"; }
sampler(){
PW=0; PT=0; PG=0; PO=0; FIRST=1; WH=ORANGE; WC=30; LAST_WDS_IF=''
while true; do
M="$(cat /etc/mx4200/mode 2>/dev/null || echo router)"
ROUTE_DEV="$(route_dev)"
UPLINK="$(uplink_kind "$M" "$ROUTE_DEV")"
STATE=online; IF=''
if [ "$M" = wds ] && { [ "$ROUTE_DEV" = br-lan ] || [ -z "$ROUTE_DEV" ]; }; then
IF="$(wdssta)"
if [ -z "$IF" ]; then
STATE=link_down; LAST_WDS_IF=''; WH=ORANGE; WC=30
elif ! iw dev "$IF" info 2>/dev/null | grep -q '4addr: on' || [ ! -e "/sys/class/net/br-lan/brif/$IF" ]; then
STATE=link_down; LAST_WDS_IF=''; WH=ORANGE; WC=30
else
[ "$IF" = "$LAST_WDS_IF" ] || { LAST_WDS_IF="$IF"; WC=30; }
WC=$((WC+1))
if [ "$WC" -ge 30 ]; then WH="$(/usr/sbin/mxw 2>/dev/null)" || WH=UNKNOWN; WC=0; fi
wds_health "$WH"
fi
else
LAST_WDS_IF=''
IF="$ROUTE_DEV"
if [ -z "$IF" ]; then
STATE=no_wan
[ "$M" = repeater ] && ! staup mx_primary && ! staup mx_backup && STATE=link_down
elif [ "$M" = repeater ] && iw dev "$IF" info 2>/dev/null | grep -q 'type managed' && ! iw dev "$IF" link 2>/dev/null | grep -q '^Connected to '; then
STATE=link_down
else
DNS_OK=0; nslookup "$DNS_TEST_NAME" 127.0.0.1 >/dev/null 2>&1 && DNS_OK=1
if ping -I "$IF" -c 1 -W 1 "$LED_TEST_IP1" >/dev/null 2>&1 || ping -I "$IF" -c 1 -W 1 "$LED_TEST_IP2" >/dev/null 2>&1; then
[ "$DNS_OK" = 1 ] || STATE=dns_fail
else STATE=no_internet
fi
fi
fi
dfs_wait && STATE=dfs_wait
[ -n "$IF" ] && W="$(bytes "$IF")" || W=0
[ -d /sys/class/net/tailscale0 ] && T="$(bytes tailscale0)" || T=0
wgup && G="$(wgbytes)" || G=0
ovpnup && O="$(ovpnbytes)" || O=0
if [ "$FIRST" = 1 ]; then
PW="$W"; PT="$T"; PG="$G"; PO="$O"; FIRST=0
write "$STATE" 0 0 0 0 "$UPLINK"
sleep "${LED_INTERVAL:-1}"
continue
fi
DW=$((W-PW)); DT=$((T-PT)); DG=$((G-PG)); DO=$((O-PO))
[ "$DW" -lt 0 ] && DW=0; [ "$DT" -lt 0 ] && DT=0; [ "$DG" -lt 0 ] && DG=0; [ "$DO" -lt 0 ] && DO=0
PW="$W"; PT="$T"; PG="$G"; PO="$O"
L="$(level "$DW")"; TA=0; GA=0; OA=0
[ "$DT" -gt 0 ] && TA=1; [ "$DG" -gt 0 ] && GA=1; [ "$DO" -gt 0 ] && OA=1
write "$STATE" "$L" "$TA" "$GA" "$OA" "$UPLINK"
sleep "${LED_INTERVAL:-1}"
done
}
PID=''; cleanup(){ [ -n "$PID" ] && kill "$PID" >/dev/null 2>&1 || true; rm -f "$SF" "$ST"; }; trap cleanup EXIT INT TERM; rm -f "$SF" "$ST"; sampler & PID=$!
"$LED" dimgreen
while true; do
load
case "$STATE" in
dfs_wait) dfs_blink ;;
link_down) beat red link_down; load; [ "$STATE" = link_down ] && beat blue link_down ;;
no_wan) beat red no_wan ;;
no_internet) beat red no_internet ;;
dns_fail) breathe yellow dns_fail ;;
online)
breathe green online
load; [ "$STATE" = online ] || continue
uplink_cue
load; [ "$STATE" = online ] || continue
[ "$TS_ACTIVE" = 1 ] && breathe blue online
load; [ "$STATE" = online ] || continue
[ "$WG_ACTIVE" = 1 ] && breathe purple online
load; [ "$STATE" = online ] || continue
[ "$OVPN_ACTIVE" = 1 ] && breathe orange online
;;
esac
done
EOF_LED_STATUS
chmod 755 /usr/bin/mxld
cat > /etc/init.d/mxl <<'EOF_LED_INIT'
#!/bin/sh /etc/rc.common
START=12
STOP=90
USE_PROCD=1
start_service(){ procd_open_instance; procd_set_param command /usr/bin/mxld; procd_set_param respawn 3600 5 5; procd_set_param stdout 1; procd_set_param stderr 1; procd_close_instance; }
EOF_LED_INIT
chmod 755 /etc/init.d/mxl
/etc/init.d/mxl enable
/etc/init.d/mxl restart >/dev/null 2>&1 || true
touch /etc/sysupgrade.conf
for F in /etc/mx4200/led.conf /usr/bin/mxls /usr/bin/mxld /etc/init.d/mxl; do grep -qxF "$F" /etc/sysupgrade.conf || echo "$F" >> /etc/sysupgrade.conf; done
