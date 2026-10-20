# GridPulse — Smart Grid Load Forecasting & Peak-Risk Alerting

**Milestone 5 (current): Kubernetes runs the containers.** GridPulse runs on a
GKE Autopilot cluster as self-healing, autoscaled replicas behind a Google
load balancer with a Google-managed certificate.

```
https://<domain>  ->  external Application Load Balancer (static IP, managed cert, http->https 301)
                  ->  Ingress gridpulse:  /api/*  -> Service backend:8000 -> backend pods  (HPA 2-4, PDB)
                                          /*      -> Service frontend:80  -> nginx pods    (HPA 2-4, PDB)
backend pods  ->  Cloud SQL (private IP, TLS)  ·  Cloud Storage bucket  ·  Secret Manager
                  as gridpulse-gke-app via Workload Identity (no key files)
```

| What | Where |
|---|---|
| Manifests (Deployment, Service, Ingress, HPA, PodDisruptionBudget, …) | [`k8s/`](k8s/) — `kubectl apply -k k8s/` |
| Liveness probe (process only, no DB) | `GET /api/health/live` |
| Readiness probe (also `SELECT 1` on Cloud SQL, 2 s limit) | `GET /api/health/ready` |
| Cluster, identity, IP/DNS, deploy, HTTPS scripts | [`deploy/m5/`](deploy/m5/) `01_…` → `06_…` |
| Autoscaling load test | [`k8s/loadtest/load-generator.yaml`](k8s/loadtest/load-generator.yaml) |
| Multi-replica safety | jobs are claimed with one atomic `UPDATE … WHERE status='queued'`; DB pools sized so 4 pods stay under Cloud SQL's connection limit; 4 request threads per pod so a busy pod still answers its probes |

**Milestone 4: the VM holds no state.**

| State | Milestone 3 (on the VM) | Milestone 4 (managed service) |
|---|---|---|
| Database | `postgres:16` container + `pgdata` volume | **Cloud SQL for PostgreSQL 16**, private IP only |
| Uploaded PDFs | `uploads` Docker volume | **Cloud Storage** bucket `gridpulse-509202-uploads` |
| DB password | `.env` file on the VM | **Secret Manager** `gridpulse-db-password` |
| Schema | `create_all()` at app start | **Alembic migration** `backend/migrations/versions/0001_initial_schema.py` |
| Identity | default compute SA (Editor) | **`gridpulse-vm-sa`**, least privilege, no key files |

## 0. Run it

**On the VM** (cloud, no `.env`):
```bash
docker compose pull && docker compose up -d --no-build
```

**On a laptop** (local stand-ins: Postgres container + local folder):
```bash
cp .env.example .env        # local-only throwaway password
docker compose -f docker-compose.local.yml up --build
```
- Dashboard: **http://localhost** · API docs: **http://localhost:8000/docs**
- Tables are created by `alembic upgrade head` on container start; the demo
  data is seeded only in local mode. The trained model is baked into the image.

## 1. What's included

### Database + API
- **PostgreSQL schema** for all 7 entities: `regions`, `hourly_readings`,
  `weather_observations`, `forecast_results`, `peak_alerts`,
  `infrastructure_documents`, `async_jobs` (see `database/init.sql` and
  `backend/app/models/`).
- **FastAPI backend**, every endpoint from the spec, backed by real DB
  queries — see `/docs` once running for the full interactive list.
- **PDF infrastructure-report ingestion** (`pdfplumber`): extracts raw
  text, best-effort auto-fills capacity impact (MW) + maintenance date
  window via regex, falls back to manual entry when unsure.
- **Peak-risk engine**: effective capacity = region capacity minus any
  currently-active infrastructure impact; risk level (`normal` / `watch`
  / `high` / `critical`) from configurable `.env` thresholds.
- **Synthetic seed dataset**: 10 regions, 30 days of hourly load +
  weather each, modeled on the *structure* of PJM data (clearly labeled
  as synthetic).

### Frontend
Five-page control-room-style dashboard (Vite + React + Recharts):
**Dashboard**, **Regional forecast**, **Alerts**, **Infrastructure
documents**, **Async jobs**.

### ML forecasting (real, trained)
`ml/train_model.py` trains an **XGBoost regressor** on the seeded data —
calendar features, lag features, rolling mean, weather. Typical result:
MAE ~20-26 MW, RMSE ~35-55 MW, MAPE ~3-4% (varies slightly with the
random synthetic data each time it's reseeded).

### Async worker (real, not a stub)
`app/workers/spike_worker.py` — an asyncio background task started when
the backend starts, polling `async_jobs` and processing several
concurrently so the API stays responsive during a simulated spike.

### Tests
38 pytest tests (`backend/tests/`) — health, regions, forecast (incl.
naive-fallback), risk-engine thresholds, PDF upload/extraction, job
creation/filtering, plus Milestone 4: uploads go to the bucket (never local disk),
DB URL built from Secret Manager + private IP, migration covers every ORM
column, stale-job recovery; and Milestone 5: a DB outage fails readiness but
not liveness, readiness answers within its time limit, a job is claimed by
only one replica, each pod caps its request threads, Google API calls retry while the GKE metadata server starts.

### Docs
- `docs/gridpulse_milestone1.pptx` — the 2-slide deck.

## 2. What you need installed (one-time, native — no Docker)

1. **PostgreSQL** — via Homebrew on Mac (`brew install postgresql@16`)
   or your OS's package manager.
2. **Python 3.11+**
3. **Node.js 18+**

## 3. Running it locally

### Step 1 — Set up PostgreSQL (one-time)

macOS (Homebrew):
```bash
brew install postgresql@16
brew link postgresql@16 --force
brew services start postgresql@16
```
Create the app's database role and database (also one-time):
```bash
psql postgres -c "CREATE ROLE gridpulse WITH LOGIN PASSWORD 'gridpulse' SUPERUSER;"
psql postgres -c "CREATE DATABASE gridpulse OWNER gridpulse;"
```

### Step 2 — Backend
```bash
cd backend
python3 -m venv venv
source venv/bin/activate        # Windows: venv\Scripts\activate
pip install -r requirements.txt
set -a; source ../.env.example; set +a   # the app reads env vars only, never a .env file
alembic upgrade head                      # creates the tables (Milestone 4)
uvicorn app.main:app --reload
```
Leave this running. Check **http://localhost:8000/docs** for the interactive API.

### Step 3 — Seed data & train the model
In a **second terminal**, from the repo root (no venv activation needed —
call the venv's python directly):
```bash
backend/venv/bin/python scripts/seed_database.py
backend/venv/bin/python ml/train_model.py
```

### Step 4 — Frontend
In a **third terminal**:
```bash
cd frontend
npm install
cp .env.example .env
npm run dev
```
Open **http://localhost:5173**.

### Demo flow
1. **Dashboard** — regions populate, all "normal" risk initially.
2. **Regional forecast** → pick a region → **Recompute forecast**.
3. **Documents** → upload a PDF with a maintenance window covering today.
4. **Regional forecast** → **Recompute forecast** again → capacity drops,
   check **Alerts**.
5. **Async jobs** → **Simulate multi-region spike** → watch jobs process
   while the app stays responsive.

### Running the tests
```bash
cd backend
source venv/bin/activate
pip install pytest reportlab
pytest tests/ -v
```
(Tests use a throwaway SQLite file automatically — no Postgres needed for
tests specifically.)

## 4. Design notes / known simplifications
- Effective capacity is computed once per forecast run (at "now").
- PDF extraction is intentionally simple regex, not NLP.
- Forecast recompute is destructive per-region — only the latest run is kept.
- ML forecasting has no live future-weather feed; uses a seasonal
  historical average for future weather features instead.
- The async worker is a single in-process asyncio loop — no external
  queue service — matching what a "local app, no cloud services" milestone
  expects.
- All datetimes stored timezone-aware (UTC).

## 5. Cloud migration mapping (for later milestones)

| Local (this milestone) | Cloud target |
|---|---|
| React (Vite) | AWS Amplify / S3 + CloudFront |
| FastAPI | ECS/Fargate or Lambda + API Gateway |
| PostgreSQL (native) | Amazon RDS for PostgreSQL |
| `uploads/` local folder | Amazon S3 |
| `async_jobs` table + asyncio worker | Amazon SQS + Lambda/ECS worker |
| — | Amazon CloudWatch for monitoring |

**Containerization** (Dockerfile / docker-compose.yml) is done in Milestone 3. **Managed state** (Cloud SQL, Cloud Storage,
Secret Manager) is Milestone 4. **Orchestration** (GKE Autopilot, Ingress + managed HTTPS, HPA, PDB) is Milestone 5.
