#!/usr/bin/env bash
set -euo pipefail
command -v podman >/dev/null 2>&1 || { echo "podman not found" >&2; exit 1; }

podman ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
