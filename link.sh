#!/usr/bin/env bash
# Links every skill of this repo into ~/.claude/skills (skips existing names).
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
mkdir -p "$HOME/.claude/skills"
for dir in "$here"/skills/*/; do
  name=$(basename "$dir")
  target="$HOME/.claude/skills/$name"
  if [ -e "$target" ] || [ -L "$target" ]; then
    echo "skip (exists): $target"
  else
    ln -s "${dir%/}" "$target"
    echo "linked: $target"
  fi
done
