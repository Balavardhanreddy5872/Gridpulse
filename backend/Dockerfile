# GridPulse API image: FastAPI + trained XGBoost model + Alembic migrations.
#
# Build context is the REPOSITORY ROOT (so the image can include ml/ and
# scripts/, which live outside backend/):
#     docker build --platform linux/amd64 -f backend/Dockerfile .
# Normally you just run `docker compose build`, which does this for you.
#
# Inside the image the repo layout is mirrored under /app:
#     /app/backend/app/...   API code      (WORKDIR /app/backend)
#     /app/ml/...            model.joblib + metrics.json
#     /app/scripts/...       seed_database.py
# The backend finds ml/ by walking up from its own file, exactly as it
# does on a laptop, so no code changes or volume mounts are needed.

############################################################
# Stage 1 - builder: install Python dependencies into a venv
############################################################
FROM python:3.11-slim AS builder

ENV PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

RUN python -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"

COPY backend/requirements.txt /tmp/requirements.txt

# 1) Swap `xgboost` for `xgboost-cpu` (same version, same `import xgboost`).
#    The default Linux x86_64 xgboost wheel ships CUDA kernels and pulls in
#    nvidia-nccl-cu12 for multi-GPU training - hundreds of MB we never use.
# 2) Delete the test suites that pandas/numpy/scipy/scikit-learn bundle
#    inside their wheels; they are never imported at runtime.
RUN sed 's/^xgboost==/xgboost-cpu==/' /tmp/requirements.txt > /tmp/requirements.docker.txt \
 && pip install -r /tmp/requirements.docker.txt \
 && find /opt/venv -type d -name tests -prune -exec rm -rf {} +

############################################################
# Stage 2 - runtime: slim Python + the venv + our code only
############################################################
FROM python:3.11-slim AS runtime

# libgomp1 = OpenMP runtime that xgboost / scikit-learn load at import time.
RUN apt-get update \
 && apt-get install -y --no-install-recommends libgomp1 \
 && rm -rf /var/lib/apt/lists/* \
 && groupadd --system --gid 10001 app \
 && useradd --system --uid 10001 --gid app --no-create-home app

# Only NON-secret defaults live in the image. Milestone 4: the DB password is
# not even passed in as an environment variable - the app reads it from
# Secret Manager at start-up using the VM's service account (see app/gcp.py).
ENV PATH="/opt/venv/bin:$PATH" \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    MODEL_PATH=/app/ml/model.joblib \
    UPLOAD_DIRECTORY=/app/uploads

COPY --from=builder /opt/venv /opt/venv

WORKDIR /app/backend
COPY backend/app                ./app
COPY backend/alembic.ini        ./alembic.ini
COPY backend/migrations         ./migrations
COPY backend/start.sh           ./start.sh
COPY scripts/seed_database.py   /app/scripts/seed_database.py
COPY ml/model.joblib ml/metrics.json ml/train_model.py /app/ml/

# Files can arrive with owner-only permissions from the build machine (e.g. 600
# on a Mac); make the code readable by every user. It stays root-owned, so the
# app user can read it but never change it.
RUN chmod -R a+rX /app/backend /app/scripts /app/ml

# Code stays root-owned (read-only to the app user). /app/uploads is only used
# for local development; on the VM the container runs with a read-only root
# filesystem and uploads go to Cloud Storage.
RUN mkdir -p /app/uploads && chown app:app /app/uploads

USER app
EXPOSE 8000

HEALTHCHECK --interval=10s --timeout=5s --start-period=90s --retries=6 \
  CMD python -c "import sys,urllib.request; sys.exit(0 if urllib.request.urlopen('http://127.0.0.1:8000/api/health', timeout=4).status == 200 else 1)"

# On start (backend/start.sh): `alembic upgrade head`, optionally seed demo
# data (local dev only), then exec uvicorn as PID 1.
CMD ["sh", "/app/backend/start.sh"]
