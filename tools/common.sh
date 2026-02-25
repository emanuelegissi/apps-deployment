#!/usr/bin/env bash
set -euo pipefail

# Unit names (adjust if your quadlet filenames differ)
NET_UNIT="apps-network.service"

UNITS=(
  "caddy.service"
  "n8n.service"
  "redis.service"
  "minio.service"
  "dex.service"
  "grist.service"
)

# Helpers
log()  { printf "\033[1;32m==>\033[0m %s\n" "$*"; }
warn() { printf "\033[1;33m[warn]\033[0m %s\n" "$*"; }

need_cmd() { command -v "$1" >/dev/null 2>&1 || { echo "Missing command: $1" >&2; exit 1; }; }

need_cmd systemctl
need_cmd journalctl

sd() { systemctl --user "$@"; }
jc() { journalctl --user "$@"; }

# Print known units in a sensible order: network first, then containers
units_ordered() {
  printf '%s\n' "${NET_UNIT}"
  printf '%s\n' "${UNITS[@]}"
}
