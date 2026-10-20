#!/usr/bin/env bash
# VIDEO, rubric "the replica count changing" - evidence that the HPA acted.
#
#  1. shows the HPA at rest (2 replicas, low CPU)
#  2. starts k8s/loadtest/load-generator.yaml (4 minutes of traffic, in-cluster)
#  3. prints a timeline every 10 s: CPU vs target, replicas, Ready pods
#  4. after the load stops, keeps watching until the HPA scales back down
#  5. saves the timeline + `kubectl describe hpa` events (SuccessfulRescale
#     "New size: 3; reason: cpu resource utilization ... above target") to
#     docs/milestone5/evidence/hpa_scaling.txt
#
#   ./deploy/m5/demo_autoscale.sh
#   NO_SCALE_DOWN=1 ./deploy/m5/demo_autoscale.sh     # stop once the load ends
#
# Tip for the video: in a second terminal run
#   kubectl -n gridpulse get hpa backend --watch
set -euo pipefail
cd "$(dirname "$0")"
source ./config.sh
mkdir -p "$EVIDENCE_DIR"
OUT="$EVIDENCE_DIR/hpa_scaling.txt"
: > "$OUT"
log() { tee -a "$OUT"; }

line() {
  local hpa ready
  hpa="$(k get hpa backend -o jsonpath='{.status.currentMetrics[0].resource.current.averageUtilization}%/{.spec.metrics[0].resource.target.averageUtilization}%  replicas: {.status.currentReplicas} -> desired {.status.desiredReplicas}')"
  ready="$(k get deploy backend -o jsonpath='{.status.readyReplicas}')"
  printf '%s  cpu %s  ready %s\n' "$(now)" "$hpa" "${ready:-0}"
}

{
  echo "=== HPA at rest  $(date '+%Y-%m-%d %H:%M:%S %Z')"
  k get hpa backend
  echo
  k top pods -l app=backend 2>/dev/null || echo "(kubectl top not available yet)"
  echo
} | log

START_REPLICAS="$(k get hpa backend -o jsonpath='{.status.currentReplicas}')"
k delete job load-generator --ignore-not-found --wait=true >/dev/null
k apply -f "$K8S_DIR/loadtest/load-generator.yaml" | log
echo | log
echo "=== Timeline (CPU is % of the 250m request; target 60%)" | log

MAX="$START_REPLICAS"
LOAD_DONE=""
for i in $(seq 1 60); do
  line | log
  cur="$(k get hpa backend -o jsonpath='{.status.currentReplicas}')"
  [ "${cur:-0}" -gt "$MAX" ] && MAX="$cur"
  if [ -z "$LOAD_DONE" ] && k get job load-generator -o jsonpath='{.status.conditions[*].type}' 2>/dev/null | grep -qE 'Complete|Failed'; then
    LOAD_DONE="$(now)"
    echo "--- $(now) load generator finished" | log
    [ "${NO_SCALE_DOWN:-0}" = "1" ] && break
  fi
  if [ -n "$LOAD_DONE" ] && [ "${cur:-0}" -le "$START_REPLICAS" ]; then
    echo "--- $(now) back to $cur replicas" | log
    break
  fi
  sleep 10
done

{
  echo
  echo "=== Result: replicas went $START_REPLICAS -> $MAX -> $(k get hpa backend -o jsonpath='{.status.currentReplicas}')"
  echo
  echo "=== Load generator summary"
  k logs job/load-generator --tail=3 2>/dev/null || true
  echo
  echo "=== kubectl describe hpa backend (events)"
  k describe hpa backend | sed -n '/^Events:/,$p'
} | log
echo
echo "saved: ${OUT#"$REPO_ROOT"/}"
