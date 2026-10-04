#!/usr/bin/env bash
# Prove that no secrets are baked into the GridPulse images.
# Run on the laptop after building (or on the VM after pulling):
#
#   ./deploy/verify_no_secrets.sh
#
# Checks, for both images:
#   1. Image config      - no password/secret-like ENV variables baked in
#   2. Build history     - the real DB password never appears in any layer's command
#   3. Filesystem        - no .env files anywhere in the image
#   4. Every layer       - byte scan of all layer tarballs for the real password
#   5. Frontend bundle   - no hard-coded http://localhost:8000 API URL
set -euo pipefail
cd "$(dirname "$0")/.."

[ -f .env ] || { echo "Missing .env"; exit 1; }
getenv() { grep -E "^$1=" .env | cut -d= -f2- || true; }
SECRET="$(getenv POSTGRES_PASSWORD)"
REGISTRY="$(getenv REGISTRY)"; REGISTRY="${REGISTRY:-us-central1-docker.pkg.dev/gridpulse-509202/gridpulse}"
IMAGE_TAG="${IMAGE_TAG:-$(getenv IMAGE_TAG)}"; IMAGE_TAG="${IMAGE_TAG:-v1}"

if [ "${#SECRET}" -lt 10 ] || [ "$SECRET" = "change-me" ]; then
  echo "Set a unique POSTGRES_PASSWORD (10+ chars) in .env first, so the byte scan is meaningful."
  exit 1
fi

fail=0
pass() { echo "    PASS - $*"; }
bad()  { echo "    FAIL - $*"; fail=1; }
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT

for svc in backend frontend; do
  img="${REGISTRY}/gridpulse-${svc}:${IMAGE_TAG}"
  echo
  echo "=================== ${img}"

  echo "[1] ENV variables baked into the image config:"
  docker image inspect --format '{{range .Config.Env}}{{println .}}{{end}}' "$img" | sed '/^$/d; s/^/      /'
  n="$(docker image inspect --format '{{range .Config.Env}}{{println .}}{{end}}' "$img" \
        | grep -Eic 'PASSWORD|SECRET|TOKEN|DATABASE_URL|API_KEY|PRIVATE' || true)"
  if [ "${n:-0}" -gt 0 ]; then bad "secret-looking variable found above"; else pass "no password/secret variables"; fi

  echo "[2] Build history (every layer's creating command):"
  n="$(docker history --no-trunc --format '{{.CreatedBy}}' "$img" | grep -Fc -- "$SECRET" || true)"
  if [ "${n:-0}" -gt 0 ]; then bad "password appears in the build history"
  else pass "password not present in any of $(docker history -q "$img" | wc -l | tr -d ' ') history entries"; fi

  echo "[3] .env files inside the image filesystem:"
  found="$(docker run --rm --platform linux/amd64 --user 0 --entrypoint sh "$img" -c \
            'find / -xdev \( -name ".env" -o -name ".env.*" \) 2>/dev/null' || true)"
  if [ -n "$found" ]; then bad "found: $found"; else pass "none"; fi

  echo "[4] Byte scan of every layer for the real password:"
  rm -rf "$WORK/x"; mkdir -p "$WORK/x"
  docker save "$img" -o "$WORK/img.tar"
  tar -xf "$WORK/img.tar" -C "$WORK/x"
  hits=0; layers=0
  while IFS= read -r -d '' f; do
    layers=$((layers + 1))
    # grep -c reads the whole stream (no early exit), so pipefail can't hide a match
    if gzip -t "$f" 2>/dev/null; then
      n="$(gzip -dc "$f" | grep -aFc -- "$SECRET" || true)"
    else
      n="$(grep -aFc -- "$SECRET" "$f" || true)"
    fi
    if [ "${n:-0}" -gt 0 ]; then hits=$((hits + 1)); fi
  done < <(find "$WORK/x" -type f -print0)
  if [ "$hits" -eq 0 ]; then pass "0 matches across $layers blobs"; else bad "$hits blob(s) contain the password"; fi
  rm -f "$WORK/img.tar"

  if [ "$svc" = "frontend" ]; then
    echo "[5] Frontend bundle has no hard-coded API host:"
    if docker run --rm --platform linux/amd64 --entrypoint sh "$img" -c 'grep -rl "localhost:8000" /usr/share/nginx/html' >/dev/null 2>&1; then
      bad "bundle contains localhost:8000"
    else
      pass "bundle uses relative /api/... paths"
    fi
  fi
done

echo
if [ "$fail" -eq 0 ]; then echo "RESULT: no secrets baked into either image."; else echo "RESULT: problems found (see FAIL lines)."; exit 1; fi
