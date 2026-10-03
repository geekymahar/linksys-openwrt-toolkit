# Validation And Build Notes

## Commands

```sh
./validate.sh
./validate.sh --runtime
./build.sh --check
./build.sh
```

These use the existing `openwrt-mx4200v2-builder` container, never an attached router. No command flashes firmware or changes a router's U-Boot environment.

## Linux Prerequisites

The builder container needs GNU AWK for ImageBuilder and Ruby, shfmt, ShellCheck and static BusyBox for validation. These were installed during this refactor. A fresh Ubuntu builder can install them with:

```sh
apt-get update
apt-get install -y gawk ruby shfmt shellcheck busybox-static cmake libjson-c-dev pkg-config git
```

Run package installation inside the builder container with its existing administrative user. The host does not need to install these packages.

Real-UCI fixture tests require a Linux-native `uci` and its libraries. This session built OpenWrt libubox and UCI into `/tmp/router-defaults-native`. To reproduce inside the container:

```sh
git clone --depth 1 https://git.openwrt.org/project/libubox.git /tmp/router-defaults-libubox
cmake -S /tmp/router-defaults-libubox -B /tmp/router-defaults-libubox/build \
    -DBUILD_LUA=OFF -DBUILD_EXAMPLES=OFF -DCMAKE_INSTALL_PREFIX=/tmp/router-defaults-native
cmake --build /tmp/router-defaults-libubox/build -j2
cmake --install /tmp/router-defaults-libubox/build
git clone --depth 1 https://git.openwrt.org/project/uci.git /tmp/router-defaults-uci
cmake -S /tmp/router-defaults-uci -B /tmp/router-defaults-uci/build \
    -DBUILD_LUA=OFF -DCMAKE_PREFIX_PATH=/tmp/router-defaults-native \
    -DCMAKE_INSTALL_PREFIX=/tmp/router-defaults-native
cmake --build /tmp/router-defaults-uci/build -j2
cmake --install /tmp/router-defaults-uci/build
```

Tests use current upstream native UCI for configuration semantics, not the router's ARM binary. The actual firmware includes the package versions resolved by the pinned 25.12.5 builder. Fixtures provide temporary command/service/hardware boundaries in chroots; they do not simulate radio physics or the bootloader.

## Checks

- Every firmware shell asset, including extensionless commands, hotplug and uci-defaults, parses under BusyBox ash and is executable where required.
- ShellCheck runs in sh mode. Only known ash `local` and `read -s` portability warnings, dynamic/absolute source resolution and cross-module unused-variable warnings are excluded.
- Parser inspection rejects arrays, process substitution, double-bracket tests and C-style loops.
- Config-variable declarations, module paths/order, firmware symlinks, JSON, central-config permissions, signed-update allowlist and original package parity are checked.
- Native UCI fixtures cover clean initialization, exact radio/port/default values, repeated execution, preserved WDS, wired AP and management isolation, baseline restore, routed mwan3 policy/restoration, legacy defaults/code migration, WPS-listener retirement, rollback/retry and board rejection.
- ImageBuilder is checked for version 25.12.5, target qualcommax/ipq807x and only the linksys_mx4200v2 profile. Builds run on Docker's case-sensitive filesystem, not the macOS bind mount.
- The built SquashFS was inspected for release identity, module permissions, central-config mode 0600 and stock WPS. Custom partition-button code is absent.

## Observed Build

The pinned ImageBuilder resolved 388 packages from the original selection, generated factory/sysupgrade images, a package manifest, SBOM, profiles metadata and checksums. Its root filesystem was about 36 MiB compressed in the first verified build. The build emitted upstream usteer post-install host-path warnings but completed; these are not router execution failures. Final artifact sizes/checksums are in `artifacts/` after each build.

## On-Device Acceptance

Before deployment, test first boot without Internet, all three radios/DFS, router and AP/WDS management access, routed failover, USB tethering, profile restores, LED colors, Samba account operations, preserved-settings sysupgrade and factory reset on an MX4200 V2. Test automatic recovery only with a known usable alternate image and a documented recovery path. Do not mistake a successful image build or ICMP health probe for full hardware certification.