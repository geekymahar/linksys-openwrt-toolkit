#!/bin/sh
# Install the optional MX dashboard. The router modes stay in local core scripts.
case "$(cat /tmp/sysinfo/board_name 2>/dev/null)" in linksys,mx4200v2*) ;; *) echo 'MX4200 V2/P2 required' >&2; exit 1 ;; esac
set -e
[ -r /usr/share/libubox/jshn.sh ] && command -v jsonfilter >/dev/null 2>&1 && [ -x /usr/sbin/mxm ] || { echo 'MX core/LuCI dependencies are missing' >&2; exit 1; }
mkdir -p /usr/libexec/rpcd /usr/share/rpcd/acl.d /usr/share/luci/menu.d /www/luci-static/resources/view/mx4200
cat > /usr/libexec/rpcd/mx.ui <<'EOF_RPC'
#!/bin/sh
. /usr/share/libubox/jshn.sh
. /usr/lib/mxc
PRIORITIES=/etc/mx4200/auto-priority
reply(){ json_init;json_add_boolean ok "$1";json_add_string message "$2";json_dump; }
run(){ OUT=$("$@" 2>&1);RC=$?;[ "$RC" = 0 ] && reply 1 "${OUT:-Done}" || reply 0 "${OUT:-Operation failed}"; }
case "$1" in
list) printf '{"status":{},"profiles":{},"action":{"name":""},"priority":{"mode":"","value":0}}\n';exit 0 ;;
call) ;;
*) exit 1 ;;
esac
case "$2" in
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
backhaul_auto|backhaul_primary|backhaul_backup)
    case "$(mode)" in wds|repeater) ;; *) reply 0 'Backhaul controls require WDS or routed repeater';exit 0 ;; esac
    run /usr/sbin/mxb "${A#backhaul_}" ;;
wds_test) run /root/mxwds ;;
auto_status) [ -x /usr/sbin/mxauto ] && run /usr/sbin/mxauto status || reply 0 'Automatic mode module is pending' ;;
auto_once) [ -x /usr/sbin/mxauto ] && run /usr/sbin/mxauto once || reply 0 'Automatic mode module is pending' ;;
led_install) run /usr/sbin/mxmod once ;;
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
chmod 755 /usr/libexec/rpcd/mx.ui
cat > /usr/share/rpcd/acl.d/mx-ui.json <<'EOF_ACL'
{
  "mx-ui": {
    "description": "View and manage MX4200 modes through dedicated actions",
    "read": { "ubus": { "mx.ui": [ "status", "profiles" ] } },
    "write": { "ubus": { "mx.ui": [ "action", "priority" ] } }
  }
}
EOF_ACL
cat > /usr/share/luci/menu.d/mx-ui.json <<'EOF_MENU'
{
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
				for (var n = 0; n <= 9; n++) rank.appendChild(E('option', { 'value': String(n), 'selected': n === (profile.priority || 0) }, String(n)));
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
			section(_('Guided setup'), _('For a new router, WDS, routed repeater or wired AP setup, open the terminal and run mx. Wi-Fi scanning and password prompts remain in the existing offline setup scripts.'), E('div', {}, [ terminalLink(), E('p', {}, 'Run: mx, mxrepeater, mxap, mxusb, or mxhelp') ])),
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
touch /etc/sysupgrade.conf
for F in /usr/libexec/rpcd/mx.ui /usr/share/rpcd/acl.d/mx-ui.json /usr/share/luci/menu.d/mx-ui.json /www/luci-static/resources/view/mx4200/manager.js; do
    grep -qxF "$F" /etc/sysupgrade.conf || printf '%s\n' "$F" >> /etc/sysupgrade.conf
done
/etc/init.d/rpcd reload >/dev/null 2>&1 || /etc/init.d/rpcd restart >/dev/null 2>&1 || true
