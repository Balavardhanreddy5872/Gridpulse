# shellcheck shell=bash disable=SC2034
# Shared settings for the Milestone 6 scripts (sourced, not executed).
# Builds on Milestones 4/5 (project, region, cluster, namespace, DOMAIN, helpers).
source ../m5/config.sh

TF_DIR="$REPO_ROOT/terraform"
TF_STATE_BUCKET="${TF_STATE_BUCKET:-${PROJECT_ID}-tfstate}"
WORKFLOW="$REPO_ROOT/.github/workflows/deploy.yml"
EVIDENCE_DIR="$REPO_ROOT/docs/milestone6/evidence"
GITHUB_REPO="${GITHUB_REPO:-Balavardhanreddy5872/Gridpulse}"
APP_URL="https://${DOMAIN}"
LOG_METRIC="gridpulse_http_5xx"

tf() { terraform -chdir="$TF_DIR" "$@"; }
