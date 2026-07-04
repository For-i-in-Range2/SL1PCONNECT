# SL1PCONNECT — Plateforme IoT (stack existante)

Reproduction de la plateforme IoT du cas d'étude : 4 services applicatifs et une base
PostgreSQL, tels qu'ils tournent actuellement chez SL1PCONNECT.

## Lancer

```bash
docker compose up --build
```

Le premier démarrage construit les images et initialise la base (quelques secondes).

## Services

| Service            | URL                      | Rôle                          |
|--------------------|--------------------------|-------------------------------|
| thread-api         | http://localhost:8080    | API REST de l'app mobile      |
| tailor-panel       | http://localhost:8081    | Back-office (login `admin`)   |
| stitch-processor   | http://localhost:8082    | Traitement des données santé  |
| fabric-watch       | http://localhost:9090    | Supervision Grafana           |
| db-velvet          | localhost:5432           | PostgreSQL                    |

## Exemples d'appels

```bash
curl http://localhost:8080/health
curl -X POST http://localhost:8080/api/login \
  -H 'Content-Type: application/json' \
  -d '{"email":"jean.dupont@example.com","password":"password123"}'
curl http://localhost:8080/api/sensors/3
curl http://localhost:8082/process
```

Pour `tailor-panel`, ouvrir http://localhost:8081, se connecter, puis rechercher un email.

## Objectif

Cette stack est fournie **en l'état**, telle que déployée à l'origine. À vous de l'auditer,
de la durcir et de l'intégrer à une chaîne CI/CD (build, scan d'images, tests, déploiement).

## Architecture de production (3 VM)

`docker-compose.yml` ci-dessus sert au dev local sur une seule machine. La cible
production utilise un Swarm à 2 nœuds (`docker-stack.yml`) + un reverse-proxy
externe sur une 3ᵉ VM en DMZ, hors cluster (voir [`reverse-proxy/`](./reverse-proxy/)) :

```
Internet → VM3 (Traefik, DMZ)  →  routing mesh Swarm  →  VM1 (manager) / VM2 (worker)
```

Pipeline de build/scan/déploiement : voir [`Makefile`](./Makefile) (`make help`).

Procédure complète de déploiement sur 3 VM (Swarm + reverse-proxy) :
voir [`RUNBOOK.md`](./RUNBOOK.md).
