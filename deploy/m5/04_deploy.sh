#!/usr/bin/env bash
# LAPTOP, step 4: ship the images and hand the containers to Kubernetes.
#
#  1. builds + pushes gridpulse-backend and gridpulse-frontend:$IMAGE_TAG (v5)
#     (skip with SKIP_BUILD=1 if they are already in Artifact Registry)
#  2. kubectl apply -k k8s/   - namespace, service account, config, 2 Deployments,
#     2 Services, 2 HPAs, 2 PDBs, load-balancer settings, http->https redirect,
#     managed certificate, Ingress
#  3. waits until both Deployments have 2 Ready replicas
#
#   ./deploy/m5/04_deploy.sh
#   SKIP_BUILD=1 ./deploy/m5/04_deploy.sh      # manifests only
set -euo pipefail
cd "$(dirname "$0")"
source ./config.sh
need kubectl "gcloud components install kubectl gke-gcloud-auth-plugin"

if [ "${SKIP_BUILD:-0}" != "1" ]; then
  need docker "Docker Desktop must be running to build the images"
  step "Building and pushing $IMAGE_TAG"
  ../build_and_push.sh "$IMAGE_TAG"
fi

step "Pre-flight checks"
for f in backend-deployment.yaml frontend-deployment.yaml; do
  grep -q ":${IMAGE_TAG}\$" "$K8S_DIR/$f" || die "k8s/$f does not use image tag $IMAGE_TAG"
done
ok "manifests use image tag $IMAGE_TAG"
[ -n "$DOMAIN" ] || die "no hostname in k8s/managed-certificate.yaml - run 03_static_ip_and_dns.sh first"
ok "hostname $DOMAIN"
gc compute addresses describe "$GKE_IP_NAME" --global >/dev/null 2>&1 \
  || die "static IP $GKE_IP_NAME is missing - run 03_static_ip_and_dns.sh first"
ok "static IP $GKE_IP_NAME exists"
kubectl config current-context | grep -q "_${CLUSTER}\$" \
  || die "kubectl is not pointed at $CLUSTER - run: gcloud container clusters get-credentials $CLUSTER --location $CLUSTER_LOCATION"
ok "kubectl context $(kubectl config current-context)"

step "kubectl apply -k k8s/"
kubectl apply -k "$K8S_DIR"

step "Waiting for the rollouts (first start on a new Autopilot cluster can take 3-5 minutes while nodes are added)"
k rollout status deploy/backend --timeout=10m
k rollout status deploy/frontend --timeout=10m

# The HPA, not the Deployment, sets the count: wait until it has raised both to 2.
for d in backend frontend; do
  for _ in $(seq 1 60); do
    ready="$(k get deploy "$d" -o jsonpath='{.status.readyReplicas}')"
    [ "${ready:-0}" -ge 2 ] && break
    sleep 5
  done
  ok "$d: ${ready:-0} replicas Ready"
done

step "What is running"
k get deploy,hpa,pdb -o wide
echo
k get pods -o wide
echo
k get svc,ingress
echo
k get managedcertificate gridpulse-cert

echo
echo "The load balancer takes ~5-10 minutes to come up and the certificate 15-60 minutes."
echo "Next: ./deploy/m5/05_wait_for_https.sh"
