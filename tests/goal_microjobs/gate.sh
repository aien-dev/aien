#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-or-later
# Allen #13 offline gate: build the seeded .om microjob kernel, drive a 12-node objective
# through the persistent journal in separate processes (restart, partial completion,
# model failure, correction, refusal, cancellation, budgets), refuse plan and event
# mutants, then show that source mutations of the kernel are caught by the probes.
# Workers and verifiers below are synthetic fixtures: no model is called, nothing leaves
# the run directory. Usage: OMEGA_WORKTREE=... bash tests/goal_microjobs/gate.sh
set -euo pipefail

repo=$(cd "$(dirname "$0")/../.." && pwd)
: "${OMEGA_WORKTREE:?Set OMEGA_WORKTREE to the isolated seeded-Omega compiler worktree}"
run_root=${GM_RUN_ROOT:-"$repo/evidence/goal-microjobs"}
mkdir -p "$run_root"
run=$(mktemp -d "$run_root/offline-$(date -u +%Y%m%dT%H%M%SZ)-XXXXXX")
work=$(mktemp -d "${TMPDIR:-/tmp}/allen-gm-XXXXXX")
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/probes"
log="$run/transcript.log"
: > "$log"

drv="$repo/scripts/goal_microjobs/microjobs.sh"
export GM_KERNEL="$work/kernel"
bash "$repo/scripts/goal_microjobs/build.sh" "$repo/src/goal_microjobs/kernel.om" "$GM_KERNEL" >> "$log"

checks=0
die() { echo "FAIL: $*" | tee -a "$log" >&2; exit 1; }
ok() { checks=$((checks + 1)); printf 'ok %d %s\n' "$checks" "$*" >> "$log"; }
dw() { bash "$drv" digest "$1"; }

# identities: owner 7, Allen runtime 9, verifiers 5 (recompute) and 6 (checker),
# workers 20 (native compute), 21 (reflex route), 22 (student route)
OWNER=7 RT=9 V5=5 V6=6 W20=20 W21=21 W22=22

# plan fields after "2 id": kind op route profile effect in out reqin reqout vkind
# verifier rclass maxatt tenant time_ms required d0 d1 d2 d3 ndeps deps...
node() { local id=$1 rest=$2 tag=$3 deps=$4; printf '2 %s %s %s %s\n' "$id" "$rest" "$(dw "operand:$tag")" "$deps"; }
# header: abi objective(4) owner runtime ceiling n terminal maxatt maxmodel maxtok budin budout budtime
HDR_ABI=1 HDR_CEIL=2 HDR_MAXATT=24 HDR_MAXMODEL=8 HDR_MAXTOK=2000 HDR_BUDIN=1000
plan() {
  printf '1 %s %s %s %s %s 12 11 %s %s %s %s 256 20000\n' "$HDR_ABI" "$(dw 'objective:allen13-fixture-weekly-budget-note')" \
    "$OWNER" "$RT" "$HDR_CEIL" "$HDR_MAXATT" "$HDR_MAXMODEL" "$HDR_MAXTOK" "$HDR_BUDIN"
  node 1 "1 1 0 0 1 0 0 0 0 1 5 2 2 7 100 1" n1 "0"
  node 2 "1 3 0 0 1 0 0 0 0 1 5 2 2 7 100 1" n2 "0"
  node 3 "1 1 0 0 1 0 0 0 0 1 5 2 2 7 100 1" n3-v1 "0"
  node 4 "2 1 1 1 0 60 12 40 8 2 6 2 3 7 2000 1" n4 "0"
  node 5 "2 2 2 2 0 120 30 100 20 2 6 2 3 7 4000 1" n5 "1 4"
  node 6 "2 3 3 4 0 500 120 300 64 3 6 2 2 7 8000 0" n6 "1 4"
  node 7 "1 1 0 0 1 0 0 0 0 1 5 2 2 7 100 1" n7 "3 1 2 3"
  node 8 "1 4 0 0 1 0 0 0 0 1 5 2 2 7 100 1" n8 "2 5 7"
  node 9 "2 4 1 2 0 120 30 90 24 2 6 2 3 7 4000 1" n9 "2 7 8"
  node 10 "1 6 0 0 1 0 0 0 0 1 5 2 2 7 100 1" n10 "2 7 9"
  node 11 "1 3 0 0 1 0 0 0 0 1 5 2 2 7 100 1" n11 "3 8 9 10"
  node 12 "1 3 0 0 2 0 0 0 0 1 5 3 1 7 100 1" n12 "1 11"
}

S=""
z4="0 0 0 0"
# ev TYPE NODE ATTEMPT GEN ISSUER VERDICT "D0 D1 D2 D3" TOK TIME
accept() { local out; out=$(bash "$drv" propose "$S" "$1" "$2" "$3" "$4" "$5" "$6" $7 "$8" "$9") || die "expected ACCEPT for $*: $out"; ok "accept $*"; }
reject() {
  local name=$1 code=$2; shift 2
  local seq=$(( $(wc -l < "$S/journal") + 1 ))
  { cat "$S/plan" "$S/journal"; printf '3 %s %s %s %s %s %s %s %s %s %s\n' "$seq" "$1" "$2" "$3" "$4" "$5" "$6" "$7" "$8" "$9"; } > "$work/probes/$name.in"
  printf '%s\n' "$code" > "$work/probes/$name.code"
  local out rc
  set +e
  out=$(bash "$drv" propose "$S" "$1" "$2" "$3" "$4" "$5" "$6" $7 "$8" "$9")
  rc=$?
  set -e
  test "$rc" -eq "$code" || die "$name: expected reject $code, got $rc ($out)"
  ok "reject $name $code"
}
status() { bash "$drv" status "$S"; }
nodef() { status | awk -v id="$1" -v f="$2" '$1 == 101 && $2 == id { print $f }'; }
objf() { status | awk -v f="$1" '$1 == 100 { print $f }'; }
expect_node() { local got; got=$(nodef "$1" 3)/$(nodef "$1" 4)/$(nodef "$1" 5); test "$got" = "$2" || die "node $1 state/gen/attempts $got, want $2"; ok "node $1 = $2"; }
expect_obj() { local got; got=$(objf 2); test "$got" = "$1" || die "objective status $got, want $1"; ok "objective status $1"; }

# compute worker and an independent recompute verifier (different arithmetic path)
work_value() { echo $(( $1 )); }
verify_value() { expr "$1" "$2" "$3"; }
run_compute() { # node gen attempt expr-for-worker tag
  local n=$1 g=$2 a=$3 val=$4 tag=$5
  accept 1 "$n" "$a" "$g" $W20 0 "$z4" 0 0
  local d; d=$(dw "n$n:$tag:$val")
  accept 2 "$n" "$a" "$g" $W20 0 "$d" 0 3
  accept 3 "$n" "$a" "$g" $V5 1 "$d" 0 0
}

echo '== plan admission and plan mutants' >> "$log"
plan > "$work/plan"
S="$work/state-a"
bash "$drv" init "$S" "$work/plan" >> "$log"
ok "init acceptance plan"
expect_obj 1

plan_mutant() { # name code awk-program
  local name=$1 code=$2 prog=$3 rc
  plan | awk "$prog" > "$work/probes/plan-$name.in"
  printf '%s\n' "$code" > "$work/probes/plan-$name.code"
  set +e
  bash "$drv" init "$work/m-$name" "$work/probes/plan-$name.in" > /dev/null
  rc=$?
  set -e
  test "$rc" -eq "$code" || die "plan mutant $name: expected $code, got $rc"
  test ! -e "$work/m-$name/plan" || die "plan mutant $name left a plan"
  ok "plan mutant $name $code"
}
plan_mutant old-abi 10 'NR == 1 { $2 = 0 } { print }'
plan_mutant cycle 20 '$1 == 2 && $2 == 1 { $NF = "1 7" } { print }'
plan_mutant missing-dep 19 '$1 == 2 && $2 == 12 { $NF = 13 } { print }'
plan_mutant self-dep 19 '$1 == 2 && $2 == 12 { $NF = 12 } { print }'
plan_mutant overlong-unsplittable 15 '$1 == 2 && $2 == 4 { $10 = 70 } { print }'
plan_mutant cap-above-profile 14 '$1 == 2 && $2 == 4 { $8 = 65 } { print }'
plan_mutant compute-with-tokens 14 '$1 == 2 && $2 == 7 { $8 = 1 } { print }'
plan_mutant changed-privacy-owner 17 '$1 == 2 && $2 == 6 { $16 = 8 } { print }'
plan_mutant unauthorized-effect 18 'NR == 1 { $9 = 1 } { print }'
plan_mutant missing-operand 22 '$1 == 2 && $2 == 9 { $19 = 0; $20 = 0; $21 = 0; $22 = 0 } { print }'
plan_mutant missing-verifier 16 '$1 == 2 && $2 == 8 { $13 = 0 } { print }'
plan_mutant never-retry-twice 23 '$1 == 2 && $2 == 12 { $14 = 1; $15 = 2 } { print }'
plan_mutant effect-idempotent-retry 23 '$1 == 2 && $2 == 12 { $14 = 2 } { print }'
plan_mutant over-budget 26 'NR == 1 { $15 = 700 } { print }'
plan_mutant terminal-optional 21 'NR == 1 { $11 = 6 } { print }'
plan_mutant truncated 2 'NR < 13 { print }'
plan_mutant malformed-word 3 '$1 == 2 && $2 == 3 { $3 = "x" } { print }'

echo '== independent microjobs before the join (several running at once)' >> "$log"
accept 1 1 1 1 $W20 0 "$z4" 0 0
accept 1 2 1 1 $W20 0 "$z4" 0 0
reject dispatch-by-verifier 39 1 3 1 1 $V5 0 "$z4" 0 0
reject dispatch-by-owner 39 1 3 1 1 $OWNER 0 "$z4" 0 0
accept 1 3 1 1 $W20 0 "$z4" 0 0
accept 1 4 1 1 $W21 0 "$z4" 0 0
expect_node 4 2/1/1
reject dispatch-before-dependencies 43 1 7 1 1 $W20 0 "$z4" 0 0
v1=$(work_value '120+80+45'); test "$v1" = "$(verify_value 120 + 125)" || die "oracle n1"
d1=$(dw "n1:sum:$v1")
accept 2 1 1 1 $W20 0 "$d1" 0 3
reject compute-result-with-tokens 48 2 2 1 1 $W20 0 "$d1" 1 3
reject self-reported-success 40 3 1 1 1 $W20 1 "$d1" 0 0
reject wrong-verifier 39 3 1 1 1 $V6 1 "$d1" 0 0
reject verifier-digest-mismatch 41 3 1 1 1 $V5 1 "$(dw "n1:sum:999")" 0 0
accept 3 1 1 1 $V5 1 "$d1" 0 0
v2=$(work_value '300+15'); d2=$(dw "n2:reduce:$v2")
accept 2 2 1 1 $W20 0 "$d2" 0 2
accept 3 2 1 1 $V5 1 "$d2" 0 0
v3=$(work_value '12*7'); test "$v3" = "$(verify_value 12 '*' 7)" || die "oracle n3"
d3=$(dw "n3:arith:$v3")
accept 2 3 1 1 $W20 0 "$d3" 0 2
accept 3 3 1 1 $V5 1 "$d3" 0 0
d4=$(dw "n4:route:budget-note")
reject result-over-token-contract 42 2 4 1 1 $W21 0 "$d4" 73 900
reject result-by-other-worker 39 2 4 1 1 $W22 0 "$d4" 50 900
accept 2 4 1 1 $W21 0 "$d4" 50 900
accept 3 4 1 1 $V6 1 "$d4" 0 0
echo '== refusal: optional teacher route has no current qualification' >> "$log"
accept 7 6 0 1 $RT 0 "$z4" 0 0
expect_node 6 7/1/0

echo '== model failure then bounded retry' >> "$log"
accept 1 5 1 1 $W22 0 "$z4" 0 0
accept 4 5 1 1 $W22 0 "$z4" 40 4000
expect_node 5 1/1/1
reject retry-reuses-attempt 35 1 5 1 1 $W22 0 "$z4" 0 0
accept 1 5 2 1 $W22 0 "$z4" 0 0
d5=$(dw "n5:extract:limit=700")
accept 2 5 2 1 $W22 0 "$d5" 110 2500
accept 3 5 2 1 $V6 1 "$d5" 0 0
expect_node 5 4/1/2

echo '== join' >> "$log"
v7=$(work_value "$v1+$v2+$v3"); test "$v7" = "$(verify_value "$v1" + "$(verify_value "$v2" + "$v3")")" || die "oracle n7"
run_compute 7 1 1 "$v7" join
run_compute 8 1 1 "$(work_value "$v7 <= 700")" compare
accept 1 9 1 1 $W21 0 "$z4" 0 0

echo '== partial completion: process stops with a live lease; restart replays exact state' >> "$log"
status > "$run/partial-1.status"
# Interrupt a real writer with SIGKILL after the kernel admitted its event but before the
# atomic rename: nothing may be committed, the lock must be released, replay must match.
cat > "$work/slow-kernel" <<EOF
#!/usr/bin/env bash
"$work/kernel"
rc=\$?
sleep 30
exit \$rc
EOF
chmod 700 "$work/slow-kernel"
jsha=$(sha256sum < "$S/journal")
GM_KERNEL="$work/slow-kernel" setsid bash "$drv" propose "$S" 4 9 1 1 $RT 0 $z4 0 0 > /dev/null 2>&1 &
wpid=$!
for _ in $(seq 200); do pgrep -s "$wpid" -x sleep > /dev/null && break; sleep 0.05; done
pgrep -s "$wpid" -x sleep > /dev/null || die "interrupted writer never reached its commit window"
kill -KILL -- -"$wpid"
wait "$wpid" 2> /dev/null || true
test -f "$S/journal.cand" || die "interrupted writer left no candidate"
test "$(sha256sum < "$S/journal")" = "$jsha" || die "SIGKILL before rename changed the journal"
ok "SIGKILL inside the commit window left the journal unchanged"
status > "$run/partial-2.status"
cmp -s "$run/partial-1.status" "$run/partial-2.status" || die "replay after restart differs"
ok "restart replay byte-identical ($(sha256sum < "$run/partial-1.status" | cut -c1-16))"
expect_node 9 2/1/1
expect_obj 1
accept 4 9 1 1 $RT 0 "$z4" 0 0
d9late=$(dw "n9:summarize:late")
reject duplicate-result-after-restart 33 2 9 1 1 $W21 0 "$d9late" 20 100
accept 1 9 2 1 $W21 0 "$z4" 0 0
d9bad=$(dw "n9:summarize:total 640")
accept 2 9 2 1 $W21 0 "$d9bad" 120 1800
accept 3 9 2 1 $V6 0 "$d9bad" 0 0
expect_node 9 1/1/2
accept 1 9 3 1 $W21 0 "$z4" 0 0
d9=$(dw "n9:summarize:total $v7 within 700")
accept 2 9 3 1 $W21 0 "$d9" 118 1700
reject result-twice 33 2 9 3 1 $W21 0 "$d9" 118 1700
accept 3 9 3 1 $V6 1 "$d9" 0 0
expect_node 9 4/1/3

echo '== human correction invalidates exactly the affected nodes' >> "$log"
reject correction-by-non-owner 39 6 3 0 1 $RT 0 "$(dw operand:n3-v2)" 0 0
reject correction-same-operand 46 6 3 0 1 $OWNER 0 "$(dw operand:n3-v1)" 0 0
reject correction-stale-generation 34 6 3 0 2 $OWNER 0 "$(dw operand:n3-v2)" 0 0
accept 6 3 0 1 $OWNER 0 "$(dw operand:n3-v2)" 0 0
for n in 1 2 4 5; do test "$(nodef $n 3)/$(nodef $n 4)" = "4/1" || die "unaffected node $n changed"; done
ok "unaffected nodes 1 2 4 5 stay DONE at generation 1"
expect_node 6 7/1/0
for n in 3 7 8 9 10 11 12; do test "$(nodef $n 3)/$(nodef $n 4)/$(nodef $n 5)" = "1/2/0" || die "affected node $n not reset"; done
ok "affected nodes 3 7 8 9 10 11 12 reset to generation 2"
reject stale-generation-dispatch 34 1 3 1 1 $W20 0 "$z4" 0 0

v3=$(work_value '12*9'); test "$v3" = "$(verify_value 12 '*' 9)" || die "oracle n3 v2"
run_compute 3 2 1 "$v3" arith
v7=$(work_value "$v1+$v2+$v3"); test "$v7" = "$(verify_value "$v1" + "$(verify_value "$v2" + "$v3")")" || die "oracle n7 v2"
run_compute 7 2 1 "$v7" join
run_compute 8 2 1 "$(work_value "$v7 <= 700")" compare
accept 1 9 1 2 $W21 0 "$z4" 0 0
d9=$(dw "n9:summarize:total $v7 within 700")
accept 2 9 1 2 $W21 0 "$d9" 116 1600
accept 3 9 1 2 $V6 1 "$d9" 0 0
run_compute 10 2 1 1 verify
run_compute 11 2 1 "$v7" "note-ok"
reject effect-before-done 44 8 12 0 2 $RT 0 "$(dw effect:n12:g2)" 0 0
run_compute 12 2 1 "$v7" publish
reject effect-on-non-effect-node 44 8 11 0 2 $RT 0 "$(dw effect:n11:g2)" 0 0
reject effect-by-worker 39 8 12 0 2 $W20 0 "$(dw effect:n12:g2)" 0 0
expect_obj 1
accept 8 12 0 2 $RT 0 "$(dw effect:n12:g2)" 0 0
reject duplicate-effect 45 8 12 0 2 $RT 0 "$(dw effect:n12:g2)" 0 0
expect_obj 2
# status words: 100 status nodes done attempts model_calls tokens_reserved last_seq time_ms
# cancelled tokens_used. Expected totals recomputed independently (docs/GOAL_MICROJOBS.md).
totals=$(awk '$1 == 100' <(status))
test "$totals" = "100 2 12 11 18 7 972 55 12531 0 554" || die "objective totals $totals"
ok "objective totals: 18 attempts, 7 model calls, 972 tokens reserved, 554 used, 12531 ms"
status > "$run/acceptance.status"
receipt=$(awk '$1 == 103' "$run/acceptance.status")
want="103 $(dw 'objective:allen13-fixture-weekly-budget-note') $(dw "n11:note-ok:$v7") 2 $(wc -l < "$S/journal")"
test "$receipt" = "$want" || die "objective receipt $receipt, want $want"
ok "terminal receipt binds objective digest and verified terminal result n11:note-ok:$v7"
cp "$S/journal" "$run/acceptance.journal"
cp "$S/plan" "$run/acceptance.plan"

echo '== event wire refusals (driven directly, the driver never writes these)' >> "$log"
wire() { # name code line
  local name=$1 code=$2 line=$3 rc
  { cat "$S/plan" "$S/journal"; printf '%s\n' "$line"; } > "$work/probes/$name.in"
  printf '%s\n' "$code" > "$work/probes/$name.code"
  set +e; "$GM_KERNEL" < "$work/probes/$name.in" > /dev/null; rc=$?; set -e
  test "$rc" -eq "$code" || die "$name: expected $code, got $rc"
  ok "wire $name $code"
}
next=$(( $(wc -l < "$S/journal") + 1 ))
wire seq-gap 30 "3 $((next + 1)) 1 1 1 1 $W20 0 $z4 0 0"
wire unknown-event-type 32 "3 $next 9 1 1 1 $W20 0 $z4 0 0"
wire unknown-node 31 "3 $next 1 13 1 1 $W20 0 $z4 0 0"
wire truncated-event 2 "3 $next 1 1"

echo '== budgets stop model-call storms' >> "$log"
HDR_MAXMODEL=2 plan > "$work/plan-b"
S="$work/state-b"
bash "$drv" init "$S" "$work/plan-b" >> "$log"
accept 1 4 1 1 $W21 0 "$z4" 0 0
accept 4 4 1 1 $W21 0 "$z4" 70 2000
accept 1 4 2 1 $W21 0 "$z4" 0 0
accept 4 4 2 1 $W21 0 "$z4" 70 2000
reject model-call-budget 37 1 4 3 1 $W21 0 "$z4" 0 0
test "$(nodef 4 7)" = 0 || die "unfundable node reported ready"
ok "unfundable model node is not offered as ready"
HDR_MAXTOK=100 plan > "$work/plan-c"
S="$work/state-c"
bash "$drv" init "$S" "$work/plan-c" >> "$log"
accept 1 4 1 1 $W21 0 "$z4" 0 0
accept 2 4 1 1 $W21 0 "$d4" 50 900
accept 3 4 1 1 $V6 1 "$d4" 0 0
reject token-budget 38 1 5 1 1 $W22 0 "$z4" 0 0
S="$work/state-d"
bash "$drv" init "$S" "$work/plan" >> "$log"
for a in 1 2 3; do accept 1 4 "$a" 1 $W21 0 "$z4" 0 0; accept 4 4 "$a" 1 $W21 0 "$z4" 10 2000; done
expect_node 4 5/1/3
reject attempts-exhausted 33 1 4 4 1 $W21 0 "$z4" 0 0
expect_obj 3
test "$(nodef 5 6)/$(nodef 9 6)/$(nodef 12 6)" = "1/1/1" || die "dependents of failed node not blocked"
ok "dependents of the exhausted model node are blocked"

echo '== cancellation' >> "$log"
S="$work/state-e"
bash "$drv" init "$S" "$work/plan" >> "$log"
accept 1 1 1 1 $W20 0 "$z4" 0 0
accept 1 4 1 1 $W21 0 "$z4" 0 0
reject cancel-by-non-owner 39 5 7 0 0 $W20 0 "$z4" 0 0
accept 5 4 0 0 $OWNER 0 "$z4" 0 0
for n in 4 5 6 8 9 10 11 12; do test "$(nodef $n 3)" = 6 || die "node $n not cancelled"; done
ok "cancel of node 4 cancels exactly 4 and its dependents 5 6 8 9 10 11 12"
reject late-result-after-cancel 33 2 4 1 1 $W21 0 "$d4" 50 900
accept 2 1 1 1 $W20 0 "$d1" 0 3
accept 3 1 1 1 $V5 1 "$d1" 0 0
expect_node 1 4/1/1
expect_obj 5
accept 5 0 0 0 $OWNER 0 "$z4" 0 0
expect_obj 4
reject dispatch-after-objective-cancel 47 1 2 1 1 $W20 0 "$z4" 0 0
reject cancel-twice 47 5 0 0 0 $OWNER 0 "$z4" 0 0

echo '== source mutation controls' >> "$log"
: > "$run/mutations.tsv"
mutate() { # name from to probe
  local name=$1 from=$2 to=$3 probe=$4 count rc want
  count=$(grep -F -x -c "$from" "$repo/src/goal_microjobs/kernel.om")
  test "$count" -eq 1 || die "mutation $name anchor occurs $count times"
  awk -v f="$from" -v t="$to" '$0 == f { print t; next } { print }' "$repo/src/goal_microjobs/kernel.om" > "$work/mutant.om"
  bash "$repo/scripts/goal_microjobs/build.sh" "$work/mutant.om" "$work/mutant" > /dev/null || die "mutant $name did not compile"
  want=$(cat "$work/probes/$probe.code")
  set +e; "$work/mutant" < "$work/probes/$probe.in" > /dev/null; rc=$?; set -e
  test "$rc" -ne "$want" || die "mutant $name survived probe $probe"
  printf '%s\t%s\t%s\t%s\tCAUGHT\n' "$name" "$probe" "$want" "$rc" >> "$run/mutations.tsv"
  ok "mutant $name caught by $probe ($want -> $rc)"
}
mutate verifier-identity 'if ne ev 4 nd i 10' 'if eq ev 4 0' wrong-verifier
mutate self-verification 'if eq ev 4 sg i 4' 'if eq ev 4 0' self-reported-success
mutate dependency-gate 'fail 43' 'put Tot 7 0' dispatch-before-dependencies
mutate generation-bump 'ss j 1 add sg j 1 1' 'ss j 1 sg j 1' stale-generation-dispatch
mutate duplicate-effect 'if eq sg i 9 sg i 1' 'if eq sg i 9 99' duplicate-effect
mutate model-budget 'fail 37' 'put Tot 7 0' model-call-budget
mutate objective-cancel 'put Tot 5 1' 'put Tot 7 1' cancel-twice
mutate cycle-check 'fail 20' 'put Tot 7 0' plan-cycle
mutate privacy-owner 'fail 17' 'put Tot 7 0' plan-changed-privacy-owner

echo '== receipt' >> "$log"
sha() { sha256sum "$1" | cut -d' ' -f1; }
cat > "$run/receipt.json" <<EOF
{
  "schema": "aien.allen.goal-microjobs.offline-gate/1",
  "verdict": "PASS",
  "scope": "seeded .om admission and journal replay kernel; synthetic fixture workers and verifiers; local journal, not Cortex",
  "signed": false,
  "allen_source_commit": "$(git -C "$repo" rev-parse HEAD)",
  "allen_tree_dirty": $(if test -n "$(git -C "$repo" status --porcelain -- src scripts tests)"; then echo true; else echo false; fi),
  "omega_source_commit": "$(git -C "$OMEGA_WORKTREE" rev-parse HEAD)",
  "compiler_sha256": "$(sha "$OMEGA_WORKTREE/build/L574/toolchain/build/bootstrap/omc")",
  "kernel_source_sha256": "$(sha "$repo/src/goal_microjobs/kernel.om")",
  "kernel_executable_sha256": "$(sha "$GM_KERNEL")",
  "driver_sha256": "$(sha "$drv")",
  "gate_sha256": "$(sha "$repo/tests/goal_microjobs/gate.sh")",
  "acceptance_journal_sha256": "$(sha "$run/acceptance.journal")",
  "acceptance_status_sha256": "$(sha "$run/acceptance.status")",
  "mutation_log_sha256": "$(sha "$run/mutations.tsv")",
  "host": "$(uname -smr)",
  "checks_passed": $checks,
  "mutants_caught": $(wc -l < "$run/mutations.tsv"),
  "model_inference": "NOT_RUN",
  "omega_or_core_dispatch": "NOT_RUN",
  "cortex_write_and_restart": "NOT_RUN",
  "canonical_mjb1_binary_abi": "NOT_RUN",
  "routing_comparison": "NOT_RUN",
  "gpu_or_physical_qualification": "NOT_RUN",
  "deployment": "OFF"
}
EOF
printf 'PASS %s checks=%d\n' "$run/receipt.json" "$checks" | tee -a "$log"
