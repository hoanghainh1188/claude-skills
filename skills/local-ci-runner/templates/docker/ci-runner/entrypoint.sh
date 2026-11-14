#!/usr/bin/env bash
# Registers as a one-job (ephemeral) runner, runs that job, exits. GitHub
# removes an ephemeral runner once its job is done; the trap removes one
# that is stopped while still waiting.
set -euo pipefail

: "${REPO_URL:?}" "${RUNNER_TOKEN:?}" "${RUNNER_NAME:?}"

cd /home/runner

unregister() {
  if [ -n "${RUNNER_REMOVE_TOKEN:-}" ]; then
    ./config.sh remove --token "$RUNNER_REMOVE_TOKEN" >/dev/null 2>&1 || true
  fi
}
trap 'kill "${child:-0}" 2>/dev/null || true; unregister; exit 143' TERM INT

./config.sh --unattended --ephemeral --replace --disableupdate \
  --url "$REPO_URL" --token "$RUNNER_TOKEN" \
  --name "$RUNNER_NAME" --labels __LABEL__

./run.sh &
child=$!
wait "$child"
