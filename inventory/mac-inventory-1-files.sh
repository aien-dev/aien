cd ~
fmt() { stat -f '%m' "$@" 2>/dev/null; }
summ() { # dir pattern
  d="$1"; p="$2"
  n=$(find "$d" -type f -name "$p" 2>/dev/null | wc -l | tr -d ' ')
  b=$(find "$d" -type f -name "$p" -exec stat -f '%z' {} + 2>/dev/null | awk '{s+=$1}END{print s+0}')
  o=$(find "$d" -type f -name "$p" -exec stat -f '%m' {} + 2>/dev/null | sort -n | head -1)
  w=$(find "$d" -type f -name "$p" -exec stat -f '%m' {} + 2>/dev/null | sort -n | tail -1)
  od=$( [ -n "$o" ] && date -u -r $o +%Y-%m-%d); wd=$( [ -n "$w" ] && date -u -r $w +%Y-%m-%d)
  echo "$d [$p] files=$n bytes=$b oldest=$od newest=$wd"
}
summ .claude/projects '*.jsonl'
echo "claude non-jsonl: $(find .claude/projects -type f ! -name '*.jsonl' | wc -l | tr -d ' ')"
echo "claude project dirs: $(ls .claude/projects | wc -l | tr -d ' ')"
summ .codex/sessions '*.jsonl'
for s in antigravity antigravity-cli antigravity-ide; do
  [ -d .gemini/$s/conversations ] && { summ .gemini/$s/conversations '*.db'; summ .gemini/$s/conversations '*.db-wal'; summ .gemini/$s/conversations '*.db-shm'; }
done
echo "--- opencode"; ls -la .local/share/opencode | head -20
echo "--- hermes"; du -sk .hermes | cut -f1; ls .hermes | head -60
