#!/usr/bin/env bash
# LAPTOP: build both GridPulse images for linux/amd64 (the VM's CPU), push them
# to Artifact Registry with an explicit version tag + :latest, then print the
# digests so you can compare them with the VM later.
#
#   ./deploy/build_and_push.sh v2       # Milestone 4 release (default)
#
# Builds from docker-compose.yml (the cloud stack). Needs no .env and never
# reads one: the images contain no configuration secrets at all.
set -euo pipefail
cd "$(dirname "$0")/.."

PROJECT_ID="${PROJECT_ID:-gridpulse-509202}"
REGION="${REGION:-us-central1}"
REPO="${REPO:-gridpulse}"
export IMAGE_TAG="${1:-v2}"
export REGISTRY="${REGION}-docker.pkg.dev/${PROJECT_ID}/${REPO}"
# One clean single-platform manifest per tag (no extra attestation entries).
export BUILDX_NO_DEFAULT_ATTESTATIONS=1

COMPOSE=(docker compose -f docker-compose.yml)

# One-time: let Docker use your gcloud login for *.pkg.dev (no-op if already set)
if ! grep -qs "${REGION}-docker.pkg.dev" "${HOME}/.docker/config.json"; then
  gcloud auth configure-docker "${REGION}-docker.pkg.dev" --quiet
fi

echo "==> Building ${REGISTRY}/gridpulse-{backend,frontend}:${IMAGE_TAG}  (linux/amd64)"
"${COMPOSE[@]}" build backend frontend

echo "==> Pushing :${IMAGE_TAG}"
"${COMPOSE[@]}" push backend frontend

echo "==> Also tagging :latest"
for svc in backend frontend; do
  docker tag  "${REGISTRY}/gridpulse-${svc}:${IMAGE_TAG}" "${REGISTRY}/gridpulse-${svc}:latest"
  docker push "${REGISTRY}/gridpulse-${svc}:latest"
done

echo
echo "==> Artifact Registry contents"
gcloud artifacts docker images list "${REGISTRY}" --include-tags

echo
echo "==> Local digests (these must match what the VM pulls)"
for svc in backend frontend; do
  docker image inspect --format '{{index .RepoDigests 0}}' "${REGISTRY}/gridpulse-${svc}:${IMAGE_TAG}"
done

echo
echo "==> Local image sizes"
docker image ls --format 'table {{.Repository}}:{{.Tag}}\t{{.Size}}' | grep -E "REPOSITORY|gridpulse-.*:${IMAGE_TAG}"
