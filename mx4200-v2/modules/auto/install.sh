#!/bin/sh
# Install saved-mode switching locally; the service never downloads anything.
case "$(cat /tmp/sysinfo/board_name 2>/dev/null)" in linksys,mx4200v2*) ;; *) echo 'MX4200 V2/P2 required' >&2; exit 1 ;; esac
set -e
if command -v fw_printenv >/dev/null 2>&1 && command -v fw_setenv >/dev/null 2>&1 && fw_printenv auto_recovery >/dev/null 2>&1; then
	fw_setenv auto_recovery no || { echo 'Unable to disable automatic image recovery' >&2; exit 1; }
fi
cat > /usr/sbin/mxauto <<'EOF_AUTO'
#!/bin/sh
. /usr/lib/mxc
PRIORITIES=/etc/mx4200/auto-priority
PAUSE=/tmp/mxauto-manual
COOLDOWN=/tmp/mxauto-cooldown
ordered(){ [ -f "$PRIORITIES" ] || return; awk '$1~/^(router|wds|repeater|ap)$/ && $2~/^[1-9]$/ {print $2,$1}' "$PRIORITIES" | sort -n | while read -r P M;do pex "$M" && echo "$P $M";done; }
rank(){ ordered | awk -v m="$1" '$2==m{print $1;exit}'; }
route_dev(){ ip -4 route show default 2>/dev/null | awk '$1=="default"{d="";m=0;for(i=1;i<=NF;i++){if($i=="dev")d=$(i+1);if($i=="metric")m=$(i+1)+0}if(d==""||d~/^(tun|tap|wg|tailscale)/)next;if(!found||m<best){found=1;best=m;chosen=d}}END{print chosen}'; }
health(){ D="$(route_dev)";[ -n "$D" ]||return 1;case "$(mode)" in ap|wds) [ "$D" = br-lan ]||return 1; ip -4 addr show dev br-lan 2>/dev/null|grep -q 'inet '||return 1;;esac;ping -I "$D" -c 1 -W 2 "$DNS_FALLBACK_1" >/dev/null 2>&1 || ping -I "$D" -c 1 -W 2 "$WDS_TEST_IP2" >/dev/null 2>&1; }
carrier(){ for I in "$@";do [ "$(cat "/sys/class/net/$I/carrier" 2>/dev/null)" = 1 ]&&return 0;done;return 1; }
possible(){ case "$1" in router)carrier wan;;ap)carrier lan1 lan2 lan3 wan;;*)return 0;;esac; }
cooled(){ T="$(cat "$COOLDOWN.$1" 2>/dev/null)";case "$T" in ''|*[!0-9]*)return 1;;esac;[ "$(date +%s)" -lt "$((T+900))" ]; }
manual(){ T="$(cat "$PAUSE" 2>/dev/null)";case "$T" in ''|*[!0-9]*)return 1;;esac;[ "$(date +%s)" -lt "$((T+600))" ]; }
try_mode(){ OLD="$(mode)"; NEW="$1";[ "$NEW" != "$OLD" ]||return 0;manual && return 1;logger -t mxauto "Trying $NEW from $OLD";if pload "$NEW";then sleep 12;N=0;while [ "$N" -lt 3 ];do health && { logger -t mxauto "Using $NEW";return 0; };N=$((N+1));sleep 5;done;fi;date +%s > "$COOLDOWN.$NEW";logger -t mxauto "$NEW failed health check; restoring $OLD";pload "$OLD";return 1; }
step(){ manual && return;[ "$(ordered|wc -l)" -ge 2 ]||return; CUR="$(mode)"; R="$(rank "$CUR")";[ -n "$R" ]||return; if health;then FAIL=0; NOW="$(date +%s)";[ "$NOW" -ge "$((LAST_TRY+300))" ]||return; LAST_TRY="$NOW"; for M in $(ordered|awk -v r="$R" '$1<r{print $2}');do cooled "$M"&&continue;possible "$M"||continue;try_mode "$M"&&return;done;else FAIL=$((FAIL+1));[ "$FAIL" -ge 3 ]||return;FAIL=0; for M in $(ordered|awk -v c="$CUR" '$2!=c{print $2}');do cooled "$M"&&continue;possible "$M"||continue;try_mode "$M"&&return;done;fi; }
case "$1" in
service) FAIL=0;LAST_TRY=0;while true;do step;sleep 10;done;;
once) FAIL=2;LAST_TRY=0;step;;
status) echo "Current: $(mode)";ordered; ;;
*) echo 'mxauto: status|once|service';exit 1;;
esac
EOF_AUTO
chmod 755 /usr/sbin/mxauto
cat > /etc/init.d/mxauto <<'EOF_INIT'
#!/bin/sh /etc/rc.common
START=98
STOP=12
USE_PROCD=1
start_service(){ procd_open_instance; procd_set_param command /usr/sbin/mxauto service; procd_set_param respawn 3600 5 5; procd_close_instance; }
EOF_INIT
chmod 755 /etc/init.d/mxauto
/etc/init.d/mxauto enable
/etc/init.d/mxauto restart >/dev/null 2>&1 || true
cat > /usr/sbin/mxroutehealth <<'EOF_ROUTE_HEALTH'
#!/bin/sh
. /usr/lib/mxc
BACKUP=/etc/mx4200/mwan3-repeater.backup
STATE=/etc/mx4200/mwan3-repeater.state
POLICY=mx4200_repeater
SIG=/tmp/mx4200-mwan3-signature

setopt(){ V=$(uci -q get "$1" 2>/dev/null || true);[ "$V" = "$2" ] || uci set "$1=$2"; }
active(){ P=$(uci -q get "network.$1.proto" 2>/dev/null || true);[ -n "$P" ] && [ "$P" != none ]; }
metric(){ V=$(uci -q get "network.$1.metric" 2>/dev/null || true);case "$V" in ''|*[!0-9]*) V=10;;esac;printf '%s' "$V"; }
signature(){ printf 'repeater';for I in wan wwanp wwanb usbwan;do printf '|%s:%s:%s' "$I" "$(uci -q get "network.$I.proto" 2>/dev/null || true)" "$(metric "$I")";done; }
rule_name(){ for R in $(uci -q show mwan3 2>/dev/null | sed -n 's/^mwan3\.\([^.=]*\)=rule$/\1/p');do [ "$(uci -q get "mwan3.$R.dest_ip" 2>/dev/null)" = 0.0.0.0/0 ] && [ "$(uci -q get "mwan3.$R.family" 2>/dev/null)" != ipv6 ] && { printf '%s' "$R";return;};done; }

restore(){
	[ -s "$BACKUP" ] || return 0
	cp "$BACKUP" /etc/config/mwan3 || return 1
	WAS_ENABLED=$(sed -n '1p' "$STATE" 2>/dev/null)
	/etc/init.d/mwan3 restart >/dev/null 2>&1 || true
	if [ "$WAS_ENABLED" != 1 ];then /etc/init.d/mwan3 stop >/dev/null 2>&1 || true;/etc/init.d/mwan3 disable >/dev/null 2>&1 || true;fi
	rm -f "$BACKUP" "$STATE" "$SIG"
}

configure(){
	[ -x /etc/init.d/mwan3 ] && [ -f /etc/config/mwan3 ] || return 0
	RULE=$(rule_name);[ -n "$RULE" ] || { logger -t mxroutehealth 'No IPv4 default rule in mwan3';return 1; }
	NEW_SIG=$(signature)
	[ "$(cat "$SIG" 2>/dev/null)" = "$NEW_SIG" ] && [ "$(uci -q get "mwan3.$RULE.use_policy" 2>/dev/null)" = "$POLICY" ] && return 0
	if [ ! -s "$BACKUP" ];then
		OLD_POLICY=$(uci -q get "mwan3.$RULE.use_policy" 2>/dev/null || true)
		ENABLED=0;for LINK in /etc/rc.d/S*mwan3;do [ -e "$LINK" ] && ENABLED=1;done
		cp /etc/config/mwan3 "$BACKUP" || return 1
		printf '%s\n%s\n' "$ENABLED" "$OLD_POLICY" > "$STATE";chmod 600 "$BACKUP" "$STATE"
	fi
	OLD_POLICY=$(sed -n '2p' "$STATE" 2>/dev/null)
	[ -n "$OLD_POLICY" ] || OLD_POLICY=balanced
	MEMBERS=''
	for I in wan wwanp wwanb usbwan;do
		active "$I" || continue
		if [ "$(uci -q get "mwan3.$I" 2>/dev/null || true)" != interface ];then uci set "mwan3.$I=interface";fi
		setopt "mwan3.$I.enabled" 1
		setopt "mwan3.$I.family" ipv4
		setopt "mwan3.$I.reliability" 1
		setopt "mwan3.$I.count" 1
		setopt "mwan3.$I.timeout" 2
		setopt "mwan3.$I.interval" 10
		setopt "mwan3.$I.down" 1
		setopt "mwan3.$I.up" 1
		uci -q delete "mwan3.$I.track_ip"
		uci add_list "mwan3.$I.track_ip=$DNS_FALLBACK_1"
		uci add_list "mwan3.$I.track_ip=$WDS_TEST_IP2"
		MEMBER=mxroute_$I
		uci -q delete "mwan3.$MEMBER"
		uci set "mwan3.$MEMBER=member"
		uci set "mwan3.$MEMBER.interface=$I"
		uci set "mwan3.$MEMBER.metric=$(metric "$I")"
		uci set "mwan3.$MEMBER.weight=1"
		MEMBERS="$MEMBERS $MEMBER"
	done
	[ -n "$MEMBERS" ] || { logger -t mxroutehealth 'No active routed uplinks';return 1; }
	uci -q delete "mwan3.$POLICY"
	uci set "mwan3.$POLICY=policy"
	for MEMBER in $MEMBERS;do uci add_list "mwan3.$POLICY.use_member=$MEMBER";done
	uci set "mwan3.$POLICY.last_resort=default"
	for R in $(uci -q show mwan3 2>/dev/null | sed -n 's/^mwan3\.\([^.=]*\)=rule$/\1/p');do
		FAMILY=$(uci -q get "mwan3.$R.family" 2>/dev/null || true)
		[ "$FAMILY" = ipv6 ] && continue
		[ "$(uci -q get "mwan3.$R.use_policy" 2>/dev/null)" = "$OLD_POLICY" ] || continue
		uci set "mwan3.$R.use_policy=$POLICY"
		[ -n "$FAMILY" ] || uci set "mwan3.$R.family=ipv4"
	done
	uci set "mwan3.$RULE.use_policy=$POLICY"
	uci commit mwan3 || return 1
	/etc/init.d/mwan3 enable >/dev/null 2>&1 || true
	/etc/init.d/mwan3 restart >/dev/null 2>&1 || return 1
	printf '%s\n' "$NEW_SIG" > "$SIG"
}

case "$1" in
service)
	while :;do
		if [ "$(mode)" = repeater ];then configure || true;else restore || true;fi
		sleep 10
	done ;;
once) [ "$(mode)" = repeater ] && configure || restore ;;
*) echo 'mxroutehealth: service|once';exit 1 ;;
esac
EOF_ROUTE_HEALTH
chmod 755 /usr/sbin/mxroutehealth
cat > /etc/init.d/mxroutehealth <<'EOF_ROUTE_INIT'
#!/bin/sh /etc/rc.common
START=97
STOP=11
USE_PROCD=1
start_service(){ procd_open_instance;procd_set_param command /usr/sbin/mxroutehealth service;procd_set_param respawn 3600 5 5;procd_close_instance; }
EOF_ROUTE_INIT
chmod 755 /etc/init.d/mxroutehealth
/etc/init.d/mxroutehealth enable
/etc/init.d/mxroutehealth restart >/dev/null 2>&1 || true
mkdir -p /etc/hotplug.d/button
cat > /etc/hotplug.d/button/95-mx-partition <<'EOF_BUTTON'
#!/bin/sh
[ "${BUTTON:-}" = wps ] && [ "${ACTION:-}" = pressed ] || exit 0
COUNT_FILE=/tmp/mx-partition-presses
NOW=$(date +%s)
case "$NOW" in ''|*[!0-9]*) exit 0;; esac
OLD_COUNT=0
OLD_TIME=0
COUNT=0
if [ -r "$COUNT_FILE" ];then
	read -r OLD_COUNT OLD_TIME < "$COUNT_FILE"
	case "$OLD_COUNT:$OLD_TIME" in *[!0-9:]*|:*|*:) OLD_COUNT=0;OLD_TIME=0;;esac
	if [ "$NOW" -ge "$OLD_TIME" ] && [ "$((NOW-OLD_TIME))" -le 60 ];then COUNT=$OLD_COUNT;fi
fi
COUNT=$((COUNT+1));printf '%s %s\n' "$COUNT" "$NOW" > "$COUNT_FILE"
[ "$COUNT" -ge 15 ] || exit 0
rm -f "$COUNT_FILE"
INFO=$(ubus -S call luci.advanced-reboot obtain_device_info 2>/dev/null) || { logger -t mx-slot 'Advanced Reboot device check failed';exit 1; }
ERR=$(printf '%s' "$INFO" | jsonfilter -e '@.error' 2>/dev/null)
[ -z "$ERR" ] || { logger -t mx-slot "Partition switch refused: $ERR";exit 1; }
ACTIVE=$(printf '%s' "$INFO" | jsonfilter -e '@.device.partition_active' 2>/dev/null)
case "$ACTIVE" in 1) TARGET=2;;2) TARGET=1;;*) logger -t mx-slot 'Cannot determine active partition';exit 1;;esac
PARTS=$(printf '%s' "$INFO" | jsonfilter -e '@.partitions[*].number' 2>/dev/null)
printf '%s\n' "$PARTS" | grep -qx "$TARGET" || { logger -t mx-slot "Partition $TARGET is unavailable";exit 1; }
RESULT=$(ubus -S call luci.advanced-reboot boot_partition "{\"number\":\"$TARGET\"}" 2>/dev/null) || { logger -t mx-slot 'Advanced Reboot rejected partition switch';exit 1; }
ERR=$(printf '%s' "$RESULT" | jsonfilter -e '@.error' 2>/dev/null)
[ -z "$ERR" ] || { logger -t mx-slot "Partition switch refused: $ERR";exit 1; }
logger -t mx-slot "15 WPS presses; rebooting to partition $TARGET"
ubus -S call system reboot >/dev/null 2>&1 || {
	ubus -S call luci.advanced-reboot boot_partition "{\"number\":\"$ACTIVE\"}" >/dev/null 2>&1 || true
	logger -t mx-slot 'Reboot request failed; attempted to restore current partition'
	exit 1
}
EOF_BUTTON
chmod 755 /etc/hotplug.d/button/95-mx-partition
touch /etc/sysupgrade.conf
for F in /usr/sbin/mxauto /etc/init.d/mxauto /usr/sbin/mxroutehealth /etc/init.d/mxroutehealth /etc/hotplug.d/button/95-mx-partition;do grep -qxF "$F" /etc/sysupgrade.conf || echo "$F" >> /etc/sysupgrade.conf;done
