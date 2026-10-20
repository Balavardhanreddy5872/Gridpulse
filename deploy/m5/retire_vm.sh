#!/usr/bin/env bash
# LAPTOP: after GKE is serving, STOP the Milestone 4 VM. The orchestrator runs
# the containers now, and two copies of the job worker should not share the
# Cloud SQL queue (the VM still runs the v2 image).
#
# Stopping (not deleting) keeps the disk and the M2-M4 static IP, so you can
# start it again for comparison:  gcloud compute instances start gridpulse-vm --zone us-central1-a
# A stopped VM costs only its disk (~US$1/month) plus the idle static IP.
#
#   ./deploy/m5/retire_vm.sh
set -euo pipefail
cd "$(dirname "$0")"
source ./config.sh

step "Is GKE serving?"
curl -fsS --max-time 10 "https://$DOMAIN/api/health/ready" >/dev/null \
  || die "https://$DOMAIN/api/health/ready does not answer - keep the VM until it does"
ok "https://$DOMAIN is up"

STATE="$(gc compute instances describe "$VM" --zone "$ZONE" --format='value(status)')"
if [ "$STATE" = "TERMINATED" ]; then ok "$VM is already stopped"; exit 0; fi
printf '    Stop %s (currently %s)? [y/N] ' "$VM" "$STATE"
read -r answer
[ "$answer" = "y" ] || [ "$answer" = "Y" ] || { note "left running"; exit 0; }
gc compute instances stop "$VM" --zone "$ZONE"
ok "$VM stopped"
