#!/usr/bin/env bash
# LAPTOP, step 4: the Cloud Storage bucket for uploaded infrastructure PDFs.
# Private: uniform bucket-level access (IAM only, no per-object ACLs) and
# public access prevention enforced (it can never be made public by mistake).
#
#   ./deploy/m4/04_bucket.sh
set -euo pipefail
cd "$(dirname "$0")"
source ./config.sh

step "Bucket gs://$BUCKET ($REGION, same region as the VM => no egress charges)"
if gc storage buckets describe "gs://$BUCKET" >/dev/null 2>&1; then
  ok "already exists"
else
  gc storage buckets create "gs://$BUCKET" \
    --location="$REGION" \
    --default-storage-class=STANDARD \
    --uniform-bucket-level-access \
    --public-access-prevention
  ok "created"
fi

gc storage buckets describe "gs://$BUCKET" \
  --format="yaml(name,location,default_storage_class,uniform_bucket_level_access,public_access_prevention)"

echo
echo "Next: ./deploy/m4/05_service_account.sh"
