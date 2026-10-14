#!/usr/bin/env bash
# LAPTOP: print the Milestone 4 evidence in screenshot-ready form.
#   - Cloud SQL IP configuration (private IP only, no public IP)
#   - every IAM role binding of the VM's service account, on every resource
#   - Secret Manager: secret names (values hidden) and who may read them
#   - the bucket's newest objects
#
#   ./deploy/m4/07_evidence.sh            # everything
#   ./deploy/m4/07_evidence.sh iam        # just one section: sql | iam | secrets | bucket
set -euo pipefail
cd "$(dirname "$0")"
source ./config.sh
SECTION="${1:-all}"
MEMBER="serviceAccount:${VM_SA_EMAIL}"

# prints "role  <TAB> where" for each binding of $MEMBER in an IAM policy
bindings_of() {
  local where="$1"; shift
  { "$@" --flatten="bindings[].members" --format="value(bindings.role,bindings.members)" 2>/dev/null || true; } \
    | awk -F'\t' -v m="$MEMBER" -v w="$where" '$2 == m { printf "    %-40s %s\n", $1, w }'
}

if [ "$SECTION" = all ] || [ "$SECTION" = sql ]; then
  step "Cloud SQL '$SQL_INSTANCE' - IP configuration"
  gc sql instances describe "$SQL_INSTANCE" --format="table[box](name,databaseVersion,settings.tier,gceZone,ipAddresses[].type.join(','):label=IP_TYPES,ipAddresses[].ipAddress.join(','):label=IP_ADDRESSES,settings.ipConfiguration.ipv4Enabled:label=PUBLIC_IPV4_ENABLED,settings.ipConfiguration.sslMode:label=SSL_MODE)"
  gc sql instances describe "$SQL_INSTANCE" --format="value(settings.ipConfiguration.privateNetwork)" | sed 's/^/    private network: /'
fi

if [ "$SECTION" = all ] || [ "$SECTION" = iam ]; then
  step "IAM role bindings of $VM_SA_EMAIL"
  printf '    %-40s %s\n' "ROLE" "GRANTED ON"
  {
    bindings_of "project $PROJECT_ID"              gc projects get-iam-policy "$PROJECT_ID"
    bindings_of "bucket gs://$BUCKET"              gc storage buckets get-iam-policy "gs://$BUCKET"
    bindings_of "secret $SECRET_DB_PASSWORD"       gc secrets get-iam-policy "$SECRET_DB_PASSWORD"
    bindings_of "secret $SECRET_DB_ROOT_PASSWORD"  gc secrets get-iam-policy "$SECRET_DB_ROOT_PASSWORD"
    bindings_of "repository $AR_REPO"              gc artifacts repositories get-iam-policy "$AR_REPO" --location="$REGION"
  }
  echo
  gc compute instances describe "$VM" --zone "$ZONE" \
    --format="value(serviceAccounts[0].email,serviceAccounts[0].scopes.list())" \
    | awk -F'\t' '{ printf "    VM %s runs as: %s\n    access scope:  %s\n", "'"$VM"'", $1, $2 }'
  KEYS="$(gc iam service-accounts keys list --iam-account="$VM_SA_EMAIL" --managed-by=user --format='value(name)' | wc -l | tr -d ' ')"
  echo "    user-managed keys for this service account: $KEYS"
fi

if [ "$SECTION" = all ] || [ "$SECTION" = secrets ]; then
  step "Secret Manager (names only - values are never shown)"
  gc secrets list --filter="labels.app=gridpulse" \
    --format="table(name.basename():label=SECRET,replication.userManaged.replicas[0].location:label=LOCATION,createTime.date('%Y-%m-%d %H:%M'):label=CREATED)"
  for s in "$SECRET_DB_PASSWORD" "$SECRET_DB_ROOT_PASSWORD"; do
    readers="$({ gc secrets get-iam-policy "$s" --flatten="bindings[].members" \
      --format="value(bindings.role,bindings.members)" 2>/dev/null || true; } \
      | awk -F'\t' '$1 == "roles/secretmanager.secretAccessor" { print $2 }' | paste -sd, -)"
    echo "    $s readable by: ${readers:-project owners only}"
  done
fi

if [ "$SECTION" = all ] || [ "$SECTION" = bucket ]; then
  step "Newest objects in gs://$BUCKET"
  gc storage ls -l "gs://$BUCKET/**" | grep -v '^TOTAL' | sort -k2 | tail -8
fi
