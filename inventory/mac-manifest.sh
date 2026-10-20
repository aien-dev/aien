#!/bin/bash
# Runs ON the MacBook (piped through ssh by gen-manifest.sh). Read only.
# Prints: bytes <TAB> mtime_epoch <TAB> sha256 <TAB> absolute path
cd ~ || exit 1
{
  find .claude/projects -type f
  find .codex/sessions .codex/archived_sessions -type f 2>/dev/null
  find .gemini/antigravity .gemini/antigravity-cli .gemini/antigravity-ide -maxdepth 2 -type f \( -path '*/conversations/*' -o -name history.jsonl \) 2>/dev/null
  ls .local/share/opencode/opencode.db* 2>/dev/null
  ls .hermes/state.db .hermes/state.db-wal .hermes/profiles/*/state.db .hermes/profiles/*/state.db-wal 2>/dev/null
  find .hermes/sessions -type f 2>/dev/null
  ls aien-chat-catalog/build/*.db 2>/dev/null
} | while IFS= read -r f; do
  printf '%s\t%s\t%s\t%s\n' "$(stat -f %z "$f")" "$(stat -f %m "$f")" "$(shasum -a 256 "$f" 2>/dev/null | cut -d' ' -f1)" "$HOME/$f"
done
