#!/usr/bin/env bash
# LAPTOP: allow this computer's current public IPv4 through the GridPulse
# firewall rule, keeping every IP that is already allowed. Run it whenever you
# switch networks (campus, home, anywhere else) before opening the app.
#
#   ./deploy/allow_my_ip.sh
set -euo pipefail

RULE="${RULE:-gridpulse-team-access}"
MYIP="$(curl -4 -s https://ifconfig.me)"
[ -n "$MYIP" ] || { echo "Could not detect your public IPv4 address."; exit 1; }

CURRENT="$(gcloud compute firewall-rules describe "$RULE" --format='value(sourceRanges.list())')"

if echo ",${CURRENT}," | grep -q ",${MYIP}/32,"; then
  echo "${MYIP} is already allowed by ${RULE} - nothing to change."
else
  gcloud compute firewall-rules update "$RULE" --source-ranges="${CURRENT},${MYIP}/32"
  echo "Added ${MYIP}/32 to ${RULE} (existing IPs kept)."
fi

echo "Allowed now: $(gcloud compute firewall-rules describe "$RULE" --format='value(sourceRanges.list())')"
