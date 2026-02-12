#!/usr/bin/env bash
set -euo pipefail

# apps-deployment uninstall script
#
# Default (non-destructive):
#   - Removes symlinks that point into THIS repo:
#       ~/.config/containers/systemd/*.container|*.network|*.volume|*.kube
#       ~/.config/apps-deployment/config  (if it points into this repo)
#       ~/.local/bin/*                    (if it points into this repo's tools/)
#       ~/apps-persist                    (if it points to this deployment persist)
#   - Keeps secrets + persist unless --purge is passed
#
# Destructive mode (--purge):
#   - Also deletes:
#       ~/.config/apps-deployment/secrets
#       ~/.local/share/apps-deployment/persist

APP_NAME="apps-deployment"

# Repo root = folder where this script lives (git working tree)
REPO_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
QUADLETS_DIR="${REPO_DIR}/quadlets"

# Deployed locations (user)
BASE_CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/${APP_NAME}"
INSTALL_CONFIG_LINK="${BASE_CONFIG_DIR}/config"
SECRETS_DIR="${BASE_CONFIG_DIR}/secrets"

BASE_DATA_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/${APP_NAME}"
PERSIST_DIR="${BASE_DATA_DIR}/persist"

QUADLET_USER_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/containers/systemd"
BIN_DIR="${HOME}/.local/bin"

# Flags
PURGE=0
FORCE=0

log()  { printf "\n\033[1;32m==>\033[0m %s\n" "$*"; }
warn() { printf "\n\033[1;33m[warn]\033[0m %s\n" "$*"; }
die()  { printf "\n\033[1;31m[err]\033[0m %s\n" "$*"; exit 1; }

usage() {
  cat <<EOF
Usage: $0 [--purge] [--force]

  --purge           Remove secrets and persistence data too (DESTRUCTIVE)
  --force           Do not prompt for confirmation

Default behavior keeps secrets + persist (non-destructive).
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --purge) PURGE=1; shift ;;
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

need_cmd() { command -v "$1" >/dev/null 2>&1 || die "Missing command: $1"; }

log "Check needed commands"
need_cmd systemctl
need_cmd readlink
need_cmd mkdir
need_cmd rm
need_cmd rmdir

# Remove quadlet symlinks in ~/.config/containers/systemd that point into THIS repo.
# This avoids deleting other unrelated quadlets the user might have.

log "Removing quadlet symlinks pointing into this repo from: ${QUADLET_USER_DIR}"
mkdir -p "${QUADLET_USER_DIR}"

shopt -s nullglob
for link in "${QUADLET_USER_DIR}"/*.container "${QUADLET_USER_DIR}"/*.network "${QUADLET_USER_DIR}"/*.volume "${QUADLET_USER_DIR}"/*.kube; do
  [[ -L "$link" ]] || continue
  target="$(readlink -f "$link" 2>/dev/null || true)"
  if [[ -n "$target" && "$target" == "${REPO_DIR}/"* ]]; then
    rm -f "$link"
  fi
done
shopt -u nullglob

# Remove ~/apps-persist convenience symlink if it points to this deployment.

log "Removing ~/apps-persist symlink (only if it points to this deployment)"
if [[ -L "${HOME}/apps-persist" ]]; then
  target="$(readlink -f "${HOME}/apps-persist" 2>/dev/null || true)"
  if [[ -n "$target" && "$target" == "${PERSIST_DIR}" ]]; then
    rm -f "${HOME}/apps-persist"
  else
    warn "~/apps-persist exists but does not point to ${PERSIST_DIR}; leaving it."
  fi
fi

# Remove ~/apps-secrets convenience symlink if it points to this deployment secrets file.

log "Removing ~/apps-secrets symlink (only if it points to this deployment)"
if [[ -L "${HOME}/apps-secrets" ]]; then
  target="$(readlink -f "${HOME}/apps-secrets" 2>/dev/null || true)"
  if [[ -n "$target" && "$target" == "${SECRETS_DIR}/apps-secrets.env" ]]; then
    rm -f "${HOME}/apps-secrets"
  else
    warn "~/apps-secrets exists but does not point to ${SECRETS_DIR}/apps-secrets.env; leaving it."
  fi
fi

# Remove config symlink if it points into THIS repo.

log "Removing config symlink (only if it points into this repo)"
if [[ -L "${INSTALL_CONFIG_LINK}" ]]; then
  target="$(readlink -f "${INSTALL_CONFIG_LINK}" 2>/dev/null || true)"
  if [[ -n "$target" && "$target" == "${REPO_DIR}/"* ]]; then
    rm -f "${INSTALL_CONFIG_LINK}"
  else
    warn "Config link exists but does not point into this repo; leaving it: ${INSTALL_CONFIG_LINK}"
  fi
fi

# Remove tool symlinks pointing into THIS repo's tools/ directory.

log "Removing tool symlinks pointing into this repo from: ${BIN_DIR}"
mkdir -p "${BIN_DIR}"

shopt -s nullglob
for link in "${BIN_DIR}"/*; do
  [[ -L "$link" ]] || continue
  target="$(readlink -f "$link" 2>/dev/null || true)"
  if [[ -n "$target" && "$target" == "${REPO_DIR}/tools/"* ]]; then
    rm -f "$link"
  fi
done
shopt -u nullglob

# Reload systemd --user to drop generated units / reset failed state.

log "Reloading systemd --user"
systemctl --user daemon-reload || true
systemctl --user reset-failed || true

# Optionally purge secrets + persist (DESTRUCTIVE).

if [[ "$PURGE" -eq 1 ]]; then
  warn "PURGE enabled: secrets and persistence data will be deleted."
  if confirm "Proceed with deleting ${SECRETS_DIR} and ${PERSIST_DIR}?"; then
    sudo rm -rf "${SECRETS_DIR}" "${PERSIST_DIR}"
    # If empty, remove top-level dirs too (best-effort)
    rmdir "${BASE_CONFIG_DIR}" 2>/dev/null || true
    rmdir "${BASE_DATA_DIR}" 2>/dev/null || true
  else
    warn "Purge cancelled; leaving secrets and persistence data intact."
  fi
else
  log "Keeping secrets and persistence data (use --purge to remove)."
fi

log "Clean complete."
cat <<EOF

Remaining (if any):
  Secrets:    ${SECRETS_DIR}      $( [[ -d "${SECRETS_DIR}" ]] && echo "(kept)" || echo "(removed)" )
  Persist:    ${PERSIST_DIR}      $( [[ -d "${PERSIST_DIR}" ]] && echo "(kept)" || echo "(removed)" )

Quadlet dir:
  ${QUADLET_USER_DIR}

EOF

