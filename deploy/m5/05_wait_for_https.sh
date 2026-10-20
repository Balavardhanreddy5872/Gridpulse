#!/usr/bin/env bash
# LAPTOP, step 5: wait for the load balancer + Google-managed certificate,
# then prove https works and http redirects.
#
# Status goes  Provisioning -> Active. It stays Provisioning (or shows
# FailedNotVisible) while DNS does not point at the load balancer's IP.
# Google says provisioning can take up to 60 minutes; leave this running.
#
#   ./deploy/m5/05_wait_for_https.sh
set -euo pipefail
cd "$(dirname "$0")"
source ./config.sh
IP="$(gc compute addresses describe "$GKE_IP_NAME" --global --format='value(address)')"

step "Ingress address"
for _ in $(seq 1 60); do
  ING_IP="$(k get ingress gridpulse -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)"
  [ -n "$ING_IP" ] && break
  note "$(now) load balancer not created yet"
  sleep 15
done
[ "$ING_IP" = "$IP" ] && ok "Ingress is on $IP (the reserved static IP)" \
  || note "Ingress IP '$ING_IP' differs from $GKE_IP_NAME ($IP) - check the global-static-ip-name annotation"

step "Certificate for $DOMAIN (checks every 60 s, up to 90 minutes)"
for i in $(seq 1 90); do
  STATUS="$(k get managedcertificate gridpulse-cert -o jsonpath='{.status.certificateStatus}' 2>/dev/null || true)"
  DSTATUS="$(k get managedcertificate gridpulse-cert -o jsonpath='{.status.domainStatus[0].status}' 2>/dev/null || true)"
  if [ "$STATUS" = "Active" ]; then ok "$(now) certificate Active"; break; fi
  note "$(now) certificate: ${STATUS:-pending}  domain: ${DSTATUS:-pending}   ($i/90)"
  if [ "$DSTATUS" = "FailedNotVisible" ]; then
    note "FailedNotVisible = Google cannot reach $DOMAIN on $IP. Check:  dig +short $DOMAIN  (must print $IP)"
  fi
  sleep 60
done
[ "$STATUS" = "Active" ] || die "still not Active - see the Troubleshooting table in docs/milestone5/RUNBOOK.md"

step "Waiting for the load balancer to serve the new certificate (can lag a few minutes behind Active)"
for i in $(seq 1 40); do
  if curl -fsS -o /dev/null --max-time 10 "https://$DOMAIN/healthz" 2>/dev/null; then
    ok "$(now) https://$DOMAIN is serving with a trusted certificate"; break
  fi
  note "$(now) not yet ($i/40)"
  sleep 30
done

step "Proof"
./https_check.sh

echo
echo "Open https://$DOMAIN in a browser and click the padlock for the certificate screenshot."
echo "Then take the Console screenshot: Network services -> Load balancing -> (k8s2-...gridpulse...) -> Certificate: ACTIVE"
