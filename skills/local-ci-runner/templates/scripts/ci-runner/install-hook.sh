#!/usr/bin/env bash
# Installs a git pre-push hook that starts the local CI runner in the
# background on every push from this machine (docs/ops/ci-runner.md).
#
#   npm run ci:runner:hook   (or: bash scripts/ci-runner/install-hook.sh)
set -euo pipefail

MARK="# __REPO_NAME__ ci-runner"
hooks="$(git rev-parse --git-common-dir)/hooks"
hook="$hooks/pre-push"

if [ -f "$hook" ] && ! grep -qF "$MARK" "$hook"; then
  echo "Đã có $hook của bạn. Thêm tay dòng sau vào cuối file đó:"
  echo '  bash "$(git rev-parse --show-toplevel)/scripts/ci-runner/start-background.sh"'
  exit 1
fi

mkdir -p "$hooks"
cat > "$hook" <<HOOK
#!/bin/sh
$MARK
# Never blocks or fails a push.
script="\$(git rev-parse --show-toplevel)/scripts/ci-runner/start-background.sh"
[ -f "\$script" ] && bash "\$script"
exit 0
HOOK
chmod +x "$hook"
echo "Đã cài hook: $hook"
