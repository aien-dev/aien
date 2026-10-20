#!/usr/bin/env bash
# Scan every file each commit adds or changes, for the commits selected by
# the git rev-list arguments given (for example `origin/main..HEAD`). CI runs
# this on every push and pull request so that a file added in one commit and
# deleted in a later one is still refused: it would stay in history.
#
# ALLEN_GUARD_BIN overrides the guard binary (default target/release/allen-guard).
set -euo pipefail

if [ "$#" -eq 0 ]; then
  echo "usage: scripts/scan-history.sh <git rev-list arguments>" >&2
  exit 1
fi
bin="${ALLEN_GUARD_BIN:-target/release/allen-guard}"
config=()
if [ -f guard/scan.toml ]; then
  config=(--config guard/scan.toml)
fi

# Assign first: a bad range must fail here, not silently scan nothing.
commits="$(git rev-list --reverse "$@")"
status=0
count=0
for commit in $commits; do
  count=$((count + 1))
  files=()
  while IFS= read -r -d '' f; do
    files+=("$f")
  done < <(git diff-tree --no-commit-id --root -r -z --name-only --diff-filter=ACMR "$commit")
  if [ "${#files[@]}" -eq 0 ]; then
    continue
  fi
  if ! "$bin" scan ${config[@]+"${config[@]}"} --rev "$commit" -- "${files[@]}"; then
    echo "allen-guard: findings in commit $commit" >&2
    status=1
  fi
done
echo "allen-guard: scanned $count commit(s)" >&2
exit "$status"
