# Linksys MX4200 V2 Embedded OpenWrt Configuration

Readable, offline firmware defaults and runtime tools for **OpenWrt 25.12.5**, target **qualcommax/ipq807x**, ImageBuilder profile **linksys_mx4200v2**. No MX4200 V1 support is included.

The active implementation is the root `files/` tree. ImageBuilder places it directly in SquashFS. First boot configures UCI and enables services; it does not download scripts or recreate programs from heredocs. There is no firmware-selector text-size gate, minification step or help-text limit in this build workflow. Firmware partition capacity still applies.

## Layout

| Path | Responsibility |
| --- | --- |
| `files/etc/router-defaults/config` | Root-only shared defaults, addresses, radio mapping, route metrics, probes, timers and recovery policy. |
| `files/etc/uci-defaults/99-router-defaults` | Small OpenWrt first-boot entrypoint. |
| `files/usr/lib/router-defaults/core.sh` | Config loading, logging, target checks, checked UCI/service operations and shared route lookup. |
| `files/usr/lib/router-defaults/initialize.sh` | Lock, preflight, module ordering, commits, rollback and completion state. |
| `files/usr/lib/router-defaults/{system,network,dhcp,wireless,firewall,vpn,samba,recovery,services}.sh` | Executable initialization modules with a `main` function. |
| `files/usr/lib/router-defaults/{network-functions,wireless-functions,firewall-functions,profiles,input,runtime}.sh` | Sourced runtime libraries; these do not run initialization on import. |
| `files/usr/lib/router-defaults/migration.sh` | Non-destructive transition from the old overlay-installed toolkit. |
| `files/usr/sbin/`, `files/root/` | Existing mode menus, profiles, scans, backhaul/USB/DNS monitors and signed manual updates. |
| `files/etc/init.d/`, `files/etc/hotplug.d/` | Runtime procd services and management-address interface events. |
| `files/usr/bin/mxls`, `files/usr/bin/mxld` | Consolidated revision-3 LED hardware control and sampler/animation. |
| `files/usr/libexec/rpcd/`, `files/usr/share/`, `files/www/` | Samba account RPC, LuCI assets, signed-update allowlist/key and offline help. |
| `packages.txt`, `build.sh`, `validate.sh`, `release.sh` | Package selection, Docker build, validation and manual-release signing. |
| `docs/legacy-inventory.md`, `docs/migration-report.md`, `docs/validation.md` | Original inventory, functionality accounting and test/build evidence. |
| `mx4200-v2/` | Original legacy sources and signed legacy releases retained for comparison. They are not ImageBuilder inputs. |

## Central Configuration

Edit `files/etc/router-defaults/config` before building. Every value comes from the existing project; no credentials were invented. It is trusted shell configuration, stored with mode `0600`. Keep it private when supplying real keys: anything baked into firmware remains recoverable from that firmware, regardless of filesystem permissions.

The existing mapping is **radio1 = 2.4 GHz**, **radio0 = separate 5 GHz client AP**, **radio2 = high-performance 5 GHz / primary backhaul**. Defaults remain `GB`, `HE40`/`HE80`, radio2 channel `100`, router LAN `192.168.40.1/24`, preferred management `172.23.247.1/24`, and the three `LS-MX4200v2` SSIDs. Root has no shared password baked into the image; the first interactive root shell login prompts for a new password and refuses to continue until it is set. This gate applies to interactive SSH/terminal shells, not non-interactive SSH commands or LuCI login. Initial router APs remain open. Repeater setup scans for the upstream AP and displays that AP's actual channel; the radio2 DFS wait has an elapsed/remaining timer and a bounded timeout.

On the live MX4200 V2 with OpenWrt 25.12.5 and country `GB`, the radio advertises HE160 capability, but an AP test using `HE160` on channel 100 failed: hostapd requested a 600-second DFS CAC and the kernel rejected the extension channel as disabled. The reliable default therefore remains HE80. Enabling HE160 needs a regulatory/driver-supported 160 MHz channel plan; changing the country code or forcing disabled channels is not a safe workaround.

Newly entered credentials, saved profiles and selected modes remain protected runtime state under `/etc/mx4200`. They are not copied into a second defaults file. The old `base.conf` and `led.conf` paths are compatibility shims that source the central config.

Changing central defaults on a running router does not automatically overwrite live UCI settings or saved profiles. Use `mx` or LuCI for normal changes, then save a profile. Do not rerun initialization to apply routine configuration changes.

## Initialization Order

1. Check the MX4200 V2 board, generated radio sections, required commands, config values and service files.
2. Migrate known legacy overlay programs and backup rules without replacing current UCI settings.
3. On a clean configuration, snapshot UCI and apply `system → network → dhcp → wireless → firewall → vpn → samba → recovery → services`.
4. Commit the owned UCI packages, save router/baseline profiles, then write completion state.
5. OpenWrt starts enabled services during its normal boot sequence. First boot does not restart the network beneath itself.

Existing mode/provision markers skip destructive default configuration. That branch only performs migration, recovery-policy verification and service enablement. Modules run in separate shell processes to isolate their globals. A serious configuration failure returns non-zero, restores backed-up UCI files and leaves the uci-defaults entrypoint available for a later boot retry. Firmware boot-environment changes are not included in UCI rollback.

## Preserved Runtime Features

Router, routed repeater, true WDS and wired AP workflows remain available through `mx`. Saved profiles, priority-based automatic switching, authenticated backhaul scanning/BSSID rediscovery, WDS association-based switching, routed mwan3 probes, USB primary/backup selection, DNS fallback and management-subnet overlap avoidance are retained. The revision-3 LED behavior and Samba-only account page are embedded, not downloaded.

In routed-repeater mode the physical WAN socket is always a separate DHCP uplink; it is never offered as a LAN bridge port. LAN1-LAN3 remain client LAN ports, and Wi-Fi is the preferred uplink by default. You can still choose wired WAN as the preferred Internet path. When loading an older saved repeater profile that bridged WAN into LAN, the profile loader repairs it to a dedicated WAN interface. Wired-AP mode intentionally continues to bridge all Ethernet ports, including WAN, into the upstream LAN.

VPN packages, firewall zones, ingress rules, forwarding sysctls, Tailscale integration and HTTPS redirection are retained. The firmware does not invent Tailscale authentication, WireGuard peers, OpenVPN connections, Samba shares/accounts, disk mounts or PBR policies.

### Service Startup Policy

The first-boot `services.sh` module enables `mxb`, `mxd`, `mxauto`, `mxroutehealth`, Tailscale and OpenVPN. It enables the LED service when `LED_AUTO_INSTALL='1'`. These services start through normal OpenWrt boot ordering after uci-defaults completes. `mxb` and `mxroutehealth` are mode-aware; `mxroutehealth` configures and enables mwan3 only in routed-repeater mode, then restores its prior configuration when leaving that mode.

Enabling a daemon does not create a VPN connection. Tailscale requires the owner to authenticate it with `tailscale up` or LuCI; after the backend reports running, `mxd` applies the configured exit-node/route flags. OpenVPN's init service is enabled, but no client/server profile is created. WireGuard tools and protocol support are installed, but no peer or interface is created.

ZeroTier is installed but is intentionally not enabled at boot. To opt in, run `/etc/init.d/zerotier enable` and start it with `/etc/init.d/zerotier start`, then join and authorize a real network using its network ID. Samba account management does not start/configure a share; PBR, Tor, UPnP, HTTPS DNS Proxy and other optional services likewise remain unconfigured unless set up separately. Package presence alone does not imply that the toolkit enables a daemon.

Run `mx help` or `mxhelp` for the full offline guide. Legacy command names and SSH aliases remain available.

## Recovery And Reset

Automatic Linksys recovery is **enabled** through `auto_recovery=yes`. `boot_part` and `maxpartialboots` are left unchanged. Use **System > Advanced Reboot** in LuCI for deliberate partition selection. There is no custom WPS multi-press partition action; stock OpenWrt WPS remains intact. A usable alternate firmware image is still required for successful fallback.

A normal factory reset wipes the overlay and exposes the baked-in uci-defaults script again, restoring this image's defaults without Internet access. A normal reboot retains configuration. A settings-preserving upgrade keeps profiles, mode, user configuration and account state; it should not preserve obsolete program copies over newer firmware code. Legacy toolkit programs replaced during migration are archived under `/etc/mx4200/legacy-program-backup` for inspection, but not added to future firmware-program backups.

## Validate And Build

Your existing Docker container is used by default:

```sh
./validate.sh
./validate.sh --runtime
./build.sh --check
./build.sh
```

Validation needs Ruby, BusyBox, ShellCheck and shfmt inside the container. Real-UCI tests additionally need the native UCI tooling described in `docs/validation.md`. The active tree, extensionless scripts, original shell-source syntax, JSON, ash compatibility, permissions, references, config variables, package parity and recovery policy are checked. There is no script-size check.

Defaults: `BUILDER_CONTAINER=openwrt-mx4200v2-builder` and `IMAGEBUILDER_DIR=/work/openwrt-imagebuilder-25.12.5-qualcommax-ipq807x.Linux-x86_64`. The helper checks target/profile/version metadata, copies ImageBuilder into a case-sensitive Linux cache, stages only the firmware overlay under `files/`, and invokes `make image` for only `linksys_mx4200v2`. The validator restricts the overlay to OpenWrt install roots (`etc`, `root`, `usr`, `www`) and rejects README/Markdown files and macOS metadata; project documentation, analysis, tools and build outputs remain outside the firmware. It removes the conflicting default `wpad-basic-mbedtls` provider while retaining the original full `wpad-mbedtls` selection and every original package name.

Completed images, checksums, manifest and SBOM are copied to root `artifacts/`. Both `*-squashfs-factory.bin` and `*-squashfs-sysupgrade.bin` are generated. Select the correct image for your installation method; these helpers never flash or reboot a router. The Linux cache defaults to `/tmp/router-defaults-imagebuilder` inside Docker; set `IMAGEBUILDER_CACHE` to another case-sensitive container path to retain it across container recreation.

## Signed Manual Updates

`mx update` remains an explicit authenticated release download. First boot has no GitHub dependency. Sign a release using the existing local Ed25519 key:

```sh
./release.sh "$HOME/.config/mx4200-v2/release-key.pem"
```

Publish root `files/` and `mx4200-v2/embedded-release/manifest.txt` plus its signature together. Downloads use the original repository URL and verify both signature and individual hashes. Updates are restricted to the baked-in file allowlist, staged before installation and backed up for rollback. Central config, account state and saved profiles are not release payloads. A new file/dependency outside that allowlist requires a firmware rebuild. Private signing keys never belong in the repository or image.

The legacy manifest/provisioner remains untouched for already-flashed legacy images. Do not run the legacy importer or installers as part of the new build. The one-time Ruby extraction/readability utilities under `tools/` document the migration; maintained source files are now the source of truth.

## Adding A Module

Create a readable ash module under `files/usr/lib/router-defaults/`, source `core.sh`, implement `main`, and return non-zero on serious failures. Assign one owner for each UCI setting, add user-editable defaults only to central config, insert the module into the explicit initializer order, and extend the validator and native-UCI tests. Put persistent programs and service/assets directly in `files/`. Add only user state to preservation rules. Regenerate the update allowlist when applicable, validate, rebuild and update the migration documentation.