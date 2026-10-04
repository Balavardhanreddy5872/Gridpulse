#!/usr/bin/env bash
# VM: pull the exact images that were pushed from the laptop and run them.
# Nothing is built here (--no-build): no pip, no npm, no model training.
#
#   ./deploy/vm_deploy.sh          # runs v1 (or IMAGE_TAG from .env)
set -euo pipefail
cd "$(dirname "$0")/.."

[ -f .env ] || { echo "Missing .env -> run: cp .env.example .env  (then set POSTGRES_PASSWORD)"; exit 1; }

getenv() { grep -E "^$1=" .env | cut -d= -f2- || true; }
REGISTRY="$(getenv REGISTRY)";        REGISTRY="${REGISTRY:-us-central1-docker.pkg.dev/gridpulse-509202/gridpulse}"
IMAGE_TAG="$(getenv IMAGE_TAG)";      IMAGE_TAG="${IMAGE_TAG:-v1}"
FRONTEND_PORT="$(getenv FRONTEND_PORT)"; FRONTEND_PORT="${FRONTEND_PORT:-80}"
PORT_SUFFIX=""; [ "$FRONTEND_PORT" = "80" ] || PORT_SUFFIX=":${FRONTEND_PORT}"

# Milestone 2's hand-started processes must not still be holding the ports.
if sudo ss -ltnp | grep -E ":(${FRONTEND_PORT}|8000)\s" | grep -v docker-proxy; then
  echo
  echo "Ports ${FRONTEND_PORT}/8000 are still held by the Milestone 2 processes listed above."
  echo "Stop them first (RUNBOOK step 5.2), then re-run this script."
  exit 1
fi

docker compose pull
docker compose up -d --no-build --wait
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
