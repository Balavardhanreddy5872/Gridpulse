#!/usr/bin/env bash
# OPTIONAL demo / written-analysis evidence: the PodDisruptionBudget at work.
#
# Asks Kubernetes to EVICT both backend pods back to back - exactly what a
# node upgrade or `kubectl drain` does (the Eviction API respects PDBs;
# `kubectl delete pod` does not).
#   first eviction  -> allowed (1 of 2 may be down)
#   second eviction -> refused: HTTP 429 "Cannot evict pod as it would
#                      violate the pod's disruption budget"
# so one replica keeps serving the whole time. Run watch_traffic.sh alongside
# to show 0 failed requests. Saved to docs/milestone5/evidence/pdb_eviction_test.txt
#
#   ./deploy/m5/pdb_test.sh
set -euo pipefail
cd "$(dirname "$0")"
source ./config.sh
mkdir -p "$EVIDENCE_DIR"
OUT="$EVIDENCE_DIR/pdb_eviction_test.txt"
: > "$OUT"
log() { tee -a "$OUT"; }

evict() {
  printf '{"apiVersion":"policy/v1","kind":"Eviction","metadata":{"name":"%s","namespace":"%s"}}' "$1" "$NAMESPACE" \
    | kubectl create --raw "/api/v1/namespaces/$NAMESPACE/pods/$1/eviction" -f - 2>&1
}

PODS=()
while IFS= read -r p; do [ -n "$p" ] && PODS+=("$p"); done \
  < <(k get pods -l app=backend --field-selector=status.phase=Running -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}')
[ "${#PODS[@]}" -ge 2 ] || die "need at least 2 running backend pods (found ${#PODS[@]})"

{
  echo "=== $(date '+%Y-%m-%d %H:%M:%S %Z')"
  echo "\$ kubectl -n $NAMESPACE get pdb backend"
  k get pdb backend
  echo
  k get pods -l app=backend -o wide
  echo
  echo "=== Evict ${PODS[0]}  (like a node drain would)"
  evict "${PODS[0]}"
  echo
  echo "=== Immediately evict ${PODS[1]} too"
  evict "${PODS[1]}" || true
  echo
  echo "\$ kubectl -n $NAMESPACE get pdb backend      (ALLOWED DISRUPTIONS is now 0)"
  k get pdb backend
} | log

echo | log
echo "=== Waiting for the replacement to be Ready" | log
k rollout status deploy/backend --timeout=5m | log
k get pods -l app=backend -o wide | log
echo
echo "saved: ${OUT#"$REPO_ROOT"/}"
