# GridPulse — Milestone 4 Demo Script (10 minutes)

**Cameras on:** every presenter's face must be visible during their segment (webcam overlay on the
screen recording). Audio over a screen recording is not accepted. Names are a suggested split, so swap freely.

## Before you hit record

- [ ] Runbook steps 0–3 done: `vm_migrate.sh` finished with **ALL 7 TABLES MATCH**
- [ ] `./deploy/m4/vm_verify.sh` passes (run it once off camera so the image scan is cached)
- [ ] Browser tabs: `http://35.184.90.182` · Cloud SQL `gridpulse-db` → **Connections** ·
      Cloud Storage bucket `gridpulse-509202-uploads` → `documents/` · Secret Manager ·
      IAM & Admin → IAM (filter `gridpulse-vm-sa`) · GitHub `backend/migrations/versions/0001_initial_schema.py`
- [ ] SSH window open in `~/gridpulse`, font size up
- [ ] A small PDF ready to upload (e.g. a maintenance report with "Capacity reduction: 150 MW" and a date range)
- [ ] `docs/milestone4/gridpulse_milestone4.pptx` open

---

## 0:00 – 1:00 · Where the state went — *Balavardhan* (slide 1)

> "In Milestone 3 everything that mattered lived on the VM's disk: the Postgres volume, the uploaded PDFs,
> and the database password in a .env file. Delete the VM and all three were gone. In Milestone 4 the VM
> runs only two stateless containers. The database is Cloud SQL on a private IP, the PDFs are in a Cloud
> Storage bucket, and the password is in Secret Manager. Deleting the VM now costs us downtime and nothing else."

## 1:00 – 2:30 · The app works end to end on the managed database — *Dhanush* *(rubric 11)*

Show:
1. Browser `http://35.184.90.182`: Dashboard (10 regions), then Regional forecast → **Recompute**, then Alerts.
2. SSH: `curl -s localhost/api/system/info | python3 -m json.tool`
   Point at `server_address` (the **10.60.x.x private IP**), `tls: true`, `migration: 0001_initial_schema`,
   storage `gs://gridpulse-509202-uploads/documents/`, and identity `gridpulse-vm-sa`.

> "The address Postgres reports for itself is the private Cloud SQL IP, over TLS. There is no database container on this VM any more."

3. `docker compose ps`: only `backend` and `frontend` are running.

## 2:30 – 3:30 · Private IP only — *Dhanush* *(rubric 11)*

Show: Console → SQL → `gridpulse-db` → **Connections → Networking**: Private IP ✔, **Public IP not enabled**.
Then Overview: the only address is the private one. Mention SSL mode **ENCRYPTED_ONLY**.

> "Cloud SQL has no public IPv4 address at all. It gets its private address from a 10.60.0.0/20 range peered into our VPC, so only the VM can reach it."

## 3:30 – 5:00 · Migration file + row counts — *Arun* *(rubric 10)*

Show:
1. GitHub: `backend/migrations/versions/0001_initial_schema.py`. Scroll through the seven `CREATE TABLE` statements.
2. SSH: `docker compose run --rm --no-deps backend alembic current` → `0001_initial_schema (head)`
3. SSH: `cat docs/milestone4/evidence/row_counts_side_by_side.txt`

> "The app no longer creates tables. This migration does, and it reproduces the Milestone 3 schema exactly, so the data dumped from the old container loaded without changes. Every table matches on row count **and** on a checksum of every row."

## 5:00 – 6:30 · Uploads go to the bucket via the VM's identity — *Harshitha* *(rubric 10)*

Show:
1. Browser → Documents → upload the PDF for a region.
2. Console → Cloud Storage → `gridpulse-509202-uploads` → `documents/region-N/` → **refresh**: the new object appears.
3. Browser: `http://35.184.90.182/api/documents/<id>/file` → the PDF opens, read back from the bucket.
4. SSH: `docker compose exec backend python -m app.gcp whoami`
   → `gridpulse-vm-sa@…` via **VM metadata server (no key file)**.

> "The PDF goes from memory straight to the bucket. It never touches the VM's disk, and the backend container can't write to disk at all. Its filesystem is read-only. Credentials come from the metadata server, and the service account has zero keys."

## 6:30 – 8:00 · No .env, secrets in Secret Manager — *Tanmaya* *(rubric 8)*

Show (SSH):
```bash
ls -la ~/gridpulse/.env                                                  # No such file or directory
docker compose exec backend sh -c 'find / -xdev -name ".env*" 2>/dev/null | wc -l'   # 0
docker compose exec backend env | grep -E '^(DB_|GCS_|CLOUDSQL)'         # names only, no password
docker compose exec backend touch /app/x                                 # Read-only file system
./deploy/m4/vm_verify.sh                                                 # scroll to RESULT: all checks passed
```
Then Console → Security → **Secret Manager**: `gridpulse-db-password`, `gridpulse-db-root-password`.
Values are hidden. Open one to show who can access it.

> "The container's environment holds the secret's *name*, not its value. The backend reads the password from Secret Manager at start-up and keeps it only in memory. The script also scans every layer of the image for the real password and finds nothing."

## 8:00 – 9:00 · Identity and network — *Arun* (slide 2) *(rubric 10 + 8)*

Show slide 2, then Console → IAM & Admin → IAM filtered to `gridpulse-vm-sa`, then (laptop)
`./deploy/m4/07_evidence.sh iam`, which lists the per-resource grants the IAM page doesn't show.

> "Each role is granted on the one resource it's for: one secret, one bucket, one repository, plus Cloud SQL Client. The VM's static IP is the only public address, and the firewall allows only our team IPs."

## 9:00 – 10:00 · If the VM were deleted right now — *Balavardhan* *(rubric 6)*

> "What survives: every table in Cloud SQL, every PDF in the bucket, both secrets, the images in
> Artifact Registry, the service account, the static IP and the firewall rule. What breaks: the app is
> offline until we build a new VM. That rebuild is manual and takes about 15 to 20 minutes. Requests in
> flight fail, and the container logs are lost because they still live on the VM's disk. Shipping logs to
> Cloud Logging and automating the rebuild are what's left."

Close on slide 1.
