#!/usr/bin/env bash
# VM: pull the exact images that were pushed from the laptop and run them.
# Nothing is built here (--no-build): no pip, no npm, no model training.
# Milestone 4: no .env is needed or read - all config is in docker-compose.yml
# and the DB password comes from Secret Manager at runtime.
#
#   ./deploy/vm_deploy.sh          # runs v2
#   ./deploy/vm_deploy.sh v3       # a later release
set -euo pipefail
cd "$(dirname "$0")/.."

export IMAGE_TAG="${1:-${IMAGE_TAG:-v2}}"
REGISTRY="${REGISTRY:-us-central1-docker.pkg.dev/gridpulse-509202/gridpulse}"
FRONTEND_PORT="${FRONTEND_PORT:-80}"
PORT_SUFFIX=""; [ "$FRONTEND_PORT" = "80" ] || PORT_SUFFIX=":${FRONTEND_PORT}"

[ ! -f .env ] || { echo "A .env file exists in $(pwd) - Milestone 4 must not use one. Delete it first."; exit 1; }

docker compose pull
docker compose up -d --no-build --remove-orphans --wait
docker compose ps

echo
echo "==> Digests running on this VM (compare with the laptop / Artifact Registry)"
for svc in backend frontend; do
  docker image inspect --format '{{index .RepoDigests 0}}' "${REGISTRY}/gridpulse-${svc}:${IMAGE_TAG}"
done

EXTERNAL_IP=$(curl -s -H "Metadata-Flavor: Google" \
  "http://metadata.google.internal/computeMetadata/v1/instance/network-interfaces/0/access-configs/0/external-ip" || true)
echo
echo "==> Health: $(curl -s "http://localhost${PORT_SUFFIX}/api/health")"
echo "==> Open   http://${EXTERNAL_IP:-<VM external IP>}${PORT_SUFFIX}        (dashboard)"
echo "           http://${EXTERNAL_IP:-<VM external IP>}:8000/docs  (API docs)"
