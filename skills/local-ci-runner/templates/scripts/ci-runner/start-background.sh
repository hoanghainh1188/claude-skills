#!/usr/bin/env bash
# Starts run.sh detached from the terminal; output goes to a log file.
set -u
dir=$(cd "$(dirname "$0")" && pwd)
if [ -d "$HOME/Library/Logs" ]; then
  log="$HOME/Library/Logs/__REPO_NAME__-ci-runner.log"
else
  log="${TMPDIR:-/tmp}/__REPO_NAME__-ci-runner.log"
fi
nohup bash "$dir/run.sh" >> "$log" 2>&1 < /dev/null &
echo "CI chạy trên máy này. Xem tiến độ: tail -f $log"
