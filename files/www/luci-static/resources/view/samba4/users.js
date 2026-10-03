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
