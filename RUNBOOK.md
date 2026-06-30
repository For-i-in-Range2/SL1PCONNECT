# RUNBOOK — Déploiement sur 3 VM (test / démo)

Procédure complète, dans l'ordre, pour déployer la plateforme SL1PCONNECT sur
3 VM : **VM1** (manager Swarm), **VM2** (worker Swarm), **VM3** (reverse-proxy,
hors Swarm). Toutes les commandes `make` s'exécutent depuis ce dépôt, cloné sur
chaque VM concernée.

## Prérequis

- Docker Engine installé sur les 3 VM
- Les 3 VM se joignent sur le réseau (même LAN / VPC)
- `git`, `make`, `openssl` sur VM1 ; `trivy` si vous voulez scanner depuis VM1

## Ports firewall requis

| Sens                    | Ports                          | Raison                          |
|-------------------------|---------------------------------|----------------------------------|
| VM1 ↔ VM2                | 2377/tcp, 7946/tcp+udp, 4789/udp | Contrôle + overlay réseau Swarm |
| VM1 → VM2 (registry)     | 5000/tcp                        | Pull d'images depuis le registry local (VM1) |
| Internet → VM3           | 80/tcp, 443/tcp                 | Trafic public (Traefik)         |
| VM3 → VM1, VM3 → VM2     | 8080, 8081, 9090 /tcp            | Routing mesh Swarm (API, panel, Grafana) |

VM3 **n'a jamais besoin** d'ouvrir les ports de contrôle Swarm (2377/7946/4789) :
elle n'en fait pas partie.

---

## Étape 1 — Initialiser le Swarm

**Sur VM1 (manager) :**
```bash
docker swarm init --advertise-addr <IP_VM1>
```
Copier la commande `docker swarm join --token ...` affichée en sortie.

**Sur VM2 (worker) :** coller et exécuter la commande `docker swarm join ...`.

**Vérifier depuis VM1 :**
```bash
docker node ls   # doit lister VM1 (Leader) et VM2 (Worker)
```

---

## Étape 2 — Registry insecure sur VM2

Le registry local (sur VM1:5000) n'a pas de certificat TLS — il faut le déclarer
explicitement comme "insecure" sur VM2 pour qu'elle puisse puller les images.

**Sur VM1 :**
```bash
make registry-insecure-hint
```
Affiche la configuration exacte à appliquer.

**Sur VM2 :**
```bash
# éditer /etc/docker/daemon.json avec le contenu affiché ci-dessus
sudo systemctl restart docker
curl -s http://<IP_VM1>:5000/v2/_catalog   # doit répondre du JSON
```

---

## Étape 3 — Secrets

**Sur VM1 :**
```bash
make secrets-init   # génère ./secrets/*.txt (1ère fois uniquement, idempotent)
make secrets        # crée les Docker Secrets dans le Swarm
```

---

## Étape 4 — Build, scan, push des images

**Sur VM1 :**
```bash
make build   # build les 3 images (registre local 127.0.0.1:5000)
make trivy   # scan CVE — bloque si CRITICAL/HIGH trouvée
make push    # push vers le registry local
```

---

## Étape 5 — Déployer le stack Swarm

**Sur VM1 :**
```bash
make deploy
docker stack services sl1p   # vérifier que tous les réplicas sont à N/N
docker stack ps sl1p         # détail des tâches (utile pour debug pull/placement)
```

---

## Étape 6 — Reverse-proxy (VM3)

**Sur VM3 :**
```bash
git clone <repo> && cd VIRTU/reverse-proxy
# éditer dynamic.yml : remplacer VM1_IP et VM2_IP par les vraies IP
docker compose up -d
curl -H 'Host: api.sl1pconnect.local' http://localhost/health
```

Détails complets : [`reverse-proxy/README.md`](./reverse-proxy/README.md).

---

## Étape 7 — Tester depuis un poste client (sans DNS)

```bash
make hosts-hint VM3_IP=<IP_VM3>
```
Ajouter les entrées affichées dans le fichier hosts du poste de test, puis :

```bash
curl http://api.sl1pconnect.local/health
curl http://panel.sl1pconnect.local
curl http://grafana.sl1pconnect.local/api/health
```

Ou directement dans un navigateur : `http://grafana.sl1pconnect.local` (identifiants
`sl1padmin` / contenu de `secrets/grafana_admin_password.txt`).

---

## Démonstration "reproductibilité" pour la soutenance

```bash
# Modifier un service, puis :
make all   # build → scan → push → deploy en une commande
docker service logs sl1p_thread-api -f   # observer le rolling update en direct
```

## Commandes utiles

```bash
docker stack ps sl1p              # état détaillé des tâches
docker service logs sl1p_<nom> -f # logs d'un service
docker service scale sl1p_thread-api=3   # scaling manuel
make undeploy                     # supprime le stack
```
