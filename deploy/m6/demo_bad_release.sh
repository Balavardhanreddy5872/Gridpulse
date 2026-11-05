#!/usr/bin/env bash
# VIDEO: push a deliberately BAD release to main and let the pipeline catch it.
#
#   crash   (default) a typo in the secret name the backend reads its DB password
#           from (k8s/backend-config.properties). The tests pass - they never
#           touch Secret Manager - so the pipeline builds and deploys it, the new
#           backend pods crash on start-up (CrashLoopBackOff), the old pods keep
#           serving (maxUnavailable: 0), the rollout check fails within ~2 min and
#           the pipeline runs `kubectl rollout undo`, then verifies the previous
#           release serves https://<domain> again.
#   unready the readiness check gets an impossible 1 ms database time limit: the
#           pods start but never pass their readiness probe, so they never get
#           traffic; the pipeline gives up after NOT_READY_LIMIT (150 s) and rolls back.
#
# Nothing touches the database or the bucket. Afterwards undo the commit with
#   ./deploy/m6/demo_fix_release.sh
#
#   ./deploy/m6/demo_bad_release.sh            # crash
#   ./deploy/m6/demo_bad_release.sh unready
set -euo pipefail
cd "$(dirname "$0")"
source ./config.sh
MODE="${1:-crash}"
PROPS="$K8S_DIR/backend-config.properties"
cd "$REPO_ROOT"

[ "$(git rev-parse --abbrev-ref HEAD)" = main ] || die "switch to main first (git checkout main)"
[ -z "$(git status --porcelain --untracked-files=no)" ] || die "commit or stash your changes first (git status)"
git fetch -q origin main
[ "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)" ] || die "main is not in sync with origin/main - git pull first"

case "$MODE" in
  crash)
    perl -pi -e 's/^DB_PASSWORD_SECRET=gridpulse-db-password$/DB_PASSWORD_SECRET=gridpulse-db-pasword/' "$PROPS"
    MSG="demo: bad release - typo in DB_PASSWORD_SECRET (expect automatic rollback)"
    ;;
  unready)
    printf '%s\n' "# DEMO (bad release): impossible readiness time limit" "READINESS_DB_TIMEOUT_SECONDS=0.001" >> "$PROPS"
    MSG="demo: bad release - readiness can never pass (expect automatic rollback)"
    ;;
  *) die "usage: $0 [crash|unready]" ;;
esac
git --no-pager diff --stat; git --no-pager diff -U0 -- "$PROPS" | sed 's/^/    /'
git diff --quiet && die "nothing changed - is the file already modified?"

step "Running now (this is what the rollback must restore)"
curl -sS --max-time 10 "$APP_URL/api/version"; echo

git commit -qam "$MSG"
step "Pushing $(git rev-parse --short=12 HEAD) to main"
git push -q origin main
ok "pushed - watch https://github.com/$GITHUB_REPO/actions"
note "keep  ./deploy/m5/watch_traffic.sh  open: the site stays up the whole time"
note "when the run has rolled back:  ./deploy/m6/demo_fix_release.sh"
