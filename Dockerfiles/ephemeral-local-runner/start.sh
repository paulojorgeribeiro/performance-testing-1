#!/bin/bash
set -e

if [ -z "$RUNNER_TOKEN" ] || [ -z "$REPO_URL" ]; then
  echo "Missing RUNNER_TOKEN or REPO_URL"
  exit 1
fi

./config.sh \
  --url "$REPO_URL" \
  --token "$RUNNER_TOKEN" \
  --ephemeral \
  --unattended \
  --labels "self-hosted,repo-ephemeral" \
  --name "$(hostname)"

exec ./run.sh
