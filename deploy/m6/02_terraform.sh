#!/usr/bin/env bash
# LAPTOP, step 2: Terraform adopts the live Milestone 3-5 infrastructure and adds
# the Milestone 6 pieces (log-based metric, dashboard, alerts, uptime check,
# CI/CD identity).
#
#  1. terraform init           (state in gs://gridpulse-509202-tfstate)
#  2. terraform plan -out      refresh ON - reads every live resource
#  3. a per-resource summary   import / create / update; STOPS if anything would
#                              be destroyed or replaced
#  4. terraform apply          only after you type "yes"
#  5. terraform plan again     must say "No changes" - the rubric's proof
#
#   ./deploy/m6/02_terraform.sh
#   PLAN_ONLY=1 ./deploy/m6/02_terraform.sh      # steps 1-3 only
set -euo pipefail
cd "$(dirname "$0")"
source ./config.sh
need terraform "brew tap hashicorp/tap && brew install hashicorp/tap/terraform"
[ -f "$TF_DIR/notification.auto.tfvars" ] || die "run ./deploy/m6/01_bootstrap_state.sh first"
if grep -q 'teammate1@' "$TF_DIR/notification.auto.tfvars"; then
  die "terraform/notification.auto.tfvars still has the example addresses - put the team's e-mails in it"
fi

step "terraform init"
tf init -input=false

step "terraform validate + fmt"
tf validate
tf fmt -check -recursive || note "formatting differs (cosmetic) - 'terraform -chdir=terraform fmt' fixes it"

step "terraform plan (refresh on: compares the code with the LIVE project)"
mkdir -p "$EVIDENCE_DIR"   # git-ignored: the plan text lists resource details and alert e-mails
tf plan -input=false -out=tfplan | tee "$EVIDENCE_DIR/terraform_plan_first.txt" | grep -E 'will be imported|will be created|will be updated|must be replaced|will be destroyed|Plan:|No changes|Error' || true

step "What this plan does, per resource"
./plan_summary.sh "$TF_DIR/tfplan"

[ "${PLAN_ONLY:-0}" = "1" ] && { note "PLAN_ONLY=1 - stopping before apply"; exit 0; }

printf '\n    Apply this plan? Type yes: '
read -r answer
[ "$answer" = "yes" ] || { note "not applied"; exit 0; }

step "terraform apply"
tf apply -input=false tfplan
rm -f "$TF_DIR/tfplan"

step "terraform plan again - must report no changes"
mkdir -p "$EVIDENCE_DIR"
set +e
tf plan -input=false -detailed-exitcode | tee "$EVIDENCE_DIR/terraform_plan_no_changes.txt"
code=${PIPESTATUS[0]}
set -e
case "$code" in
  0) ok "No changes - the code matches the live environment" ;;
  2) note "plan still shows changes (above). Usually Google filled in a default on the first apply:"
     note "run ./deploy/m6/02_terraform.sh again; if the same diff stays, send that output." ;;
  *) die "terraform plan failed" ;;
esac

echo
tf output
echo
echo "Next: ./deploy/m6/03_wire_pipeline.sh"
