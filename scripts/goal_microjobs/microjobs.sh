#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-or-later
# Allen #13 host glue for the seeded .om microjob kernel. Shell owns files, locks and
# processes only (the seeded language has no file or argument API). Every admission
# decision is made by the kernel: a proposed event is appended to the persistent
# journal only when the kernel replays plan + journal + candidate with exit 0.
# The journal is a local, owner-private file; it is not Cortex. The Omega Cortex
# writer integration is pending (see docs/GOAL_MICROJOBS.md).
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
usage: microjobs.sh init STATE_DIR PLAN_FILE
       microjobs.sh status STATE_DIR
       microjobs.sh propose STATE_DIR TYPE NODE ATTEMPT GEN ISSUER VERDICT D0 D1 D2 D3 TOK TIME_MS
       microjobs.sh digest TEXT
environment: GM_KERNEL = path to the kernel built by scripts/goal_microjobs/build.sh
EOF
  exit 64
}

kernel() {
  : "${GM_KERNEL:?Set GM_KERNEL to the kernel built by scripts/goal_microjobs/build.sh}"
  "$GM_KERNEL"
}

# digest TEXT: SHA-256 of TEXT as four big-endian 64-bit words in decimal
digest_words() {
  local hex
  hex=$(printf '%s' "$1" | sha256sum | cut -c1-64)
  printf '%u %u %u %u\n' "0x${hex:0:16}" "0x${hex:16:16}" "0x${hex:32:16}" "0x${hex:48:16}"
}

with_lock() {
  local state=$1
  exec 9>"$state/lock"
  flock -n 9 || { echo 'microjobs: state is locked by another writer' >&2; exit 75; }
}

test $# -ge 1 || usage
cmd=$1
shift
case "$cmd" in
  digest)
    test $# -eq 1 || usage
    digest_words "$1"
    ;;
  init)
    test $# -eq 2 || usage
    state=$1 plan=$2
    if test -e "$state/plan"; then
      echo "microjobs: $state already holds an objective" >&2
      exit 73
    fi
    umask 077
    mkdir -p "$state"
    with_lock "$state"
    set +e
    kernel < "$plan" > "$state/init.out"
    rc=$?
    set -e
    if test "$rc" -ne 0; then
      cat "$state/init.out"
      rm -f "$state/init.out"
      exit "$rc"
    fi
    cp "$plan" "$state/plan.tmp"
    : > "$state/journal"
    sync "$state/plan.tmp" "$state/journal"
    mv "$state/plan.tmp" "$state/plan"
    rm -f "$state/init.out"
    sync "$state"
    echo "INIT $state"
    ;;
  status)
    test $# -eq 1 || usage
    state=$1
    cat "$state/plan" "$state/journal" | kernel
    ;;
  propose)
    test $# -eq 13 || usage
    state=$1
    shift
    for word in "$@"; do
      case "$word" in
        ''|*[!0-9]*) echo "microjobs: non-decimal field '$word'" >&2; exit 64 ;;
      esac
    done
    with_lock "$state"
    seq=$(( $(wc -l < "$state/journal") + 1 ))
    cand="$state/journal.cand"
    cp "$state/journal" "$cand"
    printf '3 %s %s\n' "$seq" "$*" >> "$cand"
    set +e
    out=$(cat "$state/plan" "$cand" | kernel)
    rc=$?
    set -e
    if test "$rc" -ne 0; then
      rm -f "$cand"
      printf 'REJECT %s\n' "$out"
      exit "$rc"
    fi
    sync "$cand"
    mv "$cand" "$state/journal"
    sync "$state"
    printf 'ACCEPT %s\n' "$seq"
    ;;
  *)
    usage
    ;;
esac
