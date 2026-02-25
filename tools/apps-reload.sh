#!/usr/bin/env bash
set -euo pipefail
# Reload systemd user units (quadlet generator)
source "$(dirname "$0")/common.sh"

log "Reloading user systemd"
sd daemon-reload
sd reset-failed || true
sd list-unit-files --no-pager | grep -E 'caddy|dex|grist|minio|n8n|redis|apps-network' || true

