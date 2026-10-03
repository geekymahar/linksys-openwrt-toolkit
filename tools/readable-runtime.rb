#!/usr/bin/env ruby
# Mechanical readability pass for extracted shell, using shfmt byte positions.
require 'json'
require 'open3'
Encoding.default_external = Encoding::UTF_8
root = File.expand_path('..', __dir__)
common_names = {
  'S' => 'section', 'R' => 'radio', 'O' => 'option', 'I' => 'interface',
  'B' => 'bridge_section', 'Z' => 'zone_section', 'F' => 'config_entry',
  'N' => 'iteration', 'D' => 'device', 'M' => 'mode_name', 'P' => 'value',
  'V' => 'setting', 'T' => 'temporary_file', 'A' => 'answer',
  'C' => 'choice', 'Q' => 'ssid', 'E' => 'encryption', 'K' => 'password',
  'U' => 'upstream_ssid', 'X' => 'selected_value', 'H' => 'phy_name',
  'W' => 'wait_elapsed', 'Y' => 'green_value'
}
function_names = {
  'duo' => 'disable_usb_before_mode_change', 'sil' => 'prepare_mode_change',
  'ract' => 'router_menu', 'pact' => 'repeater_menu', 'aact' => 'ap_menu',
  'bact' => 'backhaul_menu', 'sact' => 'print_status', 'lact' => 'led_menu',
  'mact' => 'module_update_menu', 'si' => 'station_interface',
  'up' => 'station_connected', 'rp' => 'rediscover_backhaul',
  'sw' => 'select_wds_backhaul', 'rmet' => 'restore_route_metrics',
  'ordered' => 'ordered_profiles', 'rank' => 'profile_rank',
  'route_dev' => 'non_vpn_default_device', 'health' => 'uplink_healthy',
  'carrier' => 'has_carrier', 'possible' => 'mode_possible',
  'cooled' => 'mode_in_cooldown', 'manual' => 'manual_pause_active',
  'step' => 'evaluate_profiles', 'setopt' => 'set_changed_option',
  'active' => 'interface_active', 'metric' => 'interface_metric',
  'signature' => 'uplink_signature', 'rule_name' => 'default_rule',
  'restore' => 'restore_mwan_configuration', 'configure' => 'configure_mwan_policy',
  'mgmt' => 'update_management_address', 'free_ip' => 'management_subnet_free'
}
paths = Dir.glob(File.join(root, 'files/{usr/sbin/mx*,root/mx*,usr/bin/mxl*,usr/lib/router-defaults/*-functions.sh,usr/lib/router-defaults/profiles.sh,usr/lib/router-defaults/runtime.sh,usr/lib/router-defaults/input.sh}'))
paths.each do |path|
  next unless File.file?(path) && !File.symlink?(path)
  source = File.read(path)
  next unless source.start_with?('#!/bin/sh')
  names = common_names.dup
  commands = function_names.dup
  if File.basename(path) == 'mxls'
    commands = {'fl' => 'find_led_channel', 'rb' => 'find_st1202_bus', 'sc' => 'set_sysfs_channel', 'si' => 'initialize_st1202', 'rgb' => 'set_rgb'}
  elsif File.basename(path) == 'mxld'
    commands = {'load' => 'read_led_state', 'delay' => 'animation_delay', 'show' => 'show_color', 'breathe' => 'animate_breathing', 'beat' => 'animate_beat', 'write' => 'write_led_state', 'level' => 'traffic_level', 'bytes' => 'interface_bytes', 'wgifs' => 'wireguard_interfaces', 'wgup' => 'wireguard_active', 'wgbytes' => 'wireguard_bytes', 'ovpnifs' => 'openvpn_interfaces', 'ovpnup' => 'openvpn_active', 'ovpnbytes' => 'openvpn_bytes', 'wdssta' => 'wds_station_interface', 'staif' => 'station_interface', 'staup' => 'station_active', 'route_dev' => 'route_device', 'iface_dev' => 'network_interface_device', 'dfs_wait' => 'radio_waiting_for_dfs'}
  end
  case File.basename(path)
  when 'profiles.sh'
    names.merge!('N' => 'profile_name', 'D' => 'profile_directory', 'F' => 'profile_file', 'M' => 'profile_mode', 'P' => 'previous_priority', 'V' => 'selected_priority', 'I' => 'profile_lan_ip')
  when 'wireless-functions.sh'
    names.merge!('O' => 'scan_output', 'A' => 'scan_buffer', 'P' => 'scan_pass_file', 'X' => 'local_bssids', 'N' => 'scan_pass', 'D' => 'scan_delay')
  when 'mxauto'
    names.merge!('P' => 'priority', 'M' => 'candidate_mode', 'R' => 'current_rank', 'D' => 'route_device', 'T' => 'timestamp', 'N' => 'health_attempt')
  when 'mxroutehealth'
    names.merge!('I' => 'uplink', 'R' => 'rule', 'V' => 'option_value', 'P' => 'protocol')
  when 'mxls'
    names.merge!('R' => 'red_path', 'G' => 'green_path', 'B' => 'blue_path', 'P' => 'led_path', 'V' => 'brightness', 'M' => 'maximum_brightness', 'N' => 'bus_number', 'D' => 'bus_device', 'X' => 'red_value', 'Y' => 'green_value', 'Z' => 'blue_value')
  when 'mxld'
    names.merge!('R' => 'radio', 'G' => 'wireguard_bytes', 'B' => 'unused_blue', 'A' => 'received_bytes', 'Z' => 'transmitted_bytes', 'V' => 'brightness', 'W' => 'uplink_bytes', 'T' => 'tailscale_bytes', 'O' => 'openvpn_bytes', 'L' => 'traffic_level', 'X' => 'total_bytes')
  end
  encoded, errors, result = Open3.capture3('shfmt', '-ln', 'bash', '-tojson', stdin_data: source)
  abort errors unless result.success?
  edits = {}
  replace_literal = lambda do |literal, replacement|
    position = literal['Pos'] || literal['ValuePos']
    edits[position['Offset']] = [literal['Value'].bytesize, replacement] if position
  end
  visit = lambda do |node, arithmetic = false|
    case node
    when Hash
      arithmetic ||= %w[ArithmExp ArithmCmd BinaryArithm UnaryArithm].include?(node['Type'])
      %w[Name Param].each do |key|
        literal = node[key]
        replace_literal.call(literal, names.fetch(literal['Value'])) if literal.is_a?(Hash) && names.key?(literal['Value'])
      end
      if arithmetic && node['Type'] == 'Lit' && names.key?(node['Value'])
        replace_literal.call(node, names.fetch(node['Value']))
      end
      if node['Type'] == 'FuncDecl' && commands.key?(node['Name']['Value'])
        replace_literal.call(node['Name'], commands.fetch(node['Name']['Value']))
      end
      if node['Type'] == 'CallExpr'
        parts = node.fetch('Args', []).first&.fetch('Parts', [])
        if parts && parts.length == 1 && parts.first['Type'] == 'Lit'
          command = parts.first['Value']
          if commands.key?(command)
            replace_literal.call(parts.first, commands.fetch(command))
          end
          if command == 'read'
            node.fetch('Args', []).drop(1).each do |argument|
              literal = argument.fetch('Parts', []).first
              replace_literal.call(literal, names.fetch(literal['Value'])) if literal && names.key?(literal['Value'])
            end
          end
        end
      end
      if node['Semicolon'].is_a?(Hash)
        offset = node['Semicolon']['Offset']
        edits[offset] = [1, "\n"] if source.b.byteslice(offset, 1) == ';'
      end
      if node['Type'] == 'Block'
        edits[node['Lbrace']['Offset']] = [1, "{\n"]
        edits[node['Rbrace']['Offset']] = [1, "\n}"]
      end
      if node['Type'] == 'CaseItem' && node['OpPos'].is_a?(Hash)
        offset = node['OpPos']['Offset']
        edits[offset] = [2, ";;\n"] if source.b.byteslice(offset, 2) == ';;'
      end
      node.each do |key, child|
        if child.is_a?(Hash) && child.key?('Offset')
          offset = child['Offset']
          token = source.b.byteslice(offset, 4)
          if %w[ThenPos DoPos Else].include?(key) && token&.match?(/\A(?:then|do\b|else)/)
            length = token.start_with?('do') ? 2 : 4
            edits[offset] = [length, source.b.byteslice(offset, length) + "\n"]
          end
        end
        visit.call(child, arithmetic)
      end
    when Array
      node.each { |child| visit.call(child, arithmetic) }
    end
  end
  visit.call(JSON.parse(encoded))
  bytes = source.b
  edits.sort.reverse_each { |offset, (length, replacement)| bytes[offset, length] = replacement }
  source = bytes.force_encoding(Encoding::UTF_8)
  formatted, errors, result = Open3.capture3('shfmt', '-ln', 'bash', '-i', '4', '-ci', stdin_data: source)
  abort "#{path}: #{errors}" unless result.success?
  formatted = formatted.gsub(/(\{|then|do)\n[ \t]*\n/, "\\1\n")
  formatted = formatted.gsub(/\n[ \t]*\n(?=[ \t]*\})/, "\n")
  File.write(path, formatted)
end
puts "Expanded and renamed shell identifiers in #{paths.length} runtime assets"