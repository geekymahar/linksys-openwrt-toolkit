#!/usr/bin/env ruby
# Linux-only tests: real UCI and ash in disposable chroots, no router access.
require 'fileutils'
require 'tmpdir'
require 'open3'
require 'digest'
Encoding.default_external = Encoding::UTF_8
ROOT = File.expand_path('..', __dir__)
NATIVE = ENV.fetch('NATIVE_UCI', '/tmp/router-defaults-native/bin/uci')
abort 'Native UCI missing; see docs/validation.md for test prerequisites' unless File.executable?(NATIVE)

def assert(condition, message)
  abort "FAILED: #{message}" unless condition
end

def write_fixture(root, relative, text, executable: false)
  path = File.join(root, relative)
  FileUtils.mkdir_p(File.dirname(path))
  File.write(path, text)
  File.chmod(0755, path) if executable
end

def run(root, *arguments, success: true, stderr: false)
  output, errors, result = Open3.capture3('chroot', root, '/bin/busybox', 'env',
    'PATH=/usr/sbin:/usr/bin:/sbin:/bin', 'LD_LIBRARY_PATH=/tmp/router-defaults-native/lib', *arguments)
  assert(result.success? == success, "#{arguments.join(' ')}: #{output}#{errors}")
  output = "#{output}#{errors}" if stderr
  output.strip
end

def uci(root, *arguments)
  run(root, '/usr/bin/uci', '-q', *arguments)
end

def snapshot(root)
  Dir.glob(File.join(root, 'etc/config/*')).sort.to_h { |path| [File.basename(path), File.binread(path)] }
end

def fixture
  Dir.mktmpdir('router-defaults-fixture-') do |root|
    FileUtils.cp_r(File.join(ROOT, 'files', '.'), root)
    %w[bin usr/bin usr/sbin etc/config tmp/sysinfo dev var/run/uci etc/rc.d].each { |directory| FileUtils.mkdir_p(File.join(root, directory)) }
    FileUtils.cp('/bin/busybox', File.join(root, 'bin/busybox'))
    %w[sh ash awk cat chmod cp cut date dirname echo false grep head ip ln logger mkdir mv printf readlink rm sed sha256sum sleep sort sync tail tar test touch tr true wc].each do |command|
      FileUtils.ln_sf('/bin/busybox', File.join(root, 'bin', command))
    end
    assert(system('mknod', File.join(root, 'dev/null'), 'c', '1', '3'), 'Create isolated /dev/null')
    FileUtils.cp(NATIVE, File.join(root, 'usr/bin/uci-real'))
    libraries, errors, result = Open3.capture3({ 'LD_LIBRARY_PATH' => '/tmp/router-defaults-native/lib' }, 'ldd', NATIVE)
    assert(result.success?, errors)
    libraries.scan(%r{(/[a-zA-Z0-9_./+-]+)}).flatten.uniq.each do |library|
      next unless File.file?(library)
      target = File.join(root, library)
      FileUtils.mkdir_p(File.dirname(target))
      FileUtils.cp(File.realpath(library), target)
    end
    write_fixture(root, 'usr/bin/uci', <<~SHELL, executable: true)
      #!/bin/sh
      if [ -f /tmp/inject-failure ]; then
          failure=$(cat /tmp/inject-failure)
          case "$*" in *"$failure"*) exit 1;; esac
      fi
      exec /usr/bin/uci-real "$@"
    SHELL
    write_fixture(root, 'tmp/sysinfo/board_name', "linksys,mx4200v2\n")
    write_fixture(root, 'proc/sys/net/ipv4/ip_forward', "0\n")
    write_fixture(root, 'proc/sys/net/ipv6/conf/all/forwarding', "0\n")
    write_fixture(root, 'tmp/boot-env', "auto_recovery no\nboot_part 1\nmaxpartialboots 3\n")
    write_fixture(root, 'usr/sbin/fw_printenv', <<~SHELL, executable: true)
      #!/bin/sh
      if [ "$1" = -n ]; then
          awk -v key="$2" '$1==key {print $2;found=1} END{exit !found}' /tmp/boot-env
      else
          awk -v key="$1" '$1==key {print $1"="$2;found=1} END{exit !found}' /tmp/boot-env
      fi
    SHELL
    write_fixture(root, 'usr/sbin/fw_setenv', <<~SHELL, executable: true)
      #!/bin/sh
      awk -v key="$1" '$1!=key' /tmp/boot-env > /tmp/boot-env.new
      printf '%s %s\n' "$1" "$2" >> /tmp/boot-env.new
      mv /tmp/boot-env.new /tmp/boot-env
    SHELL
    %w[ubus iw iwinfo jsonfilter useradd userdel smbpasswd sysctl reload_config wifi ifup ifdown].each do |command|
      write_fixture(root, "usr/bin/#{command}", "#!/bin/sh\nprintf '%s\\n' '#{command}' >> /tmp/command-log\nexit 0\n", executable: true)
    end
    %w[network dnsmasq firewall mxauto mxroutehealth mxb mxd mxl tailscale openvpn zerotier rpcd uhttpd].each do |service|
      write_fixture(root, "etc/init.d/#{service}", "#!/bin/sh\nprintf '%s %s\\n' '#{service}' \"$*\" >> /tmp/service-log\nexit 0\n", executable: true)
    end
    write_fixture(root, 'etc/rc.common', <<~SHELL, executable: true)
      #!/bin/sh
      initscript=$1
      action=$2
      . "$initscript"
      printf '%s %s\n' "$initscript" "$action" >> /tmp/service-log
      exit 0
    SHELL
    write_fixture(root, 'etc/config/system', "config system\n option hostname 'OpenWrt'\n")
    write_fixture(root, 'etc/config/network', <<~UCI)
      config device
       option name 'br-lan'
       option type 'bridge'
       list ports 'lan1'
       list ports 'lan2'
       list ports 'lan3'
      config interface 'lan'
       option device 'br-lan'
       option proto 'static'
       option ipaddr '192.168.40.1'
       option netmask '255.255.255.0'
      config interface 'wan'
       option device 'wan'
       option proto 'dhcp'
      config interface 'wan6'
       option device '@wan'
       option proto 'dhcpv6'
    UCI
    write_fixture(root, 'etc/config/wireless', <<~UCI)
      config wifi-device 'radio0'
       option band '5g'
      config wifi-device 'radio1'
       option band '2g'
      config wifi-device 'radio2'
       option band '5g'
      config wifi-iface
       option device 'radio0'
      config wifi-iface
       option device 'radio1'
      config wifi-iface
       option device 'radio2'
    UCI
    write_fixture(root, 'etc/config/dhcp', "config dnsmasq\nconfig dhcp 'lan'\n option interface 'lan'\n")
    write_fixture(root, 'etc/config/firewall', <<~UCI)
      config defaults
       option input 'REJECT'
       option output 'ACCEPT'
       option forward 'REJECT'
      config zone
       option name 'lan'
       list network 'lan'
      config zone
       option name 'wan'
       list network 'wan'
       list network 'wan6'
      config forwarding
       option src 'lan'
       option dest 'wan'
      config rule
       option name 'Allow-DHCP-Renew'
       option src 'wan'
       option proto 'udp'
       option dest_port '68'
       option target 'ACCEPT'
    UCI
    write_fixture(root, 'etc/config/uhttpd', "config uhttpd 'main'\n")
    write_fixture(root, 'etc/config/tailscale', "config tailscale 'settings'\n")
    yield root
  end
end

fixture do |root|
  run(root, '/etc/uci-defaults/99-router-defaults')
  enabled_services = File.read(File.join(root, 'tmp/service-log')).lines.map(&:strip)
  %w[mxb mxd mxauto mxroutehealth tailscale openvpn mxl].each do |service|
    assert(enabled_services.include?("#{service} enable"), "#{service} is enabled at boot")
  end
  assert(!enabled_services.include?('zerotier enable'), 'ZeroTier remains opt-in')
  assert(uci(root, 'get', 'network.lan.ipaddr') == '192.168.40.1', 'LAN address preserved')
  assert(uci(root, 'get', 'network.@device[0].ports') == 'lan1 lan2 lan3', 'LAN port mapping')
  assert(uci(root, 'get', 'wireless.radio2.channel') == '100', 'High-performance default channel')
  assert(uci(root, 'get', 'wireless.default_radio1.device') == 'radio1', '2.4 GHz mapping')
  assert(uci(root, 'show', 'wireless').lines.count { |line| line.end_with?("=wifi-iface\n") } == 3, 'Exactly three initial APs')
  assert(uci(root, 'get', 'firewall.mx_vpn_in.dest_port') == '1194 51820 41641', 'VPN ingress ports')
  assert(run(root, '/usr/sbin/fw_printenv', '-n', 'auto_recovery') == 'yes', 'Automatic recovery enabled')
  assert(run(root, '/usr/sbin/fw_printenv', '-n', 'boot_part') == '1', 'Boot slot unchanged')
  assert(run(root, '/usr/sbin/fw_printenv', '-n', 'maxpartialboots') == '3', 'Recovery threshold unchanged')
  initial = snapshot(root)
  FileUtils.rm_f(File.join(root, 'etc/mx4200/provisioned'))
  FileUtils.rm_f(File.join(root, 'etc/mx4200/mode'))
  run(root, '/etc/uci-defaults/99-router-defaults')
  repeated = snapshot(root)
  changed = initial.keys.select { |package| repeated[package] != initial[package] }
  changed.each { |package| warn "Changed #{package}:\nBEFORE:\n#{initial[package]}AFTER:\n#{repeated[package]}" }
  assert(repeated == initial, 'Repeated initialization is deterministic')
  write_fixture(root, 'etc/mx4200/mode', "wds\n")
  uci(root, 'set', 'network.mgmt=interface')
  uci(root, 'set', 'network.mgmt.ipaddr=172.29.251.1')
  uci(root, 'commit', 'network')
  preserved = snapshot(root)
  run(root, '/etc/uci-defaults/99-router-defaults')
  assert(snapshot(root) == preserved, 'Preserved WDS settings are not replaced')
  assert(File.read(File.join(root, 'etc/mx4200/mode')).strip == 'wds', 'Mode survives migration')
  run(root, '/bin/sh', '-c', '. /usr/lib/mxc && configure_access_point test_open "$RADIO_24" lan "LS-MX4200v2" "" none')
  assert(uci(root, 'get', 'wireless.test_open.encryption') == 'none', 'Runtime AP helper')
  puts 'PASS: clean boot, radio/port/firewall parity, idempotence, recovery, preserved WDS, runtime AP helper'
end
fixture do |root|
  run(root, '/etc/uci-defaults/99-router-defaults')
  # These passwords exist only in the disposable test fixture, never firmware.
  run(root, '/bin/sh', '-c', 'printf "\\ntest-only-client\\ntest-only-management\\n0\\n" | /root/mxa')
  assert(File.read(File.join(root, 'etc/mx4200/mode')).strip == 'ap', 'Wired AP mode recorded')
  assert(uci(root, 'get', 'network.lan.proto') == 'dhcp', 'AP receives upstream DHCP')
  assert(uci(root, 'get', 'network.@device[0].ports') == 'lan1 lan2 lan3 wan', 'AP bridges WAN and LAN sockets')
  assert(uci(root, 'get', 'dhcp.lan.ignore') == '1', 'AP does not serve ordinary LAN DHCP')
  assert(uci(root, 'get', 'network.mgmt.ipaddr') == '172.23.247.1', 'AP retains isolated management')
  assert(uci(root, 'get', 'wireless.mx_mgmt.network') == 'mgmt', 'Management SSID isolated from LAN')
  run(root, '/bin/sh', '-c', '. /usr/lib/mxc && MX4200_NO_RELOAD=1 load_profile router-baseline')
  assert(uci(root, 'get', 'network.lan.proto') == 'static', 'Router baseline restoration')
  assert(File.read(File.join(root, 'etc/mx4200/mode')).strip == 'router', 'Baseline records router mode')
  write_fixture(root, 'etc/mx4200/mode', "repeater\n")
  write_fixture(root, 'etc/config/mwan3', "config policy 'balanced'\nconfig rule 'default_rule'\n option dest_ip '0.0.0.0/0'\n option use_policy 'balanced'\n")
  write_fixture(root, 'etc/init.d/mwan3', "#!/bin/sh\nexit 0\n", executable: true)
  uci(root, 'set', 'network.wwanp=interface')
  uci(root, 'set', 'network.wwanp.proto=dhcp')
  uci(root, 'set', 'network.wwanp.metric=5')
  uci(root, 'set', 'network.wwanb=interface')
  uci(root, 'set', 'network.wwanb.proto=dhcp')
  uci(root, 'set', 'network.wwanb.metric=15')
  uci(root, 'commit', 'network')
  run(root, '/usr/sbin/mxroutehealth', 'once')
  assert(uci(root, 'get', 'mwan3.wwanp.interval') == '10', 'Routed probe interval')
  assert(uci(root, 'get', 'mwan3.mxroute_wwanp.metric') == '5', 'Primary route preference')
  assert(uci(root, 'get', 'mwan3.mxroute_wwanb.metric') == '15', 'Backup route preference')
  assert(uci(root, 'get', 'mwan3.default_rule.use_policy') == 'mx4200_repeater', 'Routed failover policy applied')
  write_fixture(root, 'etc/mx4200/mode', "router\n")
  run(root, '/usr/sbin/mxroutehealth', 'once')
  assert(uci(root, 'get', 'mwan3.default_rule.use_policy') == 'balanced', 'mwan3 config restored after leaving repeater')
  puts 'PASS: wired AP, management isolation, router restore, routed health policy and restoration'
end
fixture do |root|
  FileUtils.mkdir_p(File.join(root, 'rom'))
  FileUtils.cp_r(File.join(ROOT, 'files', '.'), File.join(root, 'rom'))
  write_fixture(root, 'usr/sbin/mxm', "#!/bin/sh\necho legacy-program\n", executable: true)
  write_fixture(root, 'etc/mx4200/base.conf', "COUNTRY='GB'\nLAN_IP='192.168.40.1'\n")
  write_fixture(root, 'etc/mx4200/led.conf', "LED_INTERVAL='3'\n")
  write_fixture(root, 'etc/mx4200/mode', "router\n")
  write_fixture(root, 'etc/hotplug.d/button/95-mx-partition', "#!/bin/sh\nexit 0\n", executable: true)
  write_fixture(root, 'etc/sysupgrade.conf', "/usr/sbin/mx*\n/etc/mx4200\n/etc/config/network\n")
  original = snapshot(root)
  run(root, '/etc/uci-defaults/99-router-defaults')
  assert(snapshot(root) == original, 'Legacy migration retains live UCI settings')
  assert(File.read(File.join(root, 'usr/sbin/mxm')) == File.read(File.join(ROOT, 'files/usr/sbin/mxm')), 'Legacy program replaced with firmware code')
  assert(File.exist?(File.join(root, 'etc/mx4200/legacy-program-backup/usr/sbin/mxm')), 'Replaced legacy program archived')
  assert(!File.exist?(File.join(root, 'etc/hotplug.d/button/95-mx-partition')), 'Legacy custom WPS listener retired')
  assert(File.read(File.join(root, 'etc/router-defaults/config')).include?("LED_INTERVAL='3'"), 'Legacy LED settings merged')
  assert(File.read(File.join(root, 'etc/sysupgrade.conf')).include?('/etc/config/network'), 'Unrelated backup rule retained')
  assert(!File.read(File.join(root, 'etc/sysupgrade.conf')).include?('/usr/sbin/mx*'), 'Legacy executable backup rule retired')
  puts 'PASS: overlay code refresh, archival, config migration, WPS retirement and backup-rule preservation'
end
fixture do |root|
  initial = snapshot(root)
  write_fixture(root, 'tmp/inject-failure', 'wireless.radio2.country=GB')
  run(root, '/etc/uci-defaults/99-router-defaults', success: false)
  assert(snapshot(root) == initial, 'Failure restores all backed-up UCI files')
  assert(!File.exist?(File.join(root, 'etc/router-defaults/applied-version')), 'Failure leaves no completion marker')
  assert(!File.exist?(File.join(root, 'etc/mx4200/provisioned')), 'Failure leaves no legacy completion marker')
  FileUtils.rm_f(File.join(root, 'tmp/inject-failure'))
  run(root, '/etc/uci-defaults/99-router-defaults')
  puts 'PASS: injected UCI failure rolls back and a later boot can retry'
end
fixture do |root|
  write_fixture(root, 'usr/bin/iw', <<~SHELL, executable: true)
    #!/bin/sh
    printf 'Interface fixture\n\taddr 02:00:00:00:00:01\n'
  SHELL
  write_fixture(root, 'usr/bin/iwinfo', <<~SHELL, executable: true)
    #!/bin/sh
    if [ "$2" = scan ]; then
        cat /tmp/scan-fixture
    fi
  SHELL
  write_fixture(root, 'tmp/scan-fixture', <<~SCAN)
    Cell 01 - Address: 02:00:00:00:00:01
              ESSID: "LS-MX4200v2"
              Channel: 116
              Signal: -20 dBm
              Encryption: WPA2 PSK (CCMP)
    Cell 02 - Address: 02:00:00:00:00:02
              ESSID: "LS-MX4200v2"
              Channel: 116
              Signal: -55 dBm
              Encryption: WPA2 PSK (CCMP)
    Cell 03 - Address: 02:00:00:00:00:03
              ESSID: "LS-MX4200v2"
              Channel: 116
              Signal: -75 dBm
              Encryption: WPA2 PSK (CCMP)
  SCAN
  write_fixture(root, 'usr/bin/jsonfilter', <<~SHELL, executable: true)
    #!/bin/sh
    case "$2" in
        *pending*)
            checks=$(cat /tmp/pending-checks 2>/dev/null || echo 0)
            checks=$((checks + 1))
            printf '%s\n' "$checks" >/tmp/pending-checks
            [ "$checks" -le 2 ] && echo true || echo false
            ;;
    esac
  SHELL
  scanned = run(root, '/bin/sh', '-c', '. /usr/lib/mxc; sleep(){ :; }; scan_radio "$RADIO_5G_MAX" /tmp/scan-result; cat /tmp/scan-result')
  assert(scanned.include?('02:00:00:00:00:02'), 'Strongest non-local BSSID selected')
  assert(!scanned.include?('02:00:00:00:00:01') && !scanned.include?('02:00:00:00:00:03'), 'Self BSSID and weaker duplicate filtered')
  assert(run(root, '/bin/sh', '-c', '. /usr/lib/mxc; scan_encryption_to_uci "WPA2 PSK (CCMP)"') == 'psk2', 'WPA2 security mapping')
  assert(run(root, '/bin/sh', '-c', '. /usr/lib/mxc; scan_encryption_to_uci "WPA PSK (CCMP)"') == 'psk', 'WPA1 is not misidentified as WPA2')
  write_fixture(root, 'tmp/pending-checks', "0\n")
  wait_result = run(root, '/bin/sh', '-c', '. /usr/lib/mxc; waited=0; wireless_status(){ printf "{}\\n"; }; sleep(){ [ "$1" = 2 ] && waited=$((waited+2)); }; scan_radio "$RADIO_5G_MAX" /tmp/scan-result 10; printf "waited=%s\\n" "$waited"', stderr: true)
  assert(wait_result.include?('waited=4'), "DFS pending state waits while the readiness timer advances: #{wait_result.inspect}")
  assert(wait_result.include?('00:10 remaining'), 'DFS wait countdown is surfaced to the operator')
  assert(run(root, '/usr/sbin/mxm', 'help').include?('Automatic Linksys recovery is enabled'), 'Offline help describes recovery correctly')
  assert(run(root, '/usr/sbin/mxm', 'help').include?('kernel disabled the extension channel'), 'Offline help explains current HE160 limitation')
  puts 'PASS: scan parser, self-BSSID filtering, strongest match, WPA version mapping and offline help'
end
if File.file?(File.join(ROOT, 'mx4200-v2/embedded-release/manifest.sig'))
  fixture do |root|
    release = File.join(ROOT, 'mx4200-v2/embedded-release')
    FileUtils.mkdir_p(File.join(root, 'test-release'))
    FileUtils.cp(File.join(release, 'manifest.txt'), File.join(root, 'test-release/manifest.txt'))
    FileUtils.cp(File.join(release, 'manifest.sig'), File.join(root, 'test-release/manifest.sig'))
    FileUtils.cp_r(File.join(ROOT, 'files'), File.join(root, 'test-release/files'))
    FileUtils.cp('/usr/bin/openssl', File.join(root, 'usr/bin/openssl'))
    libraries, = Open3.capture3('ldd', '/usr/bin/openssl')
    libraries.scan(%r{(/[a-zA-Z0-9_./+-]+)}).flatten.uniq.each do |library|
      next unless File.file?(library)
      target = File.join(root, library)
      FileUtils.mkdir_p(File.dirname(target))
      FileUtils.cp(File.realpath(library), target)
    end
    write_fixture(root, 'usr/bin/uclient-fetch', <<~SHELL, executable: true)
      #!/bin/sh
      while [ "$#" -gt 0 ]; do
          case "$1" in
              -O) output=$2; shift 2;;
              -T) shift 2;;
              -q) shift;;
              *) url=$1; shift;;
          esac
      done
      case "$url" in
          */embedded-release/*) relative=${url##*/embedded-release/};;
          */files/*) relative=files/${url##*/files/};;
          *) exit 1;;
      esac
      cp "/test-release/$relative" "$output"
    SHELL
    run(root, '/usr/sbin/mxmod', 'auto-once')
    assert(File.file?(File.join(root, 'etc/mx4200/modules/auto.manifest')), 'Valid signed manual update accepted')
    write_fixture(root, 'test-release/manifest.sig', 'invalid-signature')
    before = File.binread(File.join(root, 'usr/sbin/mxauto'))
    run(root, '/usr/sbin/mxmod', 'auto-once', success: false)
    assert(File.binread(File.join(root, 'usr/sbin/mxauto')) == before, 'Invalid signature cannot change runtime code')
    puts 'PASS: signed manual update accepted; invalid signature rejected without code changes'
  end
else
  puts 'NOTE: signed transport tests run after ./release.sh generates a manifest/signature'
end
fixture do |root|
  initial = snapshot(root)
  write_fixture(root, 'tmp/sysinfo/board_name', "unsupported,test-board\n")
  run(root, '/etc/uci-defaults/99-router-defaults', success: false)
  assert(snapshot(root) == initial, 'Unsupported hardware cannot mutate UCI')
  puts 'PASS: unsupported board rejected without configuration changes'
end