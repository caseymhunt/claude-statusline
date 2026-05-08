#!/bin/bash
set -e

SCRIPT_SRC="$(cd "$(dirname "$0")" && pwd)/statusline-command.sh"
CLAUDE_DIR="$HOME/.claude"
SETTINGS="$CLAUDE_DIR/settings.json"

mkdir -p "$CLAUDE_DIR"
cp "$SCRIPT_SRC" "$CLAUDE_DIR/statusline-command.sh"
chmod +x "$CLAUDE_DIR/statusline-command.sh"
echo "Installed statusline-command.sh to $CLAUDE_DIR"

# Patch settings.json: add statusLine block if not already present
if [ ! -f "$SETTINGS" ]; then
  echo '{"statusLine":{"type":"command","command":"bash ~/.claude/statusline-command.sh"}}' > "$SETTINGS"
  echo "Created $SETTINGS"
elif grep -q '"statusLine"' "$SETTINGS"; then
  echo "statusLine already present in $SETTINGS — skipping (edit manually if needed)"
else
  # Insert before the closing brace
  tmp=$(mktemp)
  sed 's/}[[:space:]]*$/,"statusLine":{"type":"command","command":"bash ~\/.claude\/statusline-command.sh"}}/' "$SETTINGS" > "$tmp"
  mv "$tmp" "$SETTINGS"
  echo "Added statusLine to $SETTINGS"
fi

echo "Done. Restart Claude Code to activate."
