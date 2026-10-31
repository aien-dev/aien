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
canon_source=b5057df61bc2175e6e1bf23d1ebce0a2857f8584
canon_binary=4d7d2a0bda184622980f61570b8ae5294a1989c89af2aa498bdbfa443abf2b1b
# Pin the canon sources by git blob id, not by commit ancestry: a squash merge
# of feat/aienet-m1-canon leaves b5057df off main while the sources stay equal.
test "$(git -C "$repo" rev-parse HEAD:src/goal_microjobs/canon.om)" = 5719dc992cb358d7ea29dbec4ab82e310369de29
test "$(git -C "$repo" rev-parse HEAD:scripts/goal_microjobs/canon-build.sh)" = 226fcae40b2daa9dcc3da785571b1cef70b41c4b
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
(cd "$OH_TREE"; cargo build --locked --release --bin aienet0-run --bin aienet0-serve --message-format=json) > "$E/build.jsonl" 2> "$E/build.log"
export RUN SERVE
RUN=$(jq -r 'select(.reason == "compiler-artifact" and .target.name == "aienet0-run" and .profile.test == false) | .executable // empty' "$E/build.jsonl")
SERVE=$(jq -r 'select(.reason == "compiler-artifact" and .target.name == "aienet0-serve" and .profile.test == false) | .executable // empty' "$E/build.jsonl")
test -x "$RUN"; test -x "$SERVE"
oh_source=$(git -C "$OH_TREE" rev-parse HEAD)
oh_run_sha=$(sha256sum "$RUN" | cut -d' ' -f1)
oh_serve_sha=$(sha256sum "$SERVE" | cut -d' ' -f1)
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
export RECOVERY="$E/recovery"
OMEGA_OMC="$RECOMPUTE_OMC" sh "$repo/scripts/goal_microjobs/recovery-build.sh" "$RECOVERY" > "$E/recovery-build.log" 2>&1
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
  local state_seed=${2:-7} state_objective=${3:-$objective}
  STATE="$E/${CASE_PREFIX:-}$1"
  mkdir -p "$STATE/bindings"
  printf '01000200030002%016x' "$state_seed" | xxd -r -p > "$STATE/payload1"
  operand=$(hash_words < "$STATE/payload1")
  {
    printf '1 1 %s 7 9 1 1 1 4 0 0 0 0 120000\n' "$state_objective"
    printf '2 1 1 2 0 0 1 0 0 0 0 1 5 1 1 7 120000 1 %s 0\n' "$operand"
  } > "$STATE/input-plan"
  printf '4 %s %s %s %s %s %s 2 3 2 %s 1\n' "$state_objective" "$tenant" "$subject" "$approval" "$capability" "$expires" "$state_seed" > "$STATE/bindings/1"
  bash "$driver" init "$STATE" "$STATE/input-plan"
  port=$(shuf -i 49152-65535 -n 1)
  test -z "$(ss -H -ltn "sport = :$port")"
  LISTEN="127.0.0.1:$port"
}
assert_done() {
  local status_file=$1 wanted=$2 tag id st gen rest matches=0
  while read -r tag id st gen rest; do
    if test "$tag" = 101 && test "$id" = 1; then
      matches=$((matches+1))
      test "$st" = 4 || return 1
      test "$gen" = "$wanted" || return 1
    fi
  done < "$status_file"
  test "$matches" = 1 || return 1
}
done_negative() {
  printf '%s\n' "$2" > "$E/done-$1.input"
  local rc=0
  assert_done "$E/done-$1.input" 1 || rc=$?
  test "$rc" = 1
}
exactly_once() {
  bash "$driver" status "$STATE" > "$STATE/final-status"
  assert_done "$STATE/final-status" "${1:-1}" || return 1
  local tag id gen rest
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
  local mode=${1:-single} expected=24 target=2 guard=operand-pin
  new_state "stale-$mode"
  M1_PAUSE=published bash "$sequence" > "$STATE/first.log" 2>&1 &
  local pid=$!; active_pid=$pid
  wait_file "$STATE/paused" "$pid"
  correct
  if test "$mode" = roundtrip; then
    bash "$driver" propose "$STATE" 6 1 0 2 7 0 $operand 0 0
    printf '4 %s %s %s %s %s %s 2 3 2 7 1\n' "$objective" "$tenant" "$subject" "$approval" "$capability" "$expires" > "$STATE/bindings/3"
    expected=14; target=3; guard=generation-match
  fi
  cp "$STATE/journal" "$STATE/before-stale"
  rm "$STATE/paused"
  local rc=0; wait "$pid" || rc=$?
  semantic "$guard" test "$rc" = "$expected"
  cmp "$STATE/journal" "$STATE/before-stale"
  # Independently challenge canon with the saved generation1 wire receipt.
  local dag; dag=$(sha256sum "$STATE/g1/document" | cut -d' ' -f1)
  local trusted
  { printf '1\n'; cat "$STATE/plan" "$STATE/journal"; } | "$RECOVERY" > "$STATE/stale.effective"
  read -r -a trusted < "$STATE/stale.effective"
  {
    cat "$STATE/g1/document" "$STATE/g1/out/$dag.mjr1" "$STATE/g1/out/$dag.mjv"
    printf '5 1 %s 1 20 5 %s %s %s %s %s\n' "$target" "$EXECUTOR_WORDS" "$VERIFIER_WORDS" "$(( $(wc -l < "$STATE/journal") + 1 ))" "${trusted[*]:2:4}" "${trusted[*]:35:4}"
  } > "$STATE/stale.ingest"
  rc=0; "$CANON" ingest < "$STATE/stale.ingest" > "$STATE/stale.events" 2> "$STATE/stale.err" || rc=$?
  test "$rc" = "$expected" && test ! -s "$STATE/stale.events"
  run_sequence
  exactly_once "$target"
}
generation_probe() { stale roundtrip; }
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
  local old; old=$(od -An -tu1 -j176 -N1 "$STATE/g1/out/$dag.mjr1")
  printf '%b' "\\$(printf '%03o' "$((old ^ 1))")" | dd of="$STATE/g1/out/$dag.mjr1" bs=1 seek=176 conv=notrunc status=none
  cp "$STATE/journal" "$STATE/before"
  local rc=0; run_sequence > "$STATE/refusal.log" 2>&1 || rc=$?
  printf 'altered signature expected_exit=12 observed_exit=%s\n' "$rc"
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
    printf '5 1 1 1 20 5 %s %s 4 %s %s\n' "$EXECUTOR_WORDS" "$VERIFIER_WORDS" "$objective" "$operand"
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
    printf '5 1 1 1 20 5 %s %s 4 %s %s\n' "$EXECUTOR_WORDS" "$VERIFIER_WORDS" "$objective" "$operand"
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
pin_substitution() {
  local mode=$1 guard=operand-pin expected=24 source_gen=1 target_gen=1 source_state source_dag
  local other_objective old_operand target_dag pid rc=0 tag id st generation rest matches=0
  case "$mode" in
    objective)
      guard=objective-pin; expected=23
      other_objective=$(printf aienet-m1-other-objective | hash_words)
      new_state foreign-objective 7 "$other_objective"
      ;;
    operand) new_state foreign-operand 8 ;;
    after-correct)
      new_state foreign-old-operand 8
      old_operand=$(printf '010002000300020000000000000007' | xxd -r -p | hash_words)
      bash "$driver" propose "$STATE" 6 1 0 1 7 0 $old_operand 0 0
      printf '4 %s %s %s %s %s %s 2 3 2 7 1\n' "$objective" "$tenant" "$subject" "$approval" "$capability" "$expires" > "$STATE/bindings/2"
      source_gen=2; target_gen=2
      ;;
    *) return 2 ;;
  esac
  run_sequence
  exactly_once "$source_gen"
  source_state=$STATE
  source_dag=$(sha256sum "$STATE/g$source_gen/document" | cut -d' ' -f1)
  new_state "substitute-$mode"
  if test "$mode" = after-correct; then correct; fi
  # The real sequencer is paused after authentic artifacts arrive but before
  # its check/ingest. Replace the entire signed submission, not isolated bytes.
  M1_PAUSE=published bash "$sequence" > "$STATE/first.log" 2>&1 &
  pid=$!; active_pid=$pid
  wait_file "$STATE/paused" "$pid"
  target_dag=$(sha256sum "$STATE/g$target_gen/document" | cut -d' ' -f1)
  local art="$STATE/g$target_gen" foreign="$source_state/g$source_gen"
  mkdir "$STATE/original"
  cp "$art/document" "$art/job.an0b" "$art/out/$target_dag.mjr1" "$art/out/$target_dag.mjv" "$STATE/original/"
  cp "$foreign/document" "$art/document"
  cp "$foreign/job.an0b" "$art/job.an0b"
  cp "$foreign/out/$source_dag.mjr1" "$art/out/$target_dag.mjr1"
  cp "$foreign/out/$source_dag.mjv" "$art/out/$target_dag.mjv"
  "$RUN" check --bundle "$art/job.an0b" --mjr1 "$art/out/$target_dag.mjr1" --mjv "$art/out/$target_dag.mjv" --keys "$KEYS" --pins "$PINS" > "$STATE/substitute-check.log" 2>&1
  cp "$STATE/journal" "$STATE/before-substitute"
  rm "$STATE/paused"
  wait "$pid" || rc=$?
  active_pid=
  printf '%s%s\t%s\t%s\n' "${CASE_PREFIX:-}" "$mode" "$expected" "$rc" >> "$E/pin-refusals.tsv"
  semantic "$guard" test "$rc" = "$expected"
  test ! -s "$art/events"
  cmp "$STATE/journal" "$STATE/before-substitute"
  bash "$driver" status "$STATE" > "$STATE/refused-status"
  while read -r tag id st generation rest; do
    if test "$tag/$id" = 101/1; then
      matches=$((matches+1))
      test "$st/$generation" = "2/$target_gen"
    fi
  done < "$STATE/refused-status"
  test "$matches" = 1
  # Restore the originally checked bytes: the same dispatch can then complete.
  cp "$STATE/original/document" "$art/document"
  cp "$STATE/original/job.an0b" "$art/job.an0b"
  cp "$STATE/original/$target_dag.mjr1" "$art/out/$target_dag.mjr1"
  cp "$STATE/original/$target_dag.mjv" "$art/out/$target_dag.mjv"
  run_sequence
  exactly_once "$target_gen"
}
operand_substitution() { pin_substitution operand; }
objective_substitution() { pin_substitution objective; }
conflicting_result() {
  new_state conflicting-result
  M1_PAUSE=resulted bash "$sequence" > "$STATE/first.log" 2>&1 &
  local pid=$!; active_pid=$pid
  wait_file "$STATE/paused" "$pid"
  kill -KILL "$pid"; wait "$pid" || true
  rm "$STATE/paused"
  local lines fields rc=0
  mapfile -t lines < "$STATE/journal"
  read -r -a fields <<< "${lines[1]}"
  fields[13]=$((fields[13]+1))
  printf '%s\n%s\n' "${lines[0]}" "${fields[*]}" > "$STATE/journal"
  bash "$driver" status "$STATE" > "$STATE/resulted-status"
  cp "$STATE/journal" "$STATE/before-conflict"
  run_sequence > "$STATE/conflict.log" 2>&1 || rc=$?
  semantic result-conflict test "$rc" = 33
  cmp "$STATE/journal" "$STATE/before-conflict"
}
history() {
  local count=$1 gen=$(( $1+1 )) i current=1 changed expected seed effective
  new_state "history-$count"
  printf '010002000300020000000000000008' | xxd -r -p > "$STATE/payload2"
  changed=$(hash_words < "$STATE/payload2")
  for ((i=1;i<=count;i++)); do
    if ((i%2)); then effective=$changed; else effective=$operand; fi
    printf '3 %s 6 1 0 %s 7 0 %s 0 0\n' "$i" "$current" "$effective" >> "$STATE/journal"
    current=$((current+1))
  done
  if ((count%2)); then seed=8; expected=$changed; else seed=7; expected=$operand; fi
  printf '4 %s %s %s %s %s %s 2 3 2 %s 1\n' "$objective" "$tenant" "$subject" "$approval" "$capability" "$expires" "$seed" > "$STATE/bindings/$gen"
  bash "$driver" status "$STATE" > "$STATE/history-status"
  { printf '1\n'; cat "$STATE/plan" "$STATE/journal"; } | "$RECOVERY" > "$STATE/effective-probe"
  read -r -a fields < "$STATE/effective-probe"
  semantic latest-correct test "${fields[*]:35:4}" = "$expected"
  run_sequence
  exactly_once "$gen"
}
multiple_corrects() { history 2; }
correct_after_result() {
  new_state correct-after-result
  M1_PAUSE=resulted bash "$sequence" > "$STATE/first.log" 2>&1 &
  local pid=$!; active_pid=$pid
  wait_file "$STATE/paused" "$pid"
  kill -KILL "$pid"; wait "$pid" || true
  rm "$STATE/paused"
  correct
  bash "$driver" propose "$STATE" 6 1 0 2 7 0 $operand 0 0
  printf '4 %s %s %s %s %s %s 2 3 2 7 1\n' "$objective" "$tenant" "$subject" "$approval" "$capability" "$expires" > "$STATE/bindings/3"
  run_sequence
  exactly_once 3
  local tag seq type node attempt generation rest stale_verify=0
  while read -r tag seq type node attempt generation rest; do
    if test "$type/$node/$generation" = 3/1/1; then stale_verify=$((stale_verify+1)); fi
  done < "$STATE/journal"
  test "$stale_verify" = 0
}
capacity_boundaries() {
  new_state capacity
  # kernel.om:10,60-79: buffer length 262144, load refuses >= length-1.
  local capacity=262144 size bytes expected kr hr
  cat "$STATE/plan" "$STATE/journal" > "$STATE/base-input"
  bytes=$(wc -c < "$STATE/base-input")
  printf 'bytes\texpected_kernel\texpected_recovery\tobserved_kernel\tobserved_recovery\n' > "$STATE/capacity.tsv"
  for size in "$((capacity-2))" "$((capacity-1))" "$capacity" "$((capacity+1))"; do
    cp "$STATE/base-input" "$STATE/kernel-input"
    printf '%*s' "$((size-bytes))" '' >> "$STATE/kernel-input"
    expected=3; if test "$size" = "$((capacity-2))"; then expected=0; fi
    kr=0; "$GM_KERNEL" < "$STATE/kernel-input" > "$STATE/capacity-status" || kr=$?
    hr=0; { printf '1\n'; cat "$STATE/kernel-input"; } | "$RECOVERY" > "$STATE/capacity-fold" || hr=$?
    printf '%s\t%s\t%s\t%s\t%s\n' "$size" "$expected" "$expected" "$kr" "$hr" >> "$STATE/capacity.tsv"
    test "$kr" = "$expected"; test "$hr" = "$expected"
    if test "$expected" = 0; then
      {
        cat "$STATE/capacity-fold"
        while read -r tag rest; do if test "$tag" = 101; then printf '%s %s\n' "$tag" "$rest"; fi; done < "$STATE/capacity-status"
        cat "$STATE/bindings/1"
      } | "$CANON" emit > "$STATE/capacity-emission"
      test "$(wc -c < "$STATE/capacity-emission")" = 687
    else
      test ! -s "$STATE/capacity-fold"
    fi
  done
}
omega_mutant() {
  local name=$1 guard=$2 probe=$3 original=$RECOVERY line skip=0
  local source="$E/recovery-$name.om" binary="$E/recovery-$name"
  : > "$source"
  while IFS= read -r line; do
    if test "$skip" = 1; then skip=0; continue; fi
    if test "$name" = conflict && test "$line" = 'note RECOVERY-GUARD result-conflict'; then skip=1; fi
    printf '%s\n' "$line" >> "$source"
    if test "$name" = first-correct && test "$line" = 'note RECOVERY-MUTANT first-correct-stop'; then printf 'break\n' >> "$source"; fi
  done < "$repo/src/goal_microjobs/recovery.om"
  OMEGA_OMC="$RECOMPUTE_OMC" sh "$repo/scripts/goal_microjobs/recovery-build.sh" "$binary" "$source" > "$E/recovery-$name-build.log" 2>&1
  export RECOVERY="$binary" CASE_PREFIX="mutant-$name-"
  local rc=0
  set +e
  (set -e; trap cleanup_case EXIT; "$probe") > "$E/mutant-$name.log" 2>&1
  rc=$?
  set -e
  export RECOVERY=$original
  unset CASE_PREFIX
  test "$rc" = 1
  local killed=0
  while IFS= read -r line; do
    if test "$line" = "M1_SEMANTIC $guard"; then killed=1; fi
  done < "$E/mutant-$name.log"
  test "$killed" = 1
  printf '%s\tKILLED\t1\n' "$guard" >> "$E/mutants.tsv"
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
    if test "$name/$line" = 'doc-objective/# M1-GUARD objective-pin'; then
      printf 'objective_pin=$(od -An -tu8 --endian=big -j8 -N32 "$art/document")\n' >> "$sequence"
    fi
    if test "$name/$line" = 'doc-operand/# M1-GUARD operand-pin'; then
      printf 'operand_pin=$(od -An -tu8 --endian=big -j488 -N32 "$art/document")\n' >> "$sequence"
    fi
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
printf '# oh_source\t%s\n# oh_run_sha256\t%s\n# oh_serve_sha256\t%s\n' "$oh_source" "$oh_run_sha" "$oh_serve_sha" > "$E/metadata.tsv"
cat "$E/summary.tsv" >> "$E/metadata.tsv"
mv "$E/metadata.tsv" "$E/summary.tsv"
printf 'case\texpected_refusal\tobserved_exit\n' > "$E/pin-refusals.tsv"
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
case_run done-reject-resulted done_negative resulted '101 1 3 1 1 0 0 0'
case_run done-reject-missing done_negative missing '100 1 1 0'
case_run done-reject-duplicate done_negative duplicate $'101 1 4 1 1 0 0 0\n101 1 4 1 1 0 0 0'
case_run result-conflict conflicting_result
case_run multiple-corrects multiple_corrects
case_run history-257 history 257
case_run history-1000 history 1000
case_run correct-after-result correct_after_result
case_run kernel-capacity-boundaries capacity_boundaries
case_run happy happy
for boundary in persisted dispatched published resulted; do case_run "crash-$boundary" crash "$boundary"; done
case_run crash-worker-admitted worker_crash
case_run crash-worker-done worker_crash done
case_run stale stale
case_run stale-restored-operand generation_probe
case_run altered altered
case_run signed-wrong-output wrong_output
case_run duplicate duplicate
case_run attestation-signature attestation_signature
case_run substitute-operand operand_substitution
case_run substitute-objective objective_substitution
case_run substitute-pre-correct pin_substitution after-correct
if test "$failures" != 0; then
  cat "$E/summary.tsv"
  echo 'mutants NOT_RUN: baseline cases must all pass'
  exit 1
fi
printf 'mutant\tverdict\tprobe_exit\n' > "$E/mutants.tsv"
case_run mutant-persist mutant persist persist-before-dispatch persist_probe
case_run mutant-check mutant check check-before-ingest attestation_signature
case_run mutant-generation mutant generation generation-match generation_probe
case_run mutant-result-conflict omega_mutant conflict result-conflict conflicting_result
case_run mutant-first-correct omega_mutant first-correct latest-correct multiple_corrects
case_run mutant-doc-objective mutant doc-objective objective-pin objective_substitution
case_run mutant-doc-operand mutant doc-operand operand-pin operand_substitution
cat "$E/summary.tsv" "$E/mutants.tsv"
printf 'M1 cases=%s failures=%s evidence=%s\n' "$checks" "$failures" "$E"
test "$failures" = 0
