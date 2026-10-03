#!/bin/sh
set -eu
ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
if [ "$#" != 1 ]; then
    echo 'Usage: ./release.sh /path/to/local-ed25519-private-key.pem' >&2
    exit 1
fi
"$ROOT/validate.sh"
ruby "$ROOT/tools/make-release.rb" "$1"