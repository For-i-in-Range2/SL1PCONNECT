#!/usr/bin/env bash
# build.sh – Builder et versionner les images SL1PCONNECT
# A executer sur VM1 (manager)
#
# Usage :
#   ./build.sh              # version auto depuis git (ex: 1.0.0-abc1234)
#   ./build.sh 1.2.0        # version semver manuelle
#
# Tags appliques sur chaque image :
#   <semver>              ex: 1.0.0
#   <semver>-<gitsha>     ex: 1.0.0-abc1234   ← tag de deploy recommande
#   latest

set -euo pipefail

# ── Configuration ─────────────────────────────────────────────────────────
# IP de VM1 (manager) : les images sont taguees avec cette IP
# pour que VM2 puisse les puller depuis le registry
REGISTRY_HOST=$(hostname -I | awk '{print $1}')
REGISTRY="${REGISTRY_HOST}:5000"
PROJECT="sl1p"

# Version semver : argument CLI ou dernier tag git ou fallback "1.0.0"
if [ -n "${1:-}" ]; then
  SEMVER="$1"
elif git describe --tags --abbrev=0 2>/dev/null; then
  SEMVER=$(git describe --tags --abbrev=0 | sed 's/^v//')
else
  SEMVER="1.0.0"
fi

# SHA du commit actuel (7 chars)
GIT_SHA=$(git rev-parse --short HEAD 2>/dev/null || echo "nogit")

# Tag complet = semver + sha (ex: 1.0.0-abc1234)
FULL_TAG="${SEMVER}-${GIT_SHA}"

echo "════════════════════════════════════════════════"
echo "  Registry : $REGISTRY"
echo "  Semver   : $SEMVER"
echo "  Git SHA  : $GIT_SHA"
echo "  Tag full : $FULL_TAG"
echo "════════════════════════════════════════════════"

# ── 1. Lancer le registry local si pas deja en route ──────────────────────
if ! docker ps --format '{{.Names}}' | grep -q "^registry$"; then
  echo ""
  echo ">>> Demarrage du registry local..."
  docker run -d \
    --name registry \
    --restart=unless-stopped \
    -p 5000:5000 \
    -v registry-data:/var/lib/registry \
    registry:2
  sleep 2
  echo ">>> Registry demarre sur $REGISTRY"
else
  echo ""
  echo ">>> Registry deja actif sur $REGISTRY"
fi

# ── 2. Fonction build + 3 tags + push ─────────────────────────────────────
build_and_push() {
  local name=$1
  local context=$2
  local base="$REGISTRY/$PROJECT/$name"

  echo ""
  echo "=== Build : $name ==="
  # Construction avec le tag complet comme reference principale
  docker build \
    --label "org.opencontainers.image.version=$SEMVER" \
    --label "org.opencontainers.image.revision=$GIT_SHA" \
    --label "org.opencontainers.image.created=$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --label "org.opencontainers.image.title=sl1pconnect/$name" \
    -t "$base:$FULL_TAG" \
    "$context"

  # Re-tagger sans rebuilder
  docker tag "$base:$FULL_TAG" "$base:$SEMVER"
  docker tag "$base:$FULL_TAG" "$base:latest"

  # Push des 3 tags
  echo "  Push : $base:$FULL_TAG"
  docker push "$base:$FULL_TAG"

  echo "  Push : $base:$SEMVER"
  docker push "$base:$SEMVER"

  echo "  Push : $base:latest"
  docker push "$base:latest"
}

# ── 3. Build des 3 services custom ────────────────────────────────────────
build_and_push "thread-api"       "./thread-api"
build_and_push "tailor-panel"     "./tailor-panel"
build_and_push "stitch-processor" "./stitch-processor"

# ── 4. Ecrire le tag dans .image-tag (lu par deploy.sh) ──────────────────
cat > .image-tag <<EOF
# Genere par build.sh le $(date)
export IMAGE_TAG="${FULL_TAG}"
export IMAGE_SEMVER="${SEMVER}"
export IMAGE_SHA="${GIT_SHA}"
export REGISTRY="${REGISTRY}"
EOF

echo ""
echo ">>> Tag ecrit dans .image-tag : $FULL_TAG"

# ── 5. Resume des images dans le registry ─────────────────────────────────
echo ""
echo ">>> Images disponibles dans le registry ($REGISTRY) :"
curl -s "http://$REGISTRY/v2/_catalog" | python3 -m json.tool

echo ""
echo ">>> Tags de thread-api :"
curl -s "http://$REGISTRY/v2/sl1p/thread-api/tags/list" | python3 -m json.tool

echo ""
echo "════════════════════════════════════════════════"
echo "  Build OK : version $FULL_TAG"
echo "  Deploie avec : ./deploy.sh"
echo "  Ou une version specifique : IMAGE_TAG=$SEMVER ./deploy.sh"
echo "════════════════════════════════════════════════"
