#!/usr/bin/env bash
# LAPTOP, step 6: attach gridpulse-vm-sa to the VM with the cloud-platform
# access scope (IAM roles from step 5 then decide what it may actually do).
# Changing a VM's service account requires the VM to be STOPPED, so the app
# is down for ~1-2 minutes. The Milestone 3 containers restart on their own.
#
#   ./deploy/m4/06_switch_vm_identity.sh
set -euo pipefail
cd "$(dirname "$0")"
source ./config.sh

describe() { gc compute instances describe "$VM" --zone "$ZONE" --format="value($1)"; }

CURRENT_SA="$(describe 'serviceAccounts[0].email')"
CURRENT_SCOPES="$(describe 'serviceAccounts[0].scopes.list()')"
step "VM $VM currently runs as: ${CURRENT_SA:-<none>}"
note "scopes: ${CURRENT_SCOPES:-<none>}"

if [ "$CURRENT_SA" = "$VM_SA_EMAIL" ] && [[ "$CURRENT_SCOPES" == *"/auth/cloud-platform"* ]]; then
  ok "already using $VM_SA_EMAIL with the cloud-platform scope - nothing to do"
  exit 0
fi

step "Making sure the external IP is static (so http://<IP> survives the stop/start)"
EXTERNAL_IP="$(describe 'networkInterfaces[0].accessConfigs[0].natIP')"
RESERVED="$(gc compute addresses list --filter="address=${EXTERNAL_IP}" --format='value(name)')"
if [ -n "$RESERVED" ]; then
  ok "$EXTERNAL_IP is reserved as '$RESERVED'"
else
  gc compute addresses create "$STATIC_IP_NAME" --addresses="$EXTERNAL_IP" --region="$REGION"
  ok "promoted $EXTERNAL_IP to static address '$STATIC_IP_NAME'"
fi

step "Stopping $VM (app downtime starts)"
gc compute instances stop "$VM" --zone "$ZONE"

step "Attaching $VM_SA_EMAIL with scope cloud-platform"
gc compute instances set-service-account "$VM" --zone "$ZONE" \
  --service-account="$VM_SA_EMAIL" --scopes=cloud-platform

step "Starting $VM"
gc compute instances start "$VM" --zone "$ZONE"

ok "VM now runs as $(describe 'serviceAccounts[0].email')"
note "scopes: $(describe 'serviceAccounts[0].scopes.list()')"
note "external IP: $(describe 'networkInterfaces[0].accessConfigs[0].natIP')"
echo
echo "Give it ~1 minute, then SSH in and run:  ./deploy/m4/vm_migrate.sh"
