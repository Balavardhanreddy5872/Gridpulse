# GridPulse dashboard image: React/Vite static build served by nginx, which
# also reverse-proxies /api/* to the backend container.
#
# Build context is the REPOSITORY ROOT (one shared .dockerignore):
#     docker build --platform linux/amd64 -f frontend/Dockerfile .

############################################################
# Stage 1 - build the static bundle
# Runs on the build machine's NATIVE architecture ($BUILDPLATFORM, e.g. arm64
# on an M-series Mac): the output is plain HTML/JS/CSS, which is the same on
# every CPU, so there is no reason to emulate x86 just to run Vite.
############################################################
FROM --platform=$BUILDPLATFORM node:22-alpine AS build
WORKDIR /src

# Dependencies first, so this layer is cached until package*.json changes.
COPY frontend/package.json frontend/package-lock.json ./
RUN npm ci --no-audit --no-fund

COPY frontend/ ./

# Empty API base URL => the bundle calls relative paths like /api/regions.
# nginx (stage 2) forwards those to the backend, so the SAME image works at
# http://localhost and at the VM's public IP with no rebuild.
ENV VITE_API_BASE_URL=""
RUN npm run build

############################################################
# Stage 2 - serve: nginx + the built files only (no Node, no node_modules)
############################################################
FROM nginx:1.27-alpine

COPY frontend/nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=build /src/dist /usr/share/nginx/html

EXPOSE 80

HEALTHCHECK --interval=10s --timeout=3s --start-period=10s --retries=3 \
  CMD wget -q -O /dev/null http://127.0.0.1/healthz || exit 1
