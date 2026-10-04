#!/usr/bin/env bash
# VM, ONE TIME: install Docker Engine + the Compose plugin, let the current
# user run docker without sudo, and log Docker in to Artifact Registry with
# the VM's own service account (no key files are copied to the VM).
#
#   bash deploy/vm_setup.sh      # then log out and SSH back in
set -euo pipefail
REGION="${REGION:-us-central1}"

sudo apt-get update -y
sudo apt-get install -y docker.io docker-compose-v2
sudo systemctl enable --now docker
sudo usermod -aG docker "$USER"

# Ubuntu images on GCE ship the gcloud CLI; install it if this one doesn't.
if ! command -v gcloud >/dev/null 2>&1; then
  sudo snap install google-cloud-cli --classic
fi

# Writes the credential helper into ~/.docker/config.json for THIS user.
# (Run docker as this user, not with sudo, or root won't have the helper.)
gcloud auth configure-docker "${REGION}-docker.pkg.dev" --quiet

echo
docker --version
docker compose version
echo
echo "Done. Log out and SSH back in (or run: newgrp docker) so you can use docker without sudo."
