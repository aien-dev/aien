#!/bin/sh
# Named migration build adapter only; runtime logic is src/bots/bots.om.
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
OUT=${1:?usage: build.sh OUTPUT}
: "${OMEGA_OMC:?set OMEGA_OMC to e5b32567 omc}"
: "${OMEGA_MV:?set OMEGA_MV to a checkout containing 55845e70}"
[ "$(sha256sum < "$OMEGA_OMC" | cut -c1-64)" = 2c82480596bbdc50cda9626866209ef662d5834f278f839ff4ce0250c495029f ] || { echo 'BLOCKED: omc pin mismatch' >&2; exit 3; }
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT HUP INT TERM
git -C "$OMEGA_MV" show 55845e70:om/sha256/sha256-om2.om > "$T/sha.om"
[ "$(sha256sum < "$T/sha.om" | cut -c1-64)" = dbf002dd6aa36585632b9d01d98ac3f0bd2fa0f0475082940de53638847994bb ] || { echo 'BLOCKED: SHA unit mismatch' >&2; exit 3; }
sed 's/^export fn /fn /' "$T/sha.om" > "$T/unit.om"
cat "$T/unit.om" "${BOTS_SOURCE:-$HERE/src/bots/bots.om}" > "$T/source.om"
"$OMEGA_OMC" < "$T/source.om" > "$T/bots"
chmod +x "$T/bots"
mv "$T/bots" "$OUT"
sha256sum "$OUT"
