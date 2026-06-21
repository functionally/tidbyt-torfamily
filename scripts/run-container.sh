#!/usr/bin/env bash
# Run the torrelay daemon.
set -euo pipefail

CONTAINER_NAME="${CONTAINER_NAME:-torrelay}"
PUSH_AT_MINUTE_UTC="${PUSH_AT_MINUTE_UTC:-10}"
ONESHOT=0

DETACH=""
RESTART_POLICY="no"
for arg in "$@"; do
  case "$arg" in
    --detach|-d)
      DETACH="--detach"
      RESTART_POLICY="always"
      ;;
    --once)
      ONESHOT=1
      ;;
    *)
      echo "Unknown arg: $arg" >&2
      echo "Usage: $0 [--detach|-d] [--once]" >&2
      exit 1
      ;;
  esac
done

if ! command -v podman >/dev/null 2>&1; then
  echo "ERROR: podman is not on PATH." >&2
  exit 1
fi

if ! podman image exists torrelay:latest; then
  echo "ERROR: torrelay:latest is not loaded. Run ./scripts/build-container.sh first." >&2
  exit 1
fi

if podman container exists "$CONTAINER_NAME"; then
  echo "Removing existing container ${CONTAINER_NAME}…"
  podman rm -f "$CONTAINER_NAME" >/dev/null
fi

if [[ "$ONESHOT" == "1" ]]; then
  echo "Starting ${CONTAINER_NAME} (one-shot push, then exit)…"
else
  echo "Starting ${CONTAINER_NAME} (push at HH:${PUSH_AT_MINUTE_UTC} UTC every hour)…"
fi
exec podman run \
  --name "$CONTAINER_NAME" \
  --rm \
  ${DETACH} \
  --restart="$RESTART_POLICY" \
  -e "PUSH_AT_MINUTE_UTC=${PUSH_AT_MINUTE_UTC}" \
  -e "ONESHOT=${ONESHOT}" \
  torrelay:latest
