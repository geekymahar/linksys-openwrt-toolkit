#!/bin/sh
# Install the Samba account page locally. No runtime GitHub dependency.
case "$(cat /tmp/sysinfo/board_name 2>/dev/null)" in linksys,mx4200v2*) ;; *) echo 'MX4200 V2/P2 required' >&2; exit 1 ;; esac
set -e
for C in useradd userdel smbpasswd jsonfilter; do command -v "$C" >/dev/null 2>&1 || { echo "Missing $C" >&2; exit 1; }; done
mkdir -p /usr/libexec/rpcd /usr/share/rpcd/acl.d /usr/share/luci/menu.d /www/luci-static/resources/view/samba4 /etc/mx4200/samba-users
chmod 700 /etc/mx4200/samba-users
cat > /usr/libexec/rpcd/mx.samba <<'EOF_RPC'
#!/bin/sh
STORE=/etc/mx4200/samba-users
ok(){ printf '{"ok":true}\n'; }
fail(){ printf '{"ok":false,"error":"%s"}\n' "$1"; }
valid_user(){ printf '%s\n' "$USER_NAME" | LC_ALL=C grep -Eq '^mxsmb_[a-z][a-z0-9_]{0,19}$'; }
exists_unix(){ awk -F: -v n="$USER_NAME" '$1==n { found=1 } END { exit !found }' /etc/passwd; }
managed(){ valid_user && [ -f "$STORE/$USER_NAME" ] && exists_unix; }
case "$1" in
list) printf '{"users":{},"add":{"username":"","password":""},"password":{"username":"","password":""},"disable":{"username":""},"enable":{"username":""},"remove":{"username":""}}\n'; exit 0 ;;
call) ;;
*) exit 1 ;;
esac
if [ "$2" = users ]; then
    printf '{"users":['
    SEP=
    for F in "$STORE"/mxsmb_*; do
        [ -f "$F" ] || continue
        USER_NAME=${F##*/}
        managed || continue
        STATUS=$(cat "$F" 2>/dev/null)
        [ "$STATUS" = disabled ] || STATUS=enabled
        printf '%s{"name":"%s","status":"%s"}' "$SEP" "$USER_NAME" "$STATUS"
        SEP=,
    done
    printf ']}\n'
    exit 0
fi
case "$2" in add|password|disable|enable|remove) ;; *) fail 'Unsupported operation'; exit 0 ;; esac
REQUEST=$(cat)
USER_NAME=$(printf '%s' "$REQUEST" | jsonfilter -e '@.username' 2>/dev/null)
valid_user || { fail 'Use a name beginning mxsmb_ and lowercase letters, digits or underscore'; exit 0; }
if [ "$2" = add ] || [ "$2" = password ]; then
    PASSWORD=$(printf '%s' "$REQUEST" | jsonfilter -e '@.password' 2>/dev/null)
    [ "${#PASSWORD}" -ge 12 ] && [ "${#PASSWORD}" -le 127 ] && ! printf '%s' "$PASSWORD" | LC_ALL=C grep -q '[[:cntrl:]]' || { fail 'Password must contain 12–127 characters and no control characters'; exit 0; }
fi
if [ "$2" = add ]; then
    [ ! -e "$STORE/$USER_NAME" ] && ! exists_unix || { fail 'Account already exists'; exit 0; }
    awk -F: '$3==100 { found=1 } END { exit !found }' /etc/group || { fail 'OpenWrt users group (GID 100) is missing'; exit 0; }
    useradd -M -g 100 -s /bin/false -d /var/empty "$USER_NAME" >/dev/null 2>&1 || { fail 'Could not create local account'; exit 0; }
    if ! printf '%s\n%s\n' "$PASSWORD" "$PASSWORD" | smbpasswd -s -a "$USER_NAME" >/dev/null 2>&1; then
        userdel "$USER_NAME" >/dev/null 2>&1 || true
        fail 'Could not create Samba account'; exit 0
    fi
    printf 'enabled\n' > "$STORE/$USER_NAME"
    chmod 600 "$STORE/$USER_NAME"
    ok; exit 0
fi
managed || { fail 'Managed account not found'; exit 0; }
case "$2" in
password) printf '%s\n%s\n' "$PASSWORD" "$PASSWORD" | smbpasswd -s "$USER_NAME" >/dev/null 2>&1 || { fail 'Could not update Samba password'; exit 0; } ;;
disable) smbpasswd -d "$USER_NAME" >/dev/null 2>&1 || { fail 'Could not disable Samba account'; exit 0; }; printf 'disabled\n' > "$STORE/$USER_NAME" ;;
enable) smbpasswd -e "$USER_NAME" >/dev/null 2>&1 || { fail 'Could not enable Samba account'; exit 0; }; printf 'enabled\n' > "$STORE/$USER_NAME" ;;
remove) smbpasswd -x "$USER_NAME" >/dev/null 2>&1 || { fail 'Could not remove Samba credentials'; exit 0; }; userdel "$USER_NAME" >/dev/null 2>&1 || { fail 'Samba credentials removed, but local account remains; remove it manually'; exit 0; }; rm -f "$STORE/$USER_NAME" ;;
esac
ok
EOF_RPC
chmod 755 /usr/libexec/rpcd/mx.samba
cat > /usr/share/rpcd/acl.d/mx-samba.json <<'EOF_ACL'
{
  "mx-samba": {
    "description": "Manage dedicated Samba accounts",
    "read": { "ubus": { "mx.samba": [ "users" ] } },
    "write": { "ubus": { "mx.samba": [ "add", "password", "disable", "enable", "remove" ] } }
  }
}
EOF_ACL
cat > /usr/share/luci/menu.d/mx-samba.json <<'EOF_MENU'
{
  "admin/services/samba-users": {
    "title": "Samba Users",
    "order": 45,
    "action": { "type": "view", "path": "samba4/users" },
    "depends": { "acl": [ "mx-samba" ] }
  }
}
EOF_MENU
cat > /www/luci-static/resources/view/samba4/users.js <<'EOF_JS'
'use strict';
'require rpc';
'require view';
'require ui';

var listUsers = rpc.declare({ object: 'mx.samba', method: 'users' });
var addUser = rpc.declare({ object: 'mx.samba', method: 'add', params: [ 'username', 'password' ] });
var setPassword = rpc.declare({ object: 'mx.samba', method: 'password', params: [ 'username', 'password' ] });
var disableUser = rpc.declare({ object: 'mx.samba', method: 'disable', params: [ 'username' ] });
var enableUser = rpc.declare({ object: 'mx.samba', method: 'enable', params: [ 'username' ] });
var removeUser = rpc.declare({ object: 'mx.samba', method: 'remove', params: [ 'username' ] });

function notice(message) { ui.addNotification(null, E('p', {}, message)); }
function passwordOK(value) { return value.length >= 12 && value.length <= 127 && !/[\x00-\x1f\x7f]/.test(value); }
function action(call, args, refresh) {
	return call.apply(null, args).then(function(result) {
		if (!result || !result.ok) { notice(result && result.error || _('Operation failed')); return; }
		return refresh();
	}).catch(function(error) { notice(error.message || String(error)); });
}

return view.extend({
	load: function() { return listUsers(); },
	render: function(data) {
		var root = E('div', { 'class': 'cbi-map' });
		var table = E('table', { 'class': 'table' });
		var name = E('input', { 'type': 'text', 'placeholder': 'alice', 'autocomplete': 'off' });
		var password = E('input', { 'type': 'password', 'autocomplete': 'new-password' });
		var confirmPassword = E('input', { 'type': 'password', 'autocomplete': 'new-password' });
		var refresh = function() { return listUsers().then(draw); };
		function draw(result) {
			table.replaceChildren(E('tr', { 'class': 'tr table-titles' }, [
				E('th', { 'class': 'th' }, _('Account')),
				E('th', { 'class': 'th' }, _('Status')),
				E('th', { 'class': 'th' }, _('Actions'))
			]));
			(result && result.users || []).forEach(function(user) {
				var newPassword = E('input', { 'type': 'password', 'placeholder': _('New password'), 'autocomplete': 'new-password' });
				var newConfirm = E('input', { 'type': 'password', 'placeholder': _('Confirm password'), 'autocomplete': 'new-password' });
				var toggle = user.status === 'disabled' ? enableUser : disableUser;
				table.appendChild(E('tr', { 'class': 'tr' }, [
					E('td', { 'class': 'td' }, user.name),
					E('td', { 'class': 'td' }, user.status === 'disabled' ? _('Disabled') : _('Enabled')),
					E('td', { 'class': 'td' }, [
						newPassword, newConfirm,
						E('button', { 'class': 'btn', 'click': function() {
							if (!passwordOK(newPassword.value) || newPassword.value !== newConfirm.value) { notice(_('Passwords must match and be 12–127 characters.')); return; }
							return action(setPassword, [ user.name, newPassword.value ], refresh).then(function() { newPassword.value = ''; newConfirm.value = ''; });
						} }, _('Change password')),
						E('button', { 'class': 'btn', 'click': function() { return action(toggle, [ user.name ], refresh); } }, user.status === 'disabled' ? _('Enable') : _('Disable')),
						E('button', { 'class': 'btn', 'click': function() {
							if (window.confirm(_('Remove Samba account ') + user.name + '?')) return action(removeUser, [ user.name ], refresh);
						} }, _('Remove'))
					])
				]));
			});
		}
		root.appendChild(E('h2', {}, _('Samba users')));
		root.appendChild(E('p', {}, _('Create Samba-only accounts here, then add the full account name to Allowed users on each private Samba share. These accounts cannot sign in to the router.')));
		root.appendChild(E('div', { 'class': 'cbi-section' }, [
			E('h3', {}, _('Create account')),
			E('p', {}, _('Name: lowercase letters, digits or underscore. The mxsmb_ prefix is added automatically.')),
			name, password, confirmPassword,
			E('button', { 'class': 'btn cbi-button-action', 'click': function() {
				if (!/^[a-z][a-z0-9_]{0,19}$/.test(name.value)) { notice(_('Enter a valid account name.')); return; }
				if (!passwordOK(password.value) || password.value !== confirmPassword.value) { notice(_('Passwords must match and be 12–127 characters.')); return; }
				return action(addUser, [ 'mxsmb_' + name.value, password.value ], refresh).then(function() { password.value = ''; confirmPassword.value = ''; });
			} }, _('Create'))
		]));
		root.appendChild(table);
		draw(data);
		return root;
	},
	handleSave: null,
	handleSaveApply: null,
	handleReset: null
});
EOF_JS
touch /etc/sysupgrade.conf
for F in /usr/libexec/rpcd/mx.samba /usr/share/rpcd/acl.d/mx-samba.json /usr/share/luci/menu.d/mx-samba.json /www/luci-static/resources/view/samba4/users.js /etc/mx4200/samba-users; do
    grep -qxF "$F" /etc/sysupgrade.conf || printf '%s\n' "$F" >> /etc/sysupgrade.conf
done
/etc/init.d/rpcd reload >/dev/null 2>&1 || /etc/init.d/rpcd restart >/dev/null 2>&1 || true
