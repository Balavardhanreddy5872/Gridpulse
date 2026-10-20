#!/usr/bin/env bash
# LAPTOP, step 3: the address and the hostname.
#
#  1. Reserves a GLOBAL static IP (gridpulse-gke-ip) for the load balancer, so
#     the address never changes even if the Ingress is recreated.
#  2. Points your DuckDNS name at it (if you give the DuckDNS token), or tells
#     you exactly what to type on duckdns.org.
#  3. Writes the hostname into k8s/managed-certificate.yaml and
#     k8s/backend-configmap.yaml (the lines marked "# DOMAIN").
#  4. Checks that public DNS already answers with that IP - the Google-managed
#     certificate cannot be issued until it does.
#
#   ./deploy/m5/03_static_ip_and_dns.sh gridpulse-uh.duckdns.org
#   DUCKDNS_TOKEN=... ./deploy/m5/03_static_ip_and_dns.sh gridpulse-uh.duckdns.org   (no prompt)
#
# DuckDNS: sign in at https://www.duckdns.org (GitHub/Google), add a sub domain,
# copy the token shown at the top of the page. The token is never saved to disk.
set -euo pipefail
cd "$(dirname "$0")"
source ./config.sh
[ $# -ge 1 ] || die "usage: $0 <name>.duckdns.org      (the manifests currently say: $DOMAIN)"
DOMAIN="$1"
[ "${#DOMAIN}" -le 63 ] || die "$DOMAIN is longer than 63 characters (Google-managed certificate limit)"

step "Global static IP '$GKE_IP_NAME'"
if gc compute addresses describe "$GKE_IP_NAME" --global >/dev/null 2>&1; then
  ok "already reserved"
else
  gc compute addresses create "$GKE_IP_NAME" --global --ip-version=IPV4 \
    --description="GridPulse GKE Ingress (Milestone 5)"
  ok "reserved"
fi
IP="$(gc compute addresses describe "$GKE_IP_NAME" --global --format='value(address)')"
ok "$GKE_IP_NAME = $IP"

step "Hostname $DOMAIN -> $IP"
case "$DOMAIN" in
  *.duckdns.org)
    SUB="${DOMAIN%.duckdns.org}"
    if [ -z "${DUCKDNS_TOKEN:-}" ] && [ -t 0 ]; then
      printf '    DuckDNS token (hidden; press Enter to skip and set the IP on the website): '
      read -r -s DUCKDNS_TOKEN || true
      echo
    fi
    if [ -n "${DUCKDNS_TOKEN:-}" ]; then
      # the URL (with the token) goes to curl on stdin, so it never shows up in `ps`
      RESULT="$(printf 'url = "https://www.duckdns.org/update?domains=%s&token=%s&ip=%s"\n' \
        "$SUB" "$DUCKDNS_TOKEN" "$IP" | curl -fsS --max-time 20 -K - || echo "request failed")"
      unset DUCKDNS_TOKEN
      [ "$RESULT" = "OK" ] && ok "DuckDNS updated: $SUB -> $IP" \
        || die "DuckDNS said '$RESULT'. Check the sub domain is yours and the token is right."
    else
      note "On https://www.duckdns.org set the 'current ip' of '$SUB' to  $IP  and click 'update ip'."
    fi
    ;;
  *)
    note "Create a DNS  A  record:  $DOMAIN  ->  $IP   at your DNS provider."
    ;;
esac

step "Writing $DOMAIN into the manifests"
perl -pi -e "s{^(\\s*-\\s+)\\S+(\\s+# DOMAIN)\$}{\${1}$DOMAIN\${2}}" "$K8S_DIR/managed-certificate.yaml"
perl -pi -e "s{^(\\s*CORS_ORIGINS:\\s+)\"[^\"]*\"(\\s+# DOMAIN)\$}{\${1}\"https://$DOMAIN\"\${2}}" "$K8S_DIR/backend-configmap.yaml"
grep -n '# DOMAIN' "$K8S_DIR/managed-certificate.yaml" "$K8S_DIR/backend-configmap.yaml" | sed 's/^/    /'

step "Public DNS check (Google's certificate authority must see the same answer)"
resolve() {
  if command -v dig >/dev/null 2>&1; then dig +short A "$DOMAIN" @"$1" | tail -1
  else python3 -c "import socket,sys; print(socket.gethostbyname(sys.argv[1]))" "$DOMAIN" 2>/dev/null; fi
}
for attempt in 1 2 3 4 5 6; do
  GOT="$(resolve 8.8.8.8 || true)"
  [ "$GOT" = "$IP" ] && break
  note "$DOMAIN -> '${GOT:-nothing}' (want $IP), checking again in 10 s ($attempt/6)"
  sleep 10
done
if [ "$GOT" = "$IP" ]; then
  ok "$DOMAIN resolves to $IP"
else
  note "DNS does not point at $IP yet. Fix that first - the certificate stays 'Provisioning' until it does."
fi

echo
echo "Next: ./deploy/m5/04_deploy.sh      (builds + pushes $IMAGE_TAG, applies k8s/)"
