#!/usr/bin/env bash
#
# start-and-provision.sh — start the AWS Emulator container, wait for it to be
# healthy, then create all resources (DynamoDB table, IAM role/policy, Lambda)
# via the AWS CLI. One command for a full local environment.
#
# Usage:
#   ./start-and-provision.sh          # build image if needed, start, provision
#   EMULATOR_PORT=9300 ./start-and-provision.sh
#
set -euo pipefail

PORT="${EMULATOR_PORT:-9297}"
CONTAINER="${EMULATOR_CONTAINER:-aws-emulator}"
IMAGE="${EMULATOR_IMAGE:-aws-emulator}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

log() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }

# ---- Build the image if it doesn't exist ------------------------------------
if ! docker image inspect "$IMAGE" >/dev/null 2>&1; then
  log "Building emulator image '$IMAGE' ..."
  docker build -t "$IMAGE" "$SCRIPT_DIR"
fi

# ---- (Re)start the container ------------------------------------------------
if docker ps -a --format '{{.Names}}' | grep -qx "$CONTAINER"; then
  log "Removing existing container '$CONTAINER' ..."
  docker rm -f "$CONTAINER" >/dev/null
fi

mkdir -p "$HOME/.aws/emulator"
log "Starting emulator container '$CONTAINER' on 127.0.0.1:$PORT ..."
docker run -d --name "$CONTAINER" --memory=2g --memory-swap=2g \
  -p "127.0.0.1:$PORT:$PORT" \
  -e HOME="$HOME" \
  -v "$HOME/.aws/emulator:$HOME/.aws/emulator" \
  "$IMAGE" -p "$PORT" -a off >/dev/null

# ---- Provision via AWS CLI --------------------------------------------------
log "Provisioning resources ..."
EMULATOR_PORT="$PORT" "$SCRIPT_DIR/provision-cli.sh"
