#!/usr/bin/env bash
# LAPTOP, step 3: create the managed database - Cloud SQL for PostgreSQL 16
# with a PRIVATE IP ONLY (no public IP at all), TLS required, daily backups.
# Creating the instance takes ~5-15 minutes.
#
#   ./deploy/m4/03_cloudsql.sh
set -euo pipefail
cd "$(dirname "$0")"
source ./config.sh

NETWORK="$(gc compute instances describe "$VM" --zone "$ZONE" --format='value(networkInterfaces[0].network.basename())')"

instance_state() { gc sql instances describe "$SQL_INSTANCE" --format='value(state)' 2>/dev/null || true; }

step "Cloud SQL instance '$SQL_INSTANCE' (Postgres 16, $SQL_TIER, $ZONE, private IP only)"
if [ -n "$(instance_state)" ]; then
  ok "instance already exists"
else
  ROOT_PW="$(gc secrets versions access latest --secret="$SECRET_DB_ROOT_PASSWORD")"
  note "creating - this is the slow step (5-15 min). Leave the terminal open."
  # --no-assign-ip     : NO public IPv4 address
  # --network          : private IP from the peered range reserved in step 1
  # --ssl-mode=ENCRYPTED_ONLY : unencrypted connections are refused
  gc sql instances create "$SQL_INSTANCE" \
    --database-version=POSTGRES_16 \
    --edition=enterprise \
    --tier="$SQL_TIER" \
    --region="$REGION" --zone="$ZONE" \
    --availability-type=zonal \
    --storage-type=SSD --storage-size=10GB --storage-auto-increase \
    --network="projects/${PROJECT_ID}/global/networks/${NETWORK}" \
    --no-assign-ip \
    --ssl-mode=ENCRYPTED_ONLY \
    --backup-start-time=08:00 --retained-backups-count=7 \
    --deletion-protection \
    --root-password="$ROOT_PW" \
    || note "gcloud stopped waiting early - checking the instance status instead"
  unset ROOT_PW
fi

for _ in $(seq 1 60); do
  state="$(instance_state)"
  [ "$state" = "RUNNABLE" ] && break
  [ -z "$state" ] && die "the instance was not created - read the gcloud error above"
  note "state: $state ... waiting 20s"
  sleep 20
done
[ "$(instance_state)" = "RUNNABLE" ] || die "instance is not RUNNABLE yet - re-run this script in a few minutes"
ok "instance is RUNNABLE"

step "Database '$DB_NAME'"
if gc sql databases describe "$DB_NAME" --instance="$SQL_INSTANCE" >/dev/null 2>&1; then
  ok "already exists"
else
  gc sql databases create "$DB_NAME" --instance="$SQL_INSTANCE" >/dev/null
  ok "created"
fi

step "Database user '$DB_USER' (password = secret $SECRET_DB_PASSWORD)"
APP_PW="$(gc secrets versions access latest --secret="$SECRET_DB_PASSWORD")"
if gc sql users list --instance="$SQL_INSTANCE" --format='value(name)' | grep -qx "$DB_USER"; then
  gc sql users set-password "$DB_USER" --instance="$SQL_INSTANCE" --password="$APP_PW" >/dev/null
  ok "already existed - password re-synced from Secret Manager"
else
  gc sql users create "$DB_USER" --instance="$SQL_INSTANCE" --password="$APP_PW" >/dev/null
  ok "created"
fi
unset APP_PW

step "IP configuration (screenshot this, or the Console 'Connections' tab)"
gc sql instances describe "$SQL_INSTANCE" --format="yaml(name,databaseVersion,settings.tier,gceZone,ipAddresses,settings.ipConfiguration.ipv4Enabled,settings.ipConfiguration.privateNetwork,settings.ipConfiguration.allocatedIpRange,settings.ipConfiguration.sslMode)"

IPV4="$(gc sql instances describe "$SQL_INSTANCE" --format='value(settings.ipConfiguration.ipv4Enabled)')"
IP_TYPES="$(gc sql instances describe "$SQL_INSTANCE" --format='value(ipAddresses[].type)')"
case "$IPV4" in
  False|false) ok "ipv4Enabled: false -> the instance has NO public IP (address types: $IP_TYPES)" ;;
  *) die "public IPv4 is enabled on $SQL_INSTANCE - it must be private only" ;;
esac
case "$IP_TYPES" in *PRIMARY*) die "a public (PRIMARY) address is attached" ;; esac

echo
echo "Next: ./deploy/m4/04_bucket.sh"
