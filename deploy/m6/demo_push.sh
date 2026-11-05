#!/usr/bin/env bash
# VIDEO: push a new release to main and let the pipeline build, deploy and
# health-check it. The commit is empty on purpose - the release is still new: new
# image tags, new version at /api/version, /version.json and in the sidebar.
#
#   ./deploy/m6/demo_push.sh
#   ./deploy/m6/demo_push.sh "release: tweak X"      # custom commit message
set -euo pipefail
cd "$(dirname "$0")"
source ./config.sh
cd "$REPO_ROOT"
[ "$(git rev-parse --abbrev-ref HEAD)" = main ] || die "switch to main first"
[ -z "$(git status --porcelain --untracked-files=no)" ] || die "commit or stash your changes first"
git pull -q --ff-only origin main

step "Serving now"
printf '    backend  '; curl -sS --max-time 10 "$APP_URL/api/version"; echo
printf '    frontend '; curl -sS --max-time 10 "$APP_URL/version.json"

git commit -q --allow-empty -m "${1:-release: Milestone 6 live demo ($(date '+%Y-%m-%d %H:%M'))}"
git push -q origin main
ok "pushed $(git rev-parse --short=12 HEAD) to main - release version $(git rev-parse HEAD | cut -c1-12)"
note "watch it: https://github.com/$GITHUB_REPO/actions"
