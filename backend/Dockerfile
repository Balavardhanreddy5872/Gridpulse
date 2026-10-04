# GridPulse API image: FastAPI + trained XGBoost model + seed script.
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

# Only NON-secret defaults live in the image. DATABASE_URL (which contains
# the DB password) is injected at run time by docker-compose from .env.
ENV PATH="/opt/venv/bin:$PATH" \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    MODEL_PATH=/app/ml/model.joblib \
    UPLOAD_DIRECTORY=/app/uploads

COPY --from=builder /opt/venv /opt/venv

WORKDIR /app/backend
COPY backend/app                ./app
COPY scripts/seed_database.py   /app/scripts/seed_database.py
COPY ml/model.joblib ml/metrics.json ml/train_model.py /app/ml/

# Code stays root-owned (read-only to the app user); only uploads is writable.
RUN mkdir -p /app/uploads && chown app:app /app/uploads

USER app
EXPOSE 8000

HEALTHCHECK --interval=10s --timeout=5s --start-period=90s --retries=6 \
  CMD python -c "import sys,urllib.request; sys.exit(0 if urllib.request.urlopen('http://127.0.0.1:8000/api/health', timeout=4).status == 200 else 1)"

# On start: seed the synthetic demo data (the script is a no-op if regions
# already exist), then hand PID 1 to uvicorn. No --reload: that is a
# dev-only flag that watches files and wastes CPU in a container.
CMD ["sh", "-c", "python /app/scripts/seed_database.py && exec uvicorn app.main:app --host 0.0.0.0 --port 8000"]
