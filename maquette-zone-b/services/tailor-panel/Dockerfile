# ─── Stage 1: builder ───────────────────────────────────────────────────────
FROM node:20-alpine AS builder

WORKDIR /build

# Copier uniquement package.json pour profiter du cache Docker
COPY package*.json ./
RUN npm ci --only=production

COPY . .
RUN npm run build 2>/dev/null || true   # build si présent (React/Vite)

# ─── Stage 2: runtime ────────────────────────────────────────────────────────
FROM node:20-alpine AS runtime

# Créer un utilisateur non-root
RUN addgroup --gid 1001 appgroup \
 && adduser --uid 1001 --ingroup appgroup --shell /bin/false --no-create-home appuser

WORKDIR /app

# Copier uniquement le nécessaire depuis le builder
COPY --from=builder --chown=appuser:appgroup /build/node_modules ./node_modules
COPY --from=builder --chown=appuser:appgroup /build/dist ./dist 2>/dev/null || true
COPY --chown=appuser:appgroup . .

# Supprimer les outils de dev
RUN npm prune --production 2>/dev/null || true

USER appuser

ENV NODE_ENV=production \
    PORT=8081

EXPOSE 8081

HEALTHCHECK --interval=30s --timeout=10s --start-period=20s --retries=3 \
    CMD wget -qO- http://localhost:8081/health || exit 1

CMD ["node", "server.js"]
