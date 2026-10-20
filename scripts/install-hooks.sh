#!/usr/bin/env bash
# Install the allen-guard pre-commit hook in this clone. The installed hook
# delegates to scripts/pre-commit, so updates to the script apply at once.
# An existing different hook is kept as pre-commit.before-allen-guard.
set -euo pipefail

hooks="$(git rev-parse --git-path hooks)"
mkdir -p "$hooks"
target="$hooks/pre-commit"
wrapper='#!/usr/bin/env bash
# installed by scripts/install-hooks.sh (allen-guard)
exec "$(git rev-parse --show-toplevel)/scripts/pre-commit" "$@"'

if [ -e "$target" ] && [ "$(cat "$target")" != "$wrapper" ]; then
  mv "$target" "$target.before-allen-guard"
  echo "kept the previous hook as $target.before-allen-guard"
fi
printf '%s\n' "$wrapper" > "$target"
chmod +x "$target"
echo "allen-guard pre-commit hook installed at $target"
