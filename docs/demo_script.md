# GridPulse — Milestone 1 Demo Script (target: 10 minutes)

Matches the milestone's required demo flow: working local app end-to-end,
core user flow, domain rationale. Cameras must be on for each presenting
member's segment — screen-record with a webcam overlay (or cut to camera
between segments), not audio-only narration.

**Before recording:** run `docker compose up --build`, then
`python scripts/seed_database.py`, then `python ml/train_model.py`
(from repo root) so the model is trained and metrics are real for the
recording. Start the frontend with `npm run dev` in `frontend/`.

---

## 0. Cold open (30s) — whoever leads the intro, camera on

> "We're Team 9 and this is GridPulse — a smart grid load forecasting
> and peak-risk alerting platform. Grid operators today lean on
> historical averages and manual monitoring to catch demand spikes;
> that's too slow to react to a heat wave before it strains the grid.
> GridPulse forecasts short-term demand per region, flags peak-risk
> periods before they happen, and gives an operator one dashboard to
> watch and respond from."

Cut to screen: **Dashboard** page loaded, regions populated.

---

## 1. Domain & why we picked it (45s)

> "We picked energy and utilities deliberately — it's a domain every one
> of us can speak to in an interview without an electrical engineering
> background, because the actual problem is a data problem: demand
> forecasting and capacity planning. It's also different from the
> healthcare/finance projects most teams default to."

Point out on screen: region count, "at risk" stat, open alerts stat.

---

## 2. Core user flow: a Grid Operations Analyst's day (3 min)

**Regional forecast page:**
1. Select **North Houston**.
2. Point at the chart: "This is last 96 hours of actual load in teal,
   next 24 hours forecast in amber, and the dashed line is effective
   capacity."
3. Click **Recompute forecast** — note the model version badge in the
   API response reads `xgboost-v1` (or check `/api/model/metrics` in a
   second tab) — "this isn't a hardcoded number, it's a real XGBoost
   model trained on the seeded dataset, MAE of about 24 MW on held-out
   data."

**Infrastructure documents:**
4. Go to **Documents**. Upload a sample infrastructure PDF for North
   Houston with a maintenance window covering today and a stated
   capacity reduction (e.g. "150 MW", "today → +3 days").
5. Show the extracted fields in the table — "the PDF's capacity impact
   and date window were pulled out automatically; if the extractor
   missed something we can fill it in by hand right in the upload form,
   nothing gets guessed silently."

**Back to forecast:**
6. Return to **Regional forecast**, hit **Recompute forecast** again.
7. "Effective capacity just dropped by the maintenance impact — watch
   the risk badge." Point out the change from normal to watch/high.
8. Go to **Alerts** — show the new peak alert row: region, risk level,
   predicted load vs. capacity, message.

> "That's the core story: unstructured PDF becomes structured data,
> structured data changes a live forecast, forecast crosses a
> configurable threshold, threshold produces an alert an operator can
> act on."

---

## 3. Async / traffic-spike demo (2 min) — the technical centerpiece

1. Go to **Async jobs**.
2. Click **Simulate multi-region spike**.
3. "This just queued 10 forecast-recompute jobs — one per region — the
   way a real heat wave would force every region to re-score at once."
4. **While jobs are still processing**, switch back to **Dashboard** or
   **Regional forecast** and interact with it — change the selected
   region, note it still responds immediately.

> "The dashboard didn't freeze. That's because a background worker is
> draining that job queue concurrently, off the API's request thread —
> in the cloud version this is the exact same job contract sitting
> behind Amazon SQS and a Lambda or ECS worker instead of our in-process
> asyncio loop."

5. Go back to **Async jobs** — show jobs now in `completed` status,
   counts updated.

---

## 4. Quick architecture recap (1 min)

Show the PPT's architecture slide, or narrate live:

> "React talks to FastAPI, FastAPI talks to PostgreSQL for everything
> relational — regions, readings, weather, forecasts, alerts, jobs —
> uses pdfplumber for the PDF ingestion, and hands off to an asyncio
> worker for the job queue. That's all three technical dimensions:
> relational data, unstructured file processing, and async/traffic
> spikes, each with a clear cloud target we'll migrate to in later
> milestones: RDS, S3, and SQS+Lambda respectively."

---

## 5. Wrap (30s)

> "Everything you just saw is running locally right now — Postgres,
> FastAPI, the trained model, and the async worker, no cloud services
> required yet. That's Milestone 1. Thanks."

---

## Fallback / troubleshooting notes for the presenter

- If a queued job is still `processing` when you cut to it, that's fine
  — it demonstrates the async behavior even better than instant
  completion. Don't wait for 100% completion before moving on.
- If `/api/model/metrics` shows `"trained": false`, the model wasn't
  trained before recording — run `python ml/train_model.py` from the
  repo root (after seeding) and restart the backend.
- If a region shows no obvious risk change after a document upload,
  make sure the PDF's maintenance window includes **today's date** —
  effective capacity is computed at "now", not the forecast hour.
