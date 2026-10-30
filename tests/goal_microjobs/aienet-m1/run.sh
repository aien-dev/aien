#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-or-later
# Host-only acceptance. Shell sequencing is a migration adapter for aien#22.
# No GPU, settlement, public listener, remote host or persistent identities.
set -euo pipefail
repo=$(cd "$(dirname "$0")/../../.." && pwd)
here="$repo/tests/goal_microjobs/aienet-m1"
: "${OH_TREE:?own Open Humanity seal-document worktree}"
: "${PROTOCOLS:?protocols source tree}"
: "${OMEGA_WORKTREE:?Allen pinned compiler tree}"
: "${RECOMPUTE_OMC:?e5b32567 omc}"
: "${SHA_OMEGA_TREE:?tree containing pinned SHA unit}"
: "${CANON:?compiled canon from feat/aienet-m1-canon}"
canon_source=4e85855210a4828f1143c08518c0aea99208d008
canon_binary=e894ce48da2c885e84a4c68d667bd9a7cdbe965990feb423d5370e12cc09b103
git -C "$repo" merge-base --is-ancestor "$canon_source" HEAD
test "$(sha256sum "$CANON" | cut -d' ' -f1)" = "$canon_binary"
export CARGO_BUILD_JOBS=4 PYTHONDONTWRITEBYTECODE=1
umask 077
E=${1:?usage: run.sh FRESH_EVIDENCE_DIRECTORY}
test ! -e "$E"
mkdir -p "$E"
E=$(cd "$E" && pwd)
K=$(mktemp -d /dev/shm/aienet-m1-keys.XXXXXX)
cleanup() { rm -rf -- "$K"; }
trap cleanup EXIT
mkdir "$K/requester" "$K/worker" "$K/pins" "$K/wpins"
export KEYS="$K/requester" WKEYS="$K/worker" PINS="$K/pins" WPINS="$K/wpins"
for file in "$KEYS/transport.seed" "$KEYS/submitter.p256" "$KEYS/verifier.p256" "$WKEYS/transport.seed" "$WKEYS/executor.p256"; do
  openssl rand -hex -out "$file" 32
done
(cd "$OH_TREE"; cargo build --locked --release --bin aienet0-run --bin aienet0-serve) > "$E/build.log" 2>&1
export RUN="$OH_TREE/target/release/aienet0-run" SERVE="$OH_TREE/target/release/aienet0-serve"
# The test executable enables only the worker's pre-existing cfg(test) pauses.
(cd "$OH_TREE"; cargo test --locked -p oh-volunteer --bin aienet0-serve --no-run --message-format=json) > "$E/test-build.jsonl" 2> "$E/test-build.log"
TEST_WORKER=$(jq -r 'select(.reason == "compiler-artifact" and .profile.test == true) | .executable // empty' "$E/test-build.jsonl")
test -x "$TEST_WORKER"
"$RUN" keys --keys "$KEYS" > "$E/requester-public"
"$SERVE" keys --keys "$WKEYS" > "$E/worker-public"
while read -r name key; do printf '%s\n' "$key" > "$WPINS/$name"; done < "$E/requester-public"
while read -r name key; do printf '%s\n' "$key" > "$PINS/$name"; done < "$E/worker-public"
export GM_KERNEL="$E/kernel" RECOMPUTE="$E/recompute"
bash "$repo/scripts/goal_microjobs/build.sh" "$repo/src/goal_microjobs/kernel.om" "$GM_KERNEL" > "$E/kernel-build.log" 2>&1
OMEGA_OMC="$RECOMPUTE_OMC" OMEGA_MV="$SHA_OMEGA_TREE" bash "$PROTOCOLS/specs/aienet/jobpath/build.sh" "$RECOMPUTE" > "$E/recompute-build.log" 2>&1
export RECOMPUTE_SHA256=d2cd7382e0dc64e49498ae3b1ceffc73f1ddcbd3ddcf93e6d607498ccd58ea12
test "$(sha256sum "$RECOMPUTE" | cut -d' ' -f1)" = "$RECOMPUTE_SHA256"
words() { local hex=$1; printf '%u %u %u %u\n' "0x${hex:0:16}" "0x${hex:16:16}" "0x${hex:32:16}" "0x${hex:48:16}"; }
hash_words() { words "$(sha256sum | cut -d' ' -f1)"; }
export EXECUTOR_WORDS VERIFIER_WORDS
EXECUTOR_WORDS=$(xxd -r -p "$PINS/executor.p256" | hash_words)
VERIFIER_WORDS=$(xxd -r -p "$WPINS/verifier.p256" | hash_words)
objective=$(printf aienet-m1-synthetic-objective | hash_words)
tenant=$(printf AIENET0-TENANT-TUR-TEST-V1 | hash_words)
capability=$(printf AIENET0-CAPABILITY-MATMUL-U32-V1 | hash_words)
subject=$(printf aienet-m1-explicit-subject | hash_words)
approval=$(printf aienet-m1-explicit-approval | hash_words)
expires=$(date -u -d tomorrow +%s)
driver="$repo/scripts/goal_microjobs/microjobs.sh"
sequence="$here/sequence.sh"
export STATE LISTEN
new_state() {
  STATE="$E/${CASE_PREFIX:-}$1"
  mkdir -p "$STATE/bindings"
  printf '010002000300020000000000000007' | xxd -r -p > "$STATE/payload1"
  operand=$(hash_words < "$STATE/payload1")
  {
    printf '1 1 %s 7 9 1 1 1 4 0 0 0 0 120000\n' "$objective"
    printf '2 1 1 2 0 0 1 0 0 0 0 1 5 1 1 7 120000 1 %s 0\n' "$operand"
  } > "$STATE/input-plan"
  printf '4 %s %s %s %s %s %s 2 3 2 7 1\n' "$objective" "$tenant" "$subject" "$approval" "$capability" "$expires" > "$STATE/bindings/1"
  bash "$driver" init "$STATE" "$STATE/input-plan"
  port=$(shuf -i 49152-65535 -n 1)
  test -z "$(ss -H -ltn "sport = :$port")"
  LISTEN="127.0.0.1:$port"
}
exactly_once() {
  bash "$driver" status "$STATE" > "$STATE/final-status"
  local tag id st gen rest
  while read -r tag id st gen rest; do
    if test "$tag" = 101 && test "$id" = 1; then test "$st" = 4 && test "$gen" = "${1:-1}"; break; fi
  done < "$STATE/final-status"
  local dispatch=0 result=0 verify=0
  while read -r tag seq type node attempt gen rest; do
    if test "$node" = 1 && test "$gen" = "${1:-1}"; then
      case "$type" in 1) dispatch=$((dispatch+1));; 2) result=$((result+1));; 3) verify=$((verify+1));; esac
    fi
  done < "$STATE/journal"
  test "$dispatch/$result/$verify" = 1/1/1
}
wait_file() {
  local file=$1 pid=$2
  for ((i=0;i<600;i++)); do
    test ! -f "$file" || return 0
    kill -0 "$pid" || return 1
    sleep 0.05
  done
  echo "boundary not reached: $file" >&2
  return 1
}
semantic() {
  local name=$1; shift
  if ! "$@"; then echo "M1_SEMANTIC $name" >&2; return 1; fi
}
cleanup_case() {
  if test -n "${active_pid:-}"; then
    kill "$active_pid" 2>/dev/null || true
    wait "$active_pid" 2>/dev/null || true
  fi
}
run_sequence() { bash "$sequence"; }
happy() { new_state happy; run_sequence; exactly_once; }
crash() {
  local boundary=$1
  new_state "crash-$boundary"
  M1_PAUSE="$boundary" bash "$sequence" > "$STATE/first.log" 2>&1 &
  local pid=$!; active_pid=$pid
  wait_file "$STATE/paused" "$pid"
  # Persisted artifact must already exist at every post-dispatch boundary.
  if test "$boundary" != persisted; then semantic persist-before-dispatch test -s "$STATE/g1/job.an0b"; fi
  sha256sum "$STATE/g1/job.an0b" > "$STATE/bundle.before"
  kill -KILL "$pid"
  wait "$pid" || true
  rm -f "$STATE/paused"
  run_sequence
  sha256sum -c "$STATE/bundle.before"
  exactly_once
}
worker_crash() {
  local phase=${1:-admitted}
  new_state "crash-worker-$phase"
  M1_TEST_WORKER="$TEST_WORKER" M1_WORKER_PAUSE="$phase" bash "$sequence" > "$STATE/first.log" 2>&1 &
  local pid=$!; active_pid=$pid
  wait_file "$STATE/g1/worker.ready" "$pid"
  read -r worker < "$STATE/g1/worker.pid"
  sha256sum "$STATE/g1/job.an0b" > "$STATE/bundle.before"
  kill -KILL "$worker"
  wait "$pid" || true
  run_sequence
  sha256sum -c "$STATE/bundle.before"
  exactly_once
}
correct() {
  printf '010002000300020000000000000008' | xxd -r -p > "$STATE/payload2"
  local changed; changed=$(hash_words < "$STATE/payload2")
  bash "$driver" propose "$STATE" 6 1 0 1 7 0 $changed 0 0
  printf '4 %s %s %s %s %s %s 2 3 2 8 1\n' "$objective" "$tenant" "$subject" "$approval" "$capability" "$expires" > "$STATE/bindings/2"
}
stale() {
  new_state stale
  M1_PAUSE=published bash "$sequence" > "$STATE/first.log" 2>&1 &
  local pid=$!; active_pid=$pid
  wait_file "$STATE/paused" "$pid"
  correct
  cp "$STATE/journal" "$STATE/before-stale"
  rm "$STATE/paused"
  local rc=0; wait "$pid" || rc=$?
  semantic generation-match test "$rc" = 34
  cmp "$STATE/journal" "$STATE/before-stale"
  # Independently challenge canon with the saved generation1 wire receipt.
  local dag; dag=$(sha256sum "$STATE/g1/document" | cut -d' ' -f1)
  { cat "$STATE/g1/document" "$STATE/g1/out/$dag.mjr1" "$STATE/g1/out/$dag.mjv"; printf '5 1 2 1 20 5 %s %s 3\n' "$EXECUTOR_WORDS" "$VERIFIER_WORDS"; } > "$STATE/stale.ingest"
  rc=0; "$CANON" ingest < "$STATE/stale.ingest" > "$STATE/stale.events" 2> "$STATE/stale.err" || rc=$?
  test "$rc" = 14 && test ! -s "$STATE/stale.events"
  run_sequence
  exactly_once 2
}
publish_only() {
  M1_PAUSE=published bash "$sequence" > "$STATE/first.log" 2>&1 &
  local pid=$!; active_pid=$pid
  wait_file "$STATE/paused" "$pid"
  kill -KILL "$pid"; wait "$pid" || true
  rm "$STATE/paused"
}
altered() {
  new_state altered
  publish_only
  local dag; dag=$(sha256sum "$STATE/g1/document" | cut -d' ' -f1)
  cp "$STATE/g1/out/$dag.mjr1" "$STATE/receipt.original"
  # Signature-covered byte, not a malformed wire header.
  printf '\377' | dd of="$STATE/g1/out/$dag.mjr1" bs=1 seek=176 conv=notrunc status=none
  cp "$STATE/journal" "$STATE/before"
  local rc=0; run_sequence > "$STATE/refusal.log" 2>&1 || rc=$?
  test "$rc" = 12
  cmp "$STATE/journal" "$STATE/before"
  cp "$STATE/receipt.original" "$STATE/g1/out/$dag.mjr1"
  run_sequence
  exactly_once
}
wrong_output() {
  new_state signed-wrong-output
  local rc=0; M1_MISBEHAVE=wrong-output run_sequence > "$STATE/refusal.log" 2>&1 || rc=$?
  test "$rc" = 13
  test "$(wc -l < "$STATE/journal")" = 1
  test -z "$(compgen -G "$STATE/g1/out/*.mjv")"
}
duplicate() {
  new_state duplicate
  run_sequence
  cp "$STATE/journal" "$STATE/before"
  # Ingest the same signed artifacts again, then ask the kernel to admit the
  # newly sequenced RESULT. The immutable journal must refuse with code 33.
  local line rest rc dag
  dag=$(sha256sum "$STATE/g1/document" | cut -d' ' -f1)
  {
    cat "$STATE/g1/document" "$STATE/g1/out/$dag.mjr1" "$STATE/g1/out/$dag.mjv"
    printf '5 1 1 1 20 5 %s %s 4\n' "$EXECUTOR_WORDS" "$VERIFIER_WORDS"
  } | "$CANON" ingest > "$STATE/replayed.events"
  read -r line < "$STATE/replayed.events"
  read -r _ _ rest <<< "$line"
  rc=0; bash "$driver" propose "$STATE" $rest || rc=$?
  test "$rc" = 33
  # A distinct, genuinely executor-signed completion from the test worker
  # (different source_hash) is independently checked and also cannot commit.
  mkdir "$STATE/second-out"
  printf '%s\n' --connect "$LISTEN" --keys "$WKEYS" --pins "$WPINS" --state "$STATE/second-worker" --retry --connect-timeout 10 > "$STATE/second.args"
  AN0_TEST_SERVE_ARGS="$STATE/second.args" AN0_TEST_PAUSE= \
    "$TEST_WORKER" --ignored --exact tests::serve_crash_worker --nocapture > "$STATE/second-worker.log" 2>&1 &
  local second_pid=$!; active_pid=$second_pid
  "$RUN" run --resend "$STATE/g1/job.an0b" --listen "$LISTEN" --keys "$KEYS" --pins "$PINS" --out "$STATE/second-out" \
    --recompute "$RECOMPUTE" --recompute-sha256 "$RECOMPUTE_SHA256" --accept-timeout 10
  wait "$second_pid"
  if cmp -s "$STATE/g1/out/$dag.mjr1" "$STATE/second-out/$dag.mjr1"; then echo SECOND_RECEIPT_NOT_DISTINCT >&2; return 1; fi
  "$RUN" check --bundle "$STATE/second-out/$dag.an0b" --mjr1 "$STATE/second-out/$dag.mjr1" --mjv "$STATE/second-out/$dag.mjv" --keys "$KEYS" --pins "$PINS"
  {
    cat "$STATE/g1/document" "$STATE/second-out/$dag.mjr1" "$STATE/second-out/$dag.mjv"
    printf '5 1 1 1 20 5 %s %s 4\n' "$EXECUTOR_WORDS" "$VERIFIER_WORDS"
  } | "$CANON" ingest > "$STATE/second.events"
  read -r line < "$STATE/second.events"
  read -r _ _ rest <<< "$line"
  rc=0; bash "$driver" propose "$STATE" $rest || rc=$?
  test "$rc" = 33
  run_sequence
  cmp "$STATE/journal" "$STATE/before"
  exactly_once
}
# Signature-only AN0V mutation leaves binding hashes valid. canon deliberately
# does not verify P-256, so removing OH check must make this case accept falsely.
attestation_signature() {
  new_state attestation-signature
  publish_only
  local dag; dag=$(sha256sum "$STATE/g1/document" | cut -d' ' -f1)
  local old; old=$(od -An -tu1 -j235 -N1 "$STATE/g1/out/$dag.mjv")
  printf '%b' "\\$(printf '%03o' "$((old ^ 1))")" | dd of="$STATE/g1/out/$dag.mjv" bs=1 seek=235 conv=notrunc status=none
  cp "$STATE/journal" "$STATE/before"
  local rc=0; run_sequence > "$STATE/refusal.log" 2>&1 || rc=$?
  semantic check-before-ingest test "$rc" = 14
  cmp "$STATE/journal" "$STATE/before"
}
# Mutations are generated into evidence-local copies by removing exactly the
# named guard line. No candidate source, compiler or historical receipt changes.
mutant() {
  local name=$1 guard=$2 probe=$3
  local original=$sequence
  sequence="$E/mutant-$name.sh"
  local skip=0 line
  : > "$sequence"
  while IFS= read -r line; do
    if test "$skip" = 1; then skip=0; continue; fi
    if test "$line" = "# M1-GUARD $guard"; then skip=1; fi
    printf '%s\n' "$line" >> "$sequence"
    if test "$name" = persist && test "$line" = '# M1-MUTANT late-persist insertion point'; then printf 'persist\n' >> "$sequence"; fi
  done < "$original"
  # The copy is outside the repository; preserve its known adapter root.
  export M1_REPO="$repo"
  local rc=0
  export CASE_PREFIX="mutant-$name-"
  set +e
  (set -e; trap cleanup_case EXIT; "$probe") > "$E/mutant-$name.log" 2>&1
  rc=$?
  set -e
  unset CASE_PREFIX
  sequence=$original
  test "$rc" = 1
  local killed=0
  while IFS= read -r line; do
    if test "$line" = "M1_SEMANTIC $guard"; then killed=1; fi
  done < "$E/mutant-$name.log"
  test "$killed" = 1
  printf '%s\tKILLED\t%s\n' "$name" "$rc" >> "$E/mutants.tsv"
}
persist_probe() { crash dispatched; }
checks=0 failures=0
printf '# canon_source\t%s\n# canon_binary_sha256\t%s\ncase\texpected\tobserved\texit\n' "$canon_source" "$canon_binary" > "$E/summary.tsv"
case_run() {
  local name=$1; shift
  local rc=0
  set +e
  (set -e; trap cleanup_case EXIT; "$@") > "$E/$name.log" 2>&1
  rc=$?
  set -e
  checks=$((checks+1))
  if test "$rc" = 0; then
    printf '%s\tPASS\tPASS\t0\n' "$name" >> "$E/summary.tsv"
  else
    failures=$((failures+1))
    printf '%s\tPASS\tFAIL\t%s\n' "$name" "$rc" >> "$E/summary.tsv"
  fi
}
case_run happy happy
for boundary in persisted dispatched published resulted; do case_run "crash-$boundary" crash "$boundary"; done
case_run crash-worker-admitted worker_crash
case_run crash-worker-done worker_crash done
case_run stale stale
case_run altered altered
case_run signed-wrong-output wrong_output
case_run duplicate duplicate
case_run attestation-signature attestation_signature
if test "$failures" != 0; then
  cat "$E/summary.tsv"
  echo 'mutants NOT_RUN: baseline cases must all pass'
  exit 1
fi
printf 'mutant\tverdict\tprobe_exit\n' > "$E/mutants.tsv"
case_run mutant-persist mutant persist persist-before-dispatch persist_probe
case_run mutant-check mutant check check-before-ingest attestation_signature
case_run mutant-generation mutant generation generation-match stale
cat "$E/summary.tsv" "$E/mutants.tsv"
printf 'M1 cases=%s failures=%s evidence=%s\n' "$checks" "$failures" "$E"
test "$failures" = 0
