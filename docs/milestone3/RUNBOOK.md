# GridPulse — Milestone 3 Runbook (Containerize & Ship)

**Goal:** the same two images — `gridpulse-backend:v1` and `gridpulse-frontend:v1` —
run on a laptop with Docker Compose and on `gridpulse-vm`, with **identical digests**.

| | |
|---|---|
| GCP project | `gridpulse-509202` |
| Registry | `us-central1-docker.pkg.dev/gridpulse-509202/gridpulse` |
| VM | `gridpulse-vm` · `us-central1-a` · e2-medium · http://35.184.90.182 |

---

## Architecture

```
Browser ──:80──► frontend (nginx + React build) ──/api/*──► backend (FastAPI + XGBoost) ──► db (Postgres 16)
                 web-net                                   web-net + data-net               data-net only
         ──:8000/docs──────────────────────────────────►   volume: uploads                  volume: pgdata
```

| Service | Image | Host port | Networks | Volume |
|---|---|---|---|---|
| `frontend` | `gridpulse-frontend:v1` — nginx serves the Vite build and proxies `/api/*` | 80 | web-net | — |
| `backend` | `gridpulse-backend:v1` — FastAPI, async worker, baked-in `model.joblib`, seeds DB on first start | 8000 | web-net, data-net | `uploads` → `/app/uploads` |
| `db` | `postgres:16-alpine` (official) | **none** (internal only) | data-net | `pgdata` → `/var/lib/postgresql/data` |

The frontend calls **relative** URLs (`/api/...`), so the same frontend image works at
`http://localhost` and at the VM IP with no rebuild. The frontend can't reach the DB at all
(different network).

### Files added / changed

| File | Purpose |
|---|---|
| `backend/Dockerfile` | multi-stage, `xgboost-cpu`, non-root user, health check, no `--reload` |
| `frontend/Dockerfile` | multi-stage: Node build → nginx (no Node in the final image) |
| `frontend/nginx.conf` | SPA routing + `/api` reverse proxy + 12 MB upload limit |
| `docker-compose.yml` | db + backend + frontend, 2 networks, 2 volumes, registry image names, `platform: linux/amd64` |
| `.dockerignore` | keeps secrets, `.git`, Mac `node_modules`/`venv`, uploads, docs out of every build |
| `.env.example` | compose variables (copy to `.env`; `.env` is never committed or baked) |
| `frontend/src/services/api.js` | `\|\|` → `??` so an empty API base URL means "same origin" |
| `deploy/*.sh` | build & push, VM setup, VM deploy, secret verification |

---

## 1. One-time laptop setup (M-series Mac)

1. **Docker Desktop for Mac (Apple silicon)** — https://www.docker.com/products/docker-desktop/
   (or `brew install --cask docker`). Open it and wait for *Engine running*.
   *Settings → General →* **Use Rosetta for x86_64/amd64 emulation on Apple Silicon** = ON.
   (Our images are `linux/amd64` to match the VM's CPU, so the Mac emulates them.)
2. **Google Cloud CLI** — `brew install --cask google-cloud-sdk`
   (or https://cloud.google.com/sdk/docs/install).
3. Log in with the Google account that owns the project:
   ```bash
   gcloud auth login
   gcloud config set project gridpulse-509202
   ```

## 2. Run locally with Docker Compose  *(rubric: 10 pts)*

```bash
cd ~/Downloads/gridpulse
cp .env.example .env
#   edit .env → POSTGRES_PASSWORD = something unique, letters+digits, 10+ chars
docker compose up --build
```

- First build takes ~5–10 min (pip runs under amd64 emulation). Re-builds take seconds (layer cache).
- Open **http://localhost** (dashboard, 10 regions) and **http://localhost:8000/docs** (API).
- In a second terminal: `docker compose ps` → all three services `(healthy)`.
- Demo flow: Regional forecast → *Recompute* · Documents → upload a PDF · Async jobs → *Simulate spike*.
- Stop: `Ctrl+C` or `docker compose down` (keeps data). `docker compose down -v` wipes the DB and uploads; the next start re-seeds automatically.

## 3. Push `v1` to Artifact Registry  *(7 pts)*

One time:
```bash
gcloud services enable artifactregistry.googleapis.com
gcloud artifacts repositories create gridpulse \
  --repository-format=docker --location=us-central1 \
  --description="GridPulse container images"
```

Build + push (tags `v1` **and** `latest`, prints digests and sizes):
```bash
./deploy/build_and_push.sh v1
```

**Screenshot:** Console → Artifact Registry → `gridpulse` → `gridpulse-backend` → row with
tags **v1, latest** and the `sha256:` digest (click it for the detail page). Repeat for `gridpulse-frontend`.

> Once you've pushed `v1`, don't rebuild/re-push `v1` before the VM demo — a rebuild makes a
> new digest. Code changes go out as `v2` (`./deploy/build_and_push.sh v2`, then `IMAGE_TAG=v2` on the VM).

## 4. Prove no secrets are baked in  *(part of 8 pts)*

```bash
./deploy/verify_no_secrets.sh
```
For each image it checks baked ENV vars, every history entry, `.env` files in the filesystem,
a byte scan of every layer for your real password, and (frontend) no hard-coded `localhost:8000`.
It should end with **`RESULT: no secrets baked into either image.`** Screenshot it.

## 5. Deploy on the VM  *(10 pts)*

**5.1 SSH in** — Console → Compute Engine → `gridpulse-vm` → **SSH**
(or `gcloud compute ssh gridpulse-vm --zone us-central1-a`).

**5.2 Stop Milestone 2's hand-started processes** (they hold ports 80/8000):
```bash
sudo ss -ltnp | grep -E ':(80|8000|5432)\s'           # what's listening now
pkill -f "uvicorn app.main:app" || true               # M2 backend
pkill -f vite || true                                 # if M2 served the UI with vite
sudo systemctl disable --now nginx 2>/dev/null || true       # if M2 served it with nginx
sudo systemctl disable --now postgresql 2>/dev/null || true  # native DB no longer needed
```
(If you ran things in tmux/screen or as systemd units in M2, stop those instead.)

**5.3 Get the compose file** — only config is needed on the VM, not a Python/Node install.
Milestone 2 served the app on port 80 (`http://35.184.90.182`), so keep `FRONTEND_PORT=80` in `.env`.
```bash
cd ~/<the repo folder you cloned in M2> && git pull
#   or: git clone https://github.com/Balavardhanreddy5872/Gridpulse.git && cd Gridpulse
cp .env.example .env && nano .env      # set POSTGRES_PASSWORD; keep IMAGE_TAG=v1
```

**5.4 Install Docker (once):**
```bash
bash deploy/vm_setup.sh
exit        # then SSH back in so the docker group applies
```

**5.5 Pull and run** (saves the terminal output the rubric asks for):
```bash
cd ~/<repo folder>
./deploy/vm_deploy.sh 2>&1 | tee ~/m3_vm_pull_and_run.log
```
Open **http://35.184.90.182** — same URL as Milestone 2.

**The "same artifact" proof** — run on the laptop *and* the VM; the `sha256:` must match:
```bash
docker image inspect --format '{{index .RepoDigests 0}}' \
  us-central1-docker.pkg.dev/gridpulse-509202/gridpulse/gridpulse-backend:v1
```

> The VM's IP is reserved as static (`gridpulse-ip`), so it survives stop/start:
> `gcloud compute addresses create gridpulse-ip --addresses=35.184.90.182 --region=us-central1`

## 6. Budget guardrails  *(5 pts)*

The milestone text says alerts at **20/50/100 %**, the rubric says **10/25/50 %**. Cover both on the existing $50 budget:

*Billing → Budgets & alerts → GridPulse budget → Edit → Actions* — keep 20 %, 50 %, 100 % and **add 10 % and 25 %** (Actual). Save.

Show in the video / screenshot: scope = project `gridpulse-509202` only · the threshold list · **current spend**
(the budget's *Spend* / cost-trend, or *Billing → Reports* filtered to the project, current month).

Cost-control actions (also for the write-up):
```bash
# Auto-delete untagged image versions after 7 days, always keep the 5 newest
gcloud artifacts repositories set-cleanup-policies gridpulse \
  --location=us-central1 --policy=deploy/ar-cleanup-policy.json --no-dry-run
```
- Registry and VM are both in `us-central1`, so image pulls cause no cross-region egress charges.
- Smaller images = less registry storage (first 0.5 GB/month is free) and faster pulls.
- Stop the VM between work sessions (after making the IP static — see 5.5).

## 7. Image-size numbers for the written analysis

```bash
docker image ls | grep gridpulse                      # uncompressed, on your laptop
gcloud artifacts docker images list \
  us-central1-docker.pkg.dev/gridpulse-509202/gridpulse --include-tags   # compressed, in the registry

# "Before": build the original Milestone 1 Dockerfile for comparison
git show bb06b70:backend/Dockerfile | \
  docker build --platform linux/amd64 -t gridpulse-backend:naive -f - backend
docker image ls | grep -E "gridpulse-backend\s+(naive|v1)"
docker image rm gridpulse-backend:naive               # clean up afterwards
```

## 8. Commit and push

```bash
git status                     # .env must NOT appear (it's gitignored)
git add .dockerignore .gitattributes .gitignore .env.example docker-compose.yml \
        backend/Dockerfile frontend/Dockerfile frontend/nginx.conf \
        frontend/src/services/api.js deploy docs/milestone3 README.md
git commit -m "Milestone 3: containerize GridPulse (Dockerfiles, compose, .dockerignore, Artifact Registry deploy)"
git push
```

---

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| VM: `exec format error` or `no matching manifest for linux/amd64` | image built for arm64 (Mac default) | keep `platform: linux/amd64` in compose; rebuild + push |
| VM: `denied: Permission "artifactregistry.repositories.downloadArtifacts"` | VM service account can't read the repo | from the laptop: `SA=$(gcloud compute instances describe gridpulse-vm --zone us-central1-a --format='value(serviceAccounts[0].email)')` then `gcloud artifacts repositories add-iam-policy-binding gridpulse --location=us-central1 --member=serviceAccount:$SA --role=roles/artifactregistry.reader` |
| Laptop push: `unauthorized` / `Unauthenticated request` | Docker isn't using your gcloud login | `gcloud auth login` then `gcloud auth configure-docker us-central1-docker.pkg.dev` |
| VM: `permission denied … /var/run/docker.sock` | docker group not active yet | log out + back in (or `newgrp docker`). Don't use `sudo docker` — root doesn't have the registry login |
| `bind: address already in use` on 80/8000 | M2 processes still running | step 5.2 |
| backend `unhealthy`; logs: `password authentication failed` | `POSTGRES_PASSWORD` changed after the `pgdata` volume was created (Postgres only reads it on first init) | `docker compose down -v` then up again (wipes demo data; it re-seeds) |
| Dashboard loads but shows "Failed to fetch" | an old frontend build with a hard-coded URL | `curl localhost/api/health` should work; rebuild the frontend from this repo |
| Mac: `Illegal instruction` or very slow backend | emulation setting | toggle the Rosetta option in Docker Desktop settings and restart Docker |
| VM: `no space left on device` | 10 GB disk + M2 installs | `docker system prune -a`; delete M2's `backend/venv` and `frontend/node_modules` |
| `docker compose logs -f backend` | — | first thing to check for any backend error |
