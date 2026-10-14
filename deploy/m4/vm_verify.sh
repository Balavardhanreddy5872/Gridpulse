#!/usr/bin/env bash
# VM: prove the running app keeps NO state and NO secrets on this machine.
# Run it on camera for the video, and screenshot it.
#
#   ./deploy/m4/vm_verify.sh
set -uo pipefail
cd "$(dirname "$0")/../.." || exit 1
source deploy/m4/config.sh
export IMAGE_TAG="${IMAGE_TAG:-v2}"
DC=(docker compose -f docker-compose.yml)
EVIDENCE="docs/milestone4/evidence"; mkdir -p "$EVIDENCE"
exec > >(tee "$EVIDENCE/vm_verify.txt") 2>&1

FAILS=0
pass() { printf '    \033[32mPASS\033[0m  %s\n' "$*"; }
fail() { printf '    \033[31mFAIL\033[0m  %s\n' "$*"; FAILS=$((FAILS + 1)); }
in_backend() { "${DC[@]}" exec -T backend "$@"; }
BACKEND_IMAGE="us-central1-docker.pkg.dev/${PROJECT_ID}/${AR_REPO}/gridpulse-backend:${IMAGE_TAG}"

step "Running containers (no database container, no volumes)"
"${DC[@]}" ps
MOUNTS="$(docker inspect --format '{{range .Mounts}}{{.Type}}:{{.Destination}} {{end}}' "$("${DC[@]}" ps -q backend)")"
if [ -z "${MOUNTS// /}" ]; then pass "backend has no volumes or bind mounts"; else fail "backend mounts: $MOUNTS"; fi

step "1. No .env file on the VM"
FOUND="$(find . -path ./frontend/node_modules -prune -o \( -name '.env' -o -name '.env.*' \) ! -name '.env.example' -type f -print)"
ls -la .env 2>&1 | sed 's/^/    $ ls -la .env -> /'
if [ -z "$FOUND" ]; then pass "no .env files anywhere in $(pwd)"; else fail "found: $FOUND"; fi

step "2. No .env file inside the running backend container"
IN_CONTAINER="$(in_backend sh -c 'find / -xdev \( -name ".env" -o -name ".env.*" \) 2>/dev/null')"
in_backend ls -la /app/backend | sed 's/^/    /'
if [ -z "$IN_CONTAINER" ]; then pass "find / -name '.env*' inside the container: nothing"; else fail "found: $IN_CONTAINER"; fi

step "3. The container's environment holds names and addresses only - no secret values"
in_backend env | sort | grep -E '^(GCP_|CLOUDSQL_|DB_|STORAGE_|GCS_|SEED_)' | sed 's/^/    /'
REAL_PW="$("${DC[@]}" run --rm --no-deps -T backend python -m app.gcp secret "$SECRET_DB_PASSWORD" 2>/dev/null)"
if [ "${#REAL_PW}" -lt 16 ]; then
  fail "could not read the DB password from Secret Manager to scan for it"
else
  hits=0
  in_backend env | grep -qF -- "$REAL_PW" && hits=$((hits + 1))
  docker inspect "$("${DC[@]}" ps -q backend)" | grep -qF -- "$REAL_PW" && hits=$((hits + 1))
  if [ "$hits" -eq 0 ]; then pass "the real DB password is in neither the container env nor its config (docker inspect)"; else fail "password found in container env/config"; fi

  WORK="$(mktemp -d)"
  docker save "$BACKEND_IMAGE" -o "$WORK/img.tar" && mkdir "$WORK/x" && tar -xf "$WORK/img.tar" -C "$WORK/x"
  blobs=0; blob_hits=0
  while IFS= read -r -d '' f; do
    blobs=$((blobs + 1))
    if gzip -t "$f" 2>/dev/null; then n="$(gzip -dc "$f" | grep -aFc -- "$REAL_PW" || true)"; else n="$(grep -aFc -- "$REAL_PW" "$f" || true)"; fi
    [ "${n:-0}" -gt 0 ] && blob_hits=$((blob_hits + 1))
  done < <(find "$WORK/x" -type f -print0)
  rm -rf "$WORK"
  if [ "$blob_hits" -eq 0 ]; then pass "byte scan of all $blobs image blobs: password not baked into the image"; else fail "$blob_hits image blob(s) contain the password"; fi
fi
unset REAL_PW

step "4. No service-account key files - identity comes from the VM metadata server"
in_backend python -m app.gcp whoami | sed 's/^/    /'
if in_backend sh -c '[ -z "${GOOGLE_APPLICATION_CREDENTIALS:-}" ]'; then pass "GOOGLE_APPLICATION_CREDENTIALS is not set in the container"; else fail "GOOGLE_APPLICATION_CREDENTIALS is set"; fi
KEYS="$(in_backend sh -c 'find / -xdev -type f -name "*.json" -size -64k -exec grep -l "\"private_key\"" {} + 2>/dev/null | head -5')"
if [ -z "$KEYS" ]; then pass "no JSON key files (\"private_key\") anywhere in the container"; else fail "key-like files: $KEYS"; fi
if [ ! -f "$HOME/.config/gcloud/application_default_credentials.json" ]; then pass "no application-default credential file on the VM"; else fail "$HOME/.config/gcloud/application_default_credentials.json exists"; fi

step "5. The backend cannot write to its own disk (read-only root filesystem)"
OUT="$(in_backend sh -c 'touch /app/backend/probe 2>&1; touch /app/uploads/probe 2>&1' || true)"
echo "$OUT" | sed 's/^/    /'
if echo "$OUT" | grep -q "Read-only file system"; then pass "writes are refused - all state must live in managed services"; else fail "container filesystem is writable"; fi

step "6. Where the running app keeps its state (GET /api/system/info)"
curl -fsS localhost/api/system/info | python3 -m json.tool | sed 's/^/    /'

step "7. Newest uploads in gs://$BUCKET/documents/"
gcloud --project "$PROJECT_ID" --account "$VM_SA_EMAIL" storage ls -l "gs://$BUCKET/documents/**" 2>/dev/null \
  | grep -v '^TOTAL' | sort -k2 | tail -5 | sed 's/^/    /'

echo
if [ "$FAILS" -eq 0 ]; then echo "RESULT: all checks passed - no state and no secrets on the VM."; else echo "RESULT: $FAILS check(s) failed."; exit 1; fi
