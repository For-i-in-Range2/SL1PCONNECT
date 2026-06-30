# Corrections :
#   - Python 3.12 (3.8 = EOL depuis octobre 2024)
#   - Multi-stage build (builder + runtime) : image finale sans outils de build
#   - Utilisateur non-root uid 1001 (jamais root en prod)
#   - Gunicorn comme serveur WSGI (pas app.run())

# ── Stage 1 : compilation des dependances ──────────────────────────
FROM python:3.12-slim AS builder
WORKDIR /build
COPY requirements.txt .
RUN pip install --no-cache-dir --user -r requirements.txt

# ── Stage 2 : image de production ──────────────────────────────────
FROM python:3.12-slim AS runtime

# Utilisateur dedie non-root
RUN groupadd --gid 1001 appgroup \
 && useradd --uid 1001 --gid appgroup --shell /bin/false --no-create-home appuser

WORKDIR /app

# Copie uniquement les packages installes depuis le builder
COPY --from=builder /root/.local /home/appuser/.local

# Copie du code avec les bonnes permissions
COPY --chown=appuser:appgroup . .

USER appuser

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PATH="/home/appuser/.local/bin:$PATH" \
    PORT=8080

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=10s --start-period=15s --retries=3 \
    CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:8080/health')"

# Gunicorn en prod (jamais app.run())
CMD ["gunicorn", "--bind", "0.0.0.0:8080", "--workers", "2", "--timeout", "60", "app:app"]
