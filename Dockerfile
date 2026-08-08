# ============================================================
# AID Orchestrator — Multi-stage Docker build
# Builds contract, GUI frontend and API server from the npm
# workspace root into a single image.
# ============================================================

# --- Stage 1: Build the whole workspace ---
FROM node:20-alpine AS build
WORKDIR /build

# Manifests first so the dependency layer caches independently of source
COPY package.json package-lock.json* ./
COPY packages/aid-contract/package.json packages/aid-contract/
COPY packages/aid-server/package.json packages/aid-server/
COPY packages/aid-gui/package.json packages/aid-gui/
RUN npm install

COPY tsconfig.base.json ./
COPY packages/ ./packages/
RUN npm run build

# --- Stage 2: Production image ---
FROM node:20-alpine AS production
WORKDIR /app

# Production deps only, resolved through the workspace so @aid/contract links locally
COPY package.json package-lock.json* ./
COPY packages/aid-contract/package.json packages/aid-contract/
COPY packages/aid-server/package.json packages/aid-server/
COPY packages/aid-gui/package.json packages/aid-gui/
RUN npm install --omit=dev

# Compiled output — the server resolves the GUI at ../../aid-gui/dist
COPY --from=build /build/packages/aid-contract/dist packages/aid-contract/dist
COPY --from=build /build/packages/aid-server/dist packages/aid-server/dist
COPY --from=build /build/packages/aid-gui/dist packages/aid-gui/dist

# Default environment
ENV NODE_ENV=production
ENV AID_PORT=3911
ENV AID_HOST=0.0.0.0
ENV AID_PROJECT_ROOT=/project
ENV AID_CORS_ORIGINS=*

EXPOSE 3911

# Health check
HEALTHCHECK --interval=30s --timeout=5s --start-period=5s --retries=3 \
  CMD wget -q -O /dev/null http://localhost:3911/api/health || exit 1

CMD ["node", "packages/aid-server/dist/index.js"]
