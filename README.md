# GridPulse — Smart Grid Load Forecasting & Peak-Risk Alerting

**Status: All 3 stages complete. Runs entirely without Docker** — Postgres,
Python, and Node all installed and run natively. (A `Dockerfile` and
`docker-compose.yml` are included for a *later* course milestone that
explicitly asks for containerization — they are not used or needed here.)

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
16 pytest tests (`backend/tests/`) — health, regions, forecast (incl.
naive-fallback), risk-engine thresholds, PDF upload/extraction, job
creation/filtering.

### Docs
- `docs/gridpulse_milestone1.pptx` — the 2-slide deck.
- `docs/demo_script.md` — 10-minute video script.

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
cp ../.env.example .env         # already points at the role/db created above
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

**Containerization** (Dockerfile / docker-compose.yml, included in this
repo) belongs to a later milestone in the course roadmap
("Containerize & Deploy") — not part of the working-local-app requirement
this README covers.

## 6. Team
- Harshitha Tumati — Database & data modeling
- Arun Reddy Karnati — Forecasting model & business logic
- BalaVardhan Reddy Konda — API & asynchronous processing
- Tanmaya Sai Dudipalli — Frontend dashboard
- Dhanush Goud Rekhala — Integration, deployment, monitoring & load testing
