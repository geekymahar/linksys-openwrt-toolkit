#!/usr/bin/env ruby
require 'json'
require 'open3'
require 'set'
require 'pathname'
Encoding.default_external = Encoding::UTF_8
ROOT = File.expand_path('..', __dir__)
TREE = File.join(ROOT, 'files')
failures = []
shell_files = Dir.glob(File.join(TREE, '**', '*'), File::FNM_DOTMATCH).select do |path|
  File.file?(path) && !File.symlink?(path) && File.read(path).start_with?('#!/bin/sh')
end
shell_files += %w[build.sh validate.sh release.sh].map { |name| File.join(ROOT, name) }.select { |path| File.file?(path) }
shell_files.each do |path|
  relative = path.delete_prefix(ROOT + '/')
  failures << "Not executable: #{relative}" unless File.executable?(path)
  [['busybox', 'ash', '-n', path], ['shellcheck', '-s', 'sh', '-S', 'warning', '-e', 'SC1090,SC1091,SC2034,SC3043,SC3045', path]].each do |command|
    output, errors, result = Open3.capture3(*command)
    failures << "#{relative}: #{output}#{errors}" unless result.success?
  end
end
Dir.glob(File.join(ROOT, 'mx4200-v2/**/*.sh')).each do |path|
  _output, errors, result = Open3.capture3('busybox', 'ash', '-n', path)
  failures << "Legacy syntax: #{errors}" unless result.success?
end
Dir.glob(File.join(TREE, '**/*.json')).each do |path|
  begin
    JSON.parse(File.read(path))
  rescue JSON::ParserError => error
    failures << "Invalid JSON: #{path}: #{error}"
  end
end
config = File.read(File.join(TREE, 'etc/router-defaults/config'))
definitions = config.scan(/^([A-Z][A-Z0-9_]*)=/).flatten.to_set
references = Set.new
shell_files.select { |path| path.start_with?(TREE) }.each do |path|
  text = File.read(path)
  assignments = text.scan(/\b([A-Z][A-Z0-9_]*)=/).flatten.to_set
  reads = text.scan(/\bread\b[^\n;]*/).flat_map { |line| line.scan(/\b[A-Z][A-Z0-9_]*\b/) }.to_set
  reads.merge(text.scan(/\bfor\s+([A-Z][A-Z0-9_]*)\s+in\b/).flatten)
  external = Set.new(%w[ACTION INTERFACE LAST_ROLE SECRET MX4200_NO_RELOAD ROUTER_DEFAULTS_CONFIG ROUTER_DEFAULTS_CORE_LOADED])
  text.scan(/\$(?:\{)?([A-Z][A-Z0-9_]*)/).flatten.each do |name|
    references << name
    next if definitions.include?(name) || assignments.include?(name) || reads.include?(name) || external.include?(name)
    failures << "Undefined configuration/state variable #{name}: #{path.delete_prefix(ROOT + '/')}"
  end
  # Known BusyBox ash extensions are permitted; Bash-only constructs are not.
  encoded, errors, result = Open3.capture3('shfmt', '-ln', 'bash', '-tojson', stdin_data: text)
  unless result.success?
    failures << errors
    next
  end
  walk = lambda do |node|
    case node
    when Hash
      if %w[ProcSubst ArrayExpr TestClause CStyleLoop].include?(node['Type'])
        failures << "Bash-only construct #{node['Type']}: #{path}"
      end
      node.each_value { |child| walk.call(child) }
    when Array
      node.each { |child| walk.call(child) }
    end
  end
  walk.call(JSON.parse(encoded))
  text.scan(%r{(?:\. |exec )(/(?:usr/lib/router-defaults|usr/lib/mxc|usr/share/router-defaults)/?[^\s;|]*)}).flatten.each do |target|
    next if target.include?('$')
    failures << "Missing referenced file: #{target}" unless File.exist?(File.join(TREE, target))
  end
end
expected_modules = %w[preflight migration system network dhcp wireless firewall vpn samba recovery services initialize]
expected_modules.each do |name|
  path = File.join(TREE, "usr/lib/router-defaults/#{name}.sh")
  failures << "Missing module #{name}" unless File.file?(path) && File.executable?(path)
end
entry = File.read(File.join(TREE, 'etc/uci-defaults/99-router-defaults'))
failures << 'Wrong uci-defaults entrypoint' unless entry.include?('exec /usr/lib/router-defaults/initialize.sh')
initializer = File.read(File.join(TREE, 'usr/lib/router-defaults/initialize.sh'))
failures << 'Unexpected module order' unless initializer.include?('for module in system network dhcp wireless firewall vpn samba recovery services')
failures << 'Recovery not enabled' unless config.include?("AUTO_RECOVERY='yes'")
failures << 'Custom WPS feature remains' if Dir.glob(File.join(TREE, 'etc/hotplug.d/button/*')).any?
failures << 'Private config permissions must be 0600' unless File.stat(File.join(TREE, 'etc/router-defaults/config')).mode & 0777 == 0600
Dir.glob(File.join(TREE, '**', '*')).select { |path| File.symlink?(path) }.each do |path|
  target = File.readlink(path)
  resolved = target.start_with?('/') ? File.join(TREE, target) : File.expand_path(target, File.dirname(path))
  failures << "Broken firmware symlink: #{path}" unless File.exist?(resolved)
end
packages = File.read(File.join(ROOT, 'packages.txt')).lines.map(&:strip).reject { |line| line.empty? || line.start_with?('#') }
legacy_packages = File.read(File.join(ROOT, 'mx4200-v2/packages.txt')).split.uniq
failures << 'Original package set was changed' unless packages.sort == legacy_packages.sort
failures << 'Duplicate package entries' unless packages.uniq == packages
%w[core.sh config].each do |_name|
  # All shared constants should live in central configuration, not runtime code.
  shell_files.select { |path| path.start_with?(TREE) }.each do |path|
    failures << "Duplicated address default: #{path}" if File.read(path).match?(/(?:1\.1\.1\.1|8\.8\.8\.8|172\.23\.247\.1)/)
  end
  break
end
allowlist = File.join(TREE, 'usr/share/router-defaults/update-files.txt')
if File.file?(allowlist)
  File.readlines(allowlist).each do |line|
    group, mode, relative = line.split
    failures << "Invalid update allowlist entry: #{line}" unless %w[shared auto samba led].include?(group) && %w[644 755].include?(mode) && File.file?(File.join(TREE, relative))
  end
else
  failures << 'Missing signed-update allowlist'
end
if failures.any?
  abort failures.uniq.join("\n")
end
puts "Validated #{shell_files.length} executable shell assets, JSON, config variables, dependencies, symlinks, package parity and recovery policy"