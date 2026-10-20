#!/usr/bin/env bash
# VIDEO, rubric "pod deleted and replaced automatically" - run it LIVE on camera.
#
#  1. BEFORE: the Deployment and its pods (names, ages, nodes)
#  2. deletes one backend pod
#  3. watches every 2 s until the Deployment is back to full strength with a
#     NEW pod (new name, age in seconds) in place of the deleted one
#  4. AFTER: the same listing + the ReplicaSet events that prove Kubernetes
#     (not us) created the replacement
# Everything is also saved to docs/milestone5/evidence/pods_before_after_delete.txt
#
#   ./deploy/m5/demo_delete_pod.sh                 # deletes the oldest backend pod
#   ./deploy/m5/demo_delete_pod.sh <pod-name>      # or a specific one
#   APP=frontend ./deploy/m5/demo_delete_pod.sh    # or a dashboard pod
set -euo pipefail
cd "$(dirname "$0")"
source ./config.sh
APP="${APP:-backend}"
mkdir -p "$EVIDENCE_DIR"
OUT="$EVIDENCE_DIR/pods_before_after_delete.txt"
: > "$OUT"
log() { tee -a "$OUT"; }

POD="${1:-$(k get pods -l app="$APP" --sort-by=.metadata.creationTimestamp -o jsonpath='{.items[0].metadata.name}')}"
[ -n "$POD" ] || die "no $APP pods found"
WANT="$(k get deploy "$APP" -o jsonpath='{.spec.replicas}')"

{
  echo "=== BEFORE  $(date '+%Y-%m-%d %H:%M:%S %Z')"
  echo "\$ kubectl -n $NAMESPACE get deploy $APP"
  k get deploy "$APP"
  echo
  echo "\$ kubectl -n $NAMESPACE get pods -l app=$APP -o wide"
  k get pods -l app="$APP" -o wide
  echo
  echo "=== DELETE  $(date '+%H:%M:%S')"
  echo "\$ kubectl -n $NAMESPACE delete pod $POD"
} | log
k delete pod "$POD" --wait=false | log

echo | log
echo "=== WATCH (every 2 s until $WANT/$WANT Ready and $POD is gone)" | log
START=$(date +%s)
while :; do
  sleep 2
  ready="$(k get deploy "$APP" -o jsonpath='{.status.readyReplicas}')"
  still_there="$(k get pod "$POD" --ignore-not-found -o name)"
  printf -- '--- %s  (+%ss)  ready %s/%s\n' "$(now)" "$(( $(date +%s) - START ))" "${ready:-0}" "$WANT" | log
  k get pods -l app="$APP" -o wide --no-headers | log
  if [ "${ready:-0}" -ge "$WANT" ] && [ -z "$still_there" ]; then break; fi
  [ $(( $(date +%s) - START )) -gt 240 ] && { echo "(stopped watching after 4 minutes)" | log; break; }
done

{
  echo
  echo "=== AFTER  $(date '+%Y-%m-%d %H:%M:%S %Z')  - replaced in $(( $(date +%s) - START )) s"
  echo "\$ kubectl -n $NAMESPACE get deploy $APP"
  k get deploy "$APP"
  echo
  echo "\$ kubectl -n $NAMESPACE get pods -l app=$APP -o wide"
  k get pods -l app="$APP" -o wide
  echo
  echo "\$ kubectl -n $NAMESPACE get events  (ReplicaSet created the replacement)"
  k get events --sort-by=.lastTimestamp \
    --field-selector involvedObject.kind=ReplicaSet \
    -o custom-columns='TIME:.lastTimestamp,OBJECT:.involvedObject.name,REASON:.reason,MESSAGE:.message' | tail -4
} | log
echo
echo "saved: ${OUT#"$REPO_ROOT"/}"
