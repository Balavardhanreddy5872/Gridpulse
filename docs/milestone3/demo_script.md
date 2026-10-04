# GridPulse — Milestone 3 Demo Script (10 minutes)

**Cameras on** for every presenter's segment (webcam overlay on the screen recording).
Presenter names below are a suggested split by role — swap freely.

## Before you hit record

- [ ] Laptop: images built and `v1` pushed (`./deploy/build_and_push.sh v1`) — **don't rebuild after this**
- [ ] Laptop: `docker compose up -d` once so the first-boot seed is done, then `docker compose down` (keeps data)
- [ ] VM: deployed once with `./deploy/vm_deploy.sh` to confirm it works, then reset so the pull is visible on camera:
      `docker compose down && docker image rm $(docker image ls -q 'us-central1-docker.pkg.dev/*/*/gridpulse-*')`
- [ ] Budget already edited to include 10 % and 25 % thresholds
- [ ] Browser tabs open: localhost · Artifact Registry repo · Budgets page · `http://23.251.144.238` (not loaded yet)
- [ ] A small PDF ready for the Documents upload

---

## 0:00 – 0:40 · Intro — *Balavardhan*

> "Milestone 2 was a manual lift-and-shift: we hand-installed Postgres, Python and Node on the VM
> and started three processes by hand. Milestone 3 packages GridPulse into versioned images,
> so the exact artifact that runs on my laptop is the one that runs on the VM."

## 0:40 – 3:00 · Runs fully in containers locally — *Dhanush*  *(rubric 10)*

Show:
1. `docker-compose.yml` for ~15 s: three services, `web-net`/`data-net`, `pgdata`/`uploads` volumes,
   **db has no published port**.
2. Terminal: `docker compose up -d` → `docker compose ps` → all three **(healthy)**.
3. Browser `http://localhost`: Dashboard (10 regions) → Regional forecast → **Recompute** →
   Documents → upload PDF → Alerts → Async jobs → **Simulate spike**.
4. `http://localhost:8000/docs` for 5 s.

> "Everything you see — database, API, ML model, dashboard — is running in containers. Nothing is installed on this Mac except Docker."

## 3:00 – 4:00 · Dockerfile, .dockerignore, no secrets — *Balavardhan*  *(rubric 8)*

Show:
1. `backend/Dockerfile`: two stages, `xgboost-cpu` swap, non-root `USER app`, no secrets in `ENV`.
2. `.dockerignore`: `.env`, `.git`, `node_modules`, `venv`, `uploads`, docs.
3. Output of `./deploy/verify_no_secrets.sh` (pre-run, scroll it) → **RESULT: no secrets baked into either image.**

> "The DB password lives only in a gitignored .env and is injected by compose at run time. The script scans every layer of both images for the real password and finds zero matches."

## 4:00 – 5:00 · Artifact Registry: v1 tag + digest — *Arun*  *(rubric 7)*

Show:
1. Console → Artifact Registry → `gridpulse` → `gridpulse-backend`: tags **v1, latest**, the `sha256:` digest, size.
   Same for `gridpulse-frontend`.
2. Laptop terminal:
   `docker image inspect --format '{{index .RepoDigests 0}}' us-central1-docker.pkg.dev/gridpulse-509202/gridpulse/gridpulse-backend:v1`
   → read out the first 8 characters of the digest.

## 5:00 – 7:45 · Same image on the VM, same URL as M2 — *Dhanush*  *(rubric 10)*

Show (SSH window):
1. `docker image ls` → no gridpulse images yet.
2. `./deploy/vm_deploy.sh` → layers downloading from `us-central1-docker.pkg.dev`, services **healthy**.
   Point out `--no-build`: nothing is compiled on the VM.
3. The digest it prints → **same first 8 characters as the laptop.**
4. Browser `http://23.251.144.238` → Dashboard → recompute a forecast. Then `:8000/docs`.
5. `docker compose logs --tail=20 backend`.

> "Same digest, byte-for-byte the same artifact, at the same URL we used in Milestone 2."

## 7:45 – 8:45 · Budget guardrails — *Harshitha*  *(rubric 5)*

Show the budget: **scope = project gridpulse-509202**, $50/month, thresholds **10 %, 20 %, 25 %, 50 %, 100 %**,
email alerts on, and **current spend** this month. Mention the Artifact Registry cleanup policy and
that the registry + VM are in the same region (no egress charges for pulls).

## 8:45 – 9:45 · What's easier than Milestone 2 — *Tanmaya*  *(required)*

| Milestone 2 (manual) | Milestone 3 (containers) |
|---|---|
| Install Postgres, create role + DB by hand | `postgres:16-alpine` container, created from `.env` |
| Python venv + `pip install` (xgboost, pandas…) on the VM | baked into the image once, on the laptop |
| Rebuild the React app with the VM's IP in `VITE_API_BASE_URL` | relative `/api` URLs + nginx proxy — one image for every host |
| Seed DB + train model on the VM | DB seeds itself on first boot; model ships in the image |
| Start 3 processes by hand, hope they stay up | `restart: unless-stopped` + health checks |
| ~15 manual commands across 3 terminals | `git pull` + `./deploy/vm_deploy.sh` |

> "The biggest win for us: the frontend no longer has a machine-specific API URL baked in, so the exact same image works on localhost and on the VM."

## 9:45 – 10:00 · Close — *Balavardhan*

> "Next milestone, these same versioned images are what we'll hand to a managed service instead of a VM."
