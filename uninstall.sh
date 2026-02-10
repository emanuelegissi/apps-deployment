#!/usr/bin/env bash
set -euo pipefail

APP_NAME="apps-deployment"

# Repo root = folder where this script lives
REPO_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
QUADLETS_DIR="${REPO_DIR}/quadlets"
REPO_CONFIG_DIR="${REPO_DIR}/config"
REPO_TOOLS_DIR="${REPO_DIR}/tools"

BASE_CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/${APP_NAME}"
INSTALL_CONFIG_LINK="${BASE_CONFIG_DIR}/config"
SECRETS_DIR="${BASE_CONFIG_DIR}/secrets"

BASE_DATA_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/${APP_NAME}"
PERSIST_DIR="${BASE_DATA_DIR}/persist"

QUADLET_USER_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/containers/systemd"
BIN_DIR="${HOME}/.local/bin"

PURGE=0
DISABLE_LINGER=0
FORCE=0

log()  { printf "\n\033[1;32m==>\033[0m %s\n" "$*"; }
warn() { printf "\n\033[1;33m[warn]\033[0m %s\n" "$*"; }
die()  { printf "\n\033[1;31m[err]\033[0m %s\n" "$*"; exit 1; }

usage() {
  cat <<EOF
Usage: $0 [--purge] [--disable-linger] [--force]

  --purge           Remove secrets and persistence data too (DESTRUCTIVE)
  --disable-linger  Disable linger for the current user (requires sudo)
  --force           Do not prompt for confirmation

Default behavior keeps secrets + persist (non-destructive).
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --purge) PURGE=1; shift ;;
    --disable-linger) DISABLE_LINGER=1; shift ;;
    --force) FORCE=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "Unknown option: $1" ;;
  esac
done

confirm() {
  local msg="$1"
  if [[ "$FORCE" -eq 1 ]]; then
    return 0
  fi
  read -r -p "${msg} [y/N] " ans
  [[ "${ans}" == "y" || "${ans}" == "Y" ]]
}

# ----- Stop/disable units (best-effort) -----
log "Stopping and disabling user units (best-effort)"
systemctl --user daemon-reload || true
systemctl --user stop  apps.network 2>/dev/null || true
systemctl --user stop  caddy.service dex.service grist.service minio.service n8n.service redis.service 2>/dev/null || true
systemctl --user disable apps.network 2>/dev/null || true
systemctl --user disable caddy.service dex.service grist.service minio.service n8n.service redis.service 2>/dev/null || true

# ----- Remove quadlet symlinks that point into this repo -----
log "Removing quadlet symlinks pointing into this repo from: ${QUADLET_USER_DIR}"
mkdir -p "${QUADLET_USER_DIR}"

shopt -s nullglob
for link in "${QUADLET_USER_DIR}"/*.container "${QUADLET_USER_DIR}"/*.network "${QUADLET_USER_DIR}"/*.volume "${QUADLET_USER_DIR}"/*.kube; do
  [[ -L "$link" ]] || continue
  target="$(readlink -f "$link" || true)"
  if [[ -n "$target" && "$target" == "${REPO_DIR}/"* ]]; then
    rm -f "$link"
  fi
done
shopt -u nullglob

# ----- Remove config symlink if it points into this repo -----
log "Removing config symlink (only if it points into this repo)"
if [[ -L "${INSTALL_CONFIG_LINK}" ]]; then
  target="$(readlink -f "${INSTALL_CONFIG_LINK}" || true)"
  if [[ -n "$target" && "$target" == "${REPO_DIR}/"* ]]; then
    rm -f "${INSTALL_CONFIG_LINK}"
  else
    warn "Config link exists but does not point into this repo; leaving it: ${INSTALL_CONFIG_LINK}"
  fi
fi

# ----- Remove tool symlinks pointing into this repo -----
log "Removing tool symlinks pointing into this repo from: ${BIN_DIR}"
mkdir -p "${BIN_DIR}"
shopt -s nullglob
for link in "${BIN_DIR}"/*; do
  [[ -L "$link" ]] || continue
  target="$(readlink -f "$link" || true)"
  if [[ -n "$target" && "$target" == "${REPO_DIR}/tools/"* ]]; then
    rm -f "$link"
  fi
done
shopt -u nullglob

# ----- Reload systemd --user to drop generated units -----
log "Reloading systemd --user"
systemctl --user daemon-reload || true
systemctl --user reset-failed || true

# ----- Optionally purge secrets + persist -----
if [[ "$PURGE" -eq 1 ]]; then
  warn "PURGE enabled: secrets and persistence data will be deleted."
  if confirm "Proceed with deleting ${SECRETS_DIR} and ${PERSIST_DIR}?"; then
    rm -rf "${SECRETS_DIR}" "${PERSIST_DIR}"
    # If empty, remove top-level dirs too
    rmdir "${BASE_CONFIG_DIR}" 2>/dev/null || true
    rmdir "${BASE_DATA_DIR}" 2>/dev/null || true
  else
    warn "Purge cancelled; leaving secrets and persistence data intact."
  fi
else
  log "Keeping secrets and persistence data (use --purge to remove)."
fi

# ----- Optionally disable linger -----
if [[ "$DISABLE_LINGER" -eq 1 ]]; then
  log "Disabling linger for ${USER} (requires sudo)"
  if command -v sudo >/dev/null 2>&1; then
    sudo loginctl disable-linger "${USER}" || warn "Could not disable linger."
  else
    warn "sudo not found; cannot disable linger automatically."
  fi
fi

log "Clean complete."
cat <<EOF

Remaining (if any):
  Secrets:    ${SECRETS_DIR}      $( [[ -d "${SECRETS_DIR}" ]] && echo "(kept)" || echo "(removed)" )
  Persist:    ${PERSIST_DIR}      $( [[ -d "${PERSIST_DIR}" ]] && echo "(kept)" || echo "(removed)" )

Quadlet dir:
  ${QUADLET_USER_DIR}

EOF

