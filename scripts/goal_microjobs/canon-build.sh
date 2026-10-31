#!/bin/sh
# Migration-only build adapter, aien-dev/aien#22: no runtime protocol logic.
# OMEGA_OMC: e5b32567 omc; OMEGA_MV: checkout holding Omega 55845e70.
# $1: output binary. No download, substitution, or stale output on refusal.
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
OUT=${1:-./canon}
blocked() { echo "BLOCKED: $*" >&2; exit 3; }
[ -x "${OMEGA_OMC:-}" ] || blocked 'set OMEGA_OMC to pinned omc'
[ -n "${OMEGA_MV:-}" ] || blocked 'set OMEGA_MV to SHA unit checkout'
[ "$(sha256sum < "$OMEGA_OMC" | cut -c1-64)" = 2c82480596bbdc50cda9626866209ef662d5834f278f839ff4ce0250c495029f ] || blocked 'omc hash mismatch'
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT HUP INT TERM
git -C "$OMEGA_MV" show 55845e70:om/sha256/sha256-om2.om > "$T/sha.om" || blocked 'missing SHA unit revision'
[ "$(sha256sum < "$T/sha.om" | cut -c1-64)" = dbf002dd6aa36585632b9d01d98ac3f0bd2fa0f0475082940de53638847994bb ] || blocked 'SHA unit hash mismatch'
# Existing protocols jobpath/build.sh convention: program-mode export removal only.
sed 's/^export fn /fn /' "$T/sha.om" > "$T/unit.om"
cat "$T/unit.om" "$HERE/src/goal_microjobs/canon.om" > "$T/source.om"
"$OMEGA_OMC" < "$T/source.om" > "$T/canon"
chmod +x "$T/canon"
mv "$T/canon" "$OUT"
printf 'built %s\n' "$OUT"
sha256sum "$OUT"
