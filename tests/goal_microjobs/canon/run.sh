#!/usr/bin/env bash
# Synthetic host verification oracle, not production orchestration.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
repo=$(cd "$here/../../.." && pwd)
: "${CANON_RUN_ROOT:?Set CANON_RUN_ROOT to an external scratch/evidence directory}"
mkdir -p "$CANON_RUN_ROOT"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
for f in "$here"/*.hex; do xxd -r -p "$f" > "$work/$(basename "$f" .hex)"; done
bash "$repo/scripts/goal_microjobs/canon-build.sh" "$work/canon"
"$work/canon" emit < "$here/emit.in" > "$work/emission"
{ cat "$work/document" "$work/payload"; sha256sum < "$work/document" | cut -c1-64 | xxd -r -p; } > "$work/expected"
cmp "$work/emission" "$work/expected"
"$work/canon" ingest < "$work/ingest.in" > "$work/events"
cmp "$work/events" "$here/events"
printf 'PASS emit bytes + Omega dag hash; PASS exact RESULT/VERIFY\n'
checks=0
while read -r name code mode; do
  rc=0
  "$work/canon" "$mode" < "$work/$name.in" > "$work/out" 2> "$work/err" || rc=$?
  test "$rc" -eq "$code"
  test ! -s "$work/out"
  printf 'PASS refusal %s rc=%s %s\n' "$name" "$rc" "$(cat "$work/err")"
  checks=$((checks+1))
done < "$here/cases"
mkdir -p "$work/mut/scripts/goal_microjobs" "$work/mut/src/goal_microjobs"
cp "$repo/scripts/goal_microjobs/canon-build.sh" "$work/mut/scripts/goal_microjobs/"
: > "$CANON_RUN_ROOT/mutants.tsv"
while read -r name code mode; do
  # Stale-output tests both receipt and output binding; each has its isolated mutant below.
  test "$name" != staleoutput || continue
  sed "/^note CANON-GUARD $name\$/{n;s/.*/if false/;}" "$repo/src/goal_microjobs/canon.om" > "$work/mut/src/goal_microjobs/canon.om"
  bash "$work/mut/scripts/goal_microjobs/canon-build.sh" "$work/mutant" > "$work/build.log" 2>&1
  rc=0
  "$work/mutant" "$mode" < "$work/$name.in" > "$work/out" 2> "$work/err" || rc=$?
  test "$rc" -eq 0 || { printf 'SURVIVED %s rc=%s\n' "$name" "$rc"; exit 1; }
  test -s "$work/out"
  printf '%s\tKILLED\tguardless_exit=0\tguarded_exit=%s\n' "$name" "$code" | tee -a "$CANON_RUN_ROOT/mutants.tsv"
done < "$here/cases"
bash "$repo/scripts/goal_microjobs/build.sh" "$repo/src/goal_microjobs/kernel.om" "$work/kernel"
"$work/kernel" < "$here/replay.in" > "$CANON_RUN_ROOT/kernel.status"
grep -qx '101 1 4 1 1 0 0 0' "$CANON_RUN_ROOT/kernel.status"
printf 'PASS pinned kernel replay DONE; refusals=%s\n' "$checks"
# Build pin mismatch control: no output and exit 3, never silently compile with another tool.
rc=0
OMEGA_OMC=/bin/true bash "$repo/scripts/goal_microjobs/canon-build.sh" "$work/not-built" > "$work/blocked" 2>&1 || rc=$?
test "$rc" -eq 3 && test ! -e "$work/not-built"
printf 'PASS compiler pin refusal rc=3\n'
