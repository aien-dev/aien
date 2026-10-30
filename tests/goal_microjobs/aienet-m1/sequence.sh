#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-or-later
# Migration adapter, aien-dev/aien#22 (shell retirement): files, locks and
# processes only. canon.om binds wire identities; kernel.om admits every event;
# OH verifies P-256 signatures and runs the independently pinned Omega verifier.
set -euo pipefail
: "${STATE:?}" "${GM_KERNEL:?}" "${CANON:?}" "${RUN:?}" "${SERVE:?}"
: "${KEYS:?}" "${WKEYS:?}" "${PINS:?}" "${WPINS:?}" "${RECOMPUTE:?}"
: "${RECOMPUTE_SHA256:?}" "${LISTEN:?}"
repo=${M1_REPO:-$(cd "$(dirname "$0")/../../.." && pwd)}
driver="$repo/scripts/goal_microjobs/microjobs.sh"
exec 8>"$STATE/sequence.lock"
flock -n 8 || exit 75
pause() {
  if test "${M1_PAUSE:-}" = "$1"; then
    test -p "$STATE/pause.fifo" || mkfifo "$STATE/pause.fifo"
    exec 9<>"$STATE/pause.fifo"
    printf '%s\n' "$1" > "$STATE/paused"
    while test -e "$STATE/paused"; do read -r -t 0.05 -u 9 _ || true; done
    exec 9>&-
  fi
}
status=$(bash "$driver" status "$STATE")
while read -r tag id st gen attempts blocked ready effect; do
  if test "$tag" = 101 && test "$id" = 1; then break; fi
done <<< "$status"
test "$tag" = 101 && test "$id" = 1
if test "$st" = 4; then echo ALREADY_ACCEPTED; exit 0; fi
test "$st" = 1 || test "$st" = 2 || test "$st" = 3
art="$STATE/g$gen"
mkdir -p "$art"
# Kernel replay validates the journal; Omega derives the effective operand.
{
  printf '1 %s\n' "$(wc -l < "$STATE/journal")"
  cat "$STATE/plan"
  printf '101 1 %s %s %s %s %s %s\n' "$st" "$gen" "$attempts" "$blocked" "$ready" "$effect"
  cat "$STATE/bindings/$gen" "$STATE/journal"
} | "${RECOVERY:?}" | "$CANON" emit > "$art/emission.next"
dd if="$art/emission.next" of="$art/document.next" bs=1 count=640 status=none
dd if="$art/emission.next" of="$art/payload.next" bs=1 skip=640 count=15 status=none
if test -e "$art/document"; then
  cmp "$art/document" "$art/document.next"
else
  mv "$art/document.next" "$art/document"
fi
if test -e "$art/payload"; then
  cmp "$art/payload" "$art/payload.next"
else
  mv "$art/payload.next" "$art/payload"
fi
sync "$art/document" "$art/payload" "$art"
rm -f "$art/emission.next" "$art/document.next" "$art/payload.next"
bundle="$art/job.an0b"
persist() {
  if ! test -e "$bundle"; then
    "$RUN" bundle --keys "$KEYS" --out "$bundle" --document "$art/document" --payload "$art/payload"
  fi
  sync "$bundle" "$art"
}
# M1-GUARD persist-before-dispatch
persist
pause persisted
if test "$st" = 1; then
  bash "$driver" propose "$STATE" 1 1 1 "$gen" 20 0 0 0 0 0 0 0
fi
pause dispatched
# M1-MUTANT late-persist insertion point
if test "${M1_STOP_AFTER_DISPATCH:-0}" = 1; then exit 0; fi
dag=$(sha256sum "$art/document" | cut -d' ' -f1)
out="$art/out"
mkdir -p "$out"
worker_pid=
cleanup() {
  if test -n "$worker_pid"; then kill "$worker_pid" 2>/dev/null || true; wait "$worker_pid" 2>/dev/null || true; fi
}
trap cleanup EXIT
if ! test -f "$out/$dag.mjr1" || ! test -f "$out/$dag.mjv"; then
  worker_args=(--connect "$LISTEN" --keys "$WKEYS" --pins "$WPINS" --state "$art/worker" --retry --connect-timeout 10)
  if test -n "${M1_MISBEHAVE:-}"; then worker_args+=(--misbehave "$M1_MISBEHAVE"); fi
  if test -n "${M1_TEST_WORKER:-}"; then
    printf '%s\n' "${worker_args[@]}" > "$art/worker.args"
    AN0_TEST_SERVE_ARGS="$art/worker.args" AN0_TEST_PAUSE="${M1_WORKER_PAUSE:-admitted}" AN0_TEST_READY="$art/worker.ready" \
      "$M1_TEST_WORKER" --ignored --exact tests::serve_crash_worker --nocapture > "$art/worker.log" 2>&1 &
  else
    "$SERVE" "${worker_args[@]}" > "$art/worker.log" 2>&1 &
  fi
  worker_pid=$!
  printf '%s\n' "$worker_pid" > "$art/worker.pid"
  "$RUN" run --resend "$bundle" --listen "$LISTEN" --keys "$KEYS" --pins "$PINS" --out "$out" \
    --recompute "$RECOMPUTE" --recompute-sha256 "$RECOMPUTE_SHA256" --accept-timeout 10
  wait "$worker_pid"
  worker_pid=
fi
pause published
# M1-GUARD check-before-ingest
"$RUN" check --bundle "$bundle" --mjr1 "$out/$dag.mjr1" --mjv "$out/$dag.mjv" --keys "$KEYS" --pins "$PINS"
# An owner correction during network execution must win over the old response.
current=$(bash "$driver" status "$STATE")
while read -r tag id current_state current_gen rest; do
  if test "$tag" = 101 && test "$id" = 1; then break; fi
done <<< "$current"
ingest_gen=$gen
# M1-GUARD generation-match
ingest_gen=$current_gen
next=$(( $(wc -l < "$STATE/journal") + 1 ))
if test "$st" = 3; then next=$((next - 1)); fi
{
  cat "$art/document" "$out/$dag.mjr1" "$out/$dag.mjv"
  printf '5 1 %s 1 20 5 %s %s %s\n' "$ingest_gen" "$EXECUTOR_WORDS" "$VERIFIER_WORDS" "$next"
} | "$CANON" ingest > "$art/events"
# Each event is independently journaled via the kernel. Recovery from a torn
# pair proves the persisted RESULT is identical before proposing only VERIFY.
mapfile -t events < "$art/events"
test "${#events[@]}" = 2
if test "$st" = 3; then
  last=$(cat "$STATE/journal" | { mapfile -t lines; printf '%s\n' "${lines[-1]}"; })
  printf '2\n%s\n%s\n' "$last" "${events[0]}" | "$RECOVERY"
else
  read -r _ _ rest <<< "${events[0]}"
  bash "$driver" propose "$STATE" $rest
fi
pause resulted
read -r _ _ rest <<< "${events[1]}"
bash "$driver" propose "$STATE" $rest
bash "$driver" status "$STATE"
