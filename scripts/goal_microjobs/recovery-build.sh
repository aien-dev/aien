#!/bin/sh
# Migration-only build adapter, aien-dev/aien#22; runtime decisions are Omega.
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
OUT=${1:?output binary}
SOURCE=${2:-$HERE/src/goal_microjobs/recovery.om}
[ "$(sha256sum < "${OMEGA_OMC:?pinned omc}" | cut -c1-64)" = 2c82480596bbdc50cda9626866209ef662d5834f278f839ff4ce0250c495029f ] || { echo 'BLOCKED: omc hash mismatch' >&2; exit 3; }
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT HUP INT TERM
"$OMEGA_OMC" < "$SOURCE" > "$T/recovery"
chmod +x "$T/recovery"
mv "$T/recovery" "$OUT"
sha256sum "$OUT"
