#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-or-later
# Build the Allen #13 microjob kernel with the pinned seeded Omega compiler.
# Usage: OMEGA_WORKTREE=... build.sh [SOURCE.om] [OUTPUT]
set -euo pipefail

repo=$(cd "$(dirname "$0")/../.." && pwd)
: "${OMEGA_WORKTREE:?Set OMEGA_WORKTREE to the isolated seeded-Omega compiler worktree}"

# Same pins as scripts/harness_evolution/gate.sh on feat/harness-evolution-alpha (Allen #12).
omega_pin=c434565c67552c0b01df2d7f76c1a04287c70560
compiler_pin=191b776ef98821597c3e30655da6d680a9b66edbc9ceaca3c39c61ea6df098e9
seed_source_pin=8608fa11f6a2cf1c50db22d871eef16b00d5bc719bc1a222cc3e456984ac5ebf

compiler="$OMEGA_WORKTREE/build/L574/toolchain/build/bootstrap/omc"
verify_elf="$OMEGA_WORKTREE/build/L574/toolchain/tools/verify-elf.sh"
blocked() { printf 'BLOCKED: %s\n' "$*" >&2; exit 3; }
test "$(git -C "$OMEGA_WORKTREE" rev-parse HEAD)" = "$omega_pin" ||
  blocked "Omega checkout must be $omega_pin"
# This historical toolchain was an untracked build artifact, not part of the
# Omega commit. A fresh clone alone cannot supply it. Never substitute a newer
# compiler or run an unchecked binary.
test -x "$compiler" && test -f "$verify_elf" &&
  test -f "$OMEGA_WORKTREE/build/L574/toolchain/seed/omc/omc.om" ||
  blocked "missing historical build/L574/toolchain artifacts; obtain the archived toolchain listed in docs/GOAL_MICROJOBS.md"
test "$(sha256sum "$compiler" | cut -d' ' -f1)" = "$compiler_pin" ||
  blocked "historical compiler digest differs from $compiler_pin"
test "$(sha256sum "$OMEGA_WORKTREE/build/L574/toolchain/seed/omc/omc.om" | cut -d' ' -f1)" = "$seed_source_pin" ||
  blocked "historical compiler source digest differs from $seed_source_pin"

src=${1:-"$repo/src/goal_microjobs/kernel.om"}
out=${2:-"${GM_BUILD_DIR:-$repo/target/goal_microjobs}/kernel"}
mkdir -p "$(dirname "$out")"
tmp="$out.tmp.$$"
if ! "$compiler" < "$src" > "$tmp" 2> "$tmp.stderr"; then
  cat "$tmp.stderr" >&2
  rm -f "$tmp" "$tmp.stderr"
  echo 'seeded .om compile failed' >&2
  exit 65
fi
rm -f "$tmp.stderr"
sh "$verify_elf" "$tmp"
chmod 700 "$tmp"
mv "$tmp" "$out"
printf '%s\n' "$out"
