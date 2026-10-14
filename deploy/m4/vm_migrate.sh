#!/usr/bin/env bash
# VM, ONE TIME: move every piece of Milestone 3 state off the VM.
#
#   cd ~/gridpulse && git pull && ./deploy/m4/vm_migrate.sh
#
#   1. checks the VM runs as gridpulse-vm-sa (no key files)
#   2. deletes the leftover .env files (old local DB passwords)
#   3. pulls the v2 images
#   4. connects to Cloud SQL on its private IP (password from Secret Manager)
#   5-6. row counts + checksums of the OLD database (Postgres container on this VM)
#   7. full backup of the old database -> gs://<bucket>/backups/
#   8. runs the Alembic migration on Cloud SQL (creates the tables)
#   9. copies the data: pg_dump (old container) | psql (Cloud SQL private IP)
#  10. row counts + checksums of the NEW database, side by side with the old
#  11. copies the old uploaded PDFs into the bucket and re-points their rows
#  12. starts the stateless Milestone 4 stack (no DB container, no volumes)
#
# Everything it prints is also saved under docs/milestone4/evidence/.
# Safe to re-run: finished steps are detected and skipped.
set -euo pipefail
cd "$(dirname "$0")/../.."
source deploy/m4/config.sh

export IMAGE_TAG="${IMAGE_TAG:-v2}"
DC=(docker compose -f docker-compose.yml)
OLD_DB="${OLD_DB_CONTAINER:-gridpulse-db-1}"
OLD_PGDATA_VOLUME="${OLD_PGDATA_VOLUME:-gridpulse_pgdata}"
OLD_UPLOADS_VOLUME="${OLD_UPLOADS_VOLUME:-gridpulse_uploads}"
EVIDENCE="docs/milestone4/evidence"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
mkdir -p "$EVIDENCE"
exec > >(tee -a "$EVIDENCE/vm_migrate_${STAMP}.log") 2>&1

metadata() { curl -fsS -H 'Metadata-Flavor: Google' "http://metadata.google.internal/computeMetadata/v1/$1"; }
gcl() { gcloud --project "$PROJECT_ID" --account "$VM_SA_EMAIL" --quiet "$@"; }
run_app() { "${DC[@]}" run --rm --no-deps -T backend "$@"; }

# ----------------------------------------------------------------------------
step "1. Identity: which service account is this VM using?"
command -v docker >/dev/null || die "docker missing - run deploy/vm_setup.sh first"
docker info >/dev/null 2>&1 || die "cannot use docker without sudo - log out and back in (docker group)"
SA_NOW="$(metadata instance/service-accounts/default/email)"
SCOPES_NOW="$(metadata instance/service-accounts/default/scopes)"
[ "$SA_NOW" = "$VM_SA_EMAIL" ] || die "VM runs as $SA_NOW - run deploy/m4/06_switch_vm_identity.sh on the laptop first"
[[ "$SCOPES_NOW" == *"/auth/cloud-platform"* ]] || die "VM lacks the cloud-platform scope - re-run 06_switch_vm_identity.sh"
ok "running as $SA_NOW (scope cloud-platform), via the metadata server"
[ -z "${GOOGLE_APPLICATION_CREDENTIALS:-}" ] || die "GOOGLE_APPLICATION_CREDENTIALS is set - Milestone 4 must not use key files"
[ ! -f "$HOME/.config/gcloud/application_default_credentials.json" ] \
  || note "WARNING: ~/.config/gcloud/application_default_credentials.json exists (a personal login). Remove it: gcloud auth application-default revoke"
# docker pulls go through gcloud's credential helper: make sure gcloud is not
# still pinned to the VM's OLD service account (it is no longer attached).
CFG_ACCOUNT="$(gcloud config get-value account 2>/dev/null || true)"
if [ -n "$CFG_ACCOUNT" ] && [ "$CFG_ACCOUNT" != "$VM_SA_EMAIL" ]; then
  case "$CFG_ACCOUNT" in
    *.gserviceaccount.com) gcloud config set account "$VM_SA_EMAIL" >/dev/null 2>&1
                           ok "gcloud switched from $CFG_ACCOUNT to $VM_SA_EMAIL" ;;
    *) note "gcloud on this VM is logged in as $CFG_ACCOUNT (a personal login); for the VM identity run: gcloud config set account $VM_SA_EMAIL" ;;
  esac
fi

# ----------------------------------------------------------------------------
step "2. Removing leftover .env files (Milestone 2/3 local passwords)"
mapfile -t ENV_FILES < <(find . -path ./frontend/node_modules -prune -o -path ./backend/venv -prune -o \
  \( -name '.env' -o -name '.env.*' \) ! -name '.env.example' -type f -print)
if [ "${#ENV_FILES[@]}" -eq 0 ]; then
  ok "none found"
else
  for f in "${ENV_FILES[@]}"; do shred -u "$f" 2>/dev/null || rm -f "$f"; ok "deleted $f"; done
fi

# ----------------------------------------------------------------------------
step "3. Pulling gridpulse-{backend,frontend}:$IMAGE_TAG from Artifact Registry"
"${DC[@]}" pull --quiet
for svc in backend frontend; do
  note "$(docker image inspect --format '{{index .RepoDigests 0}}' "us-central1-docker.pkg.dev/${PROJECT_ID}/${AR_REPO}/gridpulse-${svc}:${IMAGE_TAG}")"
done

# ----------------------------------------------------------------------------
step "4. The NEW database: Cloud SQL '$SQL_INSTANCE' (private IP, password from Secret Manager)"
# psql/pg_dump run from the same image as the old Postgres container, so the
# client versions on both sides of the copy are identical.
if docker ps -a --format '{{.Names}}' | grep -qx "$OLD_DB"; then
  PG_IMAGE="$(docker inspect --format '{{.Image}}' "$OLD_DB")"
else
  PG_IMAGE="postgres:16-alpine"
fi
DB_HOST="$(run_app python -m app.gcp db-host)"
[[ "$DB_HOST" =~ ^(10|172\.(1[6-9]|2[0-9]|3[01])|192\.168)\. ]] || die "Cloud SQL address '$DB_HOST' is not a private IP"
PGPASSWORD="$(run_app python -m app.gcp secret "$SECRET_DB_PASSWORD")"
export PGPASSWORD
ok "Cloud SQL private IP: $DB_HOST  (password read from Secret Manager - not printed, not saved)"
psql_new() {
  docker run --rm -i -e PGPASSWORD -e PGSSLMODE=require \
    -e PGHOST="$DB_HOST" -e PGUSER="$DB_USER" -e PGDATABASE="$DB_NAME" \
    "$PG_IMAGE" psql -X -v ON_ERROR_STOP=1 "$@"
}
psql_new -qAt -c "SELECT 'connected to ' || host(inet_server_addr()) || ', PostgreSQL ' || current_setting('server_version') || ', TLS ' || CASE WHEN ssl THEN version ELSE 'OFF' END FROM pg_stat_ssl WHERE pid = pg_backend_pid()" \
  | sed 's/^/    /'

NEW_ROWS=0
if [ "$(psql_new -qAt -c "SELECT to_regclass('public.regions') IS NOT NULL")" = "t" ]; then
  NEW_ROWS="$(psql_new -qAt -F'|' < deploy/m4/sql/row_counts.sql | awk -F'|' '{s+=$2} END {print s+0}')"
fi
NEED_COPY=1
if [ "$NEW_ROWS" -gt 0 ] && [ "${FORCE_RELOAD:-0}" != "1" ]; then
  NEED_COPY=0
  note "Cloud SQL already holds $NEW_ROWS rows: the data move was done on an earlier run - skipping it."
  note "(To wipe Cloud SQL and copy again: FORCE_RELOAD=1 ./deploy/m4/vm_migrate.sh)"
fi

# ----------------------------------------------------------------------------
TEMP_OLD_DB=""
if [ "$NEED_COPY" = "1" ]; then
  step "5. The OLD database: Milestone 3's Postgres container on this VM"
  if docker ps --format '{{.Names}}' | grep -qx "$OLD_DB"; then
    ok "$OLD_DB is running"
  elif docker ps -a --format '{{.Names}}' | grep -qx "$OLD_DB"; then
    docker start "$OLD_DB" >/dev/null && ok "started the stopped container $OLD_DB"
  elif docker volume inspect "$OLD_PGDATA_VOLUME" >/dev/null 2>&1; then
    OLD_DB="gridpulse-m3-db-readback"
    docker rm -f "$OLD_DB" >/dev/null 2>&1 || true
    docker run -d --name "$OLD_DB" -v "$OLD_PGDATA_VOLUME:/var/lib/postgresql/data" "$PG_IMAGE" >/dev/null
    TEMP_OLD_DB="$OLD_DB"
    ok "started a temporary container on the old volume $OLD_PGDATA_VOLUME"
  else
    die "no Milestone 3 database (container $OLD_DB or volume $OLD_PGDATA_VOLUME) found on this VM"
  fi
  for _ in $(seq 1 30); do docker exec "$OLD_DB" pg_isready -q && break; sleep 2; done
  OLD_USER="$(docker exec "$OLD_DB" printenv POSTGRES_USER 2>/dev/null || echo gridpulse)"
  OLD_DBNAME="$(docker exec "$OLD_DB" printenv POSTGRES_DB 2>/dev/null || echo "$OLD_USER")"
  psql_old() { docker exec -i "$OLD_DB" psql -X -v ON_ERROR_STOP=1 -U "$OLD_USER" -d "$OLD_DBNAME" "$@"; }

  step "6. Row counts BEFORE the move (old container database)"
  psql_old -qAt -F'|' < deploy/m4/sql/row_counts.sql > "$EVIDENCE/row_counts_old.txt"
  (column -t -s'|' "$EVIDENCE/row_counts_old.txt" 2>/dev/null || cat "$EVIDENCE/row_counts_old.txt") | sed 's/^/    /'

  step "7. Full backup of the old database -> gs://$BUCKET/backups/"
  BACKUP="gs://$BUCKET/backups/m3-final-${STAMP}.sql.gz"
  docker exec "$OLD_DB" pg_dump -U "$OLD_USER" -d "$OLD_DBNAME" --no-owner --no-privileges \
    | gzip -9 | gcl storage cp - "$BACKUP"
  ok "$BACKUP"
fi

# ----------------------------------------------------------------------------
step "8. Migration: Alembic creates the tables on Cloud SQL"
run_app alembic upgrade head
run_app alembic current

# ----------------------------------------------------------------------------
if [ "$NEED_COPY" = "1" ]; then
  step "9. Copying the data (pg_dump old container | psql Cloud SQL), in one transaction"
  if [ "$NEW_ROWS" -gt 0 ]; then
    note "FORCE_RELOAD=1: emptying the Cloud SQL tables first"
    psql_new -q -c "TRUNCATE regions, hourly_readings, weather_observations, forecast_results, peak_alerts, infrastructure_documents, async_jobs RESTART IDENTITY CASCADE"
  fi
  docker exec "$OLD_DB" pg_dump -U "$OLD_USER" -d "$OLD_DBNAME" \
      --data-only --no-owner --no-privileges --schema=public --exclude-table=alembic_version \
    | psql_new -q --single-transaction >/dev/null
  psql_new -qAt < deploy/m4/sql/fix_sequences.sql >/dev/null
  ok "data copied and id sequences advanced"

  step "10. Row counts AFTER the move - side by side"
  psql_new -qAt -F'|' < deploy/m4/sql/row_counts.sql > "$EVIDENCE/row_counts_new.txt"
  PG_VERSION_NEW="$(psql_new -qAt -c "SHOW server_version")"
  {
    echo "GridPulse Milestone 4 - row counts before and after the database move"
    echo "Taken: $(date -u '+%Y-%m-%d %H:%M:%S UTC') on $(hostname)"
    echo "OLD = Milestone 3 Postgres container '$OLD_DB' on $(hostname) (Docker volume $OLD_PGDATA_VOLUME)"
    echo "NEW = Cloud SQL instance '$SQL_INSTANCE', private IP $DB_HOST, PostgreSQL $PG_VERSION_NEW"
    echo "checksum = md5 of every row in the table (ordered by id); equal checksums = identical contents"
    echo
    paste -d'|' "$EVIDENCE/row_counts_old.txt" "$EVIDENCE/row_counts_new.txt" | awk -F'|' '
      BEGIN { printf "%-26s %12s %12s   %-14s %-14s %s\n", "TABLE", "OLD ROWS", "NEW ROWS", "OLD CHECKSUM", "NEW CHECKSUM", "RESULT"
              printf "%-26s %12s %12s   %-14s %-14s %s\n", "-----", "--------", "--------", "------------", "------------", "------" }
      { r = ($2 == $5 && $3 == $6) ? "MATCH" : "MISMATCH"; if (r != "MATCH") bad++
        to += $2; tn += $5
        printf "%-26s %12d %12d   %-14s %-14s %s\n", $1, $2, $5, $3, $6, r }
      END { printf "%-26s %12d %12d   %-14s %-14s %s\n", "TOTAL", to, tn, "", "", (bad ? bad " MISMATCH(ES)" : "ALL 7 TABLES MATCH") }'
  } | tee "$EVIDENCE/row_counts_side_by_side.txt" | sed 's/^/    /'
  grep -q "ALL 7 TABLES MATCH" "$EVIDENCE/row_counts_side_by_side.txt" \
    || die "row counts differ - see above. The Milestone 3 stack is still running untouched."
elif [ -f "$EVIDENCE/row_counts_side_by_side.txt" ]; then
  step "10. Row counts from the original move (saved)"
  sed 's/^/    /' "$EVIDENCE/row_counts_side_by_side.txt"
fi

# ----------------------------------------------------------------------------
step "11. Uploaded PDFs: old Docker volume -> gs://$BUCKET/documents/m3/"
if docker volume inspect "$OLD_UPLOADS_VOLUME" >/dev/null 2>&1; then
  TMP="$(mktemp -d)"
  docker run --rm -v "$OLD_UPLOADS_VOLUME:/u:ro" "$PG_IMAGE" tar -C /u -cf - . | tar -C "$TMP" -xf -
  COUNT=0
  while IFS= read -r -d '' f; do
    rel="${f#"$TMP"/}"
    gcl storage cp --no-clobber "$f" "gs://$BUCKET/documents/m3/$rel" >/dev/null
    COUNT=$((COUNT + 1))
  done < <(find "$TMP" -type f ! -name '.gitkeep' -print0)
  rm -rf "$TMP"
  ok "$COUNT file(s) in the bucket under documents/m3/"
else
  note "no uploads volume ($OLD_UPLOADS_VOLUME) - nothing to copy"
fi

psql_new -qAt -F' -> ' -c "
  UPDATE infrastructure_documents
     SET filepath = 'gs://${BUCKET}/documents/m3/' || regexp_replace(filepath, '^.*/', '')
   WHERE filepath NOT LIKE 'gs://%'
  RETURNING id, filepath" | sed 's/^/    re-pointed document /'

MISSING=0; TOTAL_DOCS=0
while IFS= read -r uri; do
  [ -n "$uri" ] || continue
  TOTAL_DOCS=$((TOTAL_DOCS + 1))
  gcl storage ls "$uri" >/dev/null 2>&1 || { MISSING=$((MISSING + 1)); note "MISSING in bucket: $uri"; }
done < <(psql_new -qAt -c "SELECT filepath FROM infrastructure_documents ORDER BY id")
ok "$TOTAL_DOCS document row(s); $((TOTAL_DOCS - MISSING)) found in the bucket, $MISSING missing" \
  | tee "$EVIDENCE/uploads_moved.txt"

# ----------------------------------------------------------------------------
step "12. Starting the stateless Milestone 4 stack (removes the old DB container)"
"${DC[@]}" up -d --no-build --remove-orphans --wait
[ -z "$TEMP_OLD_DB" ] || docker rm -f "$TEMP_OLD_DB" >/dev/null
"${DC[@]}" ps
unset PGPASSWORD

step "13. Smoke test"
curl -fsS localhost/api/health; echo
curl -fsS localhost/api/system/info | python3 -m json.tool | tee "$EVIDENCE/system_info.json" | sed 's/^/    /'
echo "    regions served by the API: $(curl -fsS localhost/api/regions | python3 -c 'import sys,json; print(len(json.load(sys.stdin)))')"

cat <<EOF

Done. Evidence saved in $EVIDENCE/ :
  row_counts_side_by_side.txt   <- screenshot this for the rubric
  vm_migrate_${STAMP}.log
The old Docker volumes are no longer used by anything:
  docker volume ls | grep gridpulse_
Once you have checked the app, delete them to prove nothing depends on the VM's disk:
  docker volume rm $OLD_PGDATA_VOLUME $OLD_UPLOADS_VOLUME
Then run:  ./deploy/m4/vm_verify.sh
EOF
