#!/usr/bin/env bash
set -euo pipefail

MC_IMAGE="docker.io/minio/mc:RELEASE.2025-07-21T05-28-08Z-cpuv1"

# Load secrets
set -a
source "$HOME/apps-secrets/apps-secrets.env"
set +a

MINIO_ROOT_USER="${ADMIN_EMAIL}"
MINIO_ROOT_PASSWORD="${DEFAULT_PASSWORD}"
MINIO_DEFAULT_BUCKET="${MINIO_DEFAULT_BUCKET}" 

podman run --rm --network "container:minio" \
  -e "MC_HOST_myminio=http://${ADMIN_EMAIL}:${DEFAULT_PASSWORD}@127.0.0.1:9000" \
  "$MC_IMAGE" \
  mb myminio/$MINIO_DEFAULT_BUCKET 2>/dev/null || true

podman run --rm --network "container:minio" \
  -e "MC_HOST_myminio=http://${ADMIN_EMAIL}:${DEFAULT_PASSWORD}@127.0.0.1:9000" \
  "$MC_IMAGE" \
  version enable myminio/$MINIO_DEFAULT_BUCKET
