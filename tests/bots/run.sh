#!/bin/bash
# Harness/oracle only. Production logic remains in src/bots/bots.om.
set -eu
set -o pipefail
HERE=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
hex() { printf '%064x' "$1"; }
K=$(hex 1); L=$(hex 2); R=$(hex 3); W=$(hex 4); H=$(hex 5); V=$(hex 6); Z=$(hex 0)
fail() { echo "FAIL $*"; exit 1; }
pass() { echo "PASS $*"; }
probe_result() {
 # A separate receipt preserves the binary status even though the assertion child exits 1.
 if [ -n "${PROBE_META:-}" ]; then
  printf '%s\t%s\t%s\n' "$1" "$2" "$3" > "$PROBE_META"
 fi
}
probe_state_fail() {
 probe_result 0 0 KILLED_STATE
 fail "$*"
}
classify_status() {
 local expected=$1 actual=$2
 if ((actual>=101 && actual<=114)); then echo TRAPPED
 elif ((actual>128 && actual<=192)); then echo SIGNALLED
 elif [ "$actual" = 0 ] && [ "$expected" != 0 ]; then echo KILLED_ADMIT
 elif ((actual>=2 && actual<=19)) && [ "$(cat "$T/out")" = "REFUSE $actual" ]; then echo KILLED_CODE
 else echo ERROR
 fi
}
invoke() {
 local expected=$1; shift
 set +e
 "$@" > "$T/out" 2> "$T/err"
 local rc=$?
 set -e
 probe_result "$expected" "$rc" SURVIVED
 if [ "$rc" != "$expected" ]; then
  probe_result "$expected" "$rc" "$(classify_status "$expected" "$rc")"
  cat "$T/out" "$T/err"
  fail "expected=$expected observed=$rc command=$*"
 fi
 if [ "$expected" -ge 2 ] && [ "$expected" -le 19 ]; then
  if [ "$(cat "$T/out")" != "REFUSE $expected" ]; then
   probe_result "$expected" "$rc" KILLED_OUTPUT
   fail "refusal output $*"
  fi
 fi
 pass "rc=$rc $*"
}
patch() { # fixture modification, not runtime implementation
 printf '%s' "$3" | xxd -r -p | dd of="$1" bs=1 seek="$2" conv=notrunc status=none
}
seal() {
 local h
 h=$(dd if="$1" bs=1 count=992 status=none | sha256sum | cut -c1-64)
 patch "$1" 992 "$h"
}
record() {
 dd if="$1" of="$2" bs=1024 skip="$3" count=1 status=none
}
sequence() { patch "$1" 8 "$(printf '%016x' "$2")"; seal "$1"; }
fixture_probe() {
 local g=$1; B=$2; F=$3
 T=$(mktemp -d "$4/probe-$g-XXXXXX")
 local j=$T/j
 case "$g" in
 hex) invoke 2 "$B" rotate "$j" "${K}0" "$W";;
 nonzero) invoke 4 "$B" rotate "$j" "$Z" "$W";;
 refs) invoke 2 "$B" register "$j" "$K" "$L" "$R" Allen bad - -;;
 name) invoke 2 "$B" register "$j" "$K" "$L" "$R" '' - - -;;
 current) cp "$F/stale" "$j"; invoke 15 "$B" ack "$j" "$ID" "$MID" "$W";;
 registered) cp "$F/base" "$j"; invoke 10 "$B" register "$j" "$K" "$L" "$R" Allen "$K,$L" "$R" "$H";;
 botcap) cp "$F/botcap" "$j"; invoke 5 "$B" register "$j" "$(hex 999)" "$L" "$R" Extra - - -;;
 leaseunique) cp "$F/lease" "$j"; invoke 13 "$B" rotate "$j" "$ID" "$W";;
 dedup) cp "$F/acked" "$j"; cp "$j" "$T/before"; invoke 0 "$B" deliver "$j" "$ID" "$K" hello "$H"; [ "$(cat "$T/out")" = "DUPLICATE $MID" ] || probe_state_fail duplicate-output; cmp "$j" "$T/before" || probe_state_fail duplicate-append; pass duplicate-no-append;;
 msgcap) cp "$F/msgcap" "$j"; invoke 5 "$B" deliver "$j" "$ID" "$K" overflow "$H";;
 pending) cp "$F/acked" "$j"; invoke 16 "$B" claim "$j" "$ID" "$MID" "$V";;
 claimed) cp "$F/acked" "$j"; invoke 17 "$B" ack "$j" "$ID" "$MID" "$V";;
 claimant) cp "$F/claimed" "$j"; invoke 18 "$B" ack "$j" "$ID" "$MID" "$V";;
 expiry) cp "$F/claimed" "$j"; invoke 19 "$B" expire "$j" "$ID" "$MID" "$W";;
 active) cp "$F/retired" "$j"; invoke 12 "$B" deliver "$j" "$ID" "$K" hello "$H";;
 type) cp "$F/type" "$j"; invoke 6 "$B" show "$j";;
 magic) cp "$F/magic" "$j"; invoke 6 "$B" show "$j";;
 botvalue) cp "$F/botvalue" "$j"; invoke 6 "$B" show "$j";;
 reserved) cp "$F/reserved" "$j"; invoke 6 "$B" show "$j";;
 bindings) cp "$F/bindings" "$j"; invoke 6 "$B" show "$j";;
 identity) cp "$F/identity" "$j"; invoke 6 "$B" show "$j";;
 display) cp "$F/display" "$j"; invoke 6 "$B" show "$j";;
 nonempty) cp "$F/nonempty" "$j"; invoke 6 "$B" show "$j";;
 leasevalue) cp "$F/leasevalue" "$j"; invoke 6 "$B" show "$j";;
 envelope) cp "$F/envelope" "$j"; invoke 6 "$B" show "$j";;
 content) cp "$F/content" "$j"; invoke 6 "$B" show "$j";;
 transition) cp "$F/transition" "$j"; invoke 6 "$B" show "$j";;
 padding) cp "$F/padding" "$j"; invoke 6 "$B" show "$j";;
 sequence) cp "$F/sequence" "$j"; invoke 7 "$B" show "$j";;
 checksum) cp "$F/checksum" "$j"; invoke 8 "$B" show "$j";;
 lock) cp "$F/base" "$j"; exec 8>"$j.lock"; flock -x 8; invoke 9 "$B" show "$j"; flock -u 8; exec 8>&-;;
 alignment) dd if="$F/base" of="$j" bs=1 count=1000 status=none; invoke 6 "$B" show "$j";;
 eventcap) cp "$F/eventcap" "$j"; invoke 5 "$B" nack "$j" "$ID" "$MID" "$W";;
 *) fail "unknown probe $g";;
 esac
}
barrier_probe() {
 B=$1
 T=$(mktemp -d "$2/barrier-XXXXXX")
 local j=$T/j trace=$T/commit.strace line fd kind events=''
 declare -A kinds=()
 if ! command -v strace >/dev/null; then
  echo 'NOT_RUN commit barriers: strace unavailable'
  probe_result 0 NA ERROR
  fail 'strace required'
 fi
 invoke 0 strace -qq -s 4096 -o "$trace" -e trace=openat,close,fsync,renameat2 \
  "$B" register "$j" "$K" "$L" "$R" Allen - - -
 while IFS= read -r line; do
  if [[ "$line" == openat* && "$line" =~ =[[:space:]]([0-9]+)$ ]]; then
   fd=${BASH_REMATCH[1]}
   if [[ "$line" == *"\"$j.cand\""* ]]; then kinds[$fd]=candidate
   elif [[ "$line" == *O_DIRECTORY* ]]; then kinds[$fd]=directory
   else kinds[$fd]=other
   fi
  elif [[ "$line" =~ ^fsync\(([0-9]+)\)[[:space:]]*=[[:space:]]0$ ]]; then
   fd=${BASH_REMATCH[1]}; kind=${kinds[$fd]:-unknown}
   events="${events}${kind} "
  elif [[ "$line" == renameat2* && "$line" == *"\"$j.cand\""* && "$line" == *"\"$j\""* && "$line" =~ =[[:space:]]0$ ]]; then
   events="${events}rename "
  elif [[ "$line" =~ ^close\(([0-9]+)\) ]]; then
   unset "kinds[${BASH_REMATCH[1]}]"
  fi
 done < "$trace"
 printf '%s\n' "$events" > "$T/barriers.txt"
 if [ "$events" != 'candidate rename directory ' ]; then
  probe_result 0 0 KILLED_BARRIER
  fail "commit barriers expected=candidate,rename,directory observed=$events trace=$trace"
 fi
 pass "commit-barrier-order trace=$trace (not power-loss qualification)"
}
if [ "${1:-}" = --barrier ]; then
 barrier_probe "$2" "$3"
 exit 0
fi
if [ "${1:-}" = --probe ]; then
 ID=$5; MID=$6
 fixture_probe "$2" "$3" "$4" "$7"
 exit 0
fi
: "${BOTS_RUN_ROOT:?set an external BOTS_RUN_ROOT}"
: "${OMEGA_OMC:?set pinned OMEGA_OMC}"
: "${OMEGA_MV:?set OMEGA_MV checkout}"
case "$BOTS_RUN_ROOT" in "$HERE"|"$HERE"/*) fail 'run root must be external';; esac
mkdir -p "$BOTS_RUN_ROOT"
[ ! -e "$BOTS_RUN_ROOT/transcript" ] || fail 'use a fresh run root'
exec > >(tee "$BOTS_RUN_ROOT/transcript") 2>&1
if ! command -v strace >/dev/null; then
 printf 'barriers=NOT_RUN\nreason=strace unavailable\n' > "$BOTS_RUN_ROOT/results.txt"
 fail 'NOT_RUN: strace required for commit-barrier acceptance'
fi
T=$BOTS_RUN_ROOT/work
F=$BOTS_RUN_ROOT/fixtures
mkdir -p "$T" "$F" "$BOTS_RUN_ROOT/mutants"
B=$BOTS_RUN_ROOT/bots
sh "$HERE/scripts/bots/build.sh" "$B" > "$BOTS_RUN_ROOT/build.txt"
sha256sum "$OMEGA_OMC" "$HERE/src/bots/bots.om" "$HERE/scripts/bots/build.sh" "$0" > "$BOTS_RUN_ROOT/sources.sha256"
j=$T/j
invoke 0 "$B" show "$j"
[ ! -s "$T/out" ] || fail empty-show
invoke 0 "$B" register "$j" "$K" "$L" "$R" Allen "$K,$L" "$R" "$H"
ID=${ID:-$(cut -d' ' -f2 "$T/out")}
ORACLE=$({ printf 'AIEN-BOT-V1\0'; printf '%s' "$K$L$R" | xxd -r -p; } | sha256sum | cut -c1-64)
[ "$ID" = "$ORACLE" ] || fail identity-oracle
pass independent-identity-sha256
cp "$j" "$F/base"
invoke 0 "$B" rotate "$j" "$ID" "$W"; cp "$j" "$F/lease"
invoke 0 "$B" deliver "$j" "$ID" "$K" hello "$H"
MID=$(cut -d' ' -f2 "$T/out")
PD=$(printf hello | sha256sum | cut -c1-64)
ORACLE=$({ printf 'AIEN-BOT-MESSAGE-V1\0'; printf '%s' "$ID$K$PD$H" | xxd -r -p; } | sha256sum | cut -c1-64)
[ "$MID" = "$ORACLE" ] || fail message-oracle
pass independent-message-sha256
cp "$j" "$F/pending"
invoke 0 "$B" claim "$j" "$ID" "$MID" "$W"; cp "$j" "$F/claimed"
invoke 0 "$B" nack "$j" "$ID" "$MID" "$W"
invoke 0 "$B" claim "$j" "$ID" "$MID" "$W"
# Keep minimal fixtures to make the exact historical sequence unambiguous.
cp "$F/claimed" "$j"
invoke 0 "$B" rotate "$j" "$ID" "$V"; cp "$j" "$F/stale"
invoke 0 "$B" expire "$j" "$ID" "$MID" "$W"; cp "$j" "$F/expired"
invoke 0 "$B" claim "$j" "$ID" "$MID" "$V"; cp "$j" "$F/claim2"
invoke 0 "$B" ack "$j" "$ID" "$MID" "$V"; cp "$j" "$F/acked"
invoke 0 "$B" retire "$j" "$ID"; cp "$j" "$F/retired"
invoke 0 "$B" show "$j"; cp "$T/out" "$BOTS_RUN_ROOT/final-state.txt"
invoke 0 "$B" show "$j"; cmp "$T/out" "$BOTS_RUN_ROOT/final-state.txt"; pass deterministic-replay
# Typed, rechecksummed adversarial fixtures. The checksum is integrity, not authentication.
for name in magic reserved bindings identity display nonempty padding sequence checksum; do cp "$F/base" "$F/$name"; done
patch "$F/magic" 0 00; seal "$F/magic"
patch "$F/reserved" 5 01; seal "$F/reserved"
patch "$F/identity" 16 "$K"; seal "$F/identity"
patch "$F/display" 144 01; seal "$F/display"
printf '%0128d' 0 | xxd -r -p | dd of="$F/nonempty" bs=1 seek=144 conv=notrunc status=none; seal "$F/nonempty"
patch "$F/padding" 700 01; seal "$F/padding"
sequence "$F/sequence" 2
patch "$F/checksum" 1023 ff
patch "$F/bindings" 48 "$Z"
NEWID=$({ printf 'AIEN-BOT-V1\0'; printf '%s' "$Z$L$R" | xxd -r -p; } | sha256sum | cut -c1-64)
patch "$F/bindings" 16 "$NEWID"; seal "$F/bindings"
record "$F/retired" "$T/rec" 8
patch "$T/rec" 4 09; sequence "$T/rec" 2; cat "$F/base" "$T/rec" > "$F/type"
patch "$T/rec" 4 08; patch "$T/rec" 16 "$Z"; seal "$T/rec"; cat "$F/base" "$T/rec" > "$F/botvalue"
record "$F/lease" "$T/rec" 1; patch "$T/rec" 48 "$Z"; seal "$T/rec"; cat "$F/base" "$T/rec" > "$F/leasevalue"
record "$F/pending" "$T/rec" 2; patch "$T/rec" 48 "$Z"
NEWMID=$({ printf 'AIEN-BOT-MESSAGE-V1\0'; printf '%s' "$ID$Z$PD$H" | xxd -r -p; } | sha256sum | cut -c1-64)
patch "$T/rec" 144 "$NEWMID"; seal "$T/rec"; cat "$F/lease" "$T/rec" > "$F/envelope"
record "$F/pending" "$T/rec" 2; patch "$T/rec" 144 "$K"; seal "$T/rec"; cat "$F/lease" "$T/rec" > "$F/content"
record "$F/claimed" "$T/rec" 3; patch "$T/rec" 80 "$Z"; seal "$T/rec"; cat "$F/pending" "$T/rec" > "$F/transition"
# Capacity fixtures derive valid records with the independent SHA-256 oracle.
: > "$F/botcap"
for ((i=1;i<=64;i++)); do
 cp "$F/base" "$T/rec"; PK=$(hex "$i"); patch "$T/rec" 48 "$PK"
 BI=$({ printf 'AIEN-BOT-V1\0'; printf '%s' "$PK$L$R" | xxd -r -p; } | sha256sum | cut -c1-64)
 patch "$T/rec" 16 "$BI"; sequence "$T/rec" "$i"; cat "$T/rec" >> "$F/botcap"
done
cp "$F/lease" "$F/msgcap"
for ((i=1;i<=256;i++)); do
 record "$F/pending" "$T/rec" 2; HH=$(hex "$i"); patch "$T/rec" 112 "$HH"
 MI=$({ printf 'AIEN-BOT-MESSAGE-V1\0'; printf '%s' "$ID$K$PD$HH" | xxd -r -p; } | sha256sum | cut -c1-64)
 patch "$T/rec" 144 "$MI"; sequence "$T/rec" "$((i+2))"; cat "$T/rec" >> "$F/msgcap"
done
cp "$F/pending" "$F/eventcap"
for ((i=4;i<=1024;i++)); do
 record "$F/claimed" "$T/rec" 3
 if ((i%2)); then patch "$T/rec" 4 06; fi
 sequence "$T/rec" "$i"; cat "$T/rec" >> "$F/eventcap"
done
# Every catalogued state/integrity guard has a baseline refusal and a compiling removal mutant.
GUARDS=$(sed -n 's/^note BOT-GUARD //p' "$HERE/src/bots/bots.om")
for g in $GUARDS; do fixture_probe "$g" "$B" "$F" "$BOTS_RUN_ROOT"; done
T=$BOTS_RUN_ROOT/work
# Other exact refusal surfaces: usage, I/O, missing bot and missing message.
invoke 2 "$B" bogus "$T/unknown"
invoke 2 "$B" register "$T/unknown" "$K" "$L" "$R" $'bad\nname' - - -
invoke 3 "$B" show "$T/absent/j"
cp "$F/lease" "$T/missing"
invoke 11 "$B" rotate "$T/missing" "$K" "$W"
invoke 14 "$B" claim "$T/missing" "$ID" "$K" "$W"
# Final components must not follow symlinks; lock/journal/candidate each independently refused.
for target in lock journal candidate; do
 SJ=$T/symlink-$target
 case "$target" in lock) ln -s "$F/base" "$SJ.lock";; journal) ln -s "$F/base" "$SJ";; candidate) cp "$F/base" "$SJ"; ln -s "$F/base" "$SJ.cand";; esac
 if [ "$target" = candidate ]; then invoke 3 "$B" rotate "$SJ" "$ID" "$W"; else invoke 3 "$B" show "$SJ"; fi
done
# Each typed transition is killed after candidate open, prefix write, event write,
# candidate fsync, rename and directory fsync. Before rename old state; after rename new.
for op in register rotate deliver claim ack nack expire retire; do
 case "$op" in
 register) pre=; args=(register "$K" "$L" "$R" Allen "$K,$L" "$R" "$H");;
 rotate) pre=base; args=(rotate "$ID" "$W");;
 deliver) pre=lease; args=(deliver "$ID" "$K" hello "$H");;
 claim) pre=pending; args=(claim "$ID" "$MID" "$W");;
 ack) pre=claimed; args=(ack "$ID" "$MID" "$W");;
 nack) pre=claimed; args=(nack "$ID" "$MID" "$W");;
 expire) pre=stale; args=(expire "$ID" "$MID" "$W");;
 retire) pre=base; args=(retire "$ID");;
 esac
 d=$BOTS_RUN_ROOT/crash/$op; mkdir -p "$d"
 [ -z "$pre" ] || cp "$F/$pre" "$d/expected"
 invoke 0 "$B" "${args[0]}" "$d/expected" "${args[@]:1}"
 invoke 0 "$B" show "$d/expected"; cp "$T/out" "$d/new-show"
 for boundary in 1 2 3 4 5 6; do
  cj=$d/j-$boundary
  [ -z "$pre" ] || cp "$F/$pre" "$cj"
  invoke 137 env BOTS_KILL=$boundary "$B" "${args[0]}" "$cj" "${args[@]:1}"
  if [ "$boundary" -lt 5 ]; then
   if [ -n "$pre" ]; then cmp "$F/$pre" "$cj"; else [ ! -e "$cj" ] || fail crash-created; fi
   invoke 0 "$B" show "$cj"; cp "$T/out" "$d/old-show-$boundary"
   if [ -n "$pre" ]; then invoke 0 "$B" show "$F/$pre"; cmp "$T/out" "$d/old-show-$boundary"; else [ ! -s "$d/old-show-$boundary" ] || fail crash-old; fi
   invoke 0 "$B" "${args[0]}" "$cj" "${args[@]:1}"
  fi
  cmp "$d/expected" "$cj" || fail "crash journal $op/$boundary"
  invoke 0 "$B" show "$cj"; cmp "$T/out" "$d/new-show" || fail "crash replay $op/$boundary"
  pass "crash-equality $op/$boundary"
 done
done
# An arbitrary torn, uncommitted candidate is ignored, then safely overwritten.
cp "$F/pending" "$T/torn"; dd if="$F/claimed" of="$T/torn.cand" bs=1 count=3500 status=none
invoke 0 "$B" show "$T/torn"; cp "$T/out" "$T/torn-show"
invoke 0 "$B" show "$F/pending"; cmp "$T/out" "$T/torn-show"; pass torn-candidate-ignored
invoke 0 "$B" claim "$T/torn" "$ID" "$MID" "$W"; cmp "$T/torn" "$F/claimed"; pass torn-candidate-replaced
barrier_probe "$B" "$BOTS_RUN_ROOT"
printf 'guard\tbuild_exit\tprobe_exit\texpected_binary_exit\tbinary_exit\tverdict\n' > "$BOTS_RUN_ROOT/mutants.tsv"
declare -A counts=()
for g in $GUARDS fsync-candidate fsync-directory barrier-order; do
 md=$BOTS_RUN_ROOT/mutants/$g; mkdir -p "$md"
 case "$g" in
 dedup)
  sed '/^note BOT-GUARD dedup$/{n;s/.*/put BV 3 0/;}' "$HERE/src/bots/bots.om" > "$md/bots.om";;
 fsync-candidate)
  sed 's/^bcheck eq fsync fd 0 3$/bcheck true 3/' "$HERE/src/bots/bots.om" > "$md/bots.om";;
 fsync-directory)
  sed 's/^bcheck eq fsync df 0 3$/bcheck true 3/' "$HERE/src/bots/bots.om" > "$md/bots.om";;
 barrier-order)
  # Keep both barriers, but move the atomic rename before candidate fsync.
  sed '/^bcheck eq renames BN 0 get BV 6 0 0 3$/d; /^bcheck eq fsync fd 0 3$/i bcheck eq renames BN 0 get BV 6 0 0 3' "$HERE/src/bots/bots.om" > "$md/bots.om";;
 *)
  sed "/^note BOT-GUARD $g\$/{n;s/^bcheck .*/bcheck true 99/;}" "$HERE/src/bots/bots.om" > "$md/bots.om";;
 esac
 cmp -s "$md/bots.om" "$HERE/src/bots/bots.om" && fail "no mutation $g"
 set +e
 BOTS_SOURCE=$md/bots.om sh "$HERE/scripts/bots/build.sh" "$md/bots" > "$md/build.txt" 2>&1
 build_rc=$?
 set -e
 rc=NA; expected=NA; actual=NA; verdict=ERROR
 if [ "$build_rc" = 0 ]; then
  set +e
  case "$g" in
  fsync-*|barrier-order) PROBE_META=$md/outcome.tsv bash "$0" --barrier "$md/bots" "$md" > "$md/probe.txt" 2>&1;;
  *) PROBE_META=$md/outcome.tsv bash "$0" --probe "$g" "$md/bots" "$F" "$ID" "$MID" "$md" > "$md/probe.txt" 2>&1;;
  esac
  rc=$?
  set -e
  if [ -f "$md/outcome.tsv" ]; then
   IFS=$'\t' read -r expected actual verdict < "$md/outcome.tsv"
   # An assertion child that failed without recording a specific counterexample is infrastructure failure.
   if [ "$rc" != 0 ] && [ "$verdict" = SURVIVED ]; then verdict=ERROR; fi
   if [ "$rc" = 0 ] && [ "$verdict" != SURVIVED ]; then verdict=ERROR; fi
  fi
 fi
 counts[$verdict]=$((${counts[$verdict]:-0}+1))
 printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$g" "$build_rc" "$rc" "$expected" "$actual" "$verdict" >> "$BOTS_RUN_ROOT/mutants.tsv"
 echo "$verdict $g binary_exit=$actual probe_exit=$rc"
done
{
 for verdict in KILLED_ADMIT KILLED_CODE KILLED_STATE KILLED_OUTPUT KILLED_BARRIER TRAPPED SIGNALLED ERROR SURVIVED; do
  printf '%s=%s\n' "$verdict" "${counts[$verdict]:-0}"
 done
 printf 'crash_cases=48\nbarriers=PASS\n'
} > "$BOTS_RUN_ROOT/results.txt"
cat "$BOTS_RUN_ROOT/results.txt"
# Fixed-capacity array bounds make botcap/msgcap removals trap; do not claim semantic kills.
while IFS=$'\t' read -r g build_rc rc expected actual verdict; do
 case "$verdict" in
 KILLED_*) ;;
 TRAPPED) [[ "$g" = botcap || "$g" = msgcap ]] && [ "$actual" = 103 ] || fail "unexpected trap $g=$actual";;
 *) fail "unqualified mutant $g verdict=$verdict";;
 esac
done < <(sed '1d' "$BOTS_RUN_ROOT/mutants.tsv")
pass 'ALL classified mutants; 48 crash equalities; commit barrier order PASS (not power-loss qualification)'
