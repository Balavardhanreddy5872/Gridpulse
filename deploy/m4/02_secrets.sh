#!/usr/bin/env bash
# LAPTOP, step 2: generate the database passwords DIRECTLY into Secret Manager.
# They are piped from `openssl rand` into `gcloud secrets create` and never
# touch a file, the terminal, the repo, or an image.
#
#   ./deploy/m4/02_secrets.sh
set -euo pipefail
cd "$(dirname "$0")"
source ./config.sh

create_secret() {
  local name="$1" purpose="$2"
  if gc secrets describe "$name" >/dev/null 2>&1; then
    ok "$name already exists (keeping its current value)"
    return
  fi
  # 48 hex characters = 192 random bits; letters+digits only, safe in any URL.
  openssl rand -hex 24 | tr -d '\n' | gc secrets create "$name" \
    --replication-policy=user-managed --locations="$REGION" \
    --labels=app=gridpulse --data-file=- >/dev/null
  ok "created $name  ($purpose)"
}

step "Creating secrets in Secret Manager ($REGION)"
create_secret "$SECRET_DB_PASSWORD"      "password of DB user '$DB_USER', read by the app at runtime"
create_secret "$SECRET_DB_ROOT_PASSWORD" "password of the 'postgres' admin user, humans only"

step "Secrets in project $PROJECT_ID (names only - values are never printed)"
gc secrets list --filter="labels.app=gridpulse" \
  --format="table(name.basename():label=SECRET, replication.userManaged.replicas[0].location:label=LOCATION, createTime.date('%Y-%m-%d %H:%M'):label=CREATED)"

echo
echo "Next: ./deploy/m4/03_cloudsql.sh"
