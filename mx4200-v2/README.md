# Linksys MX4200 V2 / P2 firmware configuration

This directory defines the MX4200 V2/P2 OpenWrt firmware setup. The two configuration inputs are [`uci-defaults.sh`](uci-defaults.sh) and [`packages.txt`](packages.txt). This document describes what the current files actually configure; the shell files are the source of truth if behavior changes.

The firmware builder runs `uci-defaults.sh` on a clean first boot. It writes local scripts, configures OpenWrt through UCI, and saves an initial router profile. The offline core works even when GitHub is unavailable. During that same first boot only, a verified release may replace the pristine baseline and install the automatic saved-mode switcher, advanced LED controller, LuCI Samba user page, and MX dashboard. Later normal boots never fetch modules automatically. A factory reset erases the overlay and opens a new first-boot provisioning opportunity; a reboot does not.

## Repository and installed files

| Repository path | Role |
| --- | --- |
| `uci-defaults.sh` | First-boot configuration and all generated core scripts. Firmware selector limit: **40,960 bytes**. |
| `packages.txt` | Space-separated firmware package selection. |
| `modules/provision/install.sh` and `.sha256` | Firmware-pinned first-boot release verifier and manual module installer. |
| `release/manifest.txt`, `.sig`, and `build.py` | Signed release index and local release preparation tool. |
| `modules/auto/install.sh` and `.sha256` | Optional saved-mode switching installer. |
| `modules/samba/install.sh` and `.sha256` | Optional LuCI Samba account manager installer. |
| `modules/ui/install.sh` and `.sha256` | Optional LuCI MX dashboard and manager installer. |
| `modules/led/rev3/install.sh` and `.sha256` | **Selected** advanced LED installer. |
| `modules/led/rev2/` | Earlier LED revision; present but not selected by the bootstrap. |
| `modules/led/` | Earlier root-level LED installer; present but not selected. |

The first-boot script creates these notable router paths:

| Router path | Purpose |
| --- | --- |
| `/etc/mx4200/base.conf` | Defaults shared by the generated scripts. |
| `/etc/mx4200/mode` | Current mode: `router`, `repeater`, `wds`, or `ap`. |
| `/etc/mx4200/profiles/<mode>/` | Saved copies of the `network`, `wireless`, `dhcp`, `firewall`, and `system` UCI files. |
| `/usr/lib/mxc` | Common functions for UCI edits, profiles, radio setup, scanning, and security detection. |
| `/usr/sbin/mxm`, `/usr/bin/mx` | Interactive manager, status, and help. |
| `/root/mxr`, `/root/mxa` | Repeater/WDS and wired-AP setup dialogs. |
| `/usr/sbin/mxb`, `/etc/init.d/mxb` | Local backhaul monitor and 5 GHz/2.4 GHz selection. |
| `/usr/sbin/mxu` | USB-tether detection and configuration. |
| `/usr/sbin/mxw`, `/root/mxwds` | WDS health check and diagnostic output. |
| `/usr/sbin/mxd`, `/etc/init.d/mxd` | DNS fallback, Tailscale settings, and management-subnet overlap check. |
| `/etc/hotplug.d/iface/95-mxmgmt` | Rechecks the management address when upstream LAN DHCP comes up or changes. |
| `/usr/sbin/mxfirstboot`, `/etc/init.d/mxprovision` | One-shot background release check, started on first boot and never enabled for later boots. |
| `/usr/sbin/mxmod` | Verified release handoff and explicitly requested module installs. No recurring downloader. |
| `/etc/profile.d/mx` | SSH aliases and short login guide. |

The selected LED installer adds `/etc/mx4200/led.conf`, `/usr/bin/mxls`, `/usr/bin/mxld`, and `/etc/init.d/mxl`. The automatic-mode installer adds `/usr/sbin/mxauto` and `/etc/init.d/mxauto`. The Samba installer adds a LuCI page, a narrowly scoped rpcd method, and `/etc/mx4200/samba-users/` for its account registry. The MX manager installer adds a separate LuCI page and narrowly scoped rpcd method. Generated files are listed in `/etc/sysupgrade.conf`; each optional installer adds its own files there after installation.

## Default settings and radio mapping

| Setting | Current value |
| --- | --- |
| Device scope | Linksys MX4200 V2/P2 |
| Country | `GB` |
| Hostname | `OpenWrt-LS-MX4200v2` |
| Router/routed-repeater LAN | `192.168.40.1/24` |
| LAN DHCP pool | Start `100`, limit `150`, lease `12h` (normally `.100`–`.249`) |
| Preferred isolated management IP | `172.23.247.1/24` |
| Management DHCP pool | Start `100`, limit `100` (normally `.100`–`.199`) |
| DNS fallback servers | `1.1.1.1`, `1.0.0.1` |
| DNS test name | `openwrt.org` |

The script maps **`radio1` to 2.4 GHz**, **`radio0` to 5 GHz 2×2**, and **`radio2` to 5 GHz 4×4**. It enables all three radios with `HE40` on 2.4 GHz and `HE80` on each 5 GHz radio. In repeater modes, `radio2` is the primary upstream backhaul; `radio1` can be its 2.4 GHz backup. `radio0` supplies a separate 5 GHz client AP.

On first boot in router mode, the script creates three **open**, passwordless APs: `LS-MX4200v2` on `radio1`, `LS-MX4200v2-5GHz` on `radio0`, and `LS-MX4200v2-Max` on `radio2`. It does not set a root password. Wired-AP client Wi-Fi uses WPA2/WPA3 mixed (`sae-mixed`). In either repeater mode, the two client APs use the selected primary upstream's security type; open or OWE upstream means no client AP password. WDS Management Wi-Fi remains separately password-protected with `sae-mixed`.

## Operating modes

| Mode | Upstream and addressing | Ethernet ports | DHCP served by MX4200 | Client Wi-Fi |
| --- | --- | --- | --- | --- |
| **Router** (`router`) | Physical `wan` gets IPv4 by DHCP. `br-lan` is `192.168.40.1/24`; normal routed/NAT firewall setup. | `lan1`–`lan3` are `br-lan`; `wan` is separate. | On `br-lan`. | Three initially open SSIDs, one per radio. |
| **Routed repeater** (`repeater`) | `radio2` STA uses DHCP on `wwanp`; optional `radio1` STA uses DHCP on `wwanb`. Client LAN stays on the saved router LAN subnet. Optional wired `wan` also uses DHCP. | `lan1`–`lan3` are LAN. During setup, the user chooses whether the physical `wan` socket joins LAN or remains a wired WAN uplink. | On `br-lan`. | `${upstream SSID}-RPT-5G` on `radio0` and `${upstream SSID}-RPT-2G` on `radio1`, with the setup password. |
| **True WDS repeater** (`wds`) | Upstream 4-address Wi-Fi is bridged into `br-lan`; `br-lan` gets DHCP from upstream. Separate `wan` DHCP is configured at a lower route priority. | `lan2`–`lan3` join the upstream bridge. `lan1` belongs to isolated `br-mgmt`; `wan` stays a separate WAN interface. | **Off** on `br-lan`; **on** for `br-mgmt`. | Repeater SSIDs on `radio0`/`radio1`, plus a password-protected `${upstream SSID}-Management` AP on `radio1`. |
| **Wired AP** (`ap`) | Any Ethernet socket can connect to the upstream LAN. All four sockets and client Wi-Fi are bridged; `br-lan` gets DHCP from the upstream router. | `lan1`–`lan3` **and physical `wan`** join `br-lan`. | **Off** on `br-lan`; **on** for separate `br-mgmt`. | Chosen client SSID on all three radios, plus password-protected `${SSID}-Management` on `radio1`. |

WDS requires the **upstream AP to support compatible 4-address/WDS bridging**. If it does not, use routed repeater mode. In AP and WDS modes, the upstream router supplies the ordinary client-network addressing; the MX4200 does not assume an upstream gateway or subnet. In AP mode, the Management SSID is a separate local subnet and its firewall zone does not forward to the upstream network. In WDS mode, the management zone has an explicit forwarding path to the `wan` zone, which includes the upstream bridge.

Routed repeater setup asks two extra questions. Choosing **WAN as LAN** bridges the physical socket into `br-lan` and disables its routed WAN protocol. Choosing **wired WAN** leaves it separate and then asks whether wired WAN or Wi-Fi has priority. The configured IPv4 route metrics are:

| Routed-repeater uplink | Metric |
| --- | ---: |
| 5 GHz `wwanp` | 5 |
| 2.4 GHz `wwanb` | 15 |
| Wired WAN, when preferred | 3 |
| Wired WAN, when Wi-Fi is preferred | 20 |

Lower metrics are preferred. The metrics choose among available routes; they are **not a continuous Internet-health check** for routed repeater mode. An associated 5 GHz STA with a broken upstream Internet path may retain the preferred route until netifd withdraws it or another mode is selected.

### Management address and overlap avoidance

`br-mgmt` has a separate `/24` address in AP and WDS modes. Its preferred address is `172.23.247.1`; if that subnet overlaps an active route, the local checker tries `172.29.251.1`, `10.253.247.1`, then `192.168.247.1`. The checker examines IPv4 routes other than `br-mgmt` and also the current `br-lan` IPv4 lease, so it can detect broader upstream prefixes and an overlap even if a connected route was not installed. It runs on LAN `ifup`/`ifupdate` and once per minute in `mxd`.

When the selected address changes, the script updates UCI, restarts `mgmt`, restarts dnsmasq, and logs the selected IP under `mxmgmt`. It returns to `172.23.247.1` when that address is safe again. `mxstatus` shows the current address. A connected management client may need to reconnect its Wi-Fi or renew DHCP after a change. With no upstream IPv4 lease, the checker leaves the current management address alone. If **all four candidates overlap**, it logs a warning and keeps the current address; no fixed list can guarantee a conflict-free choice for every possible upstream/VPN layout.

This checker changes **management addressing only**. Router and routed-repeater LAN still default to `192.168.40.0/24`; a routed repeater can have a separate LAN/upstream overlap if its upstream also uses that subnet.

## Repeater setup and backhaul behavior

Run `mxrepeater` (or choose Repeater in `mx`) and select WDS or routed mode. The setup prompts explain WAN socket use, uplink priority, security selection, and saved-profile choices. For password-based security, the upstream Wi-Fi password is separate from the MX4200 client Wi-Fi password; new client and WDS Management passwords must be 8–63 characters. Open and OWE upstreams skip the client password prompt. The scanner tries four passes on the selected radio. It uses `iwinfo`, falls back to the active radio interface, and can temporarily create a managed scan interface if necessary. It filters BSSIDs belonging to the MX4200 itself, groups scan results by SSID, and presents channel, signal, advertised encryption, and BSSID. For `radio2` it waits for a pending radio/DFS state before scanning, up to the configured wait. A 2.4 GHz backup can be chosen separately or can reuse the 5 GHz SSID/password after a matching 2.4 GHz scan.

The scan text is mapped to OpenWrt encryption names (`none`, `owe`, `sae`, `sae-mixed`, `psk2`, `psk-mixed`, or legacy `psk`). `iwinfo` labels a WPA1 advertisement `WPA PSK` and WPA2 `WPA2 PSK`; CCMP alone does not identify the version. When a scan reports `WPA PSK`, setup shows the BSSID and requires an explicit WPA1/WPA2 choice in case the router's configured setting conflicts with the scan. Upstream addressing always comes from DHCP; the scan records the selected BSSID and channel rather than assuming a gateway IP.

`mxb` runs locally once a second in repeater/WDS modes. About every 30 seconds, it can rescan a disconnected configured STA and update its BSSID/channel if the same SSID appears elsewhere. This provides dynamic upstream BSSID rediscovery without connecting to one of the router's own BSSIDs. Manual `mx` Backhaul choices can enable auto, primary only, or backup only.

In **WDS**, `mxb` keeps only the selected STA enslaved to `br-lan`. If the primary association disappears and the backup is associated, it switches to backup and requests DHCP renewal. When the primary association stays present for about 30 seconds, it switches back. In **routed repeater**, both configured DHCP STA interfaces can exist and netifd uses the route metrics above; `mxb` mainly monitors association and performs BSSID rediscovery. A configured 2.4 GHz path can carry traffic while `radio2` is waiting on DFS, but this depends on the backup being associated and having a working route. The initial interactive 5 GHz scan itself waits for the radio before the backup-selection prompt.

`mxw` supplies the WDS diagnostic result: `RED` if there is no connected upstream STA, `ORANGE` if 4-address bridging, DHCP/default route, or Internet ping fails, `YELLOW` if the upstream DNS check fails, and `GREEN` if all checks pass. `mxwds` prints the upstream bridge address, route, DNS, and that health result.

## Saved profiles and automatic mode switching

Each new setup saves the current mode's five UCI configuration files. First boot also creates `router` and `router-baseline`. The manager can restore the previous saved profile or the first-boot router baseline. Reloading a saved AP/WDS profile resets its management address to the preferred value; the overlap checker can then select a fallback for the current upstream. A profile reload replaces the whole saved UCI files, so manual changes made after its last save are not guaranteed to survive a later restore. These snapshots include Wi-Fi keys; the script gives the profile directories `0700` and saved files `0600` permissions.

When saving a mode, the dialog asks for an **auto priority** from `1` (highest) to `9`; `0` disables that mode in automatic switching. Priorities are stored in `/etc/mx4200/auto-priority`. The `mxauto` service is supplied by `modules/auto`, so it becomes available only after that optional installer has been fetched once. Manual profile restore and the within-mode backhaul behavior remain local without it.

Once installed, `mxauto` polls every 10 seconds. It works only when at least two saved, enabled modes exist and the current mode has a priority. With a healthy current route, it checks for a higher-priority mode no more often than every 300 seconds. After three failed health checks, it tries other enabled profiles in priority order. It tests the selected non-VPN default-route device with pings to `1.1.1.1` or `8.8.8.8`; AP/WDS additionally require a DHCP address and default route on `br-lan`. Before trying router mode it requires WAN carrier; before trying AP it requires carrier on any Ethernet port. WDS and routed repeater are treated as possible without a carrier precheck.

A trial reloads the candidate profile, waits 12 seconds, and makes up to three health checks separated by 5 seconds. A failed candidate receives a 15-minute cooldown and the previous profile is restored. Manual mode/priority actions pause automatic changes for 10 minutes. Trials can interrupt clients, and ping reachability is a proxy for connectivity rather than proof that every application works. Use `mxauto status` to view the ordered saved modes, or `mxauto once` to run a single decision step.

## USB tethering

`mxusb` scans `/sys/class/net` for a network interface whose device path contains `/usb`; the firmware includes several common USB Ethernet, NCM, RNDIS, and iPhone tether drivers. Choosing **Primary** or **Backup** creates a DHCP `usbwan` interface, adds it to the WAN firewall zone, and restarts network/firewall. Primary uses metric `3` and moves wired WAN to `20` and, where present, the 5 GHz repeater path to `10`; backup uses metric `30`. Turning USB off removes `usbwan` and restores the mode's ordinary route metrics.

The last selected USB role is saved in `/etc/mx4200/usb.conf`, and **Previous** in the menu reapplies it. The current code does **not** automatically reapply that role at every boot or when a phone is newly plugged in. Switching to a new repeater/WDS setup turns an active USB configuration off before changing modes. In AP or WDS bridge modes, a USB route for the MX4200 itself does not automatically move bridged client traffic onto USB.

## DNS, firewall, and VPN preparation

`mxd` checks once a minute. When it can ping `1.1.1.1`, it probes nameservers learned from upstream using `dig` for `openwrt.org`. If those fail, it points dnsmasq at `1.1.1.1` and `1.0.0.1` when no explicit dnsmasq server is configured or when it already owns the fallback. When learned DNS works again, it removes the fallback it owns. It does not rewrite an upstream subnet or gateway. The check depends on public-IP reachability, so restrictive or captive upstream networks can affect its diagnosis. Changing dnsmasq's server list while this fallback is active needs care because the recovery path clears that list.

The router/routed-repeater firewall configures LAN-to-WAN forwarding and masquerading. Routed Wi-Fi DHCP interfaces get a separate masquerading `uplink` zone. The management network has its own zone. The script adds WAN/uplink rules for router management ports `22`, `80`, and `443` with source addresses restricted to `10/8`, `172.16/12`, `192.168/16`, or `100.64/10`. These are firewall-source filters; they are not upstream gateway defaults. Other existing firewall rules, if present, must be reviewed separately.

The image includes Tailscale, WireGuard, and OpenVPN tools and LuCI apps. First boot creates VPN/Tailscale firewall zones, enables IPv4/IPv6 forwarding, opens WAN TCP/UDP ports `1194`, `51820`, and `41641`, sets Tailscale's firewall mode to `nftables`, and starts Tailscale/OpenVPN init services when present. Once Tailscale reports `Running`, `mxd` tries to advertise this router as an exit node and accept routes, once per boot. The script does **not** create a Tailscale login, WireGuard peer/key, or OpenVPN client/server configuration; those still need their normal setup.

## One-time release provisioning

`uci-defaults.sh` configures the fully functional offline core first. On a clean first boot it launches a one-shot background worker, then lets boot continue; module downloads do not hold up DHCP, Wi-Fi, firewall, or the `mx` menu. The worker creates an atomic `/etc/mx4200/provision-attempted` marker and waits up to one minute for wired WAN DHCP. Immediately before fetching, it checks that the router is still on its untouched baseline. Its init service is started once and never enabled for later boots. Connect the WAN socket to an Internet-connected Ethernet network **before powering on after a flash or factory reset** if you want automatic provisioning. Wi-Fi repeater credentials have not been entered yet at this point. The worker fetches `modules/provision/install.sh` using `uclient-fetch` or `curl`; its expected SHA-256 is embedded in the firmware. Git is not installed. The provisioner then downloads `release/manifest.txt` and its Ed25519 signature, verifies them with its embedded public key and `openssl-util`, and checks the hash and shell syntax of the selected release files. The URL follows the actual `main/mx4200-v2/` directory:

```text
https://raw.githubusercontent.com/geekymahar/linksys-openwrt-toolkit/main/mx4200-v2
```

For the automatic first-boot action, the signed manifest covers `uci-defaults.sh` plus the `auto`, `samba`, `ui`, and selected `led/rev3` installers. The worker and provisioner refuse the automatic update once an MX setup has started, and the provisioner checks that the five live UCI files still match the untouched router baseline before applying the downloaded core. It backs up that pristine core and restores it if the downloaded core reports failure. It runs the new core with a one-pass flag, then installs the optional modules locally. A changed mode or UCI file cancels the automatic release instead of overwriting a user's setup. Failure to reach GitHub or verify a release leaves the already installed offline core usable. The automatic attempt is not retried on later boots. `mx update` (menu option 9) asks which signed optional module to reinstall; it does not rerun the core or reset the active mode and saved profiles. `mxmod once`, `auto-once`, `samba-once`, and `ui-once` remain direct **manual** install actions for older firmware that lacks the new menu. A module update may restart its own service; the LED installer replaces its LED configuration with its defaults.

`/etc/mx4200/provisioned` marks an installed configuration. A preserved-settings sysupgrade sees that marker, or the existing mode file from earlier MX firmware, and exits without resetting network settings. It also disables the older recurring `mxmod` service if present. A factory reset removes the marker and saved settings, so first-boot provisioning can run again against the same flashed image. Resetting does not install packages absent from that image; package/kernel changes still require a new build. A normal reboot keeps the installed files and never checks GitHub. If power is lost before the one-shot worker finishes, the attempt marker still prevents a retry on the next boot.

The public signing key is frozen into `modules/provision/install.sh`, whose SHA-256 is frozen into the firmware. To publish a new release, edit the core/modules, then run `python3 release/build.py --key /Users/toukanlabs/.config/mx4200-v2/release-key.pem` from this directory. The tool refreshes module `.sha256` files, updates the firmware's provisioner hash, validates shell syntax and the 40,960-byte limit, creates the manifest, and signs it. **Keep the private key out of GitHub**; it exists only at that local path. Do not change the provisioner file at the `main` URL without rebuilding firmware already pinned to its old hash. Publish the manifest, signature, and matching scripts in one commit. A router must be factory-reset to automatically take that release; manual module installs can fetch a signed module later without changing its network setup.

### LuCI MX manager and browser terminal

On first boot, normal LuCI is available without the UI module. If the one-time signed release handoff succeeds, the dashboard installs locally; no GitHub connection is needed on later boots. If the handoff is unavailable, normal LuCI remains available and the dashboard can be installed explicitly with `mxmod ui-once` once Internet is available. After installation, sign out of LuCI and back in. **MX Dashboard** becomes the first page after login. In **Advanced settings**, **Open in LuCI** opens the ordinary LuCI status page in a new tab; its menus and settings remain available. Both views read and change the same live OpenWrt configuration. Dashboard changes appear in regular LuCI after its page is refreshed, and changes made in regular LuCI appear in the dashboard after its refresh. The dashboard follows the MX router's own capabilities rather than implementing GL.iNet-only services.

The sidebar shows an overview, native setup, uplink status with IP/DNS/BSSID/signal/byte counters, saved-mode priorities, Wi-Fi SSIDs and backhaul, local DHCP clients, VPN status, LED controls, system and kernel logs, device health, and MX actions. The Internet probe checks two configured IPs; a failed ping is not proof that all Internet traffic is down. The Clients page lists leases issued by this router, so clients using upstream DHCP in wired AP or WDS mode may not appear. The Internet page presents the existing priority-based failover/failback; it does not claim to load-balance traffic or invent a second Ethernet WAN. The Wireless and Setup pages scan radio2 (5 GHz) and radio1 (2.4 GHz) through the offline core scanner, which excludes the MX4200's own BSSIDs. Scanning may briefly affect an active backhaul.

**Set up Internet** has MX-branded forms for router, routed repeater, WDS repeater, and wired AP. Router mode keeps the default LAN at `192.168.40.1/24` and gets upstream addressing by WAN DHCP. Routed repeater lets the WAN socket serve clients as LAN or act as a wired DHCP uplink, with wired/Wi-Fi preference. The form selects a scanned radio2 upstream and optional radio1 backup, asks explicitly whether an ambiguous `WPA PSK` scan is WPA1 or WPA2, uses the upstream security for repeater client APs, and takes separate client and management passwords. WDS and wired AP use upstream DHCP for ordinary clients and keep isolated Management Wi-Fi; the local management address can change if its subnet overlaps the upstream. USB tethering remains available from Controls. Each form saves a mode profile and priority; setup runs in the background, with a copy of the previous configuration restored if a configuration command or service restart fails. Wrong upstream credentials or incompatible WDS can still leave the newly applied mode without Internet; the Management SSID and offline `mx` menu provide recovery access. The form does not assume an upstream IP range.

**Services → MX4200 Manager** remains available for the full action list in regular LuCI. It shows `mxstatus`, saved profiles, and automatic priorities. It can restore router, baseline, routed repeater, WDS, or wired-AP profiles; save the current profile; choose USB tether and Wi-Fi backhaul roles; run WDS diagnostics or one automatic-mode decision; and inspect or control the advanced LED module. The web setup calls only the MX setup backend; it does not grant generic shell execution. Profile, setup, USB, backhaul, and automatic-mode actions can interrupt connectivity, so the pages ask before starting them.

The firmware already includes `luci-app-ttyd` for **Services → Terminal**. The MX page links to it. Set a root password before using the terminal, log in there normally, and run `mx` to use the full interactive setup, including new Wi-Fi scans, upstream passwords, WAN-port choice, WDS/routed repeater setup, and wired-AP setup. These core scripts still work offline even when the optional UI is absent. The web setup reuses the core helpers but remains a separate interface, so both paths should be tested on actual hardware after changing their shared mode behavior. A new page may need a LuCI sign-out/sign-in to appear after automatic installation.

### LuCI Samba users

After the optional Samba module is installed, sign out of LuCI and back in to refresh its menu, then open **Services → Samba Users**. Create a name such as `alice`; the page creates the Samba-only account `mxsmb_alice`. Passwords must be 12–127 characters. The page can change a Samba password, enable or disable an account, and remove an account. It creates the underlying non-login Unix account and Samba credentials together, so no shell access is granted. Passwords are sent through LuCI's authenticated RPC channel to `smbpasswd` on standard input; they are not stored in the module registry or passed as command-line arguments. Use HTTPS for the LuCI session.

To restrict a share, open **Services → Network Shares**, turn guest access off, and put the full name (for example `mxsmb_alice`) in **Allowed users** for that share. Ensure the share's filesystem permissions allow GID `100` (`users`) to access the files. The page manages only accounts it created with the `mxsmb_` prefix; it cannot alter `root` or other system accounts. The account registry and module files are preserved through `/etc/sysupgrade.conf`. The page does not create a share or change guest/share settings automatically.

## Advanced LED behavior (selected revision 3)

`modules/led/rev3/install.sh` installs `mxls`, the low-level color setter, and `mxld`, the state sampler/animator. `mxls` tries RGB LED sysfs entries and can use an ST1202 controller over I²C when detected. `mxls detect` reports what it found. The LED module does not control routing; a hardware probe failure does not stop networking. The root-level and `rev2` installers are older alternatives in the repository and are **not** selected by the current bootstrap.

The installed `/etc/mx4200/led.conf` sets `LED_INTERVAL='1'`: the network/traffic sampler normally updates every **one second**. The LED animation itself has shorter timing steps. Traffic level uses total bytes transferred on the chosen uplink per sample: under `4096` bytes is idle, under `32768` light, under `262144` medium, and higher traffic is the fastest animation level.

The repository's LED installers represent successive behavior, not three modules that run together:

| Installer | Current role and distinguishing behavior |
| --- | --- |
| `modules/led/install.sh` | Earlier implementation. Uses the basic online/DNS/no-uplink indications and VPN traffic overlays; no DFS indication or backup/USB cue. |
| `modules/led/rev2/install.sh` | Adds route-aware uplink selection and teal backup/white USB cues. It does not implement the revision-3 `link_down` or DFS states. |
| `modules/led/rev3/install.sh` | Selected by `mxmod`. Adds AP management boot readiness, separates broken backhaul from Internet loss, and adds purple DFS wait. |

| Revision-3 indication | Meaning in the current code |
| --- | --- |
| Boot color sequence, then dim green | Waiting briefly for the local management/LAN address, dnsmasq, and web service; then normal LED control starts. |
| Breathing green | Uplink classified as online. Breathing speed rises with measured uplink traffic. |
| Alternating red beat, blue beat | `link_down`: repeater backhaul association/4-address bridge is broken. This is for a broken link, not merely failed Internet. |
| Red beat only | `no_wan` (no usable default-route device) **or** `no_internet` (connectivity checks failed). The state file distinguishes them. |
| Breathing yellow | `dns_fail`: IP connectivity works but DNS test fails. |
| Purple double blink | `dfs_wait`: radio2's AP interface reports a DFS wait. This indication takes precedence even if backup Internet is working. |
| Brief teal cue after the green cycle | Current routed uplink/backhaul is classified as the 2.4 GHz backup. |
| Brief white cue after the green cycle | USB tether is the selected uplink. |
| Breathing blue after green | Tailscale interface carried traffic during the sample. |
| Breathing purple after green | A WireGuard interface with a recorded handshake carried traffic. Its breathing pattern differs from the DFS double blink. |
| Breathing orange after green | OpenVPN has a process/tun-or-tap interface and carried traffic. |

The online sequence can show several overlays in order: green, optional teal/white uplink cue, then blue (Tailscale), purple (WireGuard), and orange (OpenVPN) when each was active. The state file `/tmp/mx4200-led-state` records `STATE`, traffic `LEVEL`, VPN activity flags, and selected `UPLINK`. `mxstatus` prints that file when present. LED states use short pings and DNS lookups; blocked probe destinations, captive portals, or an upstream that answers DNS while both ping targets fail can produce a misleading color. The LED is a diagnostic indicator, not proof of application-level connectivity.

The DFS indication specifically looks for `DFS` status on a **radio2 hostapd AP interface**. Router mode creates such an AP; repeater modes normally use radio2 as a STA, so a repeater's DFS wait may not produce this purple indication even while the backup link works.

The LED menu can detect hardware, return to automatic control, show current state, or temporarily force red, green, blue, purple, orange, yellow, teal, white, or off. A forced color stops `mxl` until automatic control is restarted.

For direct hardware diagnosis after installation, `/usr/bin/mxls detect` reports the sysfs/I²C backend. `/usr/bin/mxls rgb R G B` accepts three 0–255 channel values; named commands include `red`, `green`, `blue`, `purple`, `orange`, `yellow`, `teal`, `white`, dim variants, and `off`. Direct `mxls` commands set the LED immediately, while the running `mxl` service may overwrite that color on its next animation step.

## Packages and offline dependencies

`packages.txt` preinstalls network, Wi-Fi, firewall, USB, VPN, management, and LED hardware support in the firmware. Relevant examples are `wpad-mbedtls` for the full WPA/WPA3/STA/WDS feature set; `ip-full`, `netifd`, `dnsmasq`, `firewall4`, `iw`, `iwinfo`, and `jsonfilter` for the core; USB network drivers; `tailscale`, `wireguard-tools`, `openvpn-openssl`, and `bind-dig`; `uclient-fetch` and `curl` for verified optional installers; `openssl-util` for Ed25519 release verification; and I²C/LED drivers and `i2c-tools` for the advanced LED module. `wpad-basic-mbedtls` and Git are not selected.

The package list also contains optional OpenWrt/LuCI tools such as SQM, DDNS, adblock, Samba, traffic statistics, mwan3, travelmate, and relayd. `shadow-useradd` and `shadow-userdel` support the optional Samba account page; `luci-app-ttyd` supplies the browser terminal. Package presence does not mean the core script configures Samba shares. The LED dependencies can be present before the LED software is downloaded.

## Linksys dual-image recovery and persistence

If `fw_printenv`/`fw_setenv` are available and the existing boot environment exposes both `auto_recovery` and `maxpartialboots`, first boot sets `auto_recovery=yes` and `maxpartialboots=3`. This prepares the Linksys recovery behavior; it does not force a partition switch or prove that both images are healthy. `luci-app-advanced-reboot` is included in the package list.

Profiles, module files, local helper scripts, and configuration paths are added to `/etc/sysupgrade.conf`. Whether an individual firmware upgrade preserves them also depends on the chosen sysupgrade settings. On a clean flash or factory reset, the first-boot script recreates the initial router configuration and its baseline profile. An upgrade that preserves settings skips this destructive setup.

## SSH command reference

| Command | Action |
| --- | --- |
| `mx` | Interactive mode/setup menu. |
| `mx update` or menu option `9` | Select a signed UI, LED, automatic switching, or Samba module to reinstall from GitHub without a factory reset. Internet is required. |
| `mxhelp` | Short command guide. |
| `mxstatus` | Current mode, route/gateway, addresses, WDS health, USB, and LED status. |
| `mxrouter` | Restore previous router profile, first-boot baseline, or save current router profile. |
| `mxrepeater` | Choose WDS or routed repeater and use a saved or new scan-based profile. |
| `mxap` | Restore/configure wired AP or change the AP Management SSID password. |
| `mxusb` | Detect USB tether, set primary/backup, use previous role, or turn it off. |
| `mxled` | Install optional LED module now or control it after installation. |
| `mxauto status` | Show enabled saved-mode priorities, if the optional auto module is installed. |
| `/usr/sbin/mxb auto` (or `primary`, `backup`) | Set within-mode backhaul selection. The interactive menu exposes this too. |
| `/root/mxwds` | Detailed WDS address/route/DNS/health check. |
| `/usr/sbin/mxmod status` | Check LED module installation. `auto-status` checks saved-mode module installation. |
| `/usr/sbin/mxmod samba-status` | Check LuCI Samba user page installation. `samba-once` attempts installation immediately. |
| `/usr/sbin/mxmod ui-status` | Check LuCI MX dashboard/manager installation. `ui-once` attempts installation immediately. |

The short names except `mx` are shell aliases loaded through `/etc/profile.d/mx` in an interactive SSH session. Their underlying paths, such as `/usr/sbin/mxm status`, work directly when aliases are not loaded.

## Scope of validation

This documentation is based on the current checked-in MX4200 V2/P2 sources. The release signature, hashes, shell syntax, package presence, and first-boot guards can be checked locally. The live first-boot network timing, WDS interoperability, DFS timing, WAN/USB failover, LED colors, and recovery behavior still require tests on an MX4200 V2/P2.
