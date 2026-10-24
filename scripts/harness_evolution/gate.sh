#!/usr/bin/env bash
set -euo pipefail

repo=$(cd "$(dirname "$0")/../.." && pwd)
: "${OMEGA_WORKTREE:?Set OMEGA_WORKTREE to the isolated seeded-Omega compiler worktree}"
: "${SA_SEED_REPO:?Set SA_SEED_REPO to a clone containing the pinned committed seed}"

omega_pin=c434565c67552c0b01df2d7f76c1a04287c70560
compiler_pin=191b776ef98821597c3e30655da6d680a9b66edbc9ceaca3c39c61ea6df098e9
seed_source_pin=8608fa11f6a2cf1c50db22d871eef16b00d5bc719bc1a222cc3e456984ac5ebf
recursion_pin=f73660bee1b3c93fe737d4cd2a7f9609cd8da7e0c5cb0479c1cbe4e511121558

actual_omega=$(git -C "$OMEGA_WORKTREE" rev-parse HEAD)
test "$actual_omega" = "$omega_pin"
SA_SEED_REPO="$SA_SEED_REPO" make -C "$OMEGA_WORKTREE" test-source-aware
(cd "$OMEGA_WORKTREE" && SA_SEED_REPO="$SA_SEED_REPO" bash tests/universal/recursion/replay.sh)

compiler="$OMEGA_WORKTREE/build/L574/toolchain/build/bootstrap/omc"
verify_elf="$OMEGA_WORKTREE/build/L574/toolchain/tools/verify-elf.sh"
recursion="$OMEGA_WORKTREE/src/source-aware/recursion-v2.om"
test "$(sha256sum "$compiler" | cut -d' ' -f1)" = "$compiler_pin"
test "$(sha256sum "$OMEGA_WORKTREE/build/L574/toolchain/seed/omc/omc.om" | cut -d' ' -f1)" = "$seed_source_pin"
test "$(sha256sum "$recursion" | cut -d' ' -f1)" = "$recursion_pin"

run_root=${HE_RUN_ROOT:-"$repo/evidence/harness-evolution"}
mkdir -p "$run_root"
run_dir=$(mktemp -d "$run_root/offline-$(date -u +%Y%m%dT%H%M%SZ)-XXXXXX")
stage=compile
gate_exit=NOT_RUN
last_mutant_exit=NOT_RUN
finish() {
  local exit_status=$?
  if test "$exit_status" -ne 0 && test ! -f "$run_dir/receipt.json"; then
    local verdict=INCONCLUSIVE
    if test -f "$run_dir/test.stdout"; then verdict=FAIL; fi
    local binary_sha=NOT_BUILT
    if test -f "$run_dir/program"; then binary_sha=$(sha256sum "$run_dir/program" | cut -d' ' -f1); fi
    cat > "$run_dir/receipt.json" <<EOF
{
  "schema": "aien.allen.harness-evolution.native-kernel-run/1",
  "verdict": "$verdict",
  "stage": "$stage",
  "signed": false,
  "allen_source_commit": "$(git -C "$repo" rev-parse HEAD)",
  "omega_source_commit": "$actual_omega",
  "compiler_sha256": "$compiler_pin",
  "compiler_seed_source_sha256": "$seed_source_pin",
  "bounded_recursion_source_sha256": "$recursion_pin",
  "decision_source_sha256": "$(sha256sum "$repo/src/harness_evolution/decision.om" | cut -d' ' -f1)",
  "fixture_source_sha256": "$(sha256sum "$repo/tests/harness_evolution/decision_gate.om" | cut -d' ' -f1)",
  "executable_sha256": "$binary_sha",
  "script_exit": $exit_status,
  "gate_exit": "$gate_exit",
  "last_mutant_exit": "$last_mutant_exit",
  "evidence_files": ["compile.stderr", "test.stdout", "test.stderr", "mutant-compile.stderr", "mutant-policy-effect.stdout", "mutant-policy-effect.stderr"],
  "model_inference": "NOT_RUN",
  "gpu_or_physical_qualification": "NOT_RUN",
  "deployment": "OFF"
}
EOF
  fi
  rm -f "$run_dir/program.om" "$run_dir/program" "$run_dir/mutant.om" "$run_dir/mutant"
}
trap finish EXIT

cat "$recursion" "$repo/src/harness_evolution/decision.om" \
  "$repo/tests/harness_evolution/decision_gate.om" > "$run_dir/program.om"
if ! "$compiler" < "$run_dir/program.om" > "$run_dir/program" 2> "$run_dir/compile.stderr"; then
  echo 'seeded .om compile failed' >&2
  exit 1
fi
stage=elf_verification
sh "$verify_elf" "$run_dir/program"
chmod +x "$run_dir/program"
stage=native_execution
set +e
"$run_dir/program" > "$run_dir/test.stdout" 2> "$run_dir/test.stderr"
gate_exit=$?
set -e
if test "$gate_exit" -ne 0; then
  echo "decision gate failed with exit $gate_exit" >&2
  exit "$gate_exit"
fi
stage=mutation_controls

run_mutation() {
  local name=$1 from=$2 to=$3 expected=$4
  stage="mutation-$name"
  local count
  count=$(grep -F -c "$from" "$repo/src/harness_evolution/decision.om")
  test "$count" -eq 1
  sed "s|$from|$to|" "$repo/src/harness_evolution/decision.om" > "$run_dir/mutant.om"
  cat "$recursion" "$run_dir/mutant.om" "$repo/tests/harness_evolution/decision_gate.om" > "$run_dir/program.om"
  if ! "$compiler" < "$run_dir/program.om" > "$run_dir/mutant" 2> "$run_dir/mutant-compile.stderr"; then
    echo "mutant $name did not compile; control is inconclusive" >&2
    exit 1
  fi
  sh "$verify_elf" "$run_dir/mutant"
  chmod +x "$run_dir/mutant"
  set +e
  "$run_dir/mutant" > "$run_dir/mutant-$name.stdout" 2> "$run_dir/mutant-$name.stderr"
  local mutant_exit=$?
  set -e
  last_mutant_exit=$mutant_exit
  test "$mutant_exit" -eq "$expected"
  printf '%s\tcompiled\t%s\tCAUGHT\n' "$name" "$mutant_exit" >> "$run_dir/mutations.tsv"
}

run_mutation policy-effect \
  'if ne get Obs add at 10 0' 'if gt get Obs add at 10 1' 8
run_mutation missing-cap \
  'if eq get Lim 21 0' 'if eq get Lim 21 2' 13
run_mutation protected-scope \
  'if or eq id base_id or eq scope 0 gt scope 3' 'if eq id base_id' 29

stage=receipt
compiler_sha=$(sha256sum "$compiler" | cut -d' ' -f1)
seed_source_sha=$(sha256sum "$OMEGA_WORKTREE/build/L574/toolchain/seed/omc/omc.om" | cut -d' ' -f1)
recursion_sha=$(sha256sum "$recursion" | cut -d' ' -f1)
decision_sha=$(sha256sum "$repo/src/harness_evolution/decision.om" | cut -d' ' -f1)
fixture_sha=$(sha256sum "$repo/tests/harness_evolution/decision_gate.om" | cut -d' ' -f1)
binary_sha=$(sha256sum "$run_dir/program" | cut -d' ' -f1)
allen_sha=$(git -C "$repo" rev-parse HEAD)
omega_sha=$(git -C "$OMEGA_WORKTREE" rev-parse HEAD)
machine=$(uname -smr)

cat > "$run_dir/receipt.json" <<EOF
{
  "schema": "aien.allen.harness-evolution.native-kernel-run/1",
  "verdict": "PASS",
  "scope": "seeded .om candidate validation and independently verified selection kernel only",
  "signed": false,
  "allen_source_commit": "$allen_sha",
  "omega_source_commit": "$omega_sha",
  "compiler_sha256": "$compiler_sha",
  "compiler_seed_source_sha256": "$seed_source_sha",
  "bounded_recursion_source_sha256": "$recursion_sha",
  "decision_source_sha256": "$decision_sha",
  "gate_script_sha256": "$(sha256sum "$repo/scripts/harness_evolution/gate.sh" | cut -d' ' -f1)",
  "fixture_source_sha256": "$fixture_sha",
  "executable_sha256": "$binary_sha",
  "host": "$machine",
  "compile_exit": 0,
  "elf_verification_exit": 0,
  "execution_exit": $gate_exit,
  "source_aware_gate_exit": 0,
  "bounded_recursion_gate_exit": 0,
  "execution_stdout_sha256": "$(sha256sum "$run_dir/test.stdout" | cut -d' ' -f1)",
  "execution_stderr_sha256": "$(sha256sum "$run_dir/test.stderr" | cut -d' ' -f1)",
  "mutation_log_sha256": "$(sha256sum "$run_dir/mutations.tsv" | cut -d' ' -f1)",
  "mutation_controls": [
    {"name":"policy-effect","compiled":true,"expected_exit":8,"caught":true},
    {"name":"missing-cap","compiled":true,"expected_exit":13,"caught":true},
    {"name":"protected-scope","compiled":true,"expected_exit":29,"caught":true}
  ],
  "model_inference": "NOT_RUN",
  "gpu_or_physical_qualification": "NOT_RUN",
  "core_worker_admission": "NOT_RUN",
  "cortex_lesson_write_and_restart": "NOT_RUN",
  "four_arm_evaluation": "NOT_RUN",
  "deployment": "OFF"
}
EOF
stage=complete
printf 'PASS %s\n' "$run_dir/receipt.json"
