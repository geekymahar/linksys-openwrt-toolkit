# Functionality Migration Report

The original sources are retained in `mx4200-v2/`; the active ImageBuilder input is root `files/`. `legacy-inventory.md` records original hashes, variables, function inventories and generated paths. The table below accounts for delivery changes as well as router behavior.

| Old File | Old Functionality | New Module / Function | Status | Reason |
| --- | --- | --- | --- | --- |
| `uci-defaults.sh` | Default hostname, addresses, DHCP pool, country, SSIDs, radio modes/channel and probe targets | `etc/router-defaults/config` | PRESERVED | One readable source for global defaults; no invented values. |
| `uci-defaults.sh` | Write common library and runtime programs with heredocs | Actual `files/usr/lib/`, `files/usr/sbin/`, `files/root/` files | CHANGED | Programs are embedded directly in SquashFS rather than generated in overlay. |
| `uci-defaults.sh` / `u`, `ca`, `ra` | Shared UCI writes, commit and reload | `core.sh`, `runtime.sh` / `set_option`, `commit_mode_configuration`, `reload_mode_services` | PRESERVED | Descriptive names and checked initialization helpers. Runtime profile reload remains explicit. |
| `uci-defaults.sh` / `ds`, `rwan`, `ld`, `sl`, `mc` | Bridge lookup, WAN-as-LAN, upstream DHCP, static LAN, isolated management | `network-functions.sh`, `network.sh`, `dhcp.sh` | PRESERVED | Port/radio mappings and mode behavior retained. |
| `uci-defaults.sh` / firewall helpers | LAN/WAN/uplink/management/VPN zones, forwarding, restricted management and VPN ingress | `firewall-functions.sh`, `firewall.sh` | PRESERVED | Owned objects use deterministic names; anonymous deletions run backwards. Unrelated firewall rules are retained. |
| `uci-defaults.sh` / `rb`, `ap`, `wifi_clear` | Radio defaults and AP construction | `wireless-functions.sh`, `wireless.sh` | PRESERVED | Existing country, mapping, modes, open initial SSIDs and channel 116 retained. |
| `uci-defaults.sh` / `ws`, `ri`, `sr`, `e2u`, `nk` | Wireless status, four-pass scan/DFS wait, self-BSSID filtering, strongest SSID result and security mapping | `wireless-functions.sh` | PRESERVED | Human-readable scan parser and descriptive names; no new authentication assumptions. |
| `uci-defaults.sh` / profile helpers | Save/restore five UCI packages, baseline, mode and priorities, manual pause | `profiles.sh` | PRESERVED | Existing data locations, permissions and commands retained. |
| `uci-defaults.sh` / `passok`, `rs` | Password validation and masked interactive input | `input.sh` | PRESERVED | No credentials embedded or duplicated. |
| `uci-defaults.sh` / `/root/mxr` | Routed/WDS setup, upstream credentials, client/management keys, WAN choice, primary/backup scan | `files/root/mxr` | PRESERVED | Complete setup implementation extracted; runtime metrics centralized. |
| `uci-defaults.sh` / `/root/mxa` | Wired AP, all ports bridged, upstream DHCP and isolated management | `files/root/mxa` | PRESERVED | Confirmed by native-UCI fixture tests. |
| `uci-defaults.sh` / `mxb` | WDS association-based switching, primary recovery delay, BSSID/security rediscovery, manual backhaul selection | `files/usr/sbin/mxb`, `etc/init.d/mxb` | PRESERVED | No Internet probes added to inactive WDS bridge members. |
| `uci-defaults.sh` / `mxu` | USB detection, primary/backup metrics, disable, last-role menu | `files/usr/sbin/mxu` | PRESERVED | Glob-based detection; no new automatic USB insertion/reboot behavior. |
| `uci-defaults.sh` / `mxw`, `mxwds` | WDS association/4addr/address/route/ping/DNS diagnostics | `files/usr/sbin/mxw`, `files/root/mxwds` | PRESERVED | Existing health states retained. |
| `uci-defaults.sh` / `mxd`, `95-mxmgmt` | Learned-DNS fallback, subnet overlap avoidance, Tailscale post-login settings | `files/usr/sbin/mxd`, `etc/hotplug.d/iface/95-mxmgmt` | PRESERVED | Probe values, fallback subnets and intervals centralized. |
| `uci-defaults.sh` / `mxm`, aliases | Menus, status, profile commands, LED/USB/backhaul choices and help | `files/usr/sbin/mxm`, `usr/bin/mx`, `etc/profile.d/`, `help.txt` | PRESERVED | Existing public command names remain; help no longer has a text budget. |
| `uci-defaults.sh` | HTTPS redirect, forwarding sysctls, VPN ingress/zones, Tailscale fw_mode and service enablement | `system.sh`, `vpn.sh`, `firewall.sh`, `services.sh` | PRESERVED | No new peers, keys, logins, connections or PBR policies. |
| `uci-defaults.sh`, Auto installer | Disable automatic partition fallback | `recovery.sh` / `main` | CHANGED | User explicitly requested enabled recovery: `auto_recovery=yes`; slot and threshold untouched. |
| Auto installer / `95-mx-partition` | Custom WPS multi-press partition switch | Not installed; legacy listener retired by `migration.sh` | REMOVED | Explicit user request. Stock WPS and LuCI Advanced Reboot are retained. |
| `modules/auto/install.sh` | Prioritized saved-mode trials, health polling, cooldown and restoration | `files/usr/sbin/mxauto`, `etc/init.d/mxauto` | PRESERVED | Embedded offline rather than optional download. |
| `modules/auto/install.sh` | IPv4 routed-repeater mwan3 probes, policy and backup/restore | `files/usr/sbin/mxroutehealth`, `etc/init.d/mxroutehealth` | PRESERVED | Native-UCI tests check policy, probe interval, metrics and restoration. |
| `modules/samba/install.sh` | Samba-only account CRUD, stdin passwords, account ownership registry, LuCI/RPC/ACL | `samba.sh`, `usr/libexec/rpcd/mx.samba`, LuCI assets | PRESERVED | Files embedded; no automatic users/shares created. |
| `modules/led/rev3/install.sh` | RGB sysfs/ST1202, boot readiness, traffic animation, VPN overlays, DFS/backhaul/backup/USB states | `usr/bin/mxls`, `usr/bin/mxld`, `etc/init.d/mxl` | PRESERVED | Selected revision 3 extracted with readable function names and centralized settings. |
| `modules/led/install.sh`, `modules/led/rev2/install.sh` | Earlier mutually exclusive revisions of the same LED programs | Selected revision-3 implementation; originals retained for comparison | CHANGED | Consolidated into one active service, retaining current selected behavior rather than running three conflicting revisions. |
| `modules/provision/install.sh`, `mxfirstboot`, `mxprovision` | Automatic signed downloaded-core handoff after route appears | Direct SquashFS delivery and `initialize.sh` | CHANGED | Offline embedded initialization replaces the provisioning transport; no router feature is dropped. Legacy code remains available for legacy firmware. |
| `mxmod`, provisioner, legacy release tooling | Signed explicit Auto/Samba/LED module updates | New `mxmod`, `release.sh`, `tools/make-release.rb`, embedded manifest | PRESERVED | Same signing key/repository, new path allowlist and per-file payload format; config/profiles excluded. |
| `release/build.py`, `manifest.*`, `.sha256` files | Signed legacy installer release, size gate, pinned provisioner | Legacy artifacts retained; new build/release/validation helpers | CHANGED | Original signed protocol stays compatible with legacy firmware. The new ImageBuilder workflow does not run its size gate or minification. |
| `packages.txt` | Firmware package selection | Root `packages.txt` | PRESERVED | Original distinct package names retained, one per line. Build excludes conflicting default basic-wpad provider. |
| `uci-defaults.sh`, all installers | Preserve settings and generated executable files across sysupgrade | `etc/sysupgrade.conf`, `migration.sh` | CHANGED | Preserve configuration/state, replace firmware-owned code from `/rom`, archive legacy program versions. |
| `README.md`, `.gitattributes` | Documentation and binary signature attributes | Root README/docs and attributes; originals retained | PRESERVED | New documentation describes active architecture while retaining legacy reference information. |

## Dependency And Ownership Notes

- `core.sh` loads central config once per process. Initialization modules run as separate processes; sourced runtime libraries do not perform first-boot work.
- Network, wireless, DHCP and firewall runtime operations remain coordinated by existing mode tools. The initial module order configures their dependencies before commits and profile capture.
- Shared non-VPN route selection is centralized in `core.sh`; defaults no longer repeat across LED, health and DNS tools.
- Samba backend, menu, view and ACL remain one contract. Accounts retain their existing `mxsmb_` naming protocol and protected registry.
- Service starts follow normal OpenWrt boot ordering. Runtime transitions retain reloads and waits; first boot does not restart networking unnecessarily.
- Factory reset exposes baked-in initialization again. A preserved-settings upgrade does not replace the user's mode with router defaults.
- Remaining original compressed scripts and firmware-selector size checks are historical sources only, outside the active `files/` and root build path.

## Verification Limits

Native UCI/ash fixtures validate configuration semantics, rollback, repetition, runtime AP/profile/health operations and legacy migration. ImageBuilder verifies package resolution and image creation. Radio association, WDS interoperability, live DFS timing, USB hardware, LEDs, Samba login and actual bootloader fallback still require tests on an MX4200 V2.