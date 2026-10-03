#!/bin/sh
if [ "$MX_REMOTE_PASS" != 1 ] && { [ -e /etc/mx4200/provisioned ] || [ -e /etc/mx4200/mode ]; };then
[ -x /etc/init.d/mxmod ] && { /etc/init.d/mxmod disable; /etc/init.d/mxmod stop; }
exit 0
fi
WIFI_PREFIX='LS-MX4200v2'
LED_AUTO_INSTALL='1'
COUNTRY='GB'
ROUTER_HOSTNAME='OpenWrt-LS-MX4200v2'
LAN_IP='192.168.40.1'
LAN_NETMASK='255.255.255.0'
MGMT_IP='172.23.247.1'
DHCP_START='100'
DHCP_LIMIT='150'
DHCP_LEASETIME='12h'
MODE_2G='HE40'
MODE_5G='HE80'
MODE_5G_HIGH='HE80'
CHANNEL_5G_HIGH='116'
DNS_FALLBACK_1='1.1.1.1'
DNS_FALLBACK_2='1.0.0.1'
DNS_TEST_NAME='openwrt.org'
WDS_TEST_IP2='8.8.8.8'
SSID_2G="$WIFI_PREFIX"
SSID_5G="${WIFI_PREFIX}-5GHz"
SSID_5G_HIGH="${WIFI_PREFIX}-Max"
mkdir -p /etc/mx4200/profiles /usr/lib/mx4200
chmod 700 /etc/mx4200 /etc/mx4200/profiles
cat > /etc/mx4200/base.conf <<EOF
WIFI_PREFIX='$WIFI_PREFIX'
LED_AUTO_INSTALL='$LED_AUTO_INSTALL'
COUNTRY='$COUNTRY'
ROUTER_HOSTNAME='$ROUTER_HOSTNAME'
LAN_IP='$LAN_IP'
LAN_NETMASK='$LAN_NETMASK'
MGMT_IP='$MGMT_IP'
DHCP_START='$DHCP_START'
DHCP_LIMIT='$DHCP_LIMIT'
DHCP_LEASETIME='$DHCP_LEASETIME'
MODE_2G='$MODE_2G'
MODE_5G='$MODE_5G'
MODE_5G_HIGH='$MODE_5G_HIGH'
CHANNEL_5G_HIGH='$CHANNEL_5G_HIGH'
DNS_FALLBACK_1='$DNS_FALLBACK_1'
DNS_FALLBACK_2='$DNS_FALLBACK_2'
DNS_TEST_NAME='$DNS_TEST_NAME'
WDS_TEST_IP2='$WDS_TEST_IP2'
EOF
chmod 600 /etc/mx4200/base.conf
cat > /usr/lib/mxc <<'EOF'
#!/bin/sh
. /etc/mx4200/base.conf
PROFILE_ROOT='/etc/mx4200/profiles'
PROFILE_FILES='network wireless dhcp firewall system'
u(){ uci set "$1";}
wifi_clear(){ for S in $(uci show wireless 2>/dev/null|awk -F= '$2=="wifi-iface"{print $1}');do uci -q delete "$S";done;}
ds(){ for S in $(uci show network 2>/dev/null|awk -F= '$2=="device"{print $1}');do [ "$(uci -q get "$S.name")" = "$1" ]&&{ echo "$S";return;};done;return 1;}
rwan(){
B="$(ds br-lan)";[ -n "$B" ]||return 1
uci -q del_list "${B}.ports=wan"
uci add_list "${B}.ports=wan"||return 1
uci -q delete network.wan.device
u network.wan.proto=none||return 1
if uci -q get network.wan6 >/dev/null 2>&1;then u network.wan6.disabled=1||return 1;fi
}
zs(){ for S in $(uci show firewall 2>/dev/null|awk -F= '$2=="zone"{print $1}');do [ "$(uci -q get "$S.name")" = "$1" ]&&{ echo "$S";return;};done;return 1;}
dz(){ for S in $(uci show firewall 2>/dev/null|awk -F= '$2=="zone"{print $1}');do [ "$(uci -q get "$S.name")" = "$1" ]&&uci -q delete "$S";done;for F in $(uci show firewall 2>/dev/null|awk -F= '$2=="forwarding"{print $1}');do [ "$(uci -q get "$F.src")" = "$1" ]||[ "$(uci -q get "$F.dest")" = "$1" ]&&uci -q delete "$F";done;}
df(){ for S in $(uci show firewall 2>/dev/null|awk -F= '$2=="forwarding"{print $1}');do [ "$(uci -q get "$S.src")" = "$1" ]||continue;case "$(uci -q get "$S.dest")" in vpn|tailscale);;*)uci -q delete "$S";;esac;done;}
lz(){ Z="$(zs lan)";[ -n "$Z" ]||{ Z="firewall.$(uci add firewall zone)";u ${Z}.name=lan;};u ${Z}.input=ACCEPT;u ${Z}.output=ACCEPT;u ${Z}.forward=ACCEPT;uci -q del_list "${Z}.network=lan";uci add_list "${Z}.network=lan";}
wz(){ Z="$(zs wan)";[ -n "$Z" ]||return 1;u ${Z}.masq=1;u ${Z}.mtu_fix=1;}
fw(){ for F in $(uci show firewall 2>/dev/null|awk -F= '$2=="forwarding"{print $1}');do [ "$(uci -q get "$F.src")" = "$1" ]&&[ "$(uci -q get "$F.dest")" = "$2" ]&&return;done;F="$(uci add firewall forwarding)";u "firewall.$F.src=$1";u "firewall.$F.dest=$2";}
l2w(){ df lan;fw lan wan;}
ld(){
u network.lan=interface;u network.lan.device=br-lan;u network.lan.proto=dhcp;u network.lan.delegate=0
for O in ipaddr netmask gateway dns ip6assign ip6hint ip6class metric;do uci -q delete "network.lan.$O";done
u dhcp.lan=dhcp;u dhcp.lan.interface=lan;u dhcp.lan.ignore=1;u dhcp.lan.ra=disabled;u dhcp.lan.dhcpv6=disabled;u dhcp.lan.ndp=disabled
}
sl(){
u network.lan=interface;u network.lan.device=br-lan;u network.lan.proto=static;u network.lan.ipaddr="$1";u network.lan.netmask="$2";u network.lan.delegate=1
for O in metric gateway dns;do uci -q delete "network.lan.$O";done
u dhcp.lan=dhcp;u dhcp.lan.interface=lan;u dhcp.lan.start="$3";u dhcp.lan.limit="$4";u dhcp.lan.leasetime="$5";u dhcp.lan.ignore=0
}
mc(){
uci -q delete network.br_mgmt;u network.br_mgmt=device;u network.br_mgmt.name=br-mgmt;u network.br_mgmt.type=bridge;u network.br_mgmt.bridge_empty=1
[ "$4" = lan1 ]&&uci add_list network.br_mgmt.ports=lan1
uci -q delete network.mgmt;u network.mgmt=interface;u network.mgmt.device=br-mgmt;u network.mgmt.proto=static;u network.mgmt.ipaddr="$1";u network.mgmt.netmask="$2";u network.mgmt.delegate=0
uci -q delete dhcp.mgmt;u dhcp.mgmt=dhcp;u dhcp.mgmt.interface=mgmt;u dhcp.mgmt.start="$3";u dhcp.mgmt.limit=100;u dhcp.mgmt.leasetime="${5:-$DHCP_LEASETIME}";u dhcp.mgmt.ignore=0;u dhcp.mgmt.ra=disabled;u dhcp.mgmt.dhcpv6=disabled;u dhcp.mgmt.ndp=disabled
}
znew(){ Z="$(uci add firewall zone)";u "firewall.$Z.name=$1";u "firewall.$Z.input=$2";u firewall.$Z.output=ACCEPT;u "firewall.$Z.forward=$3";}
mf(){ dz mgmt;znew mgmt ACCEPT REJECT;uci add_list "firewall.$Z.network=mgmt";}
uz(){ dz uplink;znew uplink REJECT REJECT;u firewall.$Z.masq=1;u firewall.$Z.mtu_fix=1;uci add_list "firewall.$Z.network=wwanp";uci -q get network.wwanb >/dev/null&&uci add_list "firewall.$Z.network=wwanb";for N in vpn tailscale;do [ -n "$(zs "$N")" ]&&fw "$N" uplink;done;}
pr(){ S=$1;for I in 10.0.0.0/8 172.16.0.0/12 192.168.0.0/16 100.64.0.0/10;do uci add_list "firewall.$S.src_ip=$I";done;}
mr(){ S=mx_mgmt_$1;uci -q delete firewall.$S;u firewall.$S=rule;u firewall.$S.src="$1";pr $S;u firewall.$S.proto=tcp;u firewall.$S.dest_port='22 80 443';u firewall.$S.target=ACCEPT;}
vz(){ N=$1;shift;dz "$N";znew "$N" ACCEPT ACCEPT;u firewall.$Z.masq=1;u firewall.$Z.mtu_fix=1;for D in "$@";do uci add_list "firewall.$Z.device=$D";done;fw lan "$N";fw "$N" lan;fw "$N" wan;[ -n "$(zs uplink)" ]&&fw "$N" uplink;}
rb() {
for R in radio0 radio1 radio2;do u wireless.$R.country="$COUNTRY";u wireless.$R.disabled=0;done
u wireless.radio1.band=2g;u wireless.radio1.htmode="$MODE_2G"
u wireless.radio0.band=5g;u wireless.radio0.htmode="$MODE_5G"
u wireless.radio2.band=5g;u wireless.radio2.htmode="$MODE_5G_HIGH";u wireless.radio2.channel="$CHANNEL_5G_HIGH"
}
ap(){ local S=$1 E=${6:-sae-mixed};u wireless.$S=wifi-iface;u wireless.$S.device="$2";u wireless.$S.mode=ap;u wireless.$S.network="$3";u wireless.$S.ssid="$4";u wireless.$S.encryption="$E";nk "$E"&&u wireless.$S.key="$5";u wireless.$S.disabled=0;}
ca(){ for X in system network wireless dhcp firewall;do uci commit $X;done;}
ra(){ [ "$MX4200_NO_RELOAD" = 1 ]&&return;reload_config 2>/dev/null||true;/etc/init.d/network restart;sleep 3;/etc/init.d/dnsmasq restart;/etc/init.d/firewall restart;}
pex(){ D="$PROFILE_ROOT/$1";[ -f "$D/network" ]&&[ -f "$D/wireless" ]&&[ -f "$D/dhcp" ]&&[ -f "$D/firewall" ];}
psave(){ N="$1";D="$PROFILE_ROOT/$N";mkdir -p "$D";chmod 700 "$D";for F in $PROFILE_FILES;do [ -f "/etc/config/$F" ]&&cp "/etc/config/$F" "$D/$F";done;date +%s>"$D/saved_at";chmod 600 "$D"/* 2>/dev/null||true;}
pload(){ N="$1";D="$PROFILE_ROOT/$N";pex "$N"||return 1;for F in $PROFILE_FILES;do [ -f "$D/$F" ]&&cp "$D/$F" "/etc/config/$F";done;M="$N";[ "$N" = router-baseline ]&&M=router;if [ "$M" = repeater ]&&[ "$(uci -q get network.wan.proto)" = none ];then rwan||return 1;uci commit network||return 1;psave repeater;fi;if [ "$M" = ap ]&&{ [ "$(uci -q get wireless.mx_mgmt.network)" != mgmt ]||[ "$(uci -q get network.mgmt.ipaddr)" != "$MGMT_IP" ];};then mc "$MGMT_IP" "$LAN_NETMASK" "$DHCP_START";u wireless.mx_mgmt.network=mgmt;u wireless.mx_mgmt.isolate=1;mf;ca;psave ap;fi;if [ "$M" = wds ]&&[ "$(uci -q get network.mgmt.ipaddr)" != "$MGMT_IP" ];then u network.mgmt.ipaddr="$MGMT_IP";uci commit network;psave wds;fi;echo "$M">/etc/mx4200/mode;ra;}
mode(){ cat /etc/mx4200/mode 2>/dev/null||echo router;}
savecur(){ M="$(mode)";case "$M" in router|wds|repeater|ap)psave "$M";;esac;}
priority(){
F=/etc/mx4200/auto-priority;P="$(awk -v m="$1" '$1==m{print $2}' "$F" 2>/dev/null)";printf 'Auto priority for %s (1=first, 9=last, 0=manual; online module) [%s]: ' "$1" "${P:-0}"
read -r V||return 1;V=${V:-${P:-0}};case "$V" in [0-9]);;*)return 1;;esac
[ -f "$F" ]||:>"$F";grep -v "^$1 " "$F">"$F.new";[ "$V" = 0 ]||echo "$1 $V">>"$F.new";mv "$F.new" "$F";chmod 600 "$F";date +%s >/tmp/mxauto-manual
}
psum(){ N=$1;D=$PROFILE_ROOT/$N;pex $N||{ echo 'No profile';return;};echo "Profile: $N";I="$(uci -c "$D" -q get network.lan.ipaddr)";[ -n "$I" ]&&echo "LAN: $I";U="$(uci -c "$D" -q get wireless.mx_primary.ssid)";[ -n "$U" ]&&echo "Upstream: $U";}
ws(){ ubus call network.wireless status 2>/dev/null;}
ri(){ ws|jsonfilter -e "@.$1.interfaces[0].ifname" 2>/dev/null;}
sr(){
R=$1;O=$2;WAIT_MAX=${3:-660};A=/tmp/mxscan.$$;P=$A.p;:>"$A";X="$(iw dev 2>/dev/null|awk '/addr/{printf "%s ",tolower($2)}')";N=1;D=3
if [ "$R" = radio2 ];then D=8;W=0;while [ "$(ws|jsonfilter -e "@.$R.pending" 2>/dev/null)" = true ]&&[ $W -lt "$WAIT_MAX" ];do [ $W = 0 ]&&echo 'Waiting for 5GHz radio/DFS...' >&2;sleep 2;W=$((W+2));done;fi
while [ $N -le 4 ];do
echo "Scan pass $N/4..." >&2
:>"$P";iwinfo "$R" scan >"$P" 2>/dev/null
if [ ! -s "$P" ];then I="$(ri "$R")";[ -n "$I" ]&&iwinfo "$I" scan >"$P" 2>/dev/null;fi
if [ ! -s "$P" ];then H="$(iwinfo "$R" info 2>/dev/null|sed -n 's/.*PHY name: //p'|tail -1)";[ -n "$H" ]||H=phy${R#radio};SCAN_IF=m$$;iw phy "$H" interface add "$SCAN_IF" type managed >/dev/null 2>&1&&{ ip link set "$SCAN_IF" up;sleep 2;iwinfo "$SCAN_IF" scan >"$P" 2>/dev/null;iw dev "$SCAN_IF" del >/dev/null 2>&1;};fi
[ -s "$P" ]&&cat "$P">>"$A";N=$((N+1));[ $N -le 4 ]&&sleep "$D"
done
awk -v x="$X" 'BEGIN{n=split(x,z," ");for(i=1;i<=n;i++)a[z[i]]=1}function f(){if(s!=""&&!a[tolower(b)]){v=g+0;if(!(s in q)||v>q[s]){q[s]=v;l[s]=s"\t"c"\t"g"\t"e"\t"b}}}/^Cell /{f();s=c=g=e="";b=$5;next}/ESSID:/{y=$0;sub(/.*ESSID: "/,"",y);sub(/"[[:space:]]*$/,"",y);s=y}/Channel:/{for(i=1;i<=NF;i++)if($i=="Channel:"){c=$(i+1);break}}/Signal:/{for(i=1;i<=NF;i++)if($i=="Signal:"){g=$(i+1);break}}/Encryption:/{y=$0;sub(/^[[:space:]]*Encryption:[[:space:]]*/,"",y);e=y}END{f();for(i in l)print l[i]}' "$A">"$O"
rm -f "$A" "$P";[ -s "$O" ]
}
e2u(){ E="$(echo "$1"|tr A-Z a-z)";case "$E" in *owe*)echo owe;;*sae*psk*|*psk*sae*|*sae*wpa2*|*wpa2*sae*)echo sae-mixed;;*sae*)echo sae;;*mix*wpa*psk*|*wpa*wpa2*psk*)echo psk-mixed;;*wpa2*psk*|*psk*wpa2*)echo psk2;;*wpa*psk*|*psk*wpa*)echo psk;;*none*|*open*)echo none;;*)echo unsupported;;esac;}
nk(){ case "$1" in none|owe)return 1;;*)return 0;;esac;}
passok(){ [ "${#1}" -ge 8 ]&&[ "${#1}" -le 63 ];}
rs(){ printf %s "$1";if IFS= read -r -s SECRET 2>/dev/null;then echo;else IFS= read -r SECRET;fi;}
EOF
chmod 755 /usr/lib/mxc
cat > /root/mxr <<'EOF'
#!/bin/sh
. /usr/lib/mxc
TARGET="$1"
case "$TARGET" in wds|repeater);;*) exit 1;;esac
date +%s >/tmp/mxauto-manual
WAN_PORT=wan;WAN_PREF=wifi
if [ "$TARGET" = repeater ];then
while true;do printf 'WAN socket: 1=client LAN port 2=wired uplink [2]: ';read -r A||exit 1;case "$A" in 1)WAN_PORT=lan;break;;''|2)break;;esac;done
if [ "$WAN_PORT" = wan ];then
echo 'Failover needs route loss, not just an Internet outage.'
while true;do printf 'Preferred uplink: 1=wired WAN 2=Wi-Fi repeater [2]: ';read -r A||exit 1;case "$A" in ''|2)break;;1)WAN_PREF=wan;break;;esac;done
fi
fi
scan_band(){
R=$1;L=$2;MATCH_SSID=${3:-};REUSE_PASS=${4:-};T=/tmp/mx4200-scan.$$
echo;echo "Scanning $L..."
sr "$R" "$T"||{ rm -f "$T";echo "$L scan failed (4 passes).";return 1; }
TAB="$(printf '\t')";LINE=''
if [ -n "$MATCH_SSID" ];then
while IFS= read -r ROW;do [ "${ROW%%"$TAB"*}" = "$MATCH_SSID" ]&&{ LINE="$ROW";break; };done<"$T"
[ -n "$LINE" ]||{ rm -f "$T";echo "$MATCH_SSID not found on $L.";return 1; }
else
N=0;while IFS="$TAB" read -r S C G E B;do N=$((N+1));printf '%2d) %s  [ch %s, %s dBm, %s, %s]\n' "$N" "$S" "$C" "$G" "$E" "$B";done<"$T"
while true;do printf 'Select network number (0 = rescan): ';read -r P||{ rm -f "$T";return 1; };[ "$P" = 0 ]&&{ rm -f "$T";return 2; };case "$P" in *[!0-9]*|'') continue;;esac;LINE="$(sed -n "${P}p" "$T")";[ -n "$LINE" ]&&break;done
fi
IFS="$TAB" read -r SEL_SSID SEL_CHANNEL _ SEL_ENC_TEXT SEL_BSSID <<EOT
$LINE
EOT
SEL_ENC="$(e2u "$SEL_ENC_TEXT")";rm -f "$T";[ "$SEL_ENC" != unsupported ]||{ echo "Unsupported: $SEL_ENC_TEXT";return 1; };SEL_PASS=''
case "$SEL_ENC" in
psk)
echo "Scan reports $SEL_ENC_TEXT for $SEL_BSSID (WPA1). Check router setting."
while true;do
printf 'Actual upstream: 1=WPA2-PSK 2=WPA1-PSK (no default): ';read -r ESEL||return 1
case "$ESEL" in 1)SEL_ENC=psk2;break;;2)SEL_ENC=psk;break;;*)echo 'Choose 1 or 2.';;esac
done;;
esac
case "$SEL_ENC" in none|owe|psk|psk-mixed) echo 'Backhaul requires authenticated WPA2/WPA3; open/OWE/WPA1 is refused.';return 1;;esac
if [ -n "$MATCH_SSID" ]&&[ -n "$REUSE_PASS" ]&&! nk "$SEL_ENC";then
echo "$L network has no password; choose it separately."
return 1
fi
if nk "$SEL_ENC";then
if [ -n "$MATCH_SSID" ];then SEL_PASS="$REUSE_PASS";else rs "Upstream Wi-Fi password for $SEL_SSID: ";SEL_PASS="$SECRET";fi
[ -n "$SEL_PASS" ]||{ echo 'Password required';return 1; }
fi
}
uci -q get network.usbwan >/dev/null 2>&1 && /usr/sbin/mxu off-quiet
savecur
RD="$PROFILE_ROOT/router"
R_LAN_IP="$(uci -c "$RD" -q get network.lan.ipaddr 2>/dev/null)"; [ -n "$R_LAN_IP" ] || R_LAN_IP="$LAN_IP"
R_LAN_NETMASK="$(uci -c "$RD" -q get network.lan.netmask 2>/dev/null)"; [ -n "$R_LAN_NETMASK" ] || R_LAN_NETMASK="$LAN_NETMASK"
R_DHCP_START="$(uci -c "$RD" -q get dhcp.lan.start 2>/dev/null)"; [ -n "$R_DHCP_START" ] || R_DHCP_START="$DHCP_START"
R_DHCP_LIMIT="$(uci -c "$RD" -q get dhcp.lan.limit 2>/dev/null)"; [ -n "$R_DHCP_LIMIT" ] || R_DHCP_LIMIT="$DHCP_LIMIT"
R_DHCP_LEASE="$(uci -c "$RD" -q get dhcp.lan.leasetime 2>/dev/null)"; [ -n "$R_DHCP_LEASE" ] || R_DHCP_LEASE="$DHCP_LEASETIME"
PR='radio2'; PL='5 GHz'; OR='radio1'; OL='2.4 GHz'
echo 'Primary: 5G/radio2 (DFS delay); backup: 2.4G/radio1.'
while true;do scan_band "$PR" "$PL";R=$?;[ "$R" = 0 ]&&break;[ "$R" = 2 ]&&continue;echo '1=retry  0=cancel';read -r A;[ "$A" = 1 ]||exit 1;done
PSSID="$SEL_SSID";PENC="$SEL_ENC";PPASS="$SEL_PASS";PCHAN="$SEL_CHANNEL";PAP="$SEL_BSSID"
echo;echo "Selected: $PSSID ($PL ch $PCHAN, $PENC); client APs: $PENC"
BACKUP=0;BSSID='';BENC='';BPASS='';BRAD='';BCHAN='';BAP=''
while true;do
echo;printf '2.4 backup: 1=same name/key 2=scan another 0=none: ';read -r B||break
case "$B" in
1)scan_band "$OR" "$OL" "$PSSID" "$PPASS";R=$?;;
2)scan_band "$OR" "$OL";R=$?;;
0|'')break;;
*)continue;;
esac
[ "$R" = 0 ]&&{ BACKUP=1;BRAD="$OR";BSSID="$SEL_SSID";BENC="$SEL_ENC";BPASS="$SEL_PASS";BCHAN="$SEL_CHANNEL";BAP="$SEL_BSSID";echo "Backup: $BSSID ($OL ch $BCHAN, $BENC)";break; }
done
CLIENT_PASS=''
if nk "$PENC";then
rs "MX4200 client Wi-Fi password for ${PSSID}-RPT (not upstream, 8-63 chars): "
CLIENT_PASS="$SECRET"
passok "$CLIENT_PASS" || { echo 'Repeater password must be 8-63 characters'; exit 1; }
else echo "Client Wi-Fi: $PENC (no password)";fi
MGMT_PASS=''
if [ "$TARGET" = wds ]; then
echo
echo "Mgmt AP: ${PSSID}-Management"
echo "Mgmt IP: $MGMT_IP"
rs 'Separate Management Wi-Fi password (8-63 chars): '
MGMT_PASS="$SECRET"
passok "$MGMT_PASS" || { echo 'Management password must be 8-63 characters'; exit 1; }
fi
wifi_clear
u system.@system[0].hostname="$ROUTER_HOSTNAME"
BR="$(ds br-lan)"
[ -n "$BR" ] || { echo 'br-lan not found'; exit 1; }
u ${BR}.stp=1
uci -q delete "${BR}.ports"
if [ "$TARGET" = wds ]; then
uci add_list "${BR}.ports=lan2"
uci add_list "${BR}.ports=lan3"
ld;u network.lan.metric=5
mc "$MGMT_IP" "$LAN_NETMASK" "$DHCP_START" lan1 "$R_DHCP_LEASE"
else
uci add_list "${BR}.ports=lan1"
uci add_list "${BR}.ports=lan2"
uci add_list "${BR}.ports=lan3"
sl "$R_LAN_IP" "$R_LAN_NETMASK" "$R_DHCP_START" "$R_DHCP_LIMIT" "$R_DHCP_LEASE"
uci -q delete network.br_mgmt
uci -q delete network.mgmt
uci -q delete dhcp.mgmt
fi
uci -q delete network.usbwan
if [ "$TARGET" = repeater ];then
if [ "$WAN_PORT" = lan ];then rwan||{ echo 'Could not add WAN socket to LAN bridge';exit 1; };else u network.wan.device=wan;u network.wan.proto=dhcp;uci -q delete network.wan6.disabled;fi
u network.wan.mx_priority="$WAN_PREF"
for X in wwanp wwanb;do u network.$X=interface;u network.$X.proto=dhcp;done
u network.wwanp.metric=5;u network.wwanb.metric=15;[ "$WAN_PREF" = wan ]&&u network.wan.metric=3||u network.wan.metric=20;uci -q delete network.wdsp;uci -q delete network.wdsb
else
u network.wan.device=wan
u network.wan.proto=dhcp
uci -q delete network.wan.mx_priority
uci -q delete network.wan6.disabled
for X in wdsp wdsb;do u network.$X=interface;u network.$X.proto=none;done
uci -q delete network.wwanp;uci -q delete network.wwanb;u network.wan.metric=10
fi
sta(){ S=$1;R=$2;N=$3;Q=$4;A=$5;E=$6;K=$7;u wireless.$S=wifi-iface;u wireless.$S.device="$R";u wireless.$S.mode=sta;u wireless.$S.network="$N";u wireless.$S.ssid="$Q";u wireless.$S.bssid="$A";u wireless.$S.encryption="$E";nk "$E"&&u wireless.$S.key="$K";[ "$TARGET" = wds ]&&u wireless.$S.wds=1;u wireless.$S.disabled=0;}
u "wireless.$PR.channel=$PCHAN";sta mx_primary "$PR" "$( [ "$TARGET" = wds ]&&echo wdsp||echo wwanp )" "$PSSID" "$PAP" "$PENC" "$PPASS"
if [ "$BACKUP" = 1 ];then u "wireless.$BRAD.channel=$BCHAN";sta mx_backup "$BRAD" "$( [ "$TARGET" = wds ]&&echo wdsb||echo wwanb )" "$BSSID" "$BAP" "$BENC" "$BPASS";else uci -q delete wireless.mx_backup;uci -q delete network.wwanb;uci -q delete network.wdsb;fi
ap mx_ap5 radio0 lan "${PSSID}-RPT-5G" "$CLIENT_PASS" "$PENC";ap mx_ap2 radio1 lan "${PSSID}-RPT-2G" "$CLIENT_PASS" "$PENC"
if [ "$TARGET" = wds ];then ap mx_mgmt radio1 mgmt "${PSSID}-Management" "$MGMT_PASS";else uci -q delete wireless.mx_mgmt;fi
dz mgmt;dz uplink;lz;wz
WZ="$(zs wan)";[ -n "$WZ" ]&&{ for N in wan lan wwan wwanp wwanb usbwan;do uci -q del_list "${WZ}.network=$N";done;uci add_list "${WZ}.network=wan";[ "$TARGET" = wds ]&&uci add_list "${WZ}.network=lan";}
uci -q delete firewall.mx_wan_lan
if [ "$TARGET" = wds ];then
dz lan;uci -q delete firewall.mx_mgmt_wan;mf;fw mgmt wan
else
uz;df lan;df uplink;fw lan uplink;fw lan wan;mr wan;mr uplink
fi
ca
echo "$TARGET" > /etc/mx4200/mode
psave "$TARGET"
priority "$TARGET"
ra
echo
echo 'Applied; Wi-Fi may reconnect.'
sleep 10
/usr/sbin/mxm status
[ "$TARGET" = wds ] && {
echo
/root/mxwds 2>/dev/null || true
echo
echo 'WDS DHCP/DNS: upstream'
echo "Mgmt Wi-Fi: ${PSSID}-Management"
echo "Mgmt IP: $(uci -q get network.mgmt.ipaddr)"
}
EOF
chmod 755 /root/mxr
cat > /root/mxa <<'EOF'
#!/bin/sh
. /usr/lib/mxc
date +%s >/tmp/mxauto-manual
printf 'AP Wi-Fi name [%s]: ' "$WIFI_PREFIX";IFS= read -r Q||exit 1;Q=${Q:-$WIFI_PREFIX}
[ "$(printf %s "$Q"|LC_ALL=C wc -c)" -le 21 ]||{ echo 'Name too long for -Management SSID';exit 1; }
rs "Password for $Q Wi-Fi: ";P=$SECRET
rs "Password for ${Q}-Management Wi-Fi: ";K=$SECRET
for V in "$P" "$K";do passok "$V"||{ echo 'Passwords must be 8-63 characters';exit 1; };done
savecur;wifi_clear;rb
B="$(ds br-lan)";[ -n "$B" ]||{ echo 'br-lan not found';exit 1; }
uci -q delete "${B}.ports";for I in lan1 lan2 lan3;do uci add_list "${B}.ports=$I";done
rwan||exit 1
ld
for I in wwanp wwanb wdsp wdsb usbwan;do uci -q delete "network.$I";done
mc "$MGMT_IP" "$LAN_NETMASK" "$DHCP_START"
ap mx_ap2 radio1 lan "$Q" "$P";ap mx_ap5 radio0 lan "$Q" "$P";ap mx_ap_high radio2 lan "$Q" "$P"
ap mx_mgmt radio1 mgmt "${Q}-Management" "$K";u wireless.mx_mgmt.isolate=1
dz uplink;lz;df lan;mf
Z="$(zs wan)";[ -n "$Z" ]&&{ for I in lan wwanp wwanb usbwan;do uci -q del_list "${Z}.network=$I";done; }
ca;echo ap >/etc/mx4200/mode;psave ap;priority ap;ra
echo "Wired AP: all Ethernet ports are LAN; main router supplies DHCP."
echo "Management SSID: ${Q}-Management | IP: $(uci -q get network.mgmt.ipaddr)"
EOF
chmod 755 /root/mxa
cat > /usr/sbin/mxb <<'EOF'
#!/bin/sh
. /usr/lib/mxc
si(){ S=$1;R="$(uci -q get wireless.$S.device)";J="$(ubus call network.wireless status 2>/dev/null)";for N in 0 1 2 3;do [ "$(echo "$J"|jsonfilter -e "@.$R.interfaces[$N].section" 2>/dev/null)" = "$S" ]&&{ echo "$J"|jsonfilter -e "@.$R.interfaces[$N].ifname";return;};done;}
up(){ I="$(si $1)";[ -n "$I" ]&&iw dev "$I" link 2>/dev/null|grep -q '^Connected to ';}
rp(){
S=$1;M="$(mode)";case "$M" in wds|repeater);;*)return;;esac
case "$(uci -q get wireless.$S.encryption)" in psk2|sae|sae-mixed);;*)return;;esac
up "$S"&&return
R="$(uci -q get wireless.$S.device)";Q="$(uci -q get wireless.$S.ssid)"
[ -n "$R" ]&&[ -n "$Q" ]&&[ "$(uci -q get wireless.$S.disabled)" = 0 ]||return
T=/tmp/mxb.$$;sr "$R" "$T" 20||{ rm -f "$T";return; }
[ "$(mode)" = "$M" ]&&[ "$(uci -q get wireless.$S.device)" = "$R" ]&&[ "$(uci -q get wireless.$S.ssid)" = "$Q" ]&&[ "$(uci -q get wireless.$S.disabled)" = 0 ]&&! up "$S"||{ rm -f "$T";return; }
LINE="$(awk -F '\t' -v s="$Q" '$1==s{print $2"\t"$4"\t"$5;exit}' "$T")";rm -f "$T"
C=$(printf '%s\n' "$LINE"|cut -f1);E=$(printf '%s\n' "$LINE"|cut -f2);B=$(printf '%s\n' "$LINE"|cut -f3)
case "$C" in ''|*[!0-9]*)return;;esac
[ "$(e2u "$E")" = "$(uci -q get wireless.$S.encryption)" ]||return
[ -n "$B" ]||return
CHANGED=0
[ "$(uci -q get wireless.$S.bssid)" = "$B" ]||{ uci set wireless.$S.bssid="$B";CHANGED=1; }
[ "$(uci -q get wireless.$R.channel)" = "$C" ]||{ uci set wireless.$R.channel="$C";CHANGED=1; }
[ "$CHANGED" = 1 ]&&{ uci commit wireless;wifi reload "$R"; }
}
sw(){ P="$(si mx_primary)";B="$(si mx_backup)";[ -n "$P" ]&&ip link set "$P" nomaster 2>/dev/null;[ -n "$B" ]&&ip link set "$B" nomaster 2>/dev/null;I="$P";[ "$1" = backup ]&&I="$B";if [ -n "$I" ]&&ip link set "$I" master br-lan 2>/dev/null;then ubus call network.interface.lan renew >/dev/null 2>&1;fi;echo "$1">/tmp/mx4200-backhaul-active;}
case "$1" in
primary|backup) X=$1;[ "$X" = backup ]&&uci -q get wireless.mx_backup >/dev/null||[ "$X" = primary ]||exit 1;uci set wireless.mx_primary.disabled=$([ "$X" = primary ]&&echo 0||echo 1);uci -q get wireless.mx_backup >/dev/null&&uci set wireless.mx_backup.disabled=$([ "$X" = backup ]&&echo 0||echo 1);uci commit wireless;wifi reload;[ "$(mode)" = wds ]&&{ sleep 2;sw "$X"; };;
auto) uci set wireless.mx_primary.disabled=0;uci -q get wireless.mx_backup >/dev/null&&uci set wireless.mx_backup.disabled=0;uci commit wireless;wifi reload;;
guard)
A="$(cat /tmp/mx4200-backhaul-active 2>/dev/null||echo primary)";S=0;K=29;SCAN_PID=''
trap '[ -z "$SCAN_PID" ] || kill "$SCAN_PID" 2>/dev/null' EXIT
while sleep 1;do
M="$(mode)";case "$M" in router|ap)continue;;esac
P=0;B=0;up mx_primary&&P=1;up mx_backup&&B=1
if [ "$M" = wds ];then
D="$(uci -q get wireless.mx_primary.disabled)$(uci -q get wireless.mx_backup.disabled)"
if [ "$D" = 00 ];then
if [ "$A" = primary ];then
[ "$P" = 0 ]&&[ "$B" = 1 ]&&{ A=backup;S=0;sw backup; }
else
[ "$P" = 1 ]&&S=$((S+1))||S=0
[ "$S" -ge 30 ]&&{ A=primary;S=0;sw primary; }
[ "$B" = 1 ]||[ "$P" = 0 ]||{ A=primary;S=0;sw primary; }
fi
else
[ "$(uci -q get wireless.mx_primary.disabled)" = 0 ]&&A=primary||A=backup
fi
I="$(si mx_$A)";[ -n "$I" ]&&[ -e "/sys/class/net/br-lan/brif/$I" ]||sw "$A"
fi
K=$((K+1))
if [ "$K" -ge 30 ];then
if [ -z "$SCAN_PID" ] || ! kill -0 "$SCAN_PID" 2>/dev/null;then
{ [ "$B" = 1 ] || rp mx_backup; [ "$P" = 1 ] || rp mx_primary; } &
SCAN_PID=$!
fi
K=0
fi
done;;
*) echo 'mxb: auto|primary|backup|guard';exit 1;;esac
EOF
chmod 755 /usr/sbin/mxb
cat > /etc/init.d/mxb <<'EOF'
#!/bin/sh /etc/rc.common
START=95
USE_PROCD=1
start_service(){ procd_open_instance;procd_set_param command /usr/sbin/mxb guard;procd_set_param respawn 3600 5 5;procd_close_instance;}
EOF
chmod 755 /etc/init.d/mxb
/etc/init.d/mxb enable
cat > /usr/sbin/mxu <<'EOF'
#!/bin/sh
. /usr/lib/mxc
find_usb() {
for I in $(ls /sys/class/net 2>/dev/null); do
case "$I" in lo|br-*|lan*|wan|wlan*|phy*|tailscale*|ifb*) continue ;; esac
P="$(readlink -f "/sys/class/net/$I/device" 2>/dev/null)"
echo "$P" | grep -q '/usb' && { echo "$I"; return 0; }
done
return 1
}
rmet() {
M="$(mode)"
case "$M" in
repeater) uci -q set network.wwanp.metric='5';uci -q set network.wwanb.metric='15';[ "$(uci -q get network.wan.mx_priority)" = wan ]&&uci set network.wan.metric='3'||uci set network.wan.metric='20';;
*) uci set network.wan.metric='10' ;;
esac
}
apply_usb() {
ROLE="$1"; I="$(find_usb)"
[ -n "$I" ] || { echo 'No USB tether interface'; return 1; }
uci set network.usbwan='interface'
uci set network.usbwan.device="$I"
uci set network.usbwan.proto='dhcp'
rmet
if [ "$ROLE" = primary ]; then
uci set network.usbwan.metric='3'
uci set network.wan.metric='20'
uci -q get network.wwanp >/dev/null&&uci set network.wwanp.metric='10'
else
uci set network.usbwan.metric='30'
fi
Z="$(zs wan)"
[ -n "$Z" ] && { uci -q del_list "${Z}.network=usbwan"; uci add_list "${Z}.network=usbwan"; }
uci commit network; uci commit firewall
printf "LAST_ROLE='%s'\n" "$ROLE" > /etc/mx4200/usb.conf
chmod 600 /etc/mx4200/usb.conf
/etc/init.d/network restart
/etc/init.d/firewall restart
echo "USB $ROLE: $I"
}
off_usb() {
uci -q delete network.usbwan
Z="$(zs wan)"; [ -n "$Z" ] && uci -q del_list "${Z}.network=usbwan"
rmet
uci commit network; uci commit firewall
[ "$1" = quiet ] || { /etc/init.d/network restart; /etc/init.d/firewall restart; echo 'USB off'; }
}
case "$1" in
detect) I="$(find_usb)"; [ -n "$I" ] && echo "USB tether interface: $I" || echo 'No USB interface' ;;
primary|backup) apply_usb "$1" ;;
off) off_usb ;;
off-quiet) off_usb quiet ;;
menu|'')
I="$(find_usb)"
echo "USB: ${I:-none}"
LAST=''; [ -f /etc/mx4200/usb.conf ] && . /etc/mx4200/usb.conf && LAST="$LAST_ROLE"
[ -n "$LAST" ] && echo "USB role: $LAST"
echo '1=Restore last USB role  2=Primary route  3=Backup route'
echo '4=Disable USB tethering  0=Cancel'
printf 'Choose: '; read -r C
case "$C" in
1) [ -n "$LAST" ] && apply_usb "$LAST" || echo 'No saved role' ;;
2) apply_usb primary ;;
3) apply_usb backup ;;
4) off_usb ;;
esac
;;
*) echo 'mxu: menu|detect|primary|backup|off' ;;
esac
EOF
chmod 755 /usr/sbin/mxu
cat > /usr/sbin/mxw <<'EOF'
#!/bin/sh
. /usr/lib/mxc
[ "$(mode)" = wds ] || exit 1
STA='';for I in $(iw dev 2>/dev/null|awk '/Interface/{i=$2}/type managed/{print i}');do [ -e "/sys/class/net/br-lan/brif/$I" ]&&{ STA=$I;break;};done
[ -n "$STA" ] || { echo RED; exit; }
iw dev "$STA" link 2>/dev/null | grep -q '^Connected to ' || { echo RED; exit; }
iw dev "$STA" info 2>/dev/null | grep -q '4addr: on' || { echo ORANGE; exit; }
[ -e "/sys/class/net/br-lan/brif/$STA" ] || { echo ORANGE; exit; }
IP="$(ip -4 addr show dev br-lan 2>/dev/null|awk '/inet /{sub(/\/.*/,"",$2);print $2;exit}')"
[ -n "$IP" ] && ip -4 route show default dev br-lan 2>/dev/null|grep -q '^default ' || { echo ORANGE; exit; }
if ! ping -I br-lan -c 1 -W 1 "$DNS_FALLBACK_1" >/dev/null 2>&1 && ! ping -I br-lan -c 1 -W 1 "$WDS_TEST_IP2" >/dev/null 2>&1; then echo ORANGE; exit; fi
OK=0
for D in $(ubus call network.interface.lan status 2>/dev/null|jsonfilter -e '@["dns-server"][*]' 2>/dev/null); do dig -b "$IP" +time=1 +tries=1 +short @"$D" "$DNS_TEST_NAME" 2>/dev/null | grep -q . && { OK=1; break; }; done
[ "$OK" = 1 ] && echo GREEN || echo YELLOW
EOF
chmod 755 /usr/sbin/mxw
cat > /root/mxwds <<'EOF'
#!/bin/sh
. /usr/lib/mxc
[ "$(mode)" = wds ] || { echo 'Not WDS mode'; exit 1; }
ip -4 addr show dev br-lan
ip -4 route show default dev br-lan
ubus call network.interface.lan status 2>/dev/null|jsonfilter -e '@["dns-server"][*]'|sed 's/^/DNS: /'
printf 'WDS health: ';/usr/sbin/mxw
EOF
chmod 755 /root/mxwds
cat > /usr/sbin/mxd <<'EOF'
#!/bin/sh
. /etc/mx4200/base.conf
mgmt(){
case "$(cat /etc/mx4200/mode 2>/dev/null)" in ap|wds);;*)return 0;;esac
I="$(ip -4 -o addr show dev br-lan 2>/dev/null|awk '$3=="inet"{print $4}')";[ -n "$I" ]||return 0
R="$(ip -4 route show table main 2>/dev/null;for X in $I;do echo "$X dev br-lan";done)"
free_ip(){ printf '%s\n' "$R"|awk -v a="$1" '
function n(s,v){split(s,v,".");return v[1]*16777216+v[2]*65536+v[3]*256+v[4]}
BEGIN{x=n(a)}
$1~/^[0-9]+\./&&$0!~/ dev br-mgmt( |$)/{
split($1,p,"/");m=2^(32-(p[2]?p[2]:32));y=n(p[1]);
if(int(x/m)==int(y/m)||int(x/256)==int(y/256))exit 1
}';}
P='';for A in "$MGMT_IP" 172.29.251.1 10.253.247.1 192.168.247.1;do free_ip "$A"&&{ P="$A";break;};done
[ -n "$P" ]||{ logger -t mxmgmt 'No free management subnet; keeping current IP';return 1; }
[ "$(uci -q get network.mgmt.ipaddr)" = "$P" ]&&return 0
uci set network.mgmt.ipaddr="$P"&&uci commit network||return 1
ifdown mgmt;ifup mgmt||return 1;/etc/init.d/dnsmasq restart||return 1
logger -t mxmgmt "Management IP: $P"
}
[ "$1" = mgmt ]&&{ mgmt;exit $?; }
STATE='/tmp/mx4200-dns-owned'
while true; do
if ping -c 1 -W 1 "$DNS_FALLBACK_1" >/dev/null 2>&1; then
OK=0
for D in $(awk '/^nameserver/{print $2}' /tmp/resolv.conf.d/resolv.conf.auto 2>/dev/null | grep -vE '^(127\.|::1$)'); do
dig +time=1 +tries=1 +short @"$D" "$DNS_TEST_NAME" 2>/dev/null | grep -q . && { OK=1; break; }
done
EXPLICIT="$(uci -q get dhcp.@dnsmasq[0].server 2>/dev/null)"
if [ "$OK" = 1 ]; then
if [ -f "$STATE" ]; then
uci set dhcp.@dnsmasq[0].noresolv='0'; uci -q delete dhcp.@dnsmasq[0].server; uci commit dhcp; /etc/init.d/dnsmasq restart; rm -f "$STATE"
fi
elif [ -z "$EXPLICIT" ] || [ -f "$STATE" ]; then
uci set dhcp.@dnsmasq[0].noresolv='1'; uci -q delete dhcp.@dnsmasq[0].server
uci add_list dhcp.@dnsmasq[0].server="$DNS_FALLBACK_1"; uci add_list dhcp.@dnsmasq[0].server="$DNS_FALLBACK_2"
uci commit dhcp; /etc/init.d/dnsmasq restart; touch "$STATE"
fi
fi
if command -v tailscale >/dev/null 2>&1&&[ ! -f /tmp/mx-ts-init ]&&tailscale status --json 2>/dev/null|grep -q '"BackendState"[[:space:]]*:[[:space:]]*"Running"';then tailscale set --advertise-exit-node --accept-routes=true >/dev/null 2>&1&&touch /tmp/mx-ts-init;fi
mgmt
sleep 60
done
EOF
chmod 755 /usr/sbin/mxd
cat > /etc/init.d/mxd <<'EOF'
#!/bin/sh /etc/rc.common
START=96
STOP=10
USE_PROCD=1
start_service(){ procd_open_instance; procd_set_param command /usr/sbin/mxd; procd_set_param respawn 3600 5 5; procd_close_instance; }
EOF
chmod 755 /etc/init.d/mxd
/etc/init.d/mxd enable
mkdir -p /etc/hotplug.d/iface
cat > /etc/hotplug.d/iface/95-mxmgmt <<'EOF'
#!/bin/sh
[ "$INTERFACE" = lan ]&&case "$ACTION" in ifup|ifupdate)/usr/sbin/mxd mgmt;;esac
EOF
cat > /usr/sbin/mxmod <<'EOF'
#!/bin/sh
BASE='https://raw.githubusercontent.com/geekymahar/linksys-openwrt-toolkit/main/mx4200-v2/modules/provision'
HASH='ad471d9734def02cbd9d16ad39726789df60c4e0a1e38143c1bda8d4c04b7569'
case "$1" in
status|once) N=led;BIN=/usr/bin/mxls ;;
auto-status|auto-once) N=auto;BIN=/usr/sbin/mxauto ;;
samba-status|samba-once) N=samba;BIN=/usr/libexec/rpcd/mx.samba ;;
provision) N=all ;;
*) echo 'mxmod: provision|once|auto-once|samba-once|status|auto-status|samba-status';exit 1 ;;
esac
case "$1" in *status) [ -x "$BIN" ] && [ -s "/etc/mx4200/modules/$N.installed" ] && { echo "$N installed";exit 0; };echo "$N pending";exit 1;;esac
T=/tmp/mx-provision-installer.$$
trap 'rm -f "$T"' EXIT HUP INT TERM
uclient-fetch -q -T 15 -O "$T" "$BASE/install.sh" 2>/dev/null || curl -fsSL --connect-timeout 5 --max-time 15 -o "$T" "$BASE/install.sh" 2>/dev/null || exit 1
[ "$(sha256sum "$T"|awk '{print $1}')" = "$HASH" ] && sh "$T" "$N"
EOF
chmod 755 /usr/sbin/mxmod
cat > /usr/sbin/mxfirstboot <<'EOF'
#!/bin/sh
while :;do
if ip -4 route show default 2>/dev/null|grep -q '^default ';then
if mkdir /etc/mx4200/provision-attempted 2>/dev/null;then /usr/sbin/mxmod provision||logger -t mxprovision 'Core handoff unavailable';fi
/etc/init.d/mxprovision disable
exit 0
fi
sleep 60
done
EOF
chmod 755 /usr/sbin/mxfirstboot
cat > /etc/init.d/mxprovision <<'EOF'
#!/bin/sh /etc/rc.common
START=99
USE_PROCD=1
start_service(){ procd_open_instance;procd_set_param command /usr/sbin/mxfirstboot;procd_close_instance; }
EOF
chmod 755 /etc/init.d/mxprovision
/etc/init.d/mxprovision enable
cat > /usr/sbin/mxm <<'EOF'
#!/bin/sh
. /usr/lib/mxc
duo(){
uci -q get network.usbwan >/dev/null 2>&1 && { echo 'USB tether off...'; /usr/sbin/mxu off-quiet; }
}
sil(){
TARGET="$1"
date +%s >/tmp/mxauto-manual
duo
[ "$(mode)" != "$TARGET" ] && savecur
}
ract(){
CUR="$(mode)"
echo
echo "Mode: $CUR"
[ "$CUR" = router ] && echo 'Router active.'
echo
pex router && psum router
echo
echo '1=Saved router profile  2=First-boot baseline  0=Cancel'
[ "$CUR" = router ]&&echo '3=Save current router settings'
printf 'Choose: '; read -r C
case "$C" in
1) pex router && { sil router; priority router; pload router; } || echo 'No router profile' ;;
2) duo; [ "$CUR" = router ] && psave router; [ "$CUR" != router ] && savecur; priority router; pload router-baseline || echo 'No baseline' ;;
3) [ "$CUR" = router ] && { psave router; priority router; } ;;
esac
}
pact(){
echo
echo '1=WDS: bridge/upstream DHCP; upstream AP must support WDS'
echo '2=Routed repeater: own LAN/DHCP; works with a normal Wi-Fi AP'
echo '0=Cancel'
printf 'Choose: '; read -r C
case "$C" in 1) T=wds;; 2) T=repeater;; *) return;; esac
echo
if pex "$T"; then
psum "$T"
echo
echo '1=Use saved settings  2=Scan and enter Wi-Fi credentials  0=Cancel'
printf 'Choose: '; read -r A
case "$A" in
1) sil "$T"; priority "$T"; pload "$T" ;;
2) exec /root/mxr "$T" ;;
esac
else
echo 'No saved profile; starting new setup.'
exec /root/mxr "$T"
fi
}
aact(){
echo '1=Restore saved wired AP'
echo '2=Configure wired AP; Ethernet ports become LAN'
echo '3=Change isolated Management Wi-Fi password  0=Cancel'
printf 'Choose: ';read -r C
case "$C" in
1) pex ap && { sil ap;priority ap;pload ap; } || echo 'No AP profile' ;;
2) /root/mxa ;;
3) [ "$(mode)" = ap ]||{ echo 'Wired AP mode required';return; }
rs 'New Management Wi-Fi password: ';K=$SECRET
[ "${#K}" -ge 8 ]&&[ "${#K}" -le 63 ]||{ echo 'Password must be 8-63 characters';return; }
uci set wireless.mx_mgmt.key="$K";uci commit wireless;psave ap;wifi reload radio1;;
esac
}
bact(){
case "$(mode)" in wds|repeater);;*) echo 'Repeater required.';return;;esac
echo '1=Auto: primary plus configured backup'
echo '2=5 GHz primary only  3=2.4 GHz backup only  0=Cancel'
printf 'Choose: ';read -r C
case "$C" in 1) /usr/sbin/mxb auto;;2) /usr/sbin/mxb primary;;3) /usr/sbin/mxb backup;;esac
}
sact(){
MODE="$(mode)"
echo "Mode: $MODE"
echo "Host: $(uci -q get system.@system[0].hostname)"
echo
echo 'Routes:'
ip -4 route show default
GW="$(ip -4 route show default 2>/dev/null|awk '/^default /{for(i=1;i<=NF;i++)if($i=="via"){print $(i+1);exit}}')";[ -n "$GW" ]&&echo "Upstream gateway: $GW"
echo
if [ "$MODE" = wds ]; then
for I in $(iw dev 2>/dev/null | awk '/Interface/{i=$2}/type managed/{print i}'); do
echo "--- $I ---"; iw dev "$I" link 2>/dev/null; iw dev "$I" info 2>/dev/null | grep -E 'type|channel|4addr' || true
done
printf 'WDS health: '; /usr/sbin/mxw 2>/dev/null || true
ip -4 addr show dev br-lan 2>/dev/null | awk '/inet /{print "WDS upstream IP: "$2;exit}'
MIP="$(uci -q get network.mgmt.ipaddr 2>/dev/null)"; [ -n "$MIP" ] || MIP="$MGMT_IP"
echo "Mgmt IP: $MIP"
else
for N in wwanp wwanb;do ubus call network.interface.$N status 2>/dev/null|jsonfilter -e '@["ipv4-address"][0].address' 2>/dev/null|sed "s/^/$N IPv4: /";done
ip -4 addr show br-lan 2>/dev/null | awk '/inet /{print "LAN: "$2}'
fi
[ "$MODE" = ap ]&&echo "Management: $(uci -q get wireless.mx_mgmt.ssid) at $(uci -q get network.mgmt.ipaddr)"
echo
[ -f /tmp/mx4200-led-state ] && { echo 'LED:'; cat /tmp/mx4200-led-state; }
if [ -x /usr/bin/mxls ]; then /usr/bin/mxls detect 2>/dev/null | sed 's/^/  /'; else /usr/sbin/mxmod status; fi
uci -q get network.usbwan >/dev/null 2>&1 && { echo; ubus call network.interface.usbwan status 2>/dev/null | jsonfilter -e '@["ipv4-address"][0].address' 2>/dev/null|sed 's/^/USB IPv4: /';ubus call network.interface.usbwan status 2>/dev/null|jsonfilter -e '@.l3_device' 2>/dev/null|sed 's/^/USB device: /'; }
}
lact(){
if ! /usr/sbin/mxmod status >/dev/null; then
echo 'LED module not installed. Automatic fetch runs only on a clean first boot.'
echo '1=Install now 0=Cancel'
printf 'Choose: '; read -r C
[ "$C" = 1 ] && { /usr/sbin/mxmod once && echo 'LED module installed.' || echo 'LED module download unavailable.'; }
return
fi
echo '1=Detect hardware  2=Automatic  3=Show state'
echo '4-11=Force color (red, green, blue, purple, orange, yellow, teal, white)'
echo '12=LED off  0=Cancel'
printf 'Choose: '; read -r C
case "$C" in
1) /usr/bin/mxls detect;;
2) /etc/init.d/mxl enable; /etc/init.d/mxl restart;;
3) cat /tmp/mx4200-led-state 2>/dev/null || echo 'No LED state';;
4|5|6|7|8|9|10|11|12) set -- red green blue purple orange yellow teal white off;shift $((C-4));/etc/init.d/mxl stop;/usr/bin/mxls "$1";;
esac
}
mact(){
echo 'Signed module install: 1=LED 2=Auto failover 3=Samba users 0=Cancel'
printf 'Choose: ';read -r C
case "$C" in 1|2|3) set -- once auto-once samba-once;shift $((C-1));/usr/sbin/mxmod "$1"&&echo 'Updated.'||echo 'Update failed.';;esac
}
menu(){
while true; do
echo
echo '=== MX4200 ==='
echo "Current mode: $(mode)"
echo 'Router=own DHCP | Repeater=Wi-Fi uplink | Wired-AP=cable, upstream DHCP'
echo '1=Router profiles  2=Repeater/WDS  3=USB tether  4=Wi-Fi backhaul'
echo '5=Status  6=WDS diagnostics (WDS mode)  7=LED  8=Wired AP'
echo '9=Signed module install/update  0=Exit'
printf 'Choose: '; read -r C
case "$C" in
1) ract;; 2) pact;; 3) /usr/sbin/mxu menu;; 4) bact;; 5) sact;; 6) /root/mxwds;; 7) lact;; 8) aact;; 9) mact;; 0) exit;;
esac
done
}
case "$1" in
router) ract;; repeater) pact;; ap) aact;; usb) /usr/sbin/mxu menu;; backhaul) bact;; status) sact;; led) lact;; update) mact;; wdstest) /root/mxwds;;
help|-h|--help)
echo 'mx: menu; mxstatus: mode, route, IPs'
echo 'mxrouter: saved/baseline | mxrepeater: WDS/routed setup'
echo 'mxap: wired AP | mxusb: tether | mxled: LED'
echo 'mxauto status: saved-mode priorities (optional)'
echo 'mx update: signed LED, Auto, Samba'
;;
'') menu;; *) menu;;
esac
EOF
chmod 755 /usr/sbin/mxm
ln -sf /usr/sbin/mxm /usr/bin/mx
mkdir -p /etc/profile.d
cat > /etc/profile.d/mx <<'EOF'
alias mxstatus='/usr/sbin/mxm status'
alias mxrouter='/usr/sbin/mxm router'
alias mxrepeater='/usr/sbin/mxm repeater'
alias mxap='/usr/sbin/mxm ap'
alias mxusb='/usr/sbin/mxm usb'
alias mxled='/usr/sbin/mxm led'
alias mxhelp='/usr/sbin/mxm help'
case "$-" in
*i*)
echo
echo 'MX4200: run mx for guided router, repeater/WDS and USB setup.'
echo 'Quick: mxstatus mxrouter mxrepeater mxap mxusb mxled | mxhelp'
;;
esac
EOF
chmod 644 /etc/profile.d/mx
ln -sf mx /etc/profile.d/mx.sh
. /usr/lib/mxc
wifi_clear
rb
u system.@system[0].hostname="$ROUTER_HOSTNAME"
sl "$LAN_IP" "$LAN_NETMASK" "$DHCP_START" "$DHCP_LIMIT" "$DHCP_LEASETIME"
BR="$(ds br-lan)"
[ -n "$BR" ] && { u ${BR}.stp=1; uci -q delete "${BR}.ports"; uci add_list "${BR}.ports=lan1"; uci add_list "${BR}.ports=lan2"; uci add_list "${BR}.ports=lan3"; }
uci -q delete network.br_mgmt
uci -q delete network.mgmt
for X in wwan wwanp wwanb wdsp wdsb usbwan;do uci -q delete network.$X;done
u network.wan.proto=dhcp
u network.wan.metric=10
uci -q delete dhcp.mgmt
dap(){ S=default_radio$1;u wireless.$S=wifi-iface;u wireless.$S.device=radio$1;u wireless.$S.network=lan;u wireless.$S.mode=ap;u wireless.$S.ssid="$2";u wireless.$S.encryption=none;uci -q delete wireless.$S.key;u wireless.$S.disabled=0;}
dap 1 "$SSID_2G";dap 0 "$SSID_5G";dap 2 "$SSID_5G_HIGH"
dz mgmt;dz uplink;lz;wz
WZ="$(zs wan)";[ -n "$WZ" ]&&{ for N in wan lan wwan wwanp wwanb usbwan;do uci -q del_list "${WZ}.network=$N";done;uci add_list "${WZ}.network=wan";}
l2w;uci -q delete firewall.allow_luci_from_wan;mr wan
vz vpn 'tun+' 'wg+';vz tailscale tailscale0
uci -q delete firewall.mx_vpn_in;u firewall.mx_vpn_in=rule;u firewall.mx_vpn_in.src=wan;u firewall.mx_vpn_in.proto='tcp udp';u firewall.mx_vpn_in.dest_port='1194 51820 41641';u firewall.mx_vpn_in.target=ACCEPT
mkdir -p /etc/sysctl.d;printf 'net.ipv4.ip_forward=1\nnet.ipv6.conf.all.forwarding=1\n'>/etc/sysctl.d/99-mx4200-vpn.conf;sysctl -w net.ipv4.ip_forward=1 net.ipv6.conf.all.forwarding=1 >/dev/null 2>&1
ca
echo router > /etc/mx4200/mode
psave router
psave router-baseline
if uci -q get uhttpd.main >/dev/null 2>&1; then u uhttpd.main.redirect_https=1; uci commit uhttpd; fi
uci -q set tailscale.settings.fw_mode=nftables;uci -q commit tailscale
for S in tailscale openvpn;do [ -x /etc/init.d/$S ]&&{ /etc/init.d/$S enable;/etc/init.d/$S start >/dev/null 2>&1||true;};done
touch /etc/mx4200/provisioned
if [ "$MX_REMOTE_PASS" != 1 ];then
/etc/init.d/mxprovision start
fi
/etc/init.d/mxd start >/dev/null 2>&1 || true
/etc/init.d/mxb start >/dev/null 2>&1 || true
if command -v fw_printenv >/dev/null 2>&1 && command -v fw_setenv >/dev/null 2>&1; then
if fw_printenv auto_recovery >/dev/null 2>&1; then
fw_setenv auto_recovery no || logger -t mx 'Unable to disable automatic image recovery'
fi
fi
touch /etc/sysupgrade.conf
for F in /etc/mx4200 /etc/sysctl.d/99-mx4200-vpn.conf /usr/lib/mxc /usr/sbin/mx* /usr/bin/mx /etc/init.d/mx* /root/mx* /etc/profile.d/mx* /etc/hotplug.d/iface/95-mxmgmt;do grep -qxF "$F" /etc/sysupgrade.conf 2>/dev/null||echo "$F">>/etc/sysupgrade.conf;done
logger -t mx 'V2 ready'
sync
exit 0
