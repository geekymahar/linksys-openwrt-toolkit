#!/usr/bin/env ruby
# One-time mechanical extraction. Normal builds do not run this importer.
require 'digest'
require 'fileutils'
require 'json'
require 'open3'

Encoding.default_external = Encoding::UTF_8
root = File.expand_path('..', __dir__)
legacy = File.join(root, 'mx4200-v2')
destination = File.join(root, 'files')
abort 'Runtime tree already exists; do not overwrite maintained files' if File.exist?(File.join(destination, 'usr/sbin/mxm'))

groups = {
  'network-functions' => %w[ds rwan ld sl mc],
  'firewall-functions' => %w[zs dz df lz wz fw l2w znew mf uz pr mr vz],
  'wireless-functions' => %w[wifi_clear rb ap ws ri sr e2u nk],
  'profiles' => %w[pex psave pload mode savecur priority psum],
  'input' => %w[passok rs],
  'runtime' => %w[u ca ra]
}
names = {
  'u' => 'set_option', 'ds' => 'find_bridge_section', 'rwan' => 'bridge_wan_port',
  'ld' => 'configure_bridge_dhcp_client', 'sl' => 'configure_static_lan',
  'mc' => 'configure_management_network', 'zs' => 'find_firewall_zone',
  'dz' => 'delete_firewall_zone', 'df' => 'delete_non_vpn_forwardings',
  'lz' => 'ensure_lan_zone', 'wz' => 'configure_wan_zone',
  'fw' => 'ensure_forwarding', 'l2w' => 'configure_lan_to_wan',
  'znew' => 'create_firewall_zone', 'mf' => 'configure_management_firewall',
  'uz' => 'configure_uplink_zone', 'pr' => 'add_management_source_ranges',
  'mr' => 'configure_management_rule', 'vz' => 'configure_vpn_zone',
  'rb' => 'configure_radio_defaults', 'ap' => 'configure_access_point',
  'ca' => 'commit_mode_configuration', 'ra' => 'reload_mode_services',
  'pex' => 'profile_exists', 'psave' => 'save_profile', 'pload' => 'load_profile',
  'mode' => 'current_mode', 'savecur' => 'save_current_profile',
  'priority' => 'prompt_auto_priority', 'psum' => 'print_profile_summary',
  'ws' => 'wireless_status', 'ri' => 'radio_interface', 'sr' => 'scan_radio',
  'e2u' => 'scan_encryption_to_uci', 'nk' => 'encryption_needs_key',
  'passok' => 'valid_wifi_password', 'rs' => 'read_secret'
}

def format_shell(source)
  output, errors, result = Open3.capture3('shfmt', '-ln', 'bash', '-i', '4', '-ci', stdin_data: source)
  abort errors unless result.success?
  output
end

# Rename shell command/function identifiers through parser positions, never
# through substitutions inside SSIDs, UCI values, strings or embedded AWK.
def rename_functions(source, names)
  encoded, errors, result = Open3.capture3('shfmt', '-ln', 'bash', '-tojson', stdin_data: source)
  abort errors unless result.success?
  edits = {}
  visit = lambda do |node|
    case node
    when Hash
      literal = if node['Type'] == 'FuncDecl'
                  node['Name']
                elsif node['Type'] == 'CallExpr'
                  argument = node.fetch('Args', []).first
                  parts = argument && argument['Parts']
                  parts.first if parts && parts.length == 1 && parts.first['Type'] == 'Lit'
                end
      if literal && names.key?(literal['Value'])
        position = literal['Pos'] || literal['ValuePos']
        edits[position['Offset']] = [literal['Value'].bytesize, names.fetch(literal['Value'])]
      end
      node.each_value { |child| visit.call(child) }
    when Array
      node.each { |child| visit.call(child) }
    end
  end
  visit.call(JSON.parse(encoded))
  edits.sort.reverse_each { |offset, (length, replacement)| source[offset, length] = replacement }
  source
end

sources = ['uci-defaults.sh', 'modules/auto/install.sh', 'modules/samba/install.sh', 'modules/led/rev3/install.sh']
assets = {}
origins = {}
sources.each do |relative|
  text = File.read(File.join(legacy, relative))
  text.scan(/^cat > (\/[^\s]+) <<'([^']+)'\n(.*?)^\2\n/m) do |path, _delimiter, body|
    next if path == '/etc/hotplug.d/button/95-mx-partition'
    next if %w[/usr/sbin/mxfirstboot /etc/init.d/mxprovision /usr/sbin/mxmod /etc/mx4200/led.conf].include?(path)
    assets[path] = body
    origins[path] = relative
  end
end
common = assets.delete('/usr/lib/mxc')
abort 'Missing shared library' unless common
definitions = common.scan(/^([a-zA-Z_][a-zA-Z_0-9]*)\(\)\s*\{.*?(?=^[a-zA-Z_][a-zA-Z_0-9]*\(\)|\z)/m)
function_text = {}
common.scan(/^([a-zA-Z_][a-zA-Z_0-9]*)\(\)\s*\{.*?(?=^[a-zA-Z_][a-zA-Z_0-9]*\(\)|\z)/m) do
  function_text[Regexp.last_match[1]] = Regexp.last_match[0]
end
abort 'Unmapped common function' unless function_text.keys.sort == groups.values.flatten.sort
groups.each do |group, functions|
  body = "#!/bin/sh\n. /usr/lib/router-defaults/core.sh || return 1\n\n"
  body += functions.map { |name| function_text.fetch(name) }.join("\n")
  assets["/usr/lib/router-defaults/#{group}.sh"] = rename_functions(body, names)
  origins["/usr/lib/router-defaults/#{group}.sh"] = 'uci-defaults.sh: /usr/lib/mxc'
end
assets['/usr/lib/mxc'] = "#!/bin/sh\n. /usr/lib/router-defaults/core.sh || return 1\n" +
  groups.keys.map { |group| ". /usr/lib/router-defaults/#{group}.sh || return 1\n" }.join
assets['/etc/mx4200/base.conf'] = ". /etc/router-defaults/config\n"
assets['/etc/mx4200/led.conf'] = ". /etc/router-defaults/config\n"
assets['/etc/sysctl.d/99-mx4200-vpn.conf'] = "net.ipv4.ip_forward=1\nnet.ipv6.conf.all.forwarding=1\n"
assets.each do |path, body|
  if origins[path] == 'uci-defaults.sh' && body.start_with?('#!/bin/sh')
    body = rename_functions(body, names)
  elsif origins[path] == 'modules/auto/install.sh'
    body = rename_functions(body, names)
  end
  body = body.gsub('. /etc/mx4200/base.conf', '. /usr/lib/router-defaults/core.sh || exit 1')
  body = body.gsub('. /etc/mx4200/led.conf', '')
  body = format_shell(body) if body.start_with?('#!/bin/sh') || path == '/etc/profile.d/mx'
  output = File.join(destination, path)
  FileUtils.mkdir_p(File.dirname(output))
  File.write(output, body)
  File.chmod(body.start_with?('#!/bin/sh') ? 0755 : 0644, output)
end
File.chmod(0600, File.join(destination, 'etc/router-defaults/config'))
File.chmod(0600, File.join(destination, 'etc/mx4200/base.conf'))
File.chmod(0600, File.join(destination, 'etc/mx4200/led.conf'))
FileUtils.ln_sf('/usr/sbin/mxm', File.join(destination, 'usr/bin/mx'))
FileUtils.ln_sf('mx', File.join(destination, 'etc/profile.d/mx.sh'))

packages = File.read(File.join(legacy, 'packages.txt')).split.uniq
File.write(File.join(root, 'packages.txt'), packages.join("\n") + "\n")

FileUtils.mkdir_p(File.join(root, 'docs'))
inventory = "# Legacy Inventory\n\nCaptured before the refactor. Original sources remain in mx4200-v2/.\n\n"
Dir.glob(File.join(legacy, '**', '*'), File::FNM_DOTMATCH).select { |path| File.file?(path) && File.basename(path) != '.DS_Store' }.sort.each do |path|
  relative = path.delete_prefix(root + '/')
  bytes = File.binread(path)
  inventory += "## #{relative}\n\nSHA-256: `#{Digest::SHA256.hexdigest(bytes)}`\n\n"
  if File.extname(path) == '.sh' || File.extname(path) == '.py'
    text = bytes.force_encoding('UTF-8')
    functions = text.scan(/\b([a-zA-Z_][a-zA-Z_0-9]*)\(\)\s*\{|^def ([a-zA-Z_][a-zA-Z_0-9]*)\(/).flatten.compact.uniq
    variables = text.scan(/\b([A-Z_][A-Z_0-9]*)=/).flatten.uniq
    inventory += "Functions: #{functions.join(', ')}\n\nVariables: #{variables.join(', ')}\n\n"
    inventory += "Written assets: #{text.scan(/^cat > (\S+)/).flatten.join(', ')}\n\n"
    inventory += "UCI packages referenced: #{text.scan(/\b(?:network|wireless|firewall|dhcp|system|uhttpd|tailscale|mwan3)\./).uniq.join(', ')}\n\n"
    inventory += "Services referenced: #{text.scan(%r{/etc/init\.d/([\w$]+)}).flatten.uniq.join(', ')}\n\n"
  else
    inventory += "Role: #{File.basename(path).end_with?('.sha256') ? 'Integrity sidecar for adjacent installer' : 'Package selection, documentation, or signed release metadata'}\n\n"
  end
end
inventory += "# Extracted Assets\n\n| Old source | Generated asset / new firmware path | Status |\n| --- | --- | --- |\n"
origins.sort.each { |path, source| inventory += "| #{source} | files#{path} | PRESERVED; extracted and formatted |\n" }
inventory += "\n# Shared Function Map\n\n| Old function | New library / function | Status |\n| --- | --- | --- |\n"
groups.each { |group, functions| functions.each { |name| inventory += "| #{name} | #{group}.sh / #{names.fetch(name, name)} | PRESERVED |\n" } }
File.write(File.join(root, 'docs/legacy-inventory.md'), inventory)
puts "Extracted #{assets.length} complete assets and #{function_text.length} shared functions"