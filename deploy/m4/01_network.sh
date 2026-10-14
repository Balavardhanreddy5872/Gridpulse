#!/usr/bin/env bash
# LAPTOP, step 1: enable the APIs and give Cloud SQL a PRIVATE address range
# inside the VM's VPC (Private Services Access), so the database never needs a
# public IP.
#
#   ./deploy/m4/01_network.sh
set -euo pipefail
cd "$(dirname "$0")"
source ./config.sh

step "Enabling APIs (Cloud SQL Admin, Service Networking, Secret Manager, Storage, IAM)"
gc services enable \
  compute.googleapis.com servicenetworking.googleapis.com sqladmin.googleapis.com \
  secretmanager.googleapis.com storage.googleapis.com iam.googleapis.com \
  cloudresourcemanager.googleapis.com artifactregistry.googleapis.com
ok "APIs enabled"

step "Finding the VPC network and subnet the VM uses"
NETWORK="$(gc compute instances describe "$VM" --zone "$ZONE" --format='value(networkInterfaces[0].network.basename())')"
SUBNET="$(gc compute instances describe "$VM" --zone "$ZONE" --format='value(networkInterfaces[0].subnetwork.basename())')"
VM_INTERNAL_IP="$(gc compute instances describe "$VM" --zone "$ZONE" --format='value(networkInterfaces[0].networkIP)')"
SUBNET_CIDR="$(gc compute networks subnets describe "$SUBNET" --region "$REGION" --format='value(ipCidrRange)')"
ok "VM $VM -> network '$NETWORK', subnet '$SUBNET' ($SUBNET_CIDR), internal IP $VM_INTERNAL_IP"

step "Reserving the private range $PSA_RANGE_START/$PSA_RANGE_PREFIX for Google-managed services"
if gc compute addresses describe "$PSA_RANGE_NAME" --global >/dev/null 2>&1; then
  ok "$PSA_RANGE_NAME already exists"
else
  gc compute addresses create "$PSA_RANGE_NAME" --global \
    --purpose=VPC_PEERING --addresses="$PSA_RANGE_START" --prefix-length="$PSA_RANGE_PREFIX" \
    --network="$NETWORK" --description="Private IP range for Cloud SQL (GridPulse Milestone 4)"
  ok "created $PSA_RANGE_NAME"
fi

step "Peering the VPC with Google's service network (takes 1-2 minutes)"
EXISTING="$(gc services vpc-peerings list --network="$NETWORK" \
  --service=servicenetworking.googleapis.com --format='value(reservedPeeringRanges.list())' 2>/dev/null || true)"
if [ -z "$EXISTING" ]; then
  gc services vpc-peerings connect --service=servicenetworking.googleapis.com \
    --ranges="$PSA_RANGE_NAME" --network="$NETWORK"
  ok "peering created"
elif [[ ",$EXISTING," != *",$PSA_RANGE_NAME,"* ]]; then
  gc services vpc-peerings update --service=servicenetworking.googleapis.com \
    --ranges="$EXISTING,$PSA_RANGE_NAME" --network="$NETWORK" --force
  ok "peering updated to include $PSA_RANGE_NAME"
else
  ok "peering already includes $PSA_RANGE_NAME"
fi

echo
echo "For slide 2 (network diagram):"
echo "  VPC network         : $NETWORK"
echo "  VM subnet           : $SUBNET  $SUBNET_CIDR  (VM internal IP $VM_INTERNAL_IP)"
echo "  Cloud SQL range     : $PSA_RANGE_NAME  $PSA_RANGE_START/$PSA_RANGE_PREFIX  (peered, private only)"
echo
echo "Next: ./deploy/m4/02_secrets.sh"
