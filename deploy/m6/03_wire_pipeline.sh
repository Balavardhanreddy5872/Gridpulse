#!/usr/bin/env bash
# LAPTOP, step 3: point the GitHub Actions workflow at the identity Terraform
# created (Workload Identity Federation provider + deployer service account).
# These are identifiers, not secrets, so they live in the workflow file.
#
#   ./deploy/m6/03_wire_pipeline.sh
set -euo pipefail
cd "$(dirname "$0")"
source ./config.sh

PROVIDER="$(tf output -raw workload_identity_provider)"
SA="$(tf output -raw ci_service_account)"
if [ -z "$PROVIDER" ] || [ -z "$SA" ]; then die "terraform outputs missing - run ./deploy/m6/02_terraform.sh first"; fi

# The workflow file arrives as deploy/ci/deploy.yml; GitHub only runs it from .github/workflows/.
if [ -f "$REPO_ROOT/deploy/ci/deploy.yml" ]; then
  mkdir -p "$(dirname "$WORKFLOW")"
  mv "$REPO_ROOT/deploy/ci/deploy.yml" "$WORKFLOW"
  ok "moved deploy/ci/deploy.yml -> .github/workflows/deploy.yml"
fi
[ -f "$WORKFLOW" ] || die "$WORKFLOW not found"

step "Writing the identity into .github/workflows/deploy.yml"
# values passed through the environment: an e-mail's "@" would be a Perl array
PROVIDER="$PROVIDER" perl -pi -e 's{^(\s*WIF_PROVIDER:\s+)\S+(\s+# WIF)$}{$1$ENV{PROVIDER}$2}' "$WORKFLOW"
SA="$SA" perl -pi -e 's{^(\s*DEPLOYER_SA:\s+)\S+$}{$1$ENV{SA}}' "$WORKFLOW"
grep -nE 'WIF_PROVIDER:|DEPLOYER_SA:' "$WORKFLOW" | head -2 | sed 's/^/    /'
if grep -qE "^ *WIF_PROVIDER:.*PROJECT_NUMBER" "$WORKFLOW"; then die "placeholder still there - check the WIF_PROVIDER line"; fi
ok "workflow wired"

step "Who may use it (Workload Identity Federation)"
gc iam workload-identity-pools providers describe github --location=global \
  --workload-identity-pool=github-actions --format='value(attributeCondition)' | sed 's/^/    condition: /'
gc iam service-accounts keys list --iam-account="$SA" --managed-by=user --format='value(name)' | wc -l \
  | xargs -I{} echo "    user-managed keys on $SA: {} (must be 0)"

step "One-time cluster clean-up"
# Milestone 6 generates the backend ConfigMap with a content hash
# (backend-config-<hash>). The old fixed-name one from Milestone 5 is unused once
# the pipeline has deployed; delete it only after the first green run.
if k get configmap backend-config >/dev/null 2>&1; then
  note "after the first successful pipeline run:  kubectl -n $NAMESPACE delete configmap backend-config"
fi

echo
echo "Next: commit and push to main - that push is the first pipeline run:"
echo "  git add -A && git commit -m 'Milestone 6: observability, Terraform, CI/CD with automatic rollback' && git push"
echo "  then watch https://github.com/$GITHUB_REPO/actions"
