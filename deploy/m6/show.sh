#!/usr/bin/env bash
# VIDEO HELPER: the short live checks for the Milestone 6 demo, one word each.
# Every command is printed (after "$") right before its real, live output.
#
#   ./deploy/m6/show.sh app        # live URL: HTTP status, release on backend + frontend, images
#   ./deploy/m6/show.sh logs       # the latest 5xx request entries in Cloud Logging (JSON fields)
#   ./deploy/m6/show.sh metric     # the log-based metric definition (how 5xx are counted)
#   ./deploy/m6/show.sh alerts     # alert policies + notification channels
#   ./deploy/m6/show.sh plan       # terraform plan, refresh on - must say "No changes"
#   ./deploy/m6/show.sh state      # everything Terraform manages
#   ./deploy/m6/show.sh pipeline   # branch + commit, last pipeline runs (needs gh), rollout history
set -uo pipefail
cd "$(dirname "$0")" || exit 1
source ./config.sh

run() {
  printf '\n\033[1m$ %s\033[0m\n' "$1"
  eval "$1"
}
api() {  # GET a Cloud Monitoring API path with the current gcloud login
  curl -sS "https://monitoring.googleapis.com/v3/projects/${PROJECT_ID}/$1" \
    -H "Authorization: Bearer $(gcloud auth print-access-token)"
}

clear
case "${1:-}" in
  app)
    run "curl -sS -o /dev/null -w 'HTTP %{http_code}  TLS verify %{ssl_verify_result} (0 = trusted)\n' $APP_URL/"
    run "curl -sS $APP_URL/api/version; echo; curl -sS $APP_URL/version.json"
    run "kubectl -n $NAMESPACE get deploy -o custom-columns='NAME:.metadata.name,READY:.status.readyReplicas,IMAGE:.spec.template.spec.containers[0].image'"
    ;;
  logs)
    run "gcloud logging read 'resource.type=\"k8s_container\" AND resource.labels.container_name=\"backend\" AND jsonPayload.event=\"http_request\" AND jsonPayload.status_code>=500' --freshness=1h --limit=5 --format='table(timestamp, severity, jsonPayload.method, jsonPayload.route, jsonPayload.status_code, jsonPayload.request_id, resource.labels.pod_name)'"
    ;;
  metric)
    run "gcloud logging metrics describe $LOG_METRIC --format=yaml"
    ;;
  alerts)
    run "api alertPolicies | jq -r '.alertPolicies[] | \"\\(.displayName)\\n    enabled: \\(.enabled)   severity: \\(.severity // \"-\")\\n    condition: \\(.conditions[0].displayName)\\n    channels: \\(.notificationChannels | length)\\n\"'"
    run "api notificationChannels | jq -r '.notificationChannels[] | \"\\(.type)  \\(.labels.email_address // .displayName)  verified: \\(.verificationStatus // \"n/a\")\"'"
    ;;
  plan)
    cd "$REPO_ROOT" || exit 1
    run "terraform -chdir=terraform version | head -1"
    run "terraform -chdir=terraform plan -refresh=true -input=false -detailed-exitcode; echo \"exit code \$? (0 = no changes)\""
    ;;
  state)
    cd "$REPO_ROOT" || exit 1
    run "terraform -chdir=terraform state list | grep -v '^data\\.' | sed 's/\\[.*//' | sort | uniq -c"
    ;;
  pipeline)
    cd "$REPO_ROOT" || exit 1
    run "git status -sb | head -1; git log --oneline -3"
    if command -v gh >/dev/null 2>&1; then
      run "gh run list --workflow deploy.yml --limit 5"
    else
      echo "(install the GitHub CLI for 'gh run list'; or open https://github.com/$GITHUB_REPO/actions)"
    fi
    run "kubectl -n $NAMESPACE rollout history deploy/backend | tail -6"
    ;;
  *)
    sed -n '2,13p' "$0"; exit 1 ;;
esac
echo
