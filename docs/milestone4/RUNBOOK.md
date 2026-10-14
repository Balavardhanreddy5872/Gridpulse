# GridPulse — Milestone 4 Runbook (Managed State)

**Goal:** the VM keeps *nothing*. The database moves to **Cloud SQL (private IP only)**, uploaded
PDFs move to a **Cloud Storage bucket** reached with the **VM's service account** (no key files),
and the DB password moves to **Secret Manager**. Deleting the VM should cost only downtime.

| | |
|---|---|
| GCP project | `gridpulse-509202` · region `us-central1` · zone `us-central1-a` |
| VM | `gridpulse-vm` · http://35.184.90.182 (static IP) |
| Cloud SQL | `gridpulse-db` · PostgreSQL 16 · `db-f1-micro` · private IP from `10.60.0.0/20` · TLS required |
| Bucket | `gs://gridpulse-509202-uploads` (uniform access, public access prevention on) |
| Secrets | `gridpulse-db-password` (app) · `gridpulse-db-root-password` (admin, humans only) |
| VM identity | `gridpulse-vm-sa@gridpulse-509202.iam.gserviceaccount.com` · scope `cloud-platform` · 0 keys |
| Images | `gridpulse-backend:v2`, `gridpulse-frontend:v2` in Artifact Registry |

---

## Where the state goes

| State | Milestone 3 (on the VM) | Milestone 4 (managed) | Survives VM deletion? |
|---|---|---|---|
| Tables + rows | `postgres:16-alpine` container, `gridpulse_pgdata` volume | Cloud SQL `gridpulse-db`, private IP | ✅ |
| Schema definition | `Base.metadata.create_all()` at app start | Alembic migration `0001_initial_schema` (real `CREATE TABLE`s) | ✅ (in git) |
| Uploaded PDFs | `gridpulse_uploads` volume, `/app/uploads/...` | `gs://gridpulse-509202-uploads/documents/region-N/...` | ✅ |
| DB password | `.env` → `DATABASE_URL` env var in the container | Secret Manager, read into memory at start-up | ✅ |
| Job queue (`async_jobs`) | in the container DB | in Cloud SQL (stale jobs re-queued on restart) | ✅ |
| ML model | baked into the image | baked into the image (Artifact Registry) | ✅ |
| Container logs | VM disk | VM disk | ❌ (honest gap — see written analysis) |

```
                       team IPs only (firewall gridpulse-team-access: tcp 22/80/8000)
Browser ──► 35.184.90.182 (static) ──► gridpulse-vm  [subnet default 10.128.0.0/20]
                                         │  runs as gridpulse-vm-sa (metadata server, no keys)
                                         │  frontend (nginx) ──/api──► backend (FastAPI, read-only FS)
                                         │                               │
          private IP, TLS (VPC peering)  ▼                               │ HTTPS + IAM
   Cloud SQL gridpulse-db 10.60.x.x ◄────┘     Secret Manager ◄──────────┤  (secretAccessor, 1 secret)
   (no public IP)                              Cloud Storage bucket ◄────┘  (objectCreator + objectViewer)
```

### Files added / changed

| File | What it does |
|---|---|
| `backend/migrations/versions/0001_initial_schema.py` | **the migration file** — 7 real `CREATE TABLE`s + 3 indexes |
| `backend/alembic.ini`, `backend/migrations/env.py` | Alembic; connects exactly like the app (secret + private IP) |
| `backend/app/gcp.py` | Secret Manager read, Cloud SQL private-IP lookup, `whoami` |
| `backend/app/database.py`, `config.py` | URL built at start-up from the secret; no `.env` support, no default password |
| `backend/app/services/storage.py` | uploads → GCS (`if_generation_match=0`, never overwrite); `local` mode for laptop/tests |
| `backend/app/routers/documents.py` | PDF bytes go memory → bucket; new `GET /api/documents/{id}/file` |
| `backend/app/routers/system.py` | `GET /api/system/info` — DB server IP, TLS, migration, bucket, identity |
| `backend/app/workers/spike_worker.py` | re-queues jobs stuck in `processing` (e.g. VM died mid-job) |
| `backend/start.sh`, `backend/Dockerfile` | container start = `alembic upgrade head` → uvicorn |
| `docker-compose.yml` | **cloud stack**: no DB container, no volumes, no `.env`, read-only backend |
| `docker-compose.local.yml` | laptop dev stack (local Postgres + local folder stand-ins) |
| `deploy/m4/01…07_*.sh` | laptop: network, secrets, Cloud SQL, bucket, service account, VM identity, evidence |
| `deploy/m4/vm_migrate.sh`, `vm_verify.sh` | VM: the one-time data move, and the "nothing on the VM" proof |
| `deploy/m4/sql/*.sql` | row counts + checksums, sequence fix-up |

---

## 0. Before touching the cloud (laptop, ~10 min)

```bash
cd ~/Downloads/gridpulse
git pull                                    # if a teammate pushed first

# 1) tests (26) - needs the new packages in your venv
cd backend && source venv/bin/activate
pip install -r requirements.txt pytest reportlab
pytest -q
deactivate && cd ..

# 2) the M3 .env pins IMAGE_TAG=v1 - start a fresh, local-only one
mv .env .env.m3.bak && cp .env.example .env     # then set POSTGRES_PASSWORD (any value, local only)

# 3) local smoke test of the new code (migration runs on start, demo data seeded)
docker compose -f docker-compose.local.yml up --build
#   http://localhost  -> upload a PDF on the Documents page -> it works
#   http://localhost:8000/api/system/info -> "migration": "0001_initial_schema"
docker compose -f docker-compose.local.yml down
```

## 1. Ship v2 (laptop)

```bash
./deploy/build_and_push.sh v2          # builds linux/amd64, pushes :v2 and :latest
git add -A && git status               # .env must NOT be listed
git commit -m "Milestone 4: Cloud SQL (private IP) + Cloud Storage + Secret Manager + Alembic migration"
git push
```

## 2. Create the managed services (laptop, ~20 min — mostly waiting on Cloud SQL)

Run in order. Every script is safe to re-run (it skips what already exists).

```bash
./deploy/m4/01_network.sh          # APIs + private range 10.60.0.0/20 + VPC peering   (~2 min)
./deploy/m4/02_secrets.sh          # passwords generated straight into Secret Manager  (seconds)
./deploy/m4/03_cloudsql.sh         # Cloud SQL, --no-assign-ip, ENCRYPTED_ONLY          (5-15 min)
./deploy/m4/04_bucket.sh           # private bucket                                    (seconds)
./deploy/m4/05_service_account.sh  # gridpulse-vm-sa + least-privilege roles            (seconds)
./deploy/m4/06_switch_vm_identity.sh  # stop VM, attach SA + cloud-platform scope, start  (~2 min downtime)
```

The least-privilege grants made by `05_service_account.sh`:

| Role | Granted on | Why |
|---|---|---|
| `roles/cloudsql.client` | project | look up the instance's private IP |
| `roles/secretmanager.secretAccessor` | secret `gridpulse-db-password` **only** | read the app's DB password |
| `roles/storage.objectCreator` | bucket **only** | upload PDFs (cannot overwrite/delete) |
| `roles/storage.objectViewer` | bucket **only** | read PDFs back, list |
| `roles/artifactregistry.reader` | repo `gridpulse` **only** | `docker pull` |

It is *not* granted the root-password secret, bucket admin, or anything project-wide beyond Cloud SQL Client.
(The default compute service account it replaces has **Editor** on the whole project.)

## 3. Move the data (VM, ~5 min)

SSH in (Console → Compute Engine → `gridpulse-vm` → **SSH**), then:

```bash
cd ~/gridpulse
git pull
./deploy/m4/vm_migrate.sh
```

It prints and saves (in `docs/milestone4/evidence/`):

1. identity check — VM runs as `gridpulse-vm-sa` via the metadata server
2. deletes leftover `.env` files (the M2/M3 local passwords)
3. pulls `v2`
4. connects to Cloud SQL on its **private IP**, password from Secret Manager (never printed)
5–6. row counts + checksums of the **old** container DB
7. full backup of the old DB → `gs://…/backups/m3-final-<time>.sql.gz`
8. `alembic upgrade head` → `Running upgrade  -> 0001_initial_schema`
9. `pg_dump --data-only` (old) **|** `psql --single-transaction` (Cloud SQL)
10. **side-by-side row counts** → `row_counts_side_by_side.txt` (must say `ALL 7 TABLES MATCH`)
11. old PDFs → `gs://…/documents/m3/`, their rows re-pointed to the `gs://` URIs
12. `docker compose up -d --remove-orphans` → old DB container gone, stateless stack up
13. smoke test + `GET /api/system/info`

Then prove the app works end to end and that nothing is left on the VM:

```bash
./deploy/m4/vm_verify.sh                         # no .env, no secrets, no keys, read-only FS
# upload a PDF in the browser (Documents page), then:
gcloud storage ls -l gs://gridpulse-509202-uploads/documents/**
```

Optional but convincing — remove the old volumes and show the app still works:
```bash
docker volume rm gridpulse_pgdata gridpulse_uploads
curl -s localhost/api/regions | head -c 300
```

Commit the evidence from the VM (or copy it to the laptop) so it is in the repo:
```bash
git add docs/milestone4/evidence && git commit -m "Milestone 4: migration evidence" && git push
```
(If the VM can't push, run `cat docs/milestone4/evidence/row_counts_side_by_side.txt` and paste it into the repo from the laptop.)

## 4. Evidence for the rubric

Run on the laptop: `./deploy/m4/07_evidence.sh` (prints everything below in one screen per section).

| # | Screenshot | Where | Rubric (pts) |
|---|---|---|---|
| 1 | Cloud SQL **Connections → Networking**: *Private IP* ✔ `10.60.x.x`, *Public IP* ☐ (not enabled) — plus the Overview page showing only a private address | Console → SQL → `gridpulse-db` | private IP only, no public IP (11) |
| 2 | `backend/migrations/versions/0001_initial_schema.py` on GitHub, and the VM terminal showing `Running upgrade  -> 0001_initial_schema` | GitHub · `vm_migrate.sh` step 8 | migration file (10) |
| 3 | `cat docs/milestone4/evidence/row_counts_side_by_side.txt` | VM terminal | row counts match (10) |
| 4 | Bucket object list after an upload through the app + `gridpulse-vm-sa` holding Storage Object Creator/Viewer on the bucket (bucket → **Permissions**) | Console → Cloud Storage | uploads via SA, no keys (10) |
| 5 | **IAM role bindings** of `gridpulse-vm-sa`: Console → IAM & Admin → IAM (filter `gridpulse-vm-sa`) **and** `./deploy/m4/07_evidence.sh iam` (shows the resource-level grants the IAM page doesn't) | Console + laptop terminal | identity (10 + 8) |
| 6 | **Secret Manager** list: `gridpulse-db-password`, `gridpulse-db-root-password` (values hidden) | Console → Security → Secret Manager | secrets (8) |
| 7 | `./deploy/m4/vm_verify.sh` ending in `RESULT: all checks passed` | VM terminal | no .env / secrets / keys (8) |

## 5. Video (10 min, every presenter's face on camera)

Full script with presenters and lines: [demo_script.md](demo_script.md) · slides: `gridpulse_milestone4.pptx`.

| Time | Show | Say |
|---|---|---|
| 0:00–1:00 | Slide 1 (before/after) | where state lived in M3 vs now; "deleting the VM costs only downtime" |
| 1:00–2:30 | Browser at http://35.184.90.182: dashboard, Regional forecast → Recompute, Alerts | app works end to end against Cloud SQL |
| 2:30–3:30 | VM: `curl -s localhost/api/system/info \| python3 -m json.tool` | `server_address` = Cloud SQL private IP, `tls: true`, migration `0001_initial_schema`, bucket, identity |
| 3:30–4:30 | Console → SQL → `gridpulse-db` → Connections | Private IP on, Public IP off; `ENCRYPTED_ONLY` |
| 4:30–5:30 | Migration file on GitHub + `row_counts_side_by_side.txt` | real CREATE TABLEs; 7/7 tables match, counts and checksums |
| 5:30–6:45 | Documents page → upload a PDF → Console → bucket → `documents/region-N/…` appears; open it via `/api/documents/{id}/file` | file went to the bucket, not the VM |
| 6:45–8:00 | VM: `./deploy/m4/vm_verify.sh` (or the individual commands below) | **no .env in the running container**, no password in env/image, no key files, read-only FS |
| 8:00–9:00 | Console → Secret Manager (names, values hidden) → IAM (gridpulse-vm-sa) | secrets in Secret Manager; least-privilege roles; 0 keys |
| 9:00–10:00 | Slide 2 + what would break if the VM were deleted | honest answer from the written analysis |

Individual commands for the "no .env inside the running container" segment:
```bash
ls -la ~/gridpulse/.env                                         # No such file or directory
docker compose exec backend sh -c 'find / -xdev -name ".env*" 2>/dev/null | wc -l'   # 0
docker compose exec backend env | grep -E '^(DB_|GCS_|CLOUDSQL)' # names only, no password
docker compose exec backend python -m app.gcp whoami            # gridpulse-vm-sa via metadata server
docker compose exec backend touch /app/x                        # Read-only file system
```

Upload the video to OneDrive, share with sdesini@cougarnet.uh.edu, krajan@cougarnet.uh.edu,
skolanu@cougarnet.uh.edu, and submit **the OneDrive link** in Canvas (not the file).

---

## Cost & budget

| Item | Approx. cost |
|---|---|
| Cloud SQL `db-f1-micro` + 10 GB SSD + 7 daily backups | ~US$10 / month (billed while the instance runs, even if the VM is stopped) |
| Cloud Storage (a few MB) | < US$0.01 / month |
| Secret Manager (2 secrets, few accesses) | free tier |
| Static IP, VM | as in Milestone 3 |

Pause the database between work sessions (storage is still billed, data is kept):
```bash
gcloud sql instances patch gridpulse-db --activation-policy=NEVER    # stop
gcloud sql instances patch gridpulse-db --activation-policy=ALWAYS   # start (~1 min)
```
Check spend: Billing → Budgets & alerts (the $50 budget with 10/20/25/50/100 % alerts from M3).

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `03_cloudsql.sh`: *Failed to create … the network … does not have a private services access connection* | step 1 not finished | re-run `01_network.sh`, wait 1 min, re-run `03` |
| `03_cloudsql.sh`: *Invalid Tier (db-f1-micro) for (ENTERPRISE_PLUS) Edition* | edition default | the script passes `--edition=enterprise`; make sure you run the repo version |
| `vm_migrate.sh`: *VM runs as …-compute@developer…* | identity not switched | `./deploy/m4/06_switch_vm_identity.sh` on the laptop |
| `PermissionDenied … secretmanager.versions.access` | missing binding / old scope | re-run `05_service_account.sh`; VM scope must be `cloud-platform` (`06`) |
| `Cloud SQL lookup … HTTP 403` | no `roles/cloudsql.client` | re-run `05_service_account.sh` (bindings can take ~1 min) |
| backend `unhealthy`, logs: `connection timed out` to `10.60.x.x` | peering missing or wrong network | `gcloud services vpc-peerings list --network=default`; instance must be on the VM's VPC |
| backend logs: `SSL off` / `no encryption` | client not using TLS | `DB_SSLMODE: require` must be in `docker-compose.yml` |
| upload returns **502** *Could not store the file … 403* | bucket roles missing | re-run `05_service_account.sh` |
| `password authentication failed for user "gridpulse"` | secret and DB user out of sync | re-run `03_cloudsql.sh` (re-syncs the user's password from the secret) |
| `row counts differ` | data changed during copy / partial earlier run | `FORCE_RELOAD=1 ./deploy/m4/vm_migrate.sh` (wipes Cloud SQL tables, copies again) |
| `docker compose exec backend touch` succeeds | old compose file | `git pull`; `docker compose up -d` (backend must be `read_only: true`) |
| need to undo | — | M3 stack: `git checkout <m3 commit> -- docker-compose.yml` + restore `.env.m3.bak`; old volumes are untouched until you delete them |

`docker compose logs -f backend` is always the first thing to check. At start-up it logs the database
(with the password masked as `***`), the storage location, and the Google identity in use.
