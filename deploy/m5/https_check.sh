#!/usr/bin/env bash
# The four HTTPS facts the rubric asks for, in one screen (also saved to
# docs/milestone5/evidence/https_check.txt):
#   1. https://<domain>/ answers 200 with a certificate the system trusts
#   2. who issued the certificate, for which name, and until when
#   3. http://<domain>/ answers 301 with Location: https://<domain>/
#   4. the API behind it is Ready (and which pod answered)
#
#   ./deploy/m5/https_check.sh
set -euo pipefail
cd "$(dirname "$0")"
source ./config.sh
mkdir -p "$EVIDENCE_DIR"
OUT="$EVIDENCE_DIR/https_check.txt"

{
  echo "GridPulse HTTPS check - $(date '+%Y-%m-%d %H:%M:%S %Z') - $DOMAIN"
  echo
  echo "== 1. https://$DOMAIN/  (curl verifies the certificate; no -k)"
  curl -sS -o /dev/null --max-time 15 \
    -w '   HTTP %{http_code}   TLS verify result: %{ssl_verify_result} (0 = trusted)   %{remote_ip}\n' \
    "https://$DOMAIN/"
  echo
  echo "== 2. Certificate presented by the load balancer"
  echo | openssl s_client -connect "$DOMAIN:443" -servername "$DOMAIN" 2>/dev/null \
    | openssl x509 -noout -subject -issuer -dates 2>/dev/null | sed 's/^/   /'
  echo
  echo "== 3. http://$DOMAIN/  (must redirect)"
  curl -sS -o /dev/null --max-time 15 -w '   HTTP %{http_code}  ->  Location: %{redirect_url}\n' "http://$DOMAIN/"
  curl -sS -o /dev/null --max-time 15 -w '   HTTP %{http_code}  ->  Location: %{redirect_url}\n' "http://$DOMAIN/api/regions"
  echo
  echo "== 4. https://$DOMAIN/api/health/ready"
  printf '   '; curl -sS --max-time 15 "https://$DOMAIN/api/health/ready"; echo
  echo
  echo "== 5. ManagedCertificate status in the cluster"
  k get managedcertificate gridpulse-cert \
    -o custom-columns='NAME:.metadata.name,STATUS:.status.certificateStatus,DOMAIN:.status.domainStatus[0].domain,DOMAIN_STATUS:.status.domainStatus[0].status,EXPIRES:.status.expireTime' \
    | sed 's/^/   /'
} 2>&1 | tee "$OUT"
echo
echo "saved: ${OUT#"$REPO_ROOT"/}"
