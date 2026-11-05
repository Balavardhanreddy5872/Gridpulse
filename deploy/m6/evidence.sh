#!/usr/bin/env bash
# EVIDENCE: the Milestone 6 "working artifacts" that are text, saved to
# docs/milestone6/evidence/ (never committed - see .gitignore):
#
#   terraform_plan_no_changes.txt   live plan, refresh on
#   terraform_state_list.txt        what Terraform manages
#   log_based_metric.yaml           how HTTP 5xx are counted
#   alert_policies.json             the three alert policies (conditions, channels)
#   uptime_check.json               the HTTPS uptime check
#   deployment.txt                  live URL check, branch + commit, rollout history
#
#   ./deploy/m6/evidence.sh
set -euo pipefail
cd "$(dirname "$0")"
source ./config.sh
mkdir -p "$EVIDENCE_DIR"
E="$EVIDENCE_DIR"
token() { gcloud auth print-access-token; }

step "terraform plan (refresh on)"
set +e
tf plan -refresh=true -input=false -no-color -detailed-exitcode > "$E/terraform_plan_no_changes.txt" 2>&1
code=$?
set -e
tail -3 "$E/terraform_plan_no_changes.txt"
if [ "$code" = 0 ]; then ok "No changes"; else note "exit code $code - the plan is NOT clean, look at $E/terraform_plan_no_changes.txt"; fi

step "terraform state list"
tf state list > "$E/terraform_state_list.txt"
ok "$(grep -vc '^data\.' "$E/terraform_state_list.txt") managed resources"

step "Log-based metric"
gc logging metrics describe "$LOG_METRIC" --format=yaml > "$E/log_based_metric.yaml"
grep -A9 '^filter' "$E/log_based_metric.yaml" | sed 's/^/    /'

step "Alert policies + uptime check"
curl -sS "https://monitoring.googleapis.com/v3/projects/$PROJECT_ID/alertPolicies" -H "Authorization: Bearer $(token)" \
  | jq '[.alertPolicies[] | {displayName, enabled, severity, combiner, conditions, notificationChannels, alertStrategy}]' > "$E/alert_policies.json"
jq -r '.[].displayName' "$E/alert_policies.json" | sed 's/^/    /'
curl -sS "https://monitoring.googleapis.com/v3/projects/$PROJECT_ID/uptimeCheckConfigs" -H "Authorization: Bearer $(token)" \
  | jq '.uptimeCheckConfigs' > "$E/uptime_check.json"

step "Deployment state"
{
  echo "GridPulse - $(date '+%Y-%m-%d %H:%M:%S %Z')"
  echo
  echo "== live: $APP_URL"
  curl -sS -o /dev/null -w 'GET / -> HTTP %{http_code} (TLS verify %{ssl_verify_result}, 0 = trusted)\n' "$APP_URL/"
  printf 'backend  '; curl -sS "$APP_URL/api/version"; echo
  printf 'frontend '; curl -sS "$APP_URL/version.json"
  echo
  echo "== repository"
  echo "https://github.com/$GITHUB_REPO   branch: main   HEAD: $(git -C "$REPO_ROOT" rev-parse HEAD)"
  git -C "$REPO_ROOT" log --oneline -8
  echo
  echo "== kubectl rollout history (pipeline releases + rollbacks)"
  k rollout history deploy/backend
  k get deploy -o custom-columns='NAME:.metadata.name,READY:.status.readyReplicas,IMAGE:.spec.template.spec.containers[0].image'
  if command -v gh >/dev/null 2>&1; then
    echo
    echo "== pipeline runs"
    gh run list --repo "$GITHUB_REPO" --workflow deploy.yml --limit 10 || true
  fi
} > "$E/deployment.txt" 2>&1
ok "saved"
find "$E" -maxdepth 1 -type f -exec basename {} \; | sort | sed 's/^/    /'
