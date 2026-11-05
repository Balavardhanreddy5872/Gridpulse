#!/usr/bin/env bash
# CI/CD (Milestone 6): deploy ONE release to GKE, health-check it, and roll it
# back automatically if anything fails. Called step by step by
# .github/workflows/deploy.yml; it also works from a laptop with kubectl access.
#
#   release.sh snapshot              remember what is running now = the rollback point
#   release.sh apply    <version>    kubectl apply -k k8s/ with both images = <version>
#   release.sh wait                  wait for both rollouts (startup/liveness/readiness
#                                    probes must pass); fail fast on crash loops,
#                                    image pull errors and pods that never get Ready
#   release.sh verify   <version>    health check through the public HTTPS URL
#   release.sh rollback              kubectl rollout undo to the snapshot + wait
#   release.sh verify-previous       the release from the snapshot is serving again
#   release.sh log <event> <version> structured entry in Cloud Logging (gridpulse-deployments)
#
# <version> is the first 12 characters of the git commit. Images are tagged with
# it and the app reports it at /api/version (backend) and /version.json (frontend).
set -euo pipefail

NAMESPACE="${NAMESPACE:-gridpulse}"
PROJECT_ID="${PROJECT_ID:-gridpulse-509202}"
REGISTRY="${REGISTRY:-us-central1-docker.pkg.dev/${PROJECT_ID}/gridpulse}"
APP_URL="${APP_URL:-https://gridpulse-9.duckdns.org}"
STATE_FILE="${RELEASE_STATE_FILE:-${RUNNER_TEMP:-/tmp}/gridpulse-release.state}"
DEPLOYMENTS=(backend frontend)

ROLLOUT_TIMEOUT="${ROLLOUT_TIMEOUT:-600}"   # s: whole rollout (Autopilot may first add a node)
NOT_READY_LIMIT="${NOT_READY_LIMIT:-150}"   # s: a started container that is still not Ready = broken
MAX_RESTARTS="${MAX_RESTARTS:-2}"           # restarts of a NEW pod before we call it a crash loop
VERIFY_TIMEOUT="${VERIFY_TIMEOUT:-180}"     # s: for the load balancer to serve only the new release
CONSECUTIVE_OK="${CONSECUTIVE_OK:-6}"       # this many version reads in a row must all match

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
RUN_URL="${GITHUB_SERVER_URL:-https://github.com}/${GITHUB_REPOSITORY:-local}/actions/runs/${GITHUB_RUN_ID:-0}"

k()       { kubectl --namespace "$NAMESPACE" "$@"; }
say()     { printf '%s  %s\n' "$(date -u +%H:%M:%S)" "$*"; }
fail()    { printf '::error::%s\n' "$*"; exit 1; }
# GitHub keeps each step's summary separate, so rows are collected here and the
# last step of the run (log deployed / log rollback) prints them as one table.
SUMMARY_ROWS="${STATE_FILE%.state}.summary.md"
summary() { printf '%s\n' "$*" >> "$SUMMARY_ROWS"; }
report() {
  [ -n "${GITHUB_STEP_SUMMARY:-}" ] && [ -s "$SUMMARY_ROWS" ] || return 0
  # shellcheck disable=SC2016  # the backticks are Markdown, not a command
  { printf '### Release `%s`\n\n| Step | Result |\n|---|---|\n' "${1:-}"; cat "$SUMMARY_ROWS"; } >> "$GITHUB_STEP_SUMMARY"
}
is_commit() { [[ "$1" =~ ^[0-9a-f]{7,40}$ ]]; }
upper()     { printf '%s' "$1" | tr '[:lower:]' '[:upper:]'; }   # (bash 3.2 on macOS has no ${x^^})

revision() { k get deploy "$1" -o jsonpath='{.metadata.annotations.deployment\.kubernetes\.io/revision}'; }
image_of() { k get deploy "$1" -o jsonpath='{.spec.template.spec.containers[0].image}'; }

# ---------------------------------------------------------------------------------
snapshot() {
  : > "$STATE_FILE"
  : > "$SUMMARY_ROWS"
  for d in "${DEPLOYMENTS[@]}"; do
    local rev img
    rev="$(revision "$d")"; img="$(image_of "$d")"
    [ -n "$rev" ] || fail "deployment/$d not found in namespace $NAMESPACE"
    printf '%s_REVISION=%q\n%s_IMAGE=%q\n' "$(upper "$d")" "$rev" "$(upper "$d")" "$img" >> "$STATE_FILE"
    say "running now: $d revision $rev  $img"
  done
  local previous; previous="$(image_of backend)"; previous="${previous##*:}"
  printf 'PREVIOUS_VERSION=%q\n' "$previous" >> "$STATE_FILE"
  if [ -n "${GITHUB_OUTPUT:-}" ]; then echo "previous_version=$previous" >> "$GITHUB_OUTPUT"; fi
  summary "| Rollback point | \`$previous\` (backend rev $(revision backend), frontend rev $(revision frontend)) |"
}

load_state() {
  [ -s "$STATE_FILE" ] || fail "no snapshot at $STATE_FILE - run '$0 snapshot' first"
  # shellcheck disable=SC1090
  source "$STATE_FILE"
}

# ---------------------------------------------------------------------------------
apply_release() {
  local version="$1"
  local overlay="$REPO_ROOT/.release"
  mkdir -p "$overlay"
  # A throw-away overlay: everything in k8s/, with both images set to this release.
  cat > "$overlay/kustomization.yaml" <<EOF
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ../k8s
images:
  - name: ${REGISTRY}/gridpulse-backend
    newTag: "${version}"
  - name: ${REGISTRY}/gridpulse-frontend
    newTag: "${version}"
EOF
  say "what changes in the cluster (kubectl diff):"
  kubectl diff -k "$overlay" | grep -E '^[+-] ' | grep -v -E 'generation:|resourceVersion|creationTimestamp|uid:' | head -60 || true
  say "kubectl apply -k (release $version)"
  kubectl apply -k "$overlay"
  for d in "${DEPLOYMENTS[@]}"; do
    k annotate deploy "$d" --overwrite \
      "kubernetes.io/change-cause=release ${version} (${RUN_URL})" >/dev/null
  done
  summary "| Deployed | \`$version\` -> backend rev $(revision backend), frontend rev $(revision frontend) |"
}

# ---------------------------------------------------------------------------------
# Prints why a deployment's NEWEST pods are broken (and returns 1), or nothing.
new_pods_broken() {
  local d="$1" rev hash pods
  rev="$(revision "$d")"
  hash="$(k get rs -l "app=$d" -o json | jq -r --arg rev "$rev" \
    '.items[] | select(.metadata.annotations["deployment.kubernetes.io/revision"] == $rev)
     | .metadata.labels["pod-template-hash"]' | head -1)"
  [ -n "$hash" ] || return 0
  pods="$(k get pods -l "app=$d,pod-template-hash=$hash" -o json)"
  echo "$pods" | jq -r --argjson maxr "$MAX_RESTARTS" --argjson limit "$NOT_READY_LIMIT" '
    def age($t): (now - ($t | sub("\\.[0-9]+"; "") | fromdateiso8601));
    .items[] | . as $p
    | ($p.status.containerStatuses // [])[]
    | if (.state.waiting.reason // "") as $r
         | ["CrashLoopBackOff","ImagePullBackOff","ErrImagePull","CreateContainerConfigError",
            "CreateContainerError","InvalidImageName","RunContainerError"] | index($r)
      then "\($p.metadata.name): \(.state.waiting.reason) - \(.state.waiting.message // "" | .[0:200])"
      elif .restartCount >= $maxr
      then "\($p.metadata.name): restarted \(.restartCount) times (crash loop)"
      elif (.ready | not) and .state.running.startedAt != null and (age(.state.running.startedAt) > $limit)
      then "\($p.metadata.name): running for \(age(.state.running.startedAt) | floor)s but never passed its readiness probe"
      else empty end' | head -5
}

# 0 = rollout finished, 1 = still in progress, 2 = Kubernetes gave up (progress deadline)
rollout_state() {
  k get deploy "$1" -o json | jq -r '
    (.spec.replicas // 1) as $want | .status as $s
    | if (($s.conditions // []) | map(select(.type == "Progressing" and .reason == "ProgressDeadlineExceeded")) | length) > 0 then 2
      elif ($s.observedGeneration // 0) < .metadata.generation then 1
      elif ($s.updatedReplicas // 0) < $want then 1
      elif ($s.replicas // 0) > ($s.updatedReplicas // 0) then 1
      elif ($s.availableReplicas // 0) < ($s.updatedReplicas // 0) then 1
      else 0 end'
}

diagnose() {
  local d="$1"
  echo "----- $d: pods"
  k get pods -l "app=$d" -o wide || true
  echo "----- $d: recent events"
  k get events --sort-by=.lastTimestamp 2>/dev/null | grep -E "$d" | tail -12 || true
  local pod
  pod="$(k get pods -l "app=$d" --sort-by=.metadata.creationTimestamp -o name | tail -1)"
  if [ -n "$pod" ]; then
    echo "----- $d: last log lines of $pod (previous container if it crashed)"
    k logs "$pod" --tail=15 --previous 2>/dev/null || k logs "$pod" --tail=15 2>/dev/null || true
  fi
}

wait_rollout() {
  local label="${1:-Rollout}" deadline=$((SECONDS + ROLLOUT_TIMEOUT)) last=""
  while true; do
    local pending=() d state broken
    for d in "${DEPLOYMENTS[@]}"; do
      state="$(rollout_state "$d" 2>/dev/null || echo 1)"   # API hiccup = still in progress
      if [ "$state" = 2 ]; then
        diagnose "$d"; fail "$d: Kubernetes reports ProgressDeadlineExceeded"
      fi
      if [ "$state" = 1 ]; then
        broken="$(new_pods_broken "$d" 2>/dev/null || true)"
        if [ -n "$broken" ]; then
          echo "$broken"; diagnose "$d"
          summary "| $label | **FAILED** - $d: $(echo "$broken" | head -1) |"
          fail "$d: the new release is not healthy - $(echo "$broken" | head -1)"
        fi
        pending+=("$d")
      fi
    done
    if [ "${#pending[@]}" -eq 0 ]; then
      say "rollout complete: $(k get deploy -o custom-columns='NAME:.metadata.name,READY:.status.readyReplicas,UP-TO-DATE:.status.updatedReplicas,IMAGE:.spec.template.spec.containers[0].image' --no-headers | tr -s ' ' | paste -sd ';' -)"
      summary "| $label | all pods Ready (startup, liveness and readiness probes passing) |"
      return 0
    fi
    if [ "$SECONDS" -ge "$deadline" ]; then
      for d in "${pending[@]}"; do diagnose "$d"; done
      summary "| $label | **FAILED** - not finished after ${ROLLOUT_TIMEOUT}s |"
      fail "rollout of ${pending[*]} did not finish within ${ROLLOUT_TIMEOUT}s"
    fi
    local now
    now="$(for d in "${pending[@]}"; do k get deploy "$d" -o jsonpath='{.metadata.name}: {.status.updatedReplicas}/{.spec.replicas} updated, {.status.availableReplicas} available. '; done)"
    if [ "$now" != "$last" ]; then say "waiting - $now"; last="$now"; fi
    sleep 5
  done
}

# ---------------------------------------------------------------------------------
http_get() {  # http_get <path> <body-file>  -> prints the status code (000 = no answer)
  local code
  code="$(curl -sS --max-time 10 -o "$2" -w '%{http_code}' "$APP_URL$1" 2>/dev/null)" || code=000
  printf '%s' "${code:-000}"
}

check_images() {  # both Deployments must point at the expected images
  local want_backend="$1" want_frontend="$2"
  [ "$(image_of backend)" = "$want_backend" ] || fail "backend runs $(image_of backend), expected $want_backend"
  [ "$(image_of frontend)" = "$want_frontend" ] || fail "frontend runs $(image_of frontend), expected $want_frontend"
  say "cluster spec OK: $want_backend, $want_frontend"
}

# Health check through the real public path: DNS -> load balancer -> Ingress -> pods.
verify_url() {
  local expect="$1" label="$2" tmp; tmp="$(mktemp -d)"
  local deadline=$((SECONDS + VERIFY_TIMEOUT)) streak=0 code version seen=""

  if is_commit "$expect"; then
    say "waiting until $CONSECUTIVE_OK reads in a row of $APP_URL/api/version and /version.json say $expect"
    while true; do
      code="$(http_get /api/version "$tmp/v")"
      version="$([ "$code" = 200 ] && jq -r .version "$tmp/v" 2>/dev/null || echo "HTTP $code")"
      local fcode fversion
      fcode="$(http_get /version.json "$tmp/f")"
      fversion="$([ "$fcode" = 200 ] && jq -r .version "$tmp/f" 2>/dev/null || echo "HTTP $fcode")"
      if [ "$version" = "$expect" ] && [ "$fversion" = "$expect" ]; then
        streak=$((streak + 1))
        [ "$streak" -ge "$CONSECUTIVE_OK" ] && break
      else
        if [ "$seen" != "$version/$fversion" ]; then
          say "  public URL serves backend=$version frontend=$fversion - waiting"; seen="$version/$fversion"
        fi
        streak=0
      fi
      [ "$SECONDS" -lt "$deadline" ] || fail "$label: the public URL did not switch to $expect within ${VERIFY_TIMEOUT}s (backend=$version frontend=$fversion)"
      sleep 2
    done
    say "  OK  every read: backend $expect, frontend $expect"
  else
    say "previous release $expect predates /api/version - checking the cluster spec and health only"
  fi

  code="$(http_get /api/health/ready "$tmp/h")"
  if [ "$code" != 200 ] || ! grep -q '"ready"' "$tmp/h"; then
    fail "$label: /api/health/ready answered $code: $(head -c 200 "$tmp/h")"
  fi
  say "  OK  /api/health/ready -> 200 $(head -c 120 "$tmp/h")"

  code="$(http_get /api/regions "$tmp/r")"
  local n; n="$(jq 'length' "$tmp/r" 2>/dev/null || echo 0)"
  if [ "$code" != 200 ] || [ "$n" -lt 1 ]; then fail "$label: /api/regions answered $code with $n regions"; fi
  say "  OK  /api/regions -> 200, $n regions from Cloud SQL"

  code="$(http_get / "$tmp/i")"
  if [ "$code" != 200 ] || ! grep -q 'id="root"' "$tmp/i"; then fail "$label: / answered $code without the dashboard"; fi
  say "  OK  / -> 200, dashboard HTML"

  if [ "${CHECK_HTTP_REDIRECT:-1}" = 1 ]; then
    code="$(curl -sS --max-time 10 -o /dev/null -w '%{http_code}' "${APP_URL/https:/http:}/" 2>/dev/null)" || code=000
    [ "$code" = 301 ] || fail "$label: http:// answered $code instead of the 301 redirect to https://"
    say "  OK  http:// -> 301 to https://"
  fi
  rm -rf "$tmp"
}

verify_release() {
  local version="$1"
  check_images "$REGISTRY/gridpulse-backend:$version" "$REGISTRY/gridpulse-frontend:$version"
  verify_url "$version" "health check"
  summary "| Health check | $APP_URL serves \`$version\` - /api/health/ready, /api/regions, /, http->https all OK |"
}

# ---------------------------------------------------------------------------------
rollback() {
  load_state
  local failed; failed="$(image_of backend)"; failed="${failed##*:}"
  say "ROLLING BACK: $failed -> $PREVIOUS_VERSION"
  local d rev_var target
  for d in "${DEPLOYMENTS[@]}"; do
    rev_var="$(upper "$d")_REVISION"; target="${!rev_var}"
    if [ "$(revision "$d")" = "$target" ]; then
      say "$d: still at revision $target - nothing to undo"
    else
      say "$d: kubectl rollout undo --to-revision=$target"
      k rollout undo "deploy/$d" --to-revision="$target"
    fi
  done
  wait_rollout "Rollback rollout"
  printf 'FAILED_VERSION=%q\n' "$failed" >> "$STATE_FILE"
  summary "| Rollback | \`$failed\` -> \`$PREVIOUS_VERSION\` (kubectl rollout undo) |"
}

verify_previous() {
  load_state
  check_images "$BACKEND_IMAGE" "$FRONTEND_IMAGE"
  verify_url "$PREVIOUS_VERSION" "rollback verification"
  summary "| Rollback verified | $APP_URL serves the previous release \`$PREVIOUS_VERSION\` again |"
}

# ---------------------------------------------------------------------------------
# A structured entry in Cloud Logging. The "rollback" event triggers the alert
# policy "GridPulse - release rolled back by the pipeline" (terraform/monitoring.tf).
log_event() {
  local event="$1" version="$2" severity=NOTICE payload
  report "$version"
  [ "$event" = rollback ] && severity=ERROR
  local restored="" failed="$version"
  if [ -s "$STATE_FILE" ]; then load_state; restored="${PREVIOUS_VERSION:-}"; fi
  payload="$(jq -cn --arg event "$event" --arg version "$version" --arg restored "$restored" \
    --arg failed "$failed" --arg run "$RUN_URL" --arg commit "${GITHUB_SHA:-}" --arg actor "${GITHUB_ACTOR:-}" \
    '{event: $event, version: $version, commit: $commit, actor: $actor, run: $run,
      message: (if $event == "rollback" then "Release \($failed) failed and was rolled back to \($restored)"
                else "Release \($version) deployed and healthy" end)}
     + (if $event == "rollback" then {failed_version: $failed, restored_version: $restored} else {} end)')"
  if gcloud logging write gridpulse-deployments "$payload" --payload-type=json \
       --severity="$severity" --project="$PROJECT_ID" >/dev/null 2>&1; then
    say "Cloud Logging (gridpulse-deployments): $payload"
  else
    say "could not write the deployment log entry (not fatal)"
  fi
}

case "${1:-}" in
  snapshot)        snapshot ;;
  apply)           apply_release "${2:?version}" ;;
  wait)            wait_rollout "Rollout" ;;
  verify)          verify_release "${2:?version}" ;;
  rollback)        rollback ;;
  verify-previous) verify_previous ;;
  log)             log_event "${2:?event}" "${3:?version}" ;;
  *) sed -n '2,20p' "$0"; exit 2 ;;
esac
