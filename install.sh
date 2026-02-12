#!/usr/bin/env bash
set -euo pipefail

# apps-deployment install script
#
# Repository structure (git working tree):
#
#   apps-deployment/                 (REPO_DIR)
#     install.sh                     this installer
#     quadlets/                      Podman Quadlet unit files
#                                   (e.g. *.container, *.network, optionally *.volume, *.kube)
#     config/                        configuration files referenced by quadlets (mounted into containers)
#     secrets/
#       apps-secrets.env.template    secrets env template (safe to commit; NO real secrets)
#     tools/                         convenience scripts for managing quadlets (start/stop/status/logs)
#     www-template/                  optional static website template files
#
# What this installer does (rootless; does NOT install Podman):
#
# - Creates user-owned deployment directories:
#     ~/.config/apps-deployment/               (BASE_CONFIG_DIR)
#     ~/.config/apps-deployment/secrets/       (SECRETS_DIR)
#     ~/.local/share/apps-deployment/persist/  (PERSIST_DIR)
#     ~/.config/containers/systemd/            (Quadlet search path for systemd --user)
#     ~/.local/bin/                            (destination for convenience script symlinks)
#
# - Creates persistence subfolders under PERSIST_DIR:
#     caddy-data, caddy-state, dex, grist, minio, n8n, redis, www
#
# - Creates a symlink to the repo config tree so edits in git apply immediately:
#     ~/.config/apps-deployment/config  ->  <REPO_DIR>/config
#
# - Creates the secrets env file once by copying from the repo template (if missing):
#     ~/.config/apps-deployment/secrets/apps-secrets.env
#   and enforces permissions: chmod 600.
#   The secrets file is intentionally NOT a symlink so it remains host-specific
#   and stays untracked by git.
#
# - Optionally populates the website persistence directory from www-template:
#     rsync <REPO_DIR>/www-template/.  ->  ~/.local/share/apps-deployment/persist/www/
#
# - Creates symlinks for all quadlet unit files into:
#     ~/.config/containers/systemd/
#   so editing quadlets in the repo updates the deployed units immediately.
#   Then runs: systemctl --user daemon-reload
#
# - Optionally symlinks pre-made helper scripts from <REPO_DIR>/tools into:
#     ~/.local/bin/
#
# Re-running the installer is safe and re-links quadlets/config/tools;
# it does not overwrite existing secrets.
# 
# Run minio-init.sh tool to create the minio bucket.


# Distribution
APP_NAME="apps-deployment"
REPO_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
QUADLETS_DIR="${REPO_DIR}/quadlets"
REPO_CONFIG_DIR="${REPO_DIR}/config"
REPO_TOOLS_DIR="${REPO_DIR}/tools"
WWW_TEMPLATE_DIR="${REPO_DIR}/www-template"

# Secrets template
SECRETS_TEMPLATE="${REPO_DIR}/secrets/apps-secrets.env.template"

# Config install dirs
BASE_CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/${APP_NAME}"
SECRETS_DIR="${BASE_CONFIG_DIR}/secrets"
SECRETS_FILE="${SECRETS_DIR}/apps-secrets.env"
INSTALL_CONFIG_LINK="${BASE_CONFIG_DIR}/config"
QUADLET_USER_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/containers/systemd"
BIN_DIR="${HOME}/.local/bin"

# Persist install dirs
BASE_DATA_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/${APP_NAME}"
PERSIST_DIR="${BASE_DATA_DIR}/persist"
PERSIST_SUBDIRS=(
  "caddy-data"
  "caddy-state"
  "dex"
  "grist"
  "minio"
  "n8n"
  "redis"
  "www"
)

# Tools
log()  { printf "\n\033[1;32m==>\033[0m %s\n" "$*"; }
warn() { printf "\n\033[1;33m[warn]\033[0m %s\n" "$*"; }
die()  { printf "\n\033[1;31m[err]\033[0m %s\n" "$*"; exit 1; }
need_cmd() { command -v "$1" >/dev/null 2>&1 || die "Missing command: $1"; }

log "Check needed commands"
need_cmd mkdir
need_cmd ln
need_cmd find
need_cmd readlink
need_cmd rsync
need_cmd systemctl
need_cmd chmod
need_cmd podman

log "Check distribution"
[[ -d "${QUADLETS_DIR}" ]] || die "Missing: ${QUADLETS_DIR}"
[[ -d "${REPO_CONFIG_DIR}" ]] || die "Missing: ${REPO_CONFIG_DIR}"
[[ -f "${SECRETS_TEMPLATE}" ]] || die "Missing secrets template: ${SECRETS_TEMPLATE}"
[[ -d "${REPO_TOOLS_DIR}" ]]  || warn "Missing: ${REPO_TOOLS_DIR} (tools links will be skipped)"

log "Create base directories"
mkdir -p "${BASE_CONFIG_DIR}" "${SECRETS_DIR}" "${QUADLET_USER_DIR}" "${BIN_DIR}" "${PERSIST_DIR}"

log "Create persistence subfolders"
for d in "${PERSIST_SUBDIRS[@]}"; do
  mkdir -p "${PERSIST_DIR}/${d}"
done

log "Symlink convenience shortcut in home: ~/apps-persist -> ${PERSIST_DIR}"
if [[ -e "${HOME}/apps-persist" && ! -L "${HOME}/apps-persist" ]]; then
  warn "~/apps-persist exists and is not a symlink; not overwriting."
else
  ln -sfn "${PERSIST_DIR}" "${HOME}/apps-persist"
fi

log "Symlink config to repo (editable in git working tree)"
if [[ -e "${INSTALL_CONFIG_LINK}" && ! -L "${INSTALL_CONFIG_LINK}" ]]; then
  warn "${INSTALL_CONFIG_LINK} exists and is not a symlink; not overwriting."
else
  ln -sfn "${REPO_CONFIG_DIR}" "${INSTALL_CONFIG_LINK}"
fi

log "Install secrets env file from template (create if missing)"
if [[ ! -f "${SECRETS_FILE}" ]]; then
  rsync -a "${SECRETS_TEMPLATE}" "${SECRETS_FILE}"
fi
chmod 600 "${SECRETS_FILE}"

log "Symlink convenience shortcut in home: ~/apps-secrets -> ${SECRETS_FILE}"
if [[ -e "${HOME}/apps-secrets" && ! -L "${HOME}/apps-secrets" ]]; then
  warn "~/apps-secrets exists and is not a symlink; not overwriting."
else
  ln -sfn "${SECRETS_FILE}" "${HOME}/apps-secrets"
fi

log "Populate www from www-template"
if [[ -d "${WWW_TEMPLATE_DIR}" ]]; then
  rsync -a --ignore-existing "${WWW_TEMPLATE_DIR}/." "${PERSIST_DIR}/www/"
else
  warn "Missing: ${WWW_TEMPLATE_DIR} (skipping www population)"
fi

log "Remove stale quadlet symlinks from ${QUADLET_USER_DIR}"
find "${QUADLET_USER_DIR}" -maxdepth 1 -type l \( \
  -name '*.container' -o -name '*.network' -o -name '*.volume' -o -name '*.kube' \
\) 2>/dev/null | while read -r l; do
  [[ ! -e "$l" ]] && rm -f "$l"
done

log "Symlink quadlets into ${QUADLET_USER_DIR}"
shopt -s nullglob
quadlet_files=( "${QUADLETS_DIR}"/*.container "${QUADLETS_DIR}"/*.network "${QUADLETS_DIR}"/*.volume "${QUADLETS_DIR}"/*.kube )
shopt -u nullglob
[[ ${#quadlet_files[@]} -gt 0 ]] || die "No quadlets found in ${QUADLETS_DIR}"

for f in "${quadlet_files[@]}"; do
  ln -sfn "$f" "${QUADLET_USER_DIR}/$(basename "$f")"
done

log "Symlink convenience scripts from repo tools/ into ${BIN_DIR}"
if [[ -d "${REPO_TOOLS_DIR}" ]]; then
  shopt -s nullglob
  tool_files=( "${REPO_TOOLS_DIR}"/* )
  shopt -u nullglob
  for f in "${tool_files[@]}"; do
    [[ -f "$f" ]] || continue
    [[ -x "$f" ]] || continue   # optional: only executables
    ln -sfn "$f" "${BIN_DIR}/$(basename "$f")"
  done
fi

log "Reload user systemd generator"
systemctl --user daemon-reload
systemctl --user reset-failed || true

log "Done."
cat <<EOF

Configuration symlink:
  ${INSTALL_CONFIG_LINK}

Secrets:
  ${HOME}/apps-secrets -> ${SECRETS_FILE}

Persistence directory and website:
  ${HOME}/apps-persist -> ${PERSIST_DIR}

Podman quadlets:
  ${QUADLET_USER_DIR}

Tools:
  ${BIN_DIR}

Enable linger for the current user so systemd --user units
can start at boot without an interactive login with:
  sudo loginctl enable-linger ${USER}

Run minio-init.sh tool to create the minio bucket,
and activate minio for grist in its quadlet.

EOF
