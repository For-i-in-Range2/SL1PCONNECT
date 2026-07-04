# Corrections :
#   - Node 20 LTS (14 = EOL depuis avril 2023)
#   - Multi-stage build : image finale sans npm
#   - Utilisateur non-root uid 1001

# ── Stage 1 : installation des dependances ────────────────────────
FROM node:20-alpine AS builder
WORKDIR /build
COPY package.json package-lock.json* ./
RUN npm ci --omit=dev

# ── Stage 2 : image de production ────────────────────────────────
FROM node:20-alpine AS runtime

RUN addgroup -g 1001 appgroup \
 && adduser -u 1001 -G appgroup -s /bin/false -D appuser

WORKDIR /app

COPY --from=builder /build/node_modules ./node_modules
COPY --chown=appuser:appgroup . .

USER appuser

ENV NODE_ENV=production PORT=8082

EXPOSE 8082

HEALTHCHECK --interval=30s --timeout=10s --start-period=15s --retries=3 \
    CMD wget -qO- http://127.0.0.1:8082/health || exit 1

CMD ["node", "index.js"]
