#!/usr/bin/env bash
# Copies the local-ci-runner templates into a repository and fills the
# placeholders. Never overwrites an existing file (prints it as skipped).
#
#   bash ~/.claude/skills/local-ci-runner/bin/install.sh \
#     --repo /path/to/repo --label myapp-local --slug myapp \
#     [--name my-app] [--node-file .nvmrc] [--browsers "chromium webkit"] \
#     [--db postgres --db-user app --db-password app --db-name app_test \
#      --db-image postgres:17-alpine] [--hosted-label visual] [--force-public]
set -euo pipefail

SKILL_DIR=$(cd "$(dirname "$0")/.." && pwd)
T="$SKILL_DIR/templates"

REPO_DIR="" LABEL="" SLUG="" NAME="" NODE_FILE="" BROWSERS="" DB=none
DB_USER=app DB_PASSWORD=app DB_NAME=app_test DB_IMAGE=postgres:17-alpine
HOSTED_LABEL=hosted FORCE_PUBLIC=0

while [ $# -gt 0 ]; do
  case "$1" in
    --repo) REPO_DIR=$2; shift 2 ;;
    --label) LABEL=$2; shift 2 ;;
    --slug) SLUG=$2; shift 2 ;;
    --name) NAME=$2; shift 2 ;;
    --node-file) NODE_FILE=$2; shift 2 ;;
    --browsers) BROWSERS=$2; shift 2 ;;
    --db) DB=$2; shift 2 ;;
    --db-user) DB_USER=$2; shift 2 ;;
    --db-password) DB_PASSWORD=$2; shift 2 ;;
    --db-name) DB_NAME=$2; shift 2 ;;
    --db-image) DB_IMAGE=$2; shift 2 ;;
    --hosted-label) HOSTED_LABEL=$2; shift 2 ;;
    --force-public) FORCE_PUBLIC=1; shift ;;
    *) echo "Unknown option: $1" >&2; exit 2 ;;
  esac
done

[ -n "$REPO_DIR" ] && [ -n "$LABEL" ] && [ -n "$SLUG" ] || {
  echo "Need --repo, --label and --slug" >&2; exit 2; }
REPO_DIR=$(cd "$REPO_DIR" && pwd)
[ -n "$NAME" ] || NAME=$(basename "$REPO_DIR")
case "$DB" in none|postgres) ;; *) echo "--db must be none or postgres" >&2; exit 2 ;; esac

# Refuse public repositories: a self-hosted runner there runs forks' code.
if [ "$FORCE_PUBLIC" -eq 0 ]; then
  vis=$(cd "$REPO_DIR" && gh repo view --json visibility --jq .visibility 2>/dev/null || echo UNKNOWN)
  if [ "$vis" != "PRIVATE" ]; then
    echo "Repo visibility is $vis, not PRIVATE. Refusing (self-hosted runners on public repos run strangers' code)." >&2
    exit 1
  fi
fi

if [ -f "$REPO_DIR/package.json" ]; then
  RUN_CMD="npm run ci:runner"; HOOK_CMD="npm run ci:runner:hook"
else
  RUN_CMD="bash scripts/ci-runner/run.sh"; HOOK_CMD="bash scripts/ci-runner/install-hook.sh"
fi

export LABEL SLUG NAME NODE_FILE BROWSERS DB_USER DB_PASSWORD DB_NAME DB_IMAGE \
  HOSTED_LABEL RUN_CMD HOOK_CMD

fill() { # src dest
  local src=$1 dest=$2
  if [ -e "$dest" ]; then echo "skip (exists): ${dest#$REPO_DIR/}"; return; fi
  mkdir -p "$(dirname "$dest")"
  perl -pe '
    s/__LABEL__/$ENV{LABEL}/g; s/__SLUG__/$ENV{SLUG}/g; s/__REPO_NAME__/$ENV{NAME}/g;
    s/__NODE_VERSION_FILE__/$ENV{NODE_FILE}/g; s/__PLAYWRIGHT_BROWSERS__/$ENV{BROWSERS}/g;
    s/__DB_USER__/$ENV{DB_USER}/g; s/__DB_PASSWORD__/$ENV{DB_PASSWORD}/g;
    s/__DB_NAME__/$ENV{DB_NAME}/g; s/__POSTGRES_IMAGE__/$ENV{DB_IMAGE}/g;
    s/__HOSTED_LABEL__/$ENV{HOSTED_LABEL}/g; s/__RUN_CMD__/$ENV{RUN_CMD}/g;
    s/__HOOK_CMD__/$ENV{HOOK_CMD}/g;
  ' "$src" > "$dest"
  case "$dest" in *.sh) chmod +x "$dest" ;; esac
  echo "wrote: ${dest#$REPO_DIR/}"
}

fill "$T/docker/ci-runner/Dockerfile" "$REPO_DIR/docker/ci-runner/Dockerfile"
fill "$T/docker/ci-runner/entrypoint.sh" "$REPO_DIR/docker/ci-runner/entrypoint.sh"
if [ "$DB" = postgres ]; then
  fill "$T/docker/ci-runner/compose.postgres.yml" "$REPO_DIR/docker/ci-runner/compose.yml"
else
  fill "$T/docker/ci-runner/compose.yml" "$REPO_DIR/docker/ci-runner/compose.yml"
fi
for f in run.sh start-background.sh install-hook.sh; do
  fill "$T/scripts/ci-runner/$f" "$REPO_DIR/scripts/ci-runner/$f"
done
fill "$T/docs/ci-runner.md" "$REPO_DIR/docs/ops/ci-runner.md"

echo
echo "Next: adapt workflows (see $T/workflows/*.example.yml), add scripts, install hook."
echo "Placeholders left anywhere?"
grep -rn '__[A-Z_]*__' "$REPO_DIR/docker/ci-runner" "$REPO_DIR/scripts/ci-runner" "$REPO_DIR/docs/ops/ci-runner.md" || echo "  none"
