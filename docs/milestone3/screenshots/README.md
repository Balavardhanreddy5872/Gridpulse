# Milestone 3 evidence

| File | What it shows | Rubric item |
|---|---|---|
| 03_registry_backend_v1.png | Artifact Registry: gridpulse-backend, tags **latest, v1**, digest sha256:687b32e2… | Pushed with version tag (7) |
| 04_registry_frontend_v1.png | Artifact Registry: gridpulse-frontend, tags **latest, v1**, digest sha256:403816f2… | Pushed with version tag (7) |
| 03a_registry_overview.png | Repository `gridpulse` (us-central1) holding both images | Pushed with version tag (7) |
| 05_verify_no_secrets.png | `./deploy/verify_no_secrets.sh`: all checks PASS, "no secrets baked into either image" | Dockerfile / .dockerignore / no secrets (8) |
| 06_vm_digests_match.png | VM: same sha256 digests as the laptop, model xgboost-v1, all containers (healthy) | Same image runs on the VM (10) |
| 08_budget_thresholds.png | $50 budget with alerts at 10/20/25/50/100% (Actual), email alerts on | Budget guardrails (5) |
| 08a_budget_before_update_m2.png | The same budget as set up in Milestone 2 (20/50/100%), before adding 10% and 25% | Budget guardrails (5) |
| 09_billing_spend.png | Billing overview, current month: $2.42 cost, covered by credits, $0.00 billed | Budget guardrails (5) |
| 10_trial_credits_used.png | Console home: $11 of $300 trial credit used, project gridpulse-509202 | Budget guardrails (5) |

The full VM pull-and-run log is `../m3_vm_pull_and_run.log`.
Local Compose run and both dashboards (laptop and http://35.184.90.182) are shown in the video.
