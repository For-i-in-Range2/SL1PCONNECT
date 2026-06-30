#!/usr/bin/env bash
# deploy.sh – Initialiser le Swarm et deployer la stack SL1PCONNECT
# A executer sur VM1 (manager) apres build.sh
#
# Usage :
#   ./deploy.sh                    # deploie le tag ecrit par build.sh dans .image-tag
#   IMAGE_TAG=1.0.0 ./deploy.sh    # deploie une version specifique
#   IMAGE_TAG=latest ./deploy.sh   # deploie latest

set -euo pipefail

STACK="sl1p"

# ── Resolution du tag a deployer ─────────────────────────────────────────
if [ -n "${IMAGE_TAG:-}" ]; then
  echo ">>> Tag force par la variable IMAGE_TAG : $IMAGE_TAG"
elif [ -f ".image-tag" ]; then
  source .image-tag
  echo ">>> Tag lu depuis .image-tag : $IMAGE_TAG"
else
  IMAGE_TAG="latest"
  echo ">>> Aucun tag trouve, utilisation de : latest"
fi

# Registry (detecte automatiquement ou herite de build.sh via .image-tag)
REGISTRY="${REGISTRY:-$(hostname -I | awk '{print $1}'):5000}"

echo ""
echo "════════════════════════════════════════════════"
echo "  Stack    : $STACK"
echo "  Registry : $REGISTRY"
echo "  Tag      : $IMAGE_TAG"
echo "════════════════════════════════════════════════"

# ────────────────────────────────────────────────────────────────────────────
# ETAPE 1 : Init du Swarm
# ────────────────────────────────────────────────────────────────────────────
if ! docker info --format '{{.Swarm.LocalNodeState}}' | grep -q "active"; then
  echo ""
  echo ">>> Initialisation du Swarm..."
  VM1_IP=$(hostname -I | awk '{print $1}')
  docker swarm init --advertise-addr "$VM1_IP"
  echo ""
  echo "╔══════════════════════════════════════════════════════════════╗"
  echo "║  IMPORTANT : copie la commande 'docker swarm join' ci-dessus ║"
  echo "║  et execute-la sur VM2 avant de continuer.                    ║"
  echo "╚══════════════════════════════════════════════════════════════╝"
  echo ""
  read -rp "Appuie sur [Entree] quand VM2 a rejoint le Swarm..."
else
  echo ""
  echo ">>> Swarm deja actif."
fi

echo ""
echo ">>> Noeuds du Swarm :"
docker node ls

# ────────────────────────────────────────────────────────────────────────────
# ETAPE 2 : Registry insecure sur VM2
# ────────────────────────────────────────────────────────────────────────────
echo ""
echo ">>> Rappel : le registry doit etre declare comme insecure sur VM2."
echo "    Fichier /etc/docker/daemon.json sur VM2 :"
echo "    { \"insecure-registries\": [\"${REGISTRY}\"] }"
echo "    puis : sudo systemctl restart docker"
echo ""

# ────────────────────────────────────────────────────────────────────────────
# ETAPE 3 : Creation des secrets Docker
# ────────────────────────────────────────────────────────────────────────────
echo ">>> Creation des secrets Docker..."

create_secret() {
  local name=$1
  local file=$2
  if docker secret inspect "$name" &>/dev/null; then
    echo "  [deja present] $name"
  else
    docker secret create "$name" "$file"
    echo "  [cree] $name"
  fi
}

if [ ! -d "./secrets" ]; then
  echo "ERREUR : dossier ./secrets/ manquant."
  echo "Cree-le avec les fichiers db_password.txt, jwt_secret.txt, grafana_admin_password.txt"
  exit 1
fi

create_secret "db_password"            "./secrets/db_password.txt"
create_secret "jwt_secret"             "./secrets/jwt_secret.txt"
create_secret "grafana_admin_password" "./secrets/grafana_admin_password.txt"

# ────────────────────────────────────────────────────────────────────────────
# ETAPE 4 : Deploiement de la stack avec le bon tag
# ────────────────────────────────────────────────────────────────────────────
echo ""
echo ">>> Deploiement de la stack '$STACK' (image tag : $IMAGE_TAG)..."

# Les variables IMAGE_TAG et REGISTRY sont interpolees dans docker-stack.yml
export IMAGE_TAG
export REGISTRY

docker stack deploy \
  --with-registry-auth \
  -c docker-stack.yml \
  "$STACK"

# ────────────────────────────────────────────────────────────────────────────
# ETAPE 5 : Verification
# ────────────────────────────────────────────────────────────────────────────
echo ""
echo ">>> Attente convergence (30s)..."
sleep 30

echo ""
echo ">>> Services :"
docker stack services "$STACK"

echo ""
echo ">>> Replicas :"
docker stack ps "$STACK"

echo ""
echo "════════════════════════════════════════════════"
echo "  Deploye : $STACK @ $IMAGE_TAG"
echo ""
echo "  Commandes utiles :"
echo "    docker stack services $STACK"
echo "    docker stack ps $STACK"
echo "    docker service logs ${STACK}_thread-api -f"
echo "    docker stack rm $STACK"
echo ""
echo "  Rollback vers une version precedente :"
echo "    IMAGE_TAG=1.0.0-abc1234 ./deploy.sh"
echo "════════════════════════════════════════════════"
