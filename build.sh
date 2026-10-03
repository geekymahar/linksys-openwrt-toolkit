#!/bin/sh
set -eu
ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
CONTAINER=${BUILDER_CONTAINER:-openwrt-mx4200v2-builder}
IMAGEBUILDER=${IMAGEBUILDER_DIR:-/work/openwrt-imagebuilder-25.12.5-qualcommax-ipq807x.Linux-x86_64}
PROFILE=linksys_mx4200v2

case "${1:-}" in
    --check|'') ;;
    *) echo 'Usage: ./build.sh [--check]' >&2; exit 1 ;;
esac
"$ROOT/validate.sh"
docker exec "$CONTAINER" sh -c '
    test -f "$1/.config" && test -f "$1/.profiles.mk" || exit 1
    case "$1" in */openwrt-imagebuilder-25.12.5-qualcommax-ipq807x.Linux-x86_64) ;; *) echo "Wrong pinned ImageBuilder directory" >&2; exit 1;; esac
    grep -qx "CONFIG_TARGET_qualcommax_ipq807x=y" "$1/.config" || exit 1
    grep -q "^DEVICE_linksys_mx4200v2_SUPPORTED_DEVICES:=linksys,mx4200v2$" "$1/.profiles.mk" || exit 1
    grep -q "releases/25.12.5" "$1/repositories" || exit 1
' sh "$IMAGEBUILDER"
if [ "${1:-}" = --check ]; then
    printf 'Builder verified: OpenWrt 25.12.5 qualcommax/ipq807x profile %s\n' "$PROFILE"
    exit 0
fi

LINUX_BUILDER=${IMAGEBUILDER_CACHE:-/tmp/router-defaults-imagebuilder}/openwrt-imagebuilder-25.12.5-qualcommax-ipq807x.Linux-x86_64
docker exec "$CONTAINER" sh -c '
    set -eu
    if [ ! -f "$2/Makefile" ]; then
        mkdir -p "$(dirname "$2")"
        cp -a "$1" "$2"
    fi
' sh "$IMAGEBUILDER" "$LINUX_BUILDER"
# macOS bind mounts are usually case-insensitive. Build and stage on Docker's
# Linux filesystem; only completed artifacts are copied back to the host.
stage=/tmp/router-defaults-build-$$
trap 'docker exec "$CONTAINER" rm -rf "$stage" >/dev/null 2>&1 || true' EXIT HUP INT TERM
docker exec "$CONTAINER" mkdir -p "$stage"
docker cp "$ROOT/files" "$CONTAINER:$stage/files"
docker cp "$ROOT/packages.txt" "$CONTAINER:$stage/packages.txt"
docker exec "$CONTAINER" sh -c '
    set -eu
    cd "$1"
    packages=$(awk "NF && \$1 !~ /^#/ {print \$1}" "$2/packages.txt" | tr "\n" " ")
    make -j1 clean
    # Full wpad is already selected by the original package list. Remove the
    # conflicting profile default, rather than install two wpad providers.
    make -j1 image PROFILE="linksys_mx4200v2" FILES="$2/files" \
        PACKAGES="$packages -wpad-basic-mbedtls" BIN_DIR="$2/output"
' sh "$LINUX_BUILDER" "$stage"
mkdir -p "$ROOT/artifacts"
docker cp "$CONTAINER:$stage/output/." "$ROOT/artifacts/"
printf 'Firmware artifacts: %s/artifacts/\n' "$ROOT"