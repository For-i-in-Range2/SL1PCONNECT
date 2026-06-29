# Guide de déploiement — SL1PCONNECT Zone B IoT

## Prérequis

- Docker 27+ et Docker Compose v2
- Accès SSH à l'hôte OVH
- DNS configuré pour `api.slipconnect.com`, `panel.slipconnect.com`, `grafana.slipconnect.com`

---

## 1. Premier déploiement

```bash
# Cloner le dépôt
git clone https://gitea.slipconnect.com/infra/zone-b-iot.git
cd zone-b-iot

# Créer les secrets
mkdir -p secrets
openssl rand -base64 32 > secrets/db_password.txt
echo -n "slipconnect_app" > secrets/db_user.txt
openssl rand -hex 64 > secrets/api_secret_key.txt
openssl rand -hex 64 > secrets/jwt_secret.txt
chmod 600 secrets/*.txt

# Copier et éditer les variables d'environnement
cp .env.example .env.prod
vim .env.prod

# Construire et démarrer (premier déploiement)
docker compose --env-file .env.prod up -d --build

# Vérifier l'état des services
docker compose ps
docker compose logs -f --tail=50
```

## 2. Déploiement via pipeline CI (standard)

Le pipeline CI/CD gère automatiquement :
1. Build des images avec le SHA du commit
2. Scan de vulnérabilités Trivy (bloquant si CRITICAL)
3. Push vers Harbor Registry
4. Déploiement sur validation manuelle dans GitLab/Gitea

Déclencher un déploiement manuel depuis l'interface CI.

## 3. Mise à jour d'un service spécifique

```bash
# Sur le serveur de prod
cd /opt/slipconnect-iot

# Mettre à jour thread-api uniquement
TAG=abc1234 docker compose pull thread-api
TAG=abc1234 docker compose up -d --no-build thread-api

# Vérifier le healthcheck
docker compose ps thread-api
```

## 4. Rollback

```bash
# Revenir à la version précédente (remplacer <SHA_PRECEDENT>)
TAG=<SHA_PRECEDENT> docker compose up -d --no-build

# Vérifier
docker compose ps
```

## 5. Vérification de l'isolation réseau

```bash
# Vérifier que tailor-panel n'accède PAS à db-velvet directement
docker exec tailor-panel ping db-velvet  # Doit échouer (réseau différent)

# Vérifier que thread-api accède à db-velvet
docker exec thread-api ping db-velvet    # Doit réussir

# Vérifier qu'aucun conteneur ne tourne en root
docker compose ps -q | xargs -I{} docker inspect {} --format '{{.Name}}: User={{.Config.User}}'
```

## 6. Vérification des secrets

```bash
# Les secrets doivent être montés dans /run/secrets/, jamais en variables d'env
docker exec thread-api env | grep PASSWORD  # Doit retourner vide
docker exec thread-api cat /run/secrets/db_password  # Doit afficher le mot de passe
```

## 7. Supervision

- **Grafana** : https://grafana.slipconnect.com (admin / voir secrets)
- **Alertmanager** : Configuré pour notifier Slack + PagerDuty
- **Traefik Dashboard** : https://traefik.internal.slipconnect.com (accès VPN uniquement)

## 8. Commandes utiles

```bash
# Logs en temps réel
docker compose logs -f thread-api

# Stats des conteneurs
docker compose stats

# Inspecter les réseaux
docker network ls | grep slipconnect
docker network inspect slipconnect-iot_net-api

# Vérifier les healthchecks
docker compose ps --format "table {{.Name}}\t{{.Status}}\t{{.Health}}"
```
