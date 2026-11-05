#!/usr/bin/env bash
# LAPTOP, step 1: everything Terraform needs before it can run.
#
#  1. checks terraform >= 1.5, gcloud, kubectl, jq
#  2. Application Default Credentials for Terraform (your own Google login)
#  3. the PRIVATE, VERSIONED bucket that holds the Terraform state
#     (gs://gridpulse-509202-tfstate). Terraform cannot create the bucket its own
#     state lives in, so this one bucket is made here - the only resource of the
#     project that is not in terraform/ (see terraform/README.md).
#
#   ./deploy/m6/01_bootstrap_state.sh
set -euo pipefail
cd "$(dirname "$0")"
source ./config.sh

step "Tools"
need terraform "Install it: brew tap hashicorp/tap && brew install hashicorp/tap/terraform"
need gcloud "https://cloud.google.com/sdk/docs/install"
need kubectl "gcloud components install kubectl gke-gcloud-auth-plugin"
need jq "brew install jq"
TF_VERSION="$(terraform version -json | jq -r .terraform_version)"
case "$TF_VERSION" in 0.*|1.[0-4].*) die "terraform $TF_VERSION is too old - need 1.5 or newer (import blocks)";; esac
ok "terraform $TF_VERSION, $(gcloud --version | head -1), kubectl $(kubectl version --client -o json | jq -r .clientVersion.gitVersion)"

step "Application Default Credentials (what Terraform authenticates with)"
if gcloud auth application-default print-access-token >/dev/null 2>&1; then
  ok "already logged in"
else
  note "a browser window opens - log in with the Google account that owns $PROJECT_ID"
  gcloud auth application-default login
fi
gcloud auth application-default set-quota-project "$PROJECT_ID" >/dev/null 2>&1 || true
ok "quota project $PROJECT_ID"

step "APIs Terraform itself talks to"
gc services enable cloudresourcemanager.googleapis.com serviceusage.googleapis.com storage.googleapis.com iam.googleapis.com
ok "enabled"

step "State bucket gs://$TF_STATE_BUCKET"
if gc storage buckets describe "gs://$TF_STATE_BUCKET" >/dev/null 2>&1; then
  ok "already exists"
else
  gc storage buckets create "gs://$TF_STATE_BUCKET" --location="$REGION" \
    --uniform-bucket-level-access --public-access-prevention
  ok "created"
fi
# Versioning: every state write keeps the previous version, so a bad apply or a
# corrupted state can be rolled back.
gc storage buckets update "gs://$TF_STATE_BUCKET" --versioning >/dev/null
gc storage buckets describe "gs://$TF_STATE_BUCKET" \
  --format="yaml(name,location,versioning_enabled,uniform_bucket_level_access,public_access_prevention)"

step "Alert recipients (terraform/notification.auto.tfvars - kept out of git)"
if [ -f "$TF_DIR/notification.auto.tfvars" ]; then
  ok "$(grep -c '@' "$TF_DIR/notification.auto.tfvars") address(es) configured"
else
  cp "$TF_DIR/notification.auto.tfvars.example" "$TF_DIR/notification.auto.tfvars"
  note "created terraform/notification.auto.tfvars from the example -"
  note "PUT THE TEAM'S REAL E-MAIL ADDRESSES IN IT before the next step."
fi

echo
echo "Next: ./deploy/m6/02_terraform.sh"
