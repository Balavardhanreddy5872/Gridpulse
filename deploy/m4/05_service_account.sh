#!/usr/bin/env bash
# LAPTOP, step 5: a dedicated, least-privilege identity for the VM.
#
# The Compute Engine *default* service account has the project-wide Editor
# role. gridpulse-vm-sa instead gets only what the app needs, each grant
# scoped to the single resource it is for:
#
#   role                                  on                          why
#   roles/storage.objectCreator           bucket only                 upload PDFs
#   roles/storage.objectViewer            bucket only                 read PDFs back / list
#   roles/secretmanager.secretAccessor    gridpulse-db-password only  read the app's DB password
#   roles/cloudsql.client                 project                     look up the instance's private IP
#   roles/artifactregistry.reader         gridpulse repo only         docker pull the images
#
# It can NOT read the 'postgres' admin password, delete objects, change the
# bucket, or touch anything else in the project. No key is ever created for it.
#
#   ./deploy/m4/05_service_account.sh
set -euo pipefail
cd "$(dirname "$0")"
source ./config.sh
MEMBER="serviceAccount:${VM_SA_EMAIL}"

step "Service account $VM_SA_EMAIL"
if gc iam service-accounts describe "$VM_SA_EMAIL" >/dev/null 2>&1; then
  ok "already exists"
else
  gc iam service-accounts create "$VM_SA_NAME" \
    --display-name="GridPulse VM runtime" \
    --description="Identity of gridpulse-vm: Cloud SQL lookup, upload bucket, DB secret, image pulls. No keys."
  ok "created"
  sleep 10   # new service accounts take a few seconds to become usable in IAM bindings
fi

step "Bucket gs://$BUCKET: objectCreator + objectViewer"
for role in roles/storage.objectCreator roles/storage.objectViewer; do
  gc storage buckets add-iam-policy-binding "gs://$BUCKET" --member="$MEMBER" --role="$role" >/dev/null
  ok "$role"
done

step "Secret $SECRET_DB_PASSWORD: secretAccessor (this secret only)"
gc secrets add-iam-policy-binding "$SECRET_DB_PASSWORD" --member="$MEMBER" \
  --role=roles/secretmanager.secretAccessor >/dev/null
ok "roles/secretmanager.secretAccessor"

step "Project $PROJECT_ID: Cloud SQL Client"
gc projects add-iam-policy-binding "$PROJECT_ID" --member="$MEMBER" \
  --role=roles/cloudsql.client --condition=None >/dev/null
ok "roles/cloudsql.client"

step "Artifact Registry repo '$AR_REPO': reader"
gc artifacts repositories add-iam-policy-binding "$AR_REPO" --location="$REGION" \
  --member="$MEMBER" --role=roles/artifactregistry.reader >/dev/null
ok "roles/artifactregistry.reader"

step "User-managed keys for this service account (must be none)"
KEYS="$(gc iam service-accounts keys list --iam-account="$VM_SA_EMAIL" --managed-by=user --format='value(name)' | wc -l | tr -d ' ')"
if [ "$KEYS" = "0" ]; then ok "0 keys - the VM authenticates through the metadata server"; else die "$KEYS user-managed key(s) exist - delete them"; fi

echo
echo "Next: ./deploy/m4/06_switch_vm_identity.sh   (stops the VM for ~1-2 minutes)"
