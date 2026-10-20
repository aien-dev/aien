#!/bin/bash
# Regenerates the access-controlled source manifest (never committed to git).
# Usage: gen-manifest.sh [YYYY-MM-DD]   (default: today UTC)
# Output: ~/archive/agent-chats/manifests/<date>-source-manifest.tsv, mode 0600
# Columns: host agent path bytes mtime_utc sha256 (one header line first). Files that are still being appended
# (live chats, live databases) can differ from their hash by a few bytes; the row records what was read at that moment.
set -u
DATE=${1:-$(date -u +%F)}
HERE=$(cd "$(dirname "$0")" && pwd)
OUTDIR=$HOME/archive/agent-chats/manifests
OUT=$OUTDIR/$DATE-source-manifest.tsv
mkdir -p "$OUTDIR" && chmod 700 "$OUTDIR"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
umask 077
row() { # reads path list on stdin (NUL separated), prints bytes mtime sha path
  xargs -0 -P4 -n40 bash -c 'for f; do printf "%s\t%s\t%s\t%s\n" "$(stat -c %s "$f")" "$(stat -c %Y "$f")" "$(sha256sum "$f" | cut -d" " -f1)" "$f"; done' _
}
# 1) archive trees on the Spark
find "$HOME/archive/agent-chats/raw" "$HOME/archive/agent-chats/records" -type f -print0 | row > "$TMP/archive.tsv"
# 2) Spark original sources
{
  find "$HOME/.claude/projects" -type f -print0
  find "$HOME/.codex/sessions" -type f -print0
  ls "$HOME"/.local/share/opencode/opencode.db* 2>/dev/null | tr '\n' '\0'
  find "$HOME/.gemini/antigravity-cli/conversations" "$HOME/.gemini/antigravity/conversations" "$HOME/.gemini/antigravity-ide/conversations" -type f -print0 2>/dev/null
  ls "$HOME/.gemini/antigravity-cli/history.jsonl" 2>/dev/null | tr '\n' '\0'
  find "$HOME/.local/share/muse/sessions" -type f -print0
  ls "$HOME/.local/share/muse/tui-history.jsonl" 2>/dev/null | tr '\n' '\0'
  ls "$HOME"/.hermes/state.db "$HOME"/.hermes/state.db-wal 2>/dev/null | tr '\n' '\0'
  find "$HOME/.hermes/sessions" -type f -print0 2>/dev/null
} | row > "$TMP/spark.tsv"
# 3) MacBook originals (read only over ssh)
if ssh -o BatchMode=yes -o ConnectTimeout=8 macbook 'bash -s' < "$HERE/mac-manifest.sh" > "$TMP/mac.tsv" 2> "$TMP/mac.err"; then MACSTATUS=ok; else MACSTATUS="NOT_RUN: $(head -c 200 "$TMP/mac.err")"; : > "$TMP/mac.tsv"; fi
echo "mac step: $MACSTATUS" >&2
classify() { # host ; stdin rows bytes mtime sha path -> host agent path bytes iso sha
  awk -F'\t' -v host="$1" 'BEGIN{OFS="\t"} {
    p=$4; a="other";
    if (p ~ /\/archive\/agent-chats\/(raw|records)\/claude\// || p ~ /\.claude\/projects/) a="claude";
    else if (p ~ /\/(raw|records)\/codex\// || p ~ /\.codex\//) a="codex";
    else if (p ~ /\/(raw|records)\/opencode\// || p ~ /opencode/) a="opencode";
    else if (p ~ /\/(raw|records)\/gemini\// || p ~ /\.gemini\//) a="gemini";
    else if (p ~ /\/(raw|records)\/muse\// || p ~ /\/muse\//) a="muse";
    else if (p ~ /\.hermes/) a="hermes";
    else if (p ~ /aien-chat-catalog/) a="catalog";
    cmd="date -u -d @" $2 " +%Y-%m-%dT%H:%M:%SZ"; cmd | getline iso; close(cmd);
    print host, a, p, $1, iso, ($3==""?"not-hashed":$3) }'
}
{
  printf 'host\tagent\tpath\tbytes\tmtime_utc\tsha256\n'
  classify spark < "$TMP/archive.tsv" | sed 's/^spark/spark-archive/'
  classify spark < "$TMP/spark.tsv"
  classify macbook < "$TMP/mac.tsv"
} > "$OUT"
chmod 600 "$OUT"
echo "rows=$(($(wc -l < "$OUT")-1)) sha256=$(sha256sum "$OUT" | cut -d' ' -f1) file=$OUT"
