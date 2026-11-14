#!/usr/bin/env bash
# Runs this repository's waiting CI jobs on this machine, in Docker, then
# stops (docs/ops/ci-runner.md). Safe to start twice: the second one exits.
#
#   npm run ci:runner        (or: bash scripts/ci-runner/run.sh)
#   npm run ci:runner:clean  (or: run.sh --clean) remove the image and cache volumes now
#   CI_RUNNER_CLEAN=1 ...  same, after the last job of this run: nothing left
#                          behind, but the next run builds and downloads all again
#
# Needs Docker and a signed-in GitHub CLI (`gh auth login`) on an account
# that administers the repository. Written for the bash 3.2 of macOS.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
LABEL=__LABEL__
# File holding the Node version (.nvmrc, .node-version, .tool-versions);
# empty for a repository without Node.
NODE_VERSION_FILE="__NODE_VERSION_FILE__"
# Playwright browsers whose system packages go in the image; empty for none.
PLAYWRIGHT_BROWSERS="__PLAYWRIGHT_BROWSERS__"
POLL_SECONDS=15
# How long to wait with no CI run in sight before giving up. A push takes a
# moment to show up as a run.
IDLE_SECONDS=${CI_RUNNER_IDLE_SECONDS:-180}
# 1: remove the image and the cache volumes when this run ends.
CLEAN=${CI_RUNNER_CLEAN:-0}
CLEAN_ONLY=0
case "${1:-}" in
  "") ;;
  --clean) CLEAN=1; CLEAN_ONLY=1 ;;
  *) echo "Usage: run.sh [--clean]" >&2; exit 2 ;;
esac
LOCK="${TMPDIR:-/tmp}/__SLUG__-ci-runner.lock"
COMPOSE=(docker compose -p __SLUG__-ci-runner -f "$ROOT/docker/ci-runner/compose.yml")

log() { printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"; }
die() { log "LỖI: $*"; exit 1; }

command -v gh >/dev/null || die "chưa cài GitHub CLI (brew install gh)"
command -v docker >/dev/null || die "chưa cài Docker"

# One loop per machine.
if ! mkdir "$LOCK" 2>/dev/null; then
  other=$(cat "$LOCK/pid" 2>/dev/null || true)
  if [ -n "$other" ] && kill -0 "$other" 2>/dev/null; then
    log "Runner đang chạy (pid $other), không mở thêm."
    exit 0
  fi
  rm -rf "$LOCK" && mkdir "$LOCK"
fi
echo $$ > "$LOCK/pid"

# compose.yml requires these; `down` and `stop` need any value to read the file, or
# they fail (silently here) and leave the container behind.
export REPO_URL=${REPO_URL:-unused} RUNNER_TOKEN=${RUNNER_TOKEN:-unused} RUNNER_NAME=${RUNNER_NAME:-unused}
stop_containers() { "${COMPOSE[@]}" down --remove-orphans >/dev/null 2>&1 || true; }
# Everything this runner left on the machine: containers, network, the cache volumes,
# the built image and its base image. Docker's build cache is shared by every
# project, so it stays (`docker builder prune` clears it).
purge() {
  local base
  "${COMPOSE[@]}" down --remove-orphans --volumes --rmi all >/dev/null 2>&1 || true
  base=$(awk 'toupper($1) == "FROM" { print $2; exit }' "$ROOT/docker/ci-runner/Dockerfile")
  if [ -n "$base" ]; then docker image rm "$base" >/dev/null 2>&1 || true; fi
  log "Đã dọn image và volume cache của runner."
}
cleanup() {
  if [ "$CLEAN" = 1 ] && docker info >/dev/null 2>&1; then purge; else stop_containers; fi
  rm -rf "$LOCK"
}
trap cleanup EXIT
trap 'exit 130' INT TERM

ensure_docker() {
  docker info >/dev/null 2>&1 && return
  if [ "$(uname)" = "Darwin" ]; then
    log "Docker chưa chạy, đang mở Docker Desktop..."
    open -ga Docker || true
  fi
  for _ in $(seq 1 30); do
    sleep 3
    docker info >/dev/null 2>&1 && return
  done
  die "Docker không chạy"
}

REPO=${CI_RUNNER_REPO:-$(cd "$ROOT" && gh repo view --json nameWithOwner --jq .nameWithOwner)}
[ -n "$REPO" ] || die "không đọc được tên repo"
# With several accounts signed in, use the repository owner's.
GH_TOKEN=$(gh auth token --user "${REPO%%/*}" 2>/dev/null || gh auth token)
export GH_TOKEN

# A self-hosted runner on a public repository runs strangers' fork PRs.
visibility=$(gh api "repos/$REPO" --jq .visibility 2>/dev/null || echo unknown)
[ "$visibility" = "private" ] || die "repo $REPO không riêng tư ($visibility): không chạy runner tự host"

node_major() {
  local file="$ROOT/$NODE_VERSION_FILE" v=""
  [ -n "$NODE_VERSION_FILE" ] || return 0
  [ -f "$file" ] || die "không thấy $NODE_VERSION_FILE"
  case "$NODE_VERSION_FILE" in
    *.tool-versions) v=$(awk '$1 == "nodejs" || $1 == "node" { print $2; exit }' "$file") ;;
    *) v=$(tr -d 'v \n' < "$file") ;;
  esac
  [ -n "$v" ] || die "không đọc được phiên bản Node trong $NODE_VERSION_FILE"
  echo "${v%%.*}"
}

NODE_MAJOR=$(node_major)
PLAYWRIGHT_VERSION=""
if [ -n "$PLAYWRIGHT_BROWSERS" ]; then
  PLAYWRIGHT_VERSION=$(sed -n 's/.*"@playwright\/test": *"[~^]*\([^"]*\)".*/\1/p' "$ROOT/package.json")
  [ -n "$PLAYWRIGHT_VERSION" ] || die "không đọc được phiên bản Playwright trong package.json"
fi
export NODE_MAJOR PLAYWRIGHT_VERSION PLAYWRIGHT_BROWSERS

# Ids of the runs that are waiting or running.
active_runs() {
  local status
  for status in queued in_progress; do
    gh api "repos/$REPO/actions/runs?status=$status&per_page=50" \
      --jq '.workflow_runs[].id' 2>/dev/null || true
  done | sort -u
}

# How many jobs of those runs wait for this runner.
waiting_jobs() {
  local id total=0 count
  for id in $1; do
    count=$(gh api "repos/$REPO/actions/runs/$id/jobs?per_page=100" \
      --jq "[.jobs[] | select(.status == \"queued\" and (.labels | index(\"$LABEL\")))] | length" \
      2>/dev/null || echo 0)
    total=$((total + count))
  done
  echo "$total"
}

job_number=0
run_one_job() {
  job_number=$((job_number + 1))
  local registration removal up_pid quiet=0
  registration=$(gh api -X POST "repos/$REPO/actions/runners/registration-token" --jq .token) ||
    die "không lấy được mã đăng ký runner (tài khoản gh cần quyền quản trị repo)"
  removal=$(gh api -X POST "repos/$REPO/actions/runners/remove-token" --jq .token 2>/dev/null || true)

  log "Chạy việc thứ $job_number..."
  REPO_URL="https://github.com/$REPO" \
  RUNNER_TOKEN="$registration" \
  RUNNER_REMOVE_TOKEN="$removal" \
  RUNNER_NAME="local-$(hostname -s)-$$-$job_number" \
    "${COMPOSE[@]}" up --build --abort-on-container-exit --exit-code-from runner &
  up_pid=$!

  # A job cancelled before the runner took it would leave the runner
  # listening forever: stop it once no run is left.
  while kill -0 "$up_pid" 2>/dev/null; do
    sleep 30
    if [ -z "$(active_runs)" ]; then quiet=$((quiet + 1)); else quiet=0; fi
    if [ "$quiet" -ge 2 ]; then
      log "Không còn lượt CI nào, dừng runner đang chờ."
      "${COMPOSE[@]}" stop >/dev/null 2>&1 || true
    fi
  done
  wait "$up_pid" || true
  stop_containers
}

ensure_docker
if [ "$CLEAN_ONLY" = 1 ]; then exit 0; fi  # the EXIT trap purges
log "Chờ việc CI của $REPO (nhãn $LABEL)..."
idle=0
while :; do
  runs=$(active_runs)
  if [ -z "$runs" ]; then
    idle=$((idle + POLL_SECONDS))
    if [ "$idle" -ge "$IDLE_SECONDS" ]; then break; fi
    sleep "$POLL_SECONDS"
    continue
  fi
  idle=0
  if [ "$(waiting_jobs "$runs")" -gt 0 ]; then
    run_one_job
  else
    sleep "$POLL_SECONDS"
  fi
done
log "Hết việc (đã chạy $job_number việc). Tắt."
