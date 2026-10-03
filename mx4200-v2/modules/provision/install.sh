#!/bin/sh
# First-boot only: install a signed MX4200 release while the router is pristine.
case "$(cat /tmp/sysinfo/board_name 2>/dev/null)" in linksys,mx4200v2*) ;; *) exit 1 ;; esac
command -v openssl >/dev/null 2>&1 || exit 1
set -eu
ACTION=${1:-all}
case "$ACTION" in all|auto|samba|led) ;; *) exit 1 ;; esac
BASE='https://raw.githubusercontent.com/geekymahar/linksys-openwrt-toolkit/main/mx4200-v2'
STAGE="/tmp/mx-provision.$$"
mkdir -p "$STAGE/modules/auto" "$STAGE/modules/samba" "$STAGE/modules/led/rev3" "$STAGE/release"
trap 'rm -rf "$STAGE"' EXIT HUP INT TERM
cat > "$STAGE/release.pub" <<'EOF_KEY'
-----BEGIN PUBLIC KEY-----
MCowBQYDK2VwAyEAtC57Jz4db5U9+kB3I/AtJ2fpIobVcqY8VFZeemJguMg=
-----END PUBLIC KEY-----
EOF_KEY
fetch(){ uclient-fetch -q -T 15 -O "$2" "$BASE/$1" 2>/dev/null || curl -fsSL --connect-timeout 5 --max-time 15 -o "$2" "$BASE/$1" 2>/dev/null; }
fetch release/manifest.txt "$STAGE/release/manifest.txt"
fetch release/manifest.sig "$STAGE/release/manifest.sig"
openssl pkeyutl -verify -pubin -inkey "$STAGE/release.pub" -rawin -in "$STAGE/release/manifest.txt" -sigfile "$STAGE/release/manifest.sig" >/dev/null 2>&1 || exit 1
awk 'NR==1 {if ($0!="MX4200V2P2 1") exit 1;next}
NR>1 {if (NF!=2 || length($1)!=64 || $1 ~ /[^0-9a-f]/ ||
!($2=="uci-defaults.sh" || $2=="modules/auto/install.sh" || $2=="modules/samba/install.sh" || $2=="modules/led/rev3/install.sh") || seen[$2]++) exit 1; count++}
END {if (NR!=5 || count!=4) exit 1}' "$STAGE/release/manifest.txt" || exit 1
case "$ACTION" in
all) FILES='uci-defaults.sh modules/auto/install.sh modules/samba/install.sh'
     [ "$(sed -n "s/^LED_AUTO_INSTALL='\([^']*\)'.*/\1/p" /etc/mx4200/base.conf)" != 1 ] || FILES="$FILES modules/led/rev3/install.sh" ;;
auto) FILES='modules/auto/install.sh' ;;
samba) FILES='modules/samba/install.sh' ;;
led) FILES='modules/led/rev3/install.sh' ;;
esac
for F in $FILES; do
    fetch "$F" "$STAGE/$F" || exit 1
    HASH="$(awk -v f="$F" '$2==f {print $1}' "$STAGE/release/manifest.txt")"
    [ "$(sha256sum "$STAGE/$F" | awk '{print $1}')" = "$HASH" ] || exit 1
    sh -n "$STAGE/$F" || exit 1
done
if [ "$ACTION" = all ]; then
    # A user configuration made while downloading cancels the release application.
    [ ! -e /tmp/mxauto-manual ] || exit 1
    [ "$(cat /etc/mx4200/mode 2>/dev/null)" = router ] || exit 1
    for F in network wireless dhcp firewall system; do
        [ "$(sha256sum "/etc/config/$F" | awk '{print $1}')" = "$(sha256sum "/etc/mx4200/profiles/router-baseline/$F" | awk '{print $1}')" ] || exit 1
    done
    tar -cf "$STAGE/core-backup.tar" -C / etc/config etc/mx4200 usr/lib/mxc usr/sbin/mxb usr/sbin/mxu usr/sbin/mxw usr/sbin/mxd usr/sbin/mxmod usr/sbin/mxm usr/sbin/mxfirstboot usr/bin/mx root/mxr root/mxa root/mxwds etc/init.d/mxb etc/init.d/mxd etc/init.d/mxprovision etc/profile.d/mx etc/profile.d/mx.sh etc/sysctl.d/99-mx4200-vpn.conf etc/hotplug.d/iface/95-mxmgmt || exit 1
    if ! MX_REMOTE_PASS=1 sh "$STAGE/uci-defaults.sh" || [ ! -x /usr/sbin/mxm ] || [ ! -x /usr/lib/mxc ]; then
        tar -xf "$STAGE/core-backup.tar" -C / || true
        /etc/init.d/network restart >/dev/null 2>&1 || true
        /etc/init.d/dnsmasq restart >/dev/null 2>&1 || true
        /etc/init.d/firewall restart >/dev/null 2>&1 || true
        exit 1
    fi
fi
FAILED=0
for ENTRY in 'auto modules/auto/install.sh' 'samba modules/samba/install.sh' 'led modules/led/rev3/install.sh'; do
    set -- $ENTRY
    [ "$ACTION" = all ] || [ "$ACTION" = "$1" ] || continue
    [ "$ACTION" != all ] || [ "$1" != led ] || [ "$(sed -n "s/^LED_AUTO_INSTALL='\([^']*\)'.*/\1/p" /etc/mx4200/base.conf)" = 1 ] || continue
    if sh "$STAGE/$2"; then
        HASH="$(awk -v f="$2" '$2==f {print $1}' "$STAGE/release/manifest.txt")"
        mkdir -p /etc/mx4200/modules
        printf '%s\n' "$HASH" > "/etc/mx4200/modules/$1.installed"
    else
        FAILED=1
        logger -t mxprovision "Optional module $1 failed; offline core remains available"
    fi
done
[ "$ACTION" != all ] || cp "$STAGE/release/manifest.txt" /etc/mx4200/release-manifest.txt
logger -t mxprovision "Signed release action $ACTION finished"
[ "$FAILED" = 0 ]
