#!/bin/sh
set -eu
ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
CONTAINER=${BUILDER_CONTAINER:-openwrt-mx4200v2-builder}

if [ "${ROUTER_DEFAULTS_LINUX:-0}" != 1 ]; then
    command -v docker >/dev/null 2>&1 || { echo 'Docker is required for Linux validation' >&2; exit 1; }
    stage=/tmp/router-defaults-validation-$$
    trap 'docker exec "$CONTAINER" rm -rf "$stage" >/dev/null 2>&1 || true' EXIT HUP INT TERM
    docker exec "$CONTAINER" mkdir -p "$stage"
    for path in files tools mx4200-v2 build.sh validate.sh release.sh packages.txt; do
        docker cp "$ROOT/$path" "$CONTAINER:$stage/$path"
    done
    docker exec -e ROUTER_DEFAULTS_LINUX=1 "$CONTAINER" sh "$stage/validate.sh" "$@"
    exit $?
fi

cd "$ROOT"
for command in ruby busybox shellcheck shfmt; do
    command -v "$command" >/dev/null 2>&1 || { echo "Missing validation tool: $command" >&2; exit 1; }
done
ruby tools/validate.rb
case "${1:-}" in
    --runtime) ruby tools/test-uci.rb ;;
    '') ;;
    *) echo 'Usage: ./validate.sh [--runtime]' >&2; exit 1 ;;
esac