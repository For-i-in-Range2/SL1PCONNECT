# ─── Stage 1: builder ───────────────────────────────────────────────────────
FROM python:3.12-slim AS builder

WORKDIR /build

# Installer uniquement les dépendances de build
COPY requirements.txt .
RUN pip install --no-cache-dir --user -r requirements.txt

# ─── Stage 2: runtime ────────────────────────────────────────────────────────
FROM python:3.12-slim AS runtime

# Créer un utilisateur non-root dédié
RUN groupadd --gid 1001 appgroup \
 && useradd --uid 1001 --gid appgroup --shell /bin/false --no-create-home appuser

WORKDIR /app

# Copier uniquement les packages installés depuis le builder
COPY --from=builder /root/.local /home/appuser/.local

# Copier le code applicatif
COPY --chown=appuser:appgroup . .

# Supprimer les fichiers inutiles en production
RUN find /app -name "*.pyc" -delete \
 && find /app -name "__pycache__" -delete \
 && find /app -name "*.test.*" -delete

# Basculer vers l'utilisateur non-root
USER appuser

# Variables d'environnement (sans secrets — fournis via Docker Secrets)
ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PATH="/home/appuser/.local/bin:$PATH" \
    PORT=8080

EXPOSE 8080

# Healthcheck — vérifie que l'API répond
HEALTHCHECK --interval=30s --timeout=10s --start-period=15s --retries=3 \
    CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:8080/health')"

CMD ["python", "-m", "uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8080"]
