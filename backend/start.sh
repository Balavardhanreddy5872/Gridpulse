#!/bin/sh
# Container start-up (the image's CMD).
#  1. Apply database migrations. Idempotent: "already at head" is a no-op.
#     On the VM this reaches Cloud SQL over its private IP, with the password
#     read from Secret Manager by the VM's service account.
#  2. Local development only: load the synthetic demo data into an empty DB.
#     (Cloud SQL got the Milestone 3 data from deploy/m4/vm_migrate.sh.)
#  3. Hand PID 1 to uvicorn. No --reload in a container.
#     On SIGTERM (pod deleted / scaled down / rolled) uvicorn stops accepting
#     new connections and gives in-flight requests up to 20 s to finish.
#     --proxy-headers: trust X-Forwarded-Proto from the Google load balancer.
set -e
cd /app/backend
alembic upgrade head
if [ "${SEED_DEMO_DATA:-false}" = "true" ]; then
  python /app/scripts/seed_database.py
fi
exec uvicorn app.main:app --host 0.0.0.0 --port 8000 \
  --proxy-headers --forwarded-allow-ips='*' --timeout-graceful-shutdown 20
