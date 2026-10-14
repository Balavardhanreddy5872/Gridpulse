# shellcheck shell=bash disable=SC2034
# Shared settings for the Milestone 4 scripts (sourced, not executed).
# Nothing in here is secret: passwords are generated straight into Secret
# Manager by 02_secrets.sh and are never written to a file.

PROJECT_ID="${PROJECT_ID:-gridpulse-509202}"
REGION="${REGION:-us-central1}"
ZONE="${ZONE:-us-central1-a}"

# Compute (from Milestones 2/3)
VM="${VM:-gridpulse-vm}"
STATIC_IP_NAME="${STATIC_IP_NAME:-gridpulse-ip}"
AR_REPO="${AR_REPO:-gridpulse}"

# Private Services Access: the IP range Google uses for Cloud SQL inside our VPC
PSA_RANGE_NAME="${PSA_RANGE_NAME:-gridpulse-psa-range}"
PSA_RANGE_START="${PSA_RANGE_START:-10.60.0.0}"
PSA_RANGE_PREFIX="${PSA_RANGE_PREFIX:-20}"            # 10.60.0.0/20

# Cloud SQL
SQL_INSTANCE="${SQL_INSTANCE:-gridpulse-db}"
SQL_TIER="${SQL_TIER:-db-f1-micro}"                    # shared core, ~US$9/month
DB_NAME="${DB_NAME:-gridpulse}"
DB_USER="${DB_USER:-gridpulse}"

# Secret Manager (names only)
SECRET_DB_PASSWORD="${SECRET_DB_PASSWORD:-gridpulse-db-password}"            # app user - the VM can read it
SECRET_DB_ROOT_PASSWORD="${SECRET_DB_ROOT_PASSWORD:-gridpulse-db-root-password}"  # 'postgres' admin - the VM can NOT read it

# Cloud Storage
BUCKET="${BUCKET:-gridpulse-509202-uploads}"

# The VM's own identity
VM_SA_NAME="${VM_SA_NAME:-gridpulse-vm-sa}"
VM_SA_EMAIL="${VM_SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"

gc() { gcloud --project "$PROJECT_ID" "$@"; }
step() { printf '\n\033[1m==> %s\033[0m\n' "$*"; }
ok()   { printf '    \033[32mOK\033[0m  %s\n' "$*"; }
note() { printf '    ..  %s\n' "$*"; }
die()  { printf '\n\033[31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }
