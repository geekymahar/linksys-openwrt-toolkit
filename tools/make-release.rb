#!/usr/bin/env ruby
require 'digest'
require 'fileutils'
require 'open3'
Encoding.default_external = Encoding::UTF_8
root = File.expand_path('..', __dir__)
tree = File.join(root, 'files')
entries = []
Dir.glob(File.join(tree, '**', '*')).sort.each do |path|
  next unless File.file?(path) && !File.symlink?(path)
  relative = path.delete_prefix(tree + '/')
  group = case relative
          when %r{\Ausr/lib/router-defaults/}, 'usr/lib/mxc', 'usr/share/router-defaults/help.txt' then 'shared'
          when 'usr/sbin/mxauto', 'usr/sbin/mxroutehealth', 'etc/init.d/mxauto', 'etc/init.d/mxroutehealth' then 'auto'
          when 'usr/bin/mxls', 'usr/bin/mxld', 'etc/init.d/mxl' then 'led'
          when 'usr/libexec/rpcd/mx.samba', 'usr/share/rpcd/acl.d/mx-samba.json', 'usr/share/luci/menu.d/mx-samba.json', 'www/luci-static/resources/view/samba4/users.js' then 'samba'
          else next
          end
  mode = File.executable?(path) ? '755' : '644'
  entries << [group, Digest::SHA256.file(path).hexdigest, mode, relative]
end
allowlist = File.join(tree, 'usr/share/router-defaults/update-files.txt')
File.write(allowlist, entries.map { |group, _hash, mode, relative| "#{group} #{mode} #{relative}\n" }.join)
exit 0 if ARGV == ['--allowlist']
key = ARGV.fetch(0) { abort 'Usage: ruby tools/make-release.rb PRIVATE_KEY | --allowlist' }
public, errors, result = Open3.capture3('openssl', 'pkey', '-in', key, '-pubout')
abort errors unless result.success?
abort 'Key does not match the firmware public key' unless public.strip == File.read(File.join(tree, 'usr/share/router-defaults/release.pub')).strip
release = File.join(root, 'mx4200-v2/embedded-release')
FileUtils.mkdir_p(release)
manifest = File.join(release, 'manifest.txt')
signature = File.join(release, 'manifest.sig')
File.write(manifest, "MX4200V2-EMBEDDED 1\n" + entries.map { |entry| entry.join(' ') + "\n" }.join)
abort 'Signing failed' unless system('openssl', 'pkeyutl', '-sign', '-inkey', key, '-rawin', '-in', manifest, '-out', signature)
abort 'Signature verification failed' unless system('openssl', 'pkeyutl', '-verify', '-pubin', '-inkey', File.join(tree, 'usr/share/router-defaults/release.pub'), '-rawin', '-in', manifest, '-sigfile', signature)
puts "Signed #{entries.length} embedded runtime assets; no first-boot download or config payload"