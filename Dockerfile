# ============================================================
# AID Orchestrator — Multi-stage Docker build
# Builds both GUI frontend and API server into a single image.
# ============================================================

# --- Stage 1: Build GUI frontend ---
FROM node:20-alpine AS gui-build
WORKDIR /build/gui
COPY packages/aid-gui/package.json packages/aid-gui/package-lock.json* ./
RUN npm install
COPY packages/aid-gui/ ./
RUN npm run build

# --- Stage 2: Build API server ---
FROM node:20-alpine AS server-build
WORKDIR /build/server
COPY packages/aid-server/package.json packages/aid-server/package-lock.json* ./
RUN npm install
COPY packages/aid-server/ ./
RUN npx tsc

# --- Stage 3: Production image ---
FROM node:20-alpine AS production
WORKDIR /app

# Install production deps for server
COPY packages/aid-server/package.json packages/aid-server/package-lock.json* ./
RUN npm install --omit=dev

# Copy compiled server
COPY --from=server-build /build/server/dist ./dist

# Copy built GUI into the expected path
# (server serves static files from ../aid-gui/dist relative to itself)
COPY --from=gui-build /build/gui/dist ./gui-dist

# Create a symlink so the server finds the GUI where it expects
RUN mkdir -p /app/packages/aid-gui && ln -s /app/gui-dist /app/packages/aid-gui/dist

# Default environment
ENV NODE_ENV=production
ENV AID_PORT=3910
ENV AID_HOST=0.0.0.0
ENV AID_PROJECT_ROOT=/project
ENV AID_CORS_ORIGINS=*

EXPOSE 3910

# Health check
HEALTHCHECK --interval=30s --timeout=5s --start-period=5s --retries=3 \
  CMD wget -q -O /dev/null http://localhost:3910/api/health || exit 1

CMD ["node", "dist/index.js"]
