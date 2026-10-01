#!/bin/sh
# Install saved-mode switching locally; the service never downloads anything.
case "$(cat /tmp/sysinfo/board_name 2>/dev/null)" in linksys,mx4200v2*) ;; *) echo 'MX4200 V2/P2 required' >&2; exit 1 ;; esac
set -e
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
touch /etc/sysupgrade.conf
for F in /usr/sbin/mxauto /etc/init.d/mxauto;do grep -qxF "$F" /etc/sysupgrade.conf || echo "$F" >> /etc/sysupgrade.conf;done
