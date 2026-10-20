#!/usr/bin/env bash
# VIDEO HELPER: one request every 0.5 s through the real public path
# (DNS -> load balancer -> Ingress -> Service -> pod). Prints the status code
# and WHICH POD answered, plus a running count of failures.
# Leave it running in a second terminal while you delete a pod or run the
# autoscaling demo: replicas come and go, the error count stays at 0.
#
#   ./deploy/m5/watch_traffic.sh                    # https://<domain>/api/health/ready
#   ./deploy/m5/watch_traffic.sh /api/regions       # any path
#   Ctrl-C prints the totals
set -uo pipefail
cd "$(dirname "$0")"
source ./config.sh
URL="https://${DOMAIN}${1:-/api/health/ready}"
total=0; failed=0
trap 'echo; echo "TOTAL: $total requests, $failed failed (non-2xx or no answer)"; exit 0' INT TERM
echo "GET $URL every 0.5 s - Ctrl-C to stop"
while true; do
  resp="$(curl -sS --max-time 5 -w $'\n%{http_code}' "$URL" 2>/dev/null)"
  code="${resp##*$'\n'}"; body="${resp%$'\n'*}"
  pod="$(printf '%s' "$body" | sed -n 's/.*"pod":"\([^"]*\)".*/\1/p')"
  total=$((total + 1))
  case "$code" in 2??) mark="ok  " ;; *) mark="FAIL"; failed=$((failed + 1)) ;; esac
  printf '%s  %s  %s  %-34s  failed so far: %d/%d\n' "$(now)" "$mark" "${code:-000}" "${pod:--}" "$failed" "$total"
  sleep 0.5
done
