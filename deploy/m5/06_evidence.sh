#!/usr/bin/env bash
# LAPTOP: everything the "Working Artifacts" part asks for, screenshot-ready,
# and saved to docs/milestone5/evidence/cluster_state.txt
#   - Deployments with >= 2 Ready replicas, pods spread over nodes/zones
#   - Services, Ingress, HPAs, PDBs, ManagedCertificate (Active)
#   - load balancer backends HEALTHY, Google certificate ACTIVE
#   - the two probes, side by side
#   - pods run as gridpulse-gke-app through Workload Identity (no key file)
#   - the manifests are committed in git
#
#   ./deploy/m5/06_evidence.sh
set -euo pipefail
cd "$(dirname "$0")"
source ./config.sh
mkdir -p "$EVIDENCE_DIR"
OUT="$EVIDENCE_DIR/cluster_state.txt"

{
  echo "GridPulse on GKE - $(date '+%Y-%m-%d %H:%M:%S %Z')"
  echo "cluster $CLUSTER ($CLUSTER_LOCATION, Autopilot)   namespace $NAMESPACE   https://$DOMAIN"

  step "Deployments / HPAs / PDBs"
  k get deploy,hpa,pdb -o wide

  step "Pods (node + zone of each replica)"
  k get pods -o wide -L app
  for p in $(k get pods -l 'app in (backend,frontend)' -o jsonpath='{.items[*].spec.nodeName}' | tr ' ' '\n' | sort -u); do
    printf '    node %-55s zone %s\n' "$p" "$(kubectl get node "$p" -o jsonpath='{.metadata.labels.topology\.kubernetes\.io/zone}' 2>/dev/null)"
  done

  step "Services and Ingress"
  k get svc,ingress -o wide

  step "Load balancer backends as Google sees them"
  k get ingress gridpulse -o jsonpath='{.metadata.annotations.ingress\.kubernetes\.io/backends}' \
    | tr ',' '\n' | sed 's/[{}"]//g; s/^/    /'
  echo

  step "Certificates"
  k get managedcertificate gridpulse-cert \
    -o custom-columns='NAME:.metadata.name,STATUS:.status.certificateStatus,DOMAIN:.status.domainStatus[0].domain,DOMAIN_STATUS:.status.domainStatus[0].status,EXPIRES:.status.expireTime'
  gc compute ssl-certificates list --global \
    --format="table(name,type,managed.status:label=MANAGED_STATUS,managed.domains.list():label=DOMAINS,expireTime.date('%Y-%m-%d'):label=EXPIRES)"

  step "Health probes on the backend container"
  k get deploy backend -o jsonpath='{range .spec.template.spec.containers[0]}    startup   : {.startupProbe.httpGet.path}  every {.startupProbe.periodSeconds}s, up to {.startupProbe.failureThreshold} failures{"\n"}    liveness  : {.livenessProbe.httpGet.path}  every {.livenessProbe.periodSeconds}s, restart after {.livenessProbe.failureThreshold} failures{"\n"}    readiness : {.readinessProbe.httpGet.path}  every {.readinessProbe.periodSeconds}s, out of the LB after {.readinessProbe.failureThreshold} failures{"\n"}{end}'
  POD="$(k get pods -l app=backend -o jsonpath='{.items[0].metadata.name}')"
  echo "    from inside $POD:"
  printf '      /api/health/live  -> '; k exec "$POD" -c backend -- python -c "import urllib.request as u; print(u.urlopen('http://127.0.0.1:8000/api/health/live').read().decode())"
  printf '      /api/health/ready -> '; k exec "$POD" -c backend -- python -c "import urllib.request as u; print(u.urlopen('http://127.0.0.1:8000/api/health/ready').read().decode())"

  step "Identity of the backend pods (Workload Identity, no key file)"
  k exec "$POD" -c backend -- python -m app.gcp whoami | sed 's/^/    /'
  k get sa "$KSA" -o jsonpath='    k8s service account {.metadata.name} -> {.metadata.annotations.iam\.gke\.io/gcp-service-account}{"\n"}'

  step "Where the state lives (GET https://$DOMAIN/api/system/info)"
  curl -sS --max-time 15 "https://$DOMAIN/api/system/info" | python3 -m json.tool | sed 's/^/    /'

  step "Manifests committed to git"
  git -C "$REPO_ROOT" ls-files k8s | sed 's/^/    /'
  git -C "$REPO_ROOT" log -1 --format='    last commit touching k8s/: %h %s (%cr)' -- k8s
  if [ -n "$(git -C "$REPO_ROOT" status --porcelain -- k8s)" ]; then
    echo "    WARNING: k8s/ has uncommitted changes - commit and push them"
  fi
} 2>&1 | tee "$OUT"
echo
echo "saved: ${OUT#"$REPO_ROOT"/}"
