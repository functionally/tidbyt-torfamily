#!/usr/bin/env bash
# Render one frame to out.webp
set -euo pipefail
cd "$(dirname "$0")/.."

if [[ ! -f config.yaml ]]; then
  echo "ERROR: config.yaml is missing. Run: cp config-example.yaml config.yaml" >&2
  exit 1
fi

FAMILY="$(yq -r '.family_fingerprint' config.yaml)"
if [[ -z "$FAMILY" || "$FAMILY" == "null" ]]; then
  echo "ERROR: family_fingerprint not set in config.yaml" >&2
  exit 1
fi

pixlet render main.star "family_fingerprint=${FAMILY}" -o out.webp
echo "Rendered: $PWD/out.webp"
