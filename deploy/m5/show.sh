#!/usr/bin/env bash
# VIDEO HELPER: the short live checks for the Milestone 5 demo, one word each,
# so nothing long has to be typed on camera. Every command is printed (after
# "$") right before its real, live output.
#
#   ./deploy/m5/show.sh replicas   # Deployments, HPAs, PDBs, pods + nodes
#   ./deploy/m5/show.sh https      # http -> 301 -> https, ManagedCertificate status
#   ./deploy/m5/show.sh hpa        # the backend autoscaler right now
#   ./deploy/m5/show.sh probes     # the three probes + both health endpoints
#   ./deploy/m5/show.sh git        # the manifests are committed and pushed
set -uo pipefail
cd "$(dirname "$0")"
source ./config.sh

run() {
  printf '\n\033[1m$ %s\033[0m\n' "$1"
  eval "$1"
}

clear
case "${1:-}" in
  replicas)
    run "kubectl -n $NAMESPACE get deploy,hpa,pdb"
    run "kubectl -n $NAMESPACE get pods -o wide"
    ;;
  https)
    run "curl -sI http://$DOMAIN | grep -iE '^HTTP|^location'"
    run "kubectl -n $NAMESPACE get managedcertificate"
    ;;
  hpa)
    run "kubectl -n $NAMESPACE get hpa backend"
    ;;
  probes)
    run "kubectl -n $NAMESPACE describe deploy backend | grep -E 'Liveness|Readiness|Startup'"
    run "curl -s https://$DOMAIN/api/health/live; echo"
    run "curl -s https://$DOMAIN/api/health/ready; echo"
    ;;
  git)
    cd "$REPO_ROOT" || exit 1
    run "git status -sb"
    run "git log --oneline -3 -- k8s/"
    run "ls k8s/"
    ;;
  *)
    echo "usage: $0 replicas | https | hpa | probes | git"
    exit 1
    ;;
esac
echo
