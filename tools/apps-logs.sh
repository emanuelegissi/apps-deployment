#!/usr/bin/env bash
set -euo pipefail
command -v podman >/dev/null 2>&1 || { echo "podman not found" >&2; exit 1; }

name="${1:-}"
if [[ -z "$name" ]]; then
  echo "Usage: $(basename "$0") <container_name>"
  echo "Example: $(basename "$0") caddy"
  exit 1
fi

podman logs -f --tail=200 "$name"
