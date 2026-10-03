# Legacy Inventory

Captured before the refactor. Original sources remain in mx4200-v2/.

## mx4200-v2/.gitattributes

SHA-256: `effadf2606acddc1990eaf6cb5af63a81219dfe61a96d0f7988884cb7dd8058b`

Role: Package selection, documentation, or signed release metadata

## mx4200-v2/README.md

SHA-256: `3ed2b43f7154c76b538350320275844df4724429a3491621818d3cccd793064c`

Role: Package selection, documentation, or signed release metadata

## mx4200-v2/modules/auto/install.sh

SHA-256: `365375cef30605bd7ed7f16104c631e3ee4e3441c603e92a4b99d9056228d1ba`

Functions: ordered, rank, route_dev, health, carrier, possible, cooled, manual, try_mode, step, start_service, setopt, active, metric, signature, rule_name, restore, configure

Variables: PRIORITIES, PAUSE, COOLDOWN, D, T, OLD, NEW, N, CUR, R, FAIL, NOW, LAST_TRY, START, STOP, USE_PROCD, BACKUP, STATE, POLICY, SIG, V, P, WAS_ENABLED, RULE, NEW_SIG, OLD_POLICY, ENABLED, MEMBERS, I, MEMBER, FAMILY, COUNT_FILE, OLD_COUNT, OLD_TIME, COUNT, INFO, ERR, ACTIVE, TARGET, PARTS, RESULT

Written assets: /usr/sbin/mxauto, /etc/init.d/mxauto, /usr/sbin/mxroutehealth, /etc/init.d/mxroutehealth, /etc/hotplug.d/button/95-mx-partition

UCI packages referenced: network., mwan3.

Services referenced: mxauto, mwan3, mxroutehealth

## mx4200-v2/modules/auto/install.sh.sha256

SHA-256: `42f073cf975534c327350de0049a561bbdf8552dbe2d6cb08897830b38097472`

Role: Integrity sidecar for adjacent installer

## mx4200-v2/modules/led/install.sh

SHA-256: `83bf1e6becfad45ca3801125e1a4c8a0c979974188ade5c99a9890a067fdb47d`

Functions: fl, rb, sc, si, rgb, load, delay, show, breathe, beat, boot_ready, bytes, defif, wgifs, wgup, wgbytes, ovpnifs, ovpnup, ovpnbytes, wdssta, level, write, sampler, cleanup, start_service

Variables: LED_TEST_IP1, LED_TEST_IP2, LED_INTERVAL, LED_IDLE_THRESHOLD, LED_LIGHT_THRESHOLD, LED_MEDIUM_THRESHOLD, C, R, G, B, N, IB, BK, P, V, M, X, Y, Z, GH, RH, BH, LED, SF, ST, CURVE, D0, D1, D2, D3, DF, STATE, LEVEL, TS_ACTIVE, WG_ACTIVE, OVPN_ACTIVE, O, EXPECT, DEV, IP, A, PW, PT, PG, PO, FIRST, WH, WC, IF, W, T, DW, DT, DG, DO, L, TA, GA, OA, PID, START, STOP, USE_PROCD

Written assets: /etc/mx4200/led.conf, /usr/bin/mxls, /usr/bin/mxld, /etc/init.d/mxl

UCI packages referenced: network.

Services referenced: mxl, uhttpd

## mx4200-v2/modules/led/install.sh.sha256

SHA-256: `cbd4f65caecd89c92200f07b4d02dbc1e00f197a1c4d20c1e7400e44bde710b1`

Role: Integrity sidecar for adjacent installer

## mx4200-v2/modules/led/rev2/install.sh

SHA-256: `e6e1df51010c15e7e7d0347ad6c639ec9d9b267692668caa3fe5137ae6f0b38b`

Functions: fl, rb, sc, si, rgb, load, delay, show, breathe, beat, boot_ready, bytes, defif, wgifs, wgup, wgbytes, ovpnifs, ovpnup, ovpnbytes, wdssta, route_dev, iface_dev, uplink_kind, wds_health, uplink_cue, level, write, sampler, cleanup, start_service

Variables: LED_TEST_IP1, LED_TEST_IP2, LED_INTERVAL, LED_IDLE_THRESHOLD, LED_LIGHT_THRESHOLD, LED_MEDIUM_THRESHOLD, C, R, G, B, N, IB, BK, P, V, M, X, Y, Z, GH, RH, BH, LED, SF, ST, CURVE, D0, D1, D2, D3, DF, STATE, LEVEL, TS_ACTIVE, WG_ACTIVE, OVPN_ACTIVE, UPLINK, O, EXPECT, DEV, IP, A, USB_DEV, BACKUP_DEV, PW, PT, PG, PO, FIRST, WH, WC, LAST_WDS_IF, ROUTE_DEV, IF, W, T, DW, DT, DG, DO, L, TA, GA, OA, PID, START, STOP, USE_PROCD

Written assets: /etc/mx4200/led.conf, /usr/bin/mxls, /usr/bin/mxld, /etc/init.d/mxl

UCI packages referenced: network.

Services referenced: mxl, uhttpd

## mx4200-v2/modules/led/rev2/install.sh.sha256

SHA-256: `dc1770248ee447782a360fdaed8a7e0d1b3fddeaed45dbc7b7827665f2439d89`

Role: Integrity sidecar for adjacent installer

## mx4200-v2/modules/led/rev3/install.sh

SHA-256: `8393f1a814f0800fde32abeae9197fd52c5249dff3928b6f3481f0f3616abd52`

Functions: fl, rb, sc, si, rgb, load, delay, show, breathe, beat, dfs_blink, boot_ready, bytes, wgifs, wgup, wgbytes, ovpnifs, ovpnup, ovpnbytes, wdssta, staif, staup, route_dev, iface_dev, uplink_kind, wds_health, dfs_wait, uplink_cue, level, write, sampler, cleanup, start_service

Variables: LED_TEST_IP1, LED_TEST_IP2, LED_INTERVAL, LED_IDLE_THRESHOLD, LED_LIGHT_THRESHOLD, LED_MEDIUM_THRESHOLD, C, R, G, B, N, IB, BK, P, V, M, X, Y, Z, GH, RH, BH, LED, SF, ST, CURVE, D0, D1, D2, D3, DF, STATE, LEVEL, TS_ACTIVE, WG_ACTIVE, OVPN_ACTIVE, UPLINK, O, EXPECT, DEV, IP, A, S, J, I, USB_DEV, BACKUP_DEV, PW, PT, PG, PO, FIRST, WH, WC, LAST_WDS_IF, ROUTE_DEV, IF, DNS_OK, W, T, DW, DT, DG, DO, L, TA, GA, OA, PID, START, STOP, USE_PROCD

Written assets: /etc/mx4200/led.conf, /usr/bin/mxls, /usr/bin/mxld, /etc/init.d/mxl

UCI packages referenced: network., wireless.

Services referenced: mxl, uhttpd

## mx4200-v2/modules/led/rev3/install.sh.sha256

SHA-256: `0b045cca4cdd60e14a2b2aeca4603486c866551333d2b4017b017bbd62d24a2f`

Role: Integrity sidecar for adjacent installer

## mx4200-v2/modules/provision/install.sh

SHA-256: `ad471d9734def02cbd9d16ad39726789df60c4e0a1e38143c1bda8d4c04b7569`

Functions: fetch

Variables: ACTION, BASE, STAGE, NR, FILES, LED_AUTO_INSTALL, HASH, MX_REMOTE_PASS, FAILED

Written assets: "$STAGE/release.pub"

UCI packages referenced: 

Services referenced: network, dnsmasq, firewall

## mx4200-v2/modules/provision/install.sh.sha256

SHA-256: `1e2878d03e7aa950f30d1ec1b343f0eda9aca7fa69f38f725399823722571b0f`

Role: Integrity sidecar for adjacent installer

## mx4200-v2/modules/samba/install.sh

SHA-256: `a46442f90917be5c2c267b6f6e69c99c1034580583af57fe18d885b0c7d2ce9a`

Functions: ok, fail, valid_user, exists_unix, managed, function

Variables: STORE, LC_ALL, SEP, USER_NAME, STATUS, REQUEST, PASSWORD

Written assets: /usr/libexec/rpcd/mx.samba, /usr/share/rpcd/acl.d/mx-samba.json, /usr/share/luci/menu.d/mx-samba.json, /www/luci-static/resources/view/samba4/users.js

UCI packages referenced: 

Services referenced: rpcd

## mx4200-v2/modules/samba/install.sh.sha256

SHA-256: `1a29ce0f4fa59a93f057661577d43c78e18c82462dd8b64d4f7de265bdbef3c8`

Role: Integrity sidecar for adjacent installer

## mx4200-v2/packages.txt

SHA-256: `557b25d59d6ee71b11fca4e97bf3a5dbf9870fe534a7f1539f2a0c65c86b80fa`

Role: Package selection, documentation, or signed release metadata

## mx4200-v2/release/build.py

SHA-256: `ab633cf2b6b37d40a75cfff39899d52efd340f17d493552338c2d89e29d2e033`

Functions: digest, check_shell, main

Variables: HASH

Written assets: 

UCI packages referenced: 

Services referenced: 

## mx4200-v2/release/manifest.sig

SHA-256: `bb4d07d63b800ce8cb8a85fce5f7dbac217b4d2480626a73fc1097657a0a4922`

Role: Package selection, documentation, or signed release metadata

## mx4200-v2/release/manifest.txt

SHA-256: `f64598cd8a8922caec361c625c495afb13179d5adb3d1b1b1d2ccfa5ba81f7ea`

Role: Package selection, documentation, or signed release metadata

## mx4200-v2/uci-defaults.sh

SHA-256: `88b8d9fd82333e84924bd281c3f361161b22ebc83f541adc2d57cf4f53d4003e`

Functions: u, wifi_clear, ds, rwan, zs, dz, df, lz, wz, fw, l2w, ld, sl, mc, znew, mf, uz, pr, mr, vz, rb, ap, ca, ra, pex, psave, pload, mode, savecur, priority, psum, ws, ri, sr, f, e2u, nk, passok, rs, scan_band, sta, si, up, rp, sw, start_service, find_usb, rmet, apply_usb, off_usb, mgmt, free_ip, duo, sil, ract, pact, aact, bact, sact, lact, mact, menu, dap

Variables: WIFI_PREFIX, LED_AUTO_INSTALL, COUNTRY, ROUTER_HOSTNAME, LAN_IP, LAN_NETMASK, MGMT_IP, DHCP_START, DHCP_LIMIT, DHCP_LEASETIME, MODE_2G, MODE_5G, MODE_5G_HIGH, CHANNEL_5G_HIGH, DNS_FALLBACK_1, DNS_FALLBACK_2, DNS_TEST_NAME, WDS_TEST_IP2, SSID_2G, SSID_5G, SSID_5G_HIGH, PROFILE_ROOT, PROFILE_FILES, F, B, Z, S, N, E, D, M, P, V, I, U, R, O, WAIT_MAX, A, X, W, H, SCAN_IF, IFS, TARGET, WAN_PORT, WAN_PREF, L, MATCH_SSID, REUSE_PASS, T, TAB, LINE, SEL_ENC, SEL_PASS, RD, R_LAN_IP, R_LAN_NETMASK, R_DHCP_START, R_DHCP_LIMIT, R_DHCP_LEASE, PR, PL, OR, OL, PSSID, PENC, PPASS, PCHAN, PAP, BACKUP, BSSID, BENC, BPASS, BRAD, BCHAN, BAP, CLIENT_PASS, MGMT_PASS, BR, Q, K, WZ, LC_ALL, J, C, CHANGED, SCAN_PID, START, USE_PROCD, ROLE, LAST_ROLE, LAST, STA, IP, OK, STATE, EXPLICIT, STOP, BASE, HASH, BIN, CUR, MODE, GW, MIP, AP

Written assets: /etc/mx4200/base.conf, /usr/lib/mxc, /root/mxr, /root/mxa, /usr/sbin/mxb, /etc/init.d/mxb, /usr/sbin/mxu, /usr/sbin/mxw, /root/mxwds, /usr/sbin/mxd, /etc/init.d/mxd, /etc/hotplug.d/iface/95-mxmgmt, /usr/sbin/mxmod, /usr/sbin/mxfirstboot, /etc/init.d/mxprovision, /usr/sbin/mxm, /etc/profile.d/mx

UCI packages referenced: network., firewall., dhcp., wireless., system., uhttpd., tailscale.

Services referenced: mxmod, network, dnsmasq, firewall, mxb, mxd, mxprovision, mxl, $S, mx

# Extracted Assets

| Old source | Generated asset / new firmware path | Status |
| --- | --- | --- |
| uci-defaults.sh | files/etc/hotplug.d/iface/95-mxmgmt | PRESERVED; extracted and formatted |
| modules/auto/install.sh | files/etc/init.d/mxauto | PRESERVED; extracted and formatted |
| uci-defaults.sh | files/etc/init.d/mxb | PRESERVED; extracted and formatted |
| uci-defaults.sh | files/etc/init.d/mxd | PRESERVED; extracted and formatted |
| modules/led/rev3/install.sh | files/etc/init.d/mxl | PRESERVED; extracted and formatted |
| modules/auto/install.sh | files/etc/init.d/mxroutehealth | PRESERVED; extracted and formatted |
| uci-defaults.sh | files/etc/profile.d/mx | PRESERVED; extracted and formatted |
| uci-defaults.sh | files/root/mxa | PRESERVED; extracted and formatted |
| uci-defaults.sh | files/root/mxr | PRESERVED; extracted and formatted |
| uci-defaults.sh | files/root/mxwds | PRESERVED; extracted and formatted |
| modules/led/rev3/install.sh | files/usr/bin/mxld | PRESERVED; extracted and formatted |
| modules/led/rev3/install.sh | files/usr/bin/mxls | PRESERVED; extracted and formatted |
| uci-defaults.sh | files/usr/lib/mxc | PRESERVED; extracted and formatted |
| uci-defaults.sh: /usr/lib/mxc | files/usr/lib/router-defaults/firewall-functions.sh | PRESERVED; extracted and formatted |
| uci-defaults.sh: /usr/lib/mxc | files/usr/lib/router-defaults/input.sh | PRESERVED; extracted and formatted |
| uci-defaults.sh: /usr/lib/mxc | files/usr/lib/router-defaults/network-functions.sh | PRESERVED; extracted and formatted |
| uci-defaults.sh: /usr/lib/mxc | files/usr/lib/router-defaults/profiles.sh | PRESERVED; extracted and formatted |
| uci-defaults.sh: /usr/lib/mxc | files/usr/lib/router-defaults/runtime.sh | PRESERVED; extracted and formatted |
| uci-defaults.sh: /usr/lib/mxc | files/usr/lib/router-defaults/wireless-functions.sh | PRESERVED; extracted and formatted |
| modules/samba/install.sh | files/usr/libexec/rpcd/mx.samba | PRESERVED; extracted and formatted |
| modules/auto/install.sh | files/usr/sbin/mxauto | PRESERVED; extracted and formatted |
| uci-defaults.sh | files/usr/sbin/mxb | PRESERVED; extracted and formatted |
| uci-defaults.sh | files/usr/sbin/mxd | PRESERVED; extracted and formatted |
| uci-defaults.sh | files/usr/sbin/mxm | PRESERVED; extracted and formatted |
| modules/auto/install.sh | files/usr/sbin/mxroutehealth | PRESERVED; extracted and formatted |
| uci-defaults.sh | files/usr/sbin/mxu | PRESERVED; extracted and formatted |
| uci-defaults.sh | files/usr/sbin/mxw | PRESERVED; extracted and formatted |
| modules/samba/install.sh | files/usr/share/luci/menu.d/mx-samba.json | PRESERVED; extracted and formatted |
| modules/samba/install.sh | files/usr/share/rpcd/acl.d/mx-samba.json | PRESERVED; extracted and formatted |
| modules/samba/install.sh | files/www/luci-static/resources/view/samba4/users.js | PRESERVED; extracted and formatted |

# Shared Function Map

| Old function | New library / function | Status |
| --- | --- | --- |
| ds | network-functions.sh / find_bridge_section | PRESERVED |
| rwan | network-functions.sh / bridge_wan_port | PRESERVED |
| ld | network-functions.sh / configure_bridge_dhcp_client | PRESERVED |
| sl | network-functions.sh / configure_static_lan | PRESERVED |
| mc | network-functions.sh / configure_management_network | PRESERVED |
| zs | firewall-functions.sh / find_firewall_zone | PRESERVED |
| dz | firewall-functions.sh / delete_firewall_zone | PRESERVED |
| df | firewall-functions.sh / delete_non_vpn_forwardings | PRESERVED |
| lz | firewall-functions.sh / ensure_lan_zone | PRESERVED |
| wz | firewall-functions.sh / configure_wan_zone | PRESERVED |
| fw | firewall-functions.sh / ensure_forwarding | PRESERVED |
| l2w | firewall-functions.sh / configure_lan_to_wan | PRESERVED |
| znew | firewall-functions.sh / create_firewall_zone | PRESERVED |
| mf | firewall-functions.sh / configure_management_firewall | PRESERVED |
| uz | firewall-functions.sh / configure_uplink_zone | PRESERVED |
| pr | firewall-functions.sh / add_management_source_ranges | PRESERVED |
| mr | firewall-functions.sh / configure_management_rule | PRESERVED |
| vz | firewall-functions.sh / configure_vpn_zone | PRESERVED |
| wifi_clear | wireless-functions.sh / wifi_clear | PRESERVED |
| rb | wireless-functions.sh / configure_radio_defaults | PRESERVED |
| ap | wireless-functions.sh / configure_access_point | PRESERVED |
| ws | wireless-functions.sh / wireless_status | PRESERVED |
| ri | wireless-functions.sh / radio_interface | PRESERVED |
| sr | wireless-functions.sh / scan_radio | PRESERVED |
| e2u | wireless-functions.sh / scan_encryption_to_uci | PRESERVED |
| nk | wireless-functions.sh / encryption_needs_key | PRESERVED |
| pex | profiles.sh / profile_exists | PRESERVED |
| psave | profiles.sh / save_profile | PRESERVED |
| pload | profiles.sh / load_profile | PRESERVED |
| mode | profiles.sh / current_mode | PRESERVED |
| savecur | profiles.sh / save_current_profile | PRESERVED |
| priority | profiles.sh / prompt_auto_priority | PRESERVED |
| psum | profiles.sh / print_profile_summary | PRESERVED |
| passok | input.sh / valid_wifi_password | PRESERVED |
| rs | input.sh / read_secret | PRESERVED |
| u | runtime.sh / set_option | PRESERVED |
| ca | runtime.sh / commit_mode_configuration | PRESERVED |
| ra | runtime.sh / reload_mode_services | PRESERVED |
