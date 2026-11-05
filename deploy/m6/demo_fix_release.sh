#!/usr/bin/env bash
# VIDEO: after the bad-release demo, revert that commit and push. The pipeline
# deploys the reverted (good) code as a new release.
#
#   ./deploy/m6/demo_fix_release.sh
set -euo pipefail
cd "$(dirname "$0")"
source ./config.sh
cd "$REPO_ROOT"
[ "$(git rev-parse --abbrev-ref HEAD)" = main ] || die "switch to main first"
git pull -q --ff-only origin main
case "$(git log -1 --format=%s)" in
  "demo: bad release"*) ;;
  *) die "the last commit is not a demo bad release: $(git log -1 --format='%h %s')" ;;
esac
git revert --no-edit HEAD
git push -q origin main
ok "pushed revert $(git rev-parse --short=12 HEAD) - watch https://github.com/$GITHUB_REPO/actions"
