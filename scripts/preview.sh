#!/usr/bin/env bash
# Local browser preview at http://localhost:8080
set -euo pipefail
cd "$(dirname "$0")/.."

if [[ ! -f config.yaml ]]; then
  echo "ERROR: config.yaml is missing. Run: cp config-example.yaml config.yaml" >&2
  exit 1
fi

FAMILY="$(yq -r '.family_fingerprint' config.yaml)"

PORT="${PIXLET_PORT:-8080}"
HOST="${PIXLET_HOST:-127.0.0.1}"
BROWSER_HOST="${PIXLET_BROWSER_HOST:-localhost}"

URL_FAM="$(python3 -c 'import sys, urllib.parse; print(urllib.parse.quote(sys.argv[1], safe=""))' "$FAMILY")"

cat <<EOF

Pixlet serving on ${HOST}:${PORT}. Hot-reloads on main.star changes.

Open ONE of these URLs in your browser:

  Pre-filled preview (recommended):
    http://${BROWSER_HOST}:${PORT}/legacy?family_fingerprint=${URL_FAM}

  Raw rendered frame as WebP:
    http://${BROWSER_HOST}:${PORT}/api/v1/preview.webp?family_fingerprint=${URL_FAM}

  React SPA (schema form):
    http://${BROWSER_HOST}:${PORT}/

Ctrl-C to stop.

EOF

exec pixlet serve -i "${HOST}" -p "${PORT}" main.star
