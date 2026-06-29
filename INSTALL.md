# Guide d'installation — SL1PCONNECT
## Virtualisation + Conteneurisation + Supervision

Ce guide couvre l'installation complète de la maquette sur **1 machine physique**.

---

## Vue d'ensemble

```
Machine physique
└── Proxmox VE (hyperviseur)
    ├── vm-docker  →  Docker Compose (Zone B IoT)
    │                  ├── thread-api:8080
    │                  ├── tailor-panel:8081
    │                  ├── stitch-processor:8082
    │                  ├── fabric-watch:9090
    │                  ├── Traefik (reverse proxy TLS)
    │                  ├── Prometheus + Grafana
    │                  └── Loki + Promtail
    ├── vm-bdd     →  PostgreSQL 16
    ├── vm-dns     →  Bind9
    └── vm-web     →  Nginx (optionnel pour la maquette)
```

Temps estimé : **2 à 3 heures** pour la maquette complète.

---

## PARTIE 1 — Installation de Proxmox VE

### 1.1 Prérequis matériels

- CPU x86-64 avec **VT-x ou AMD-V activé** dans le BIOS
- RAM : 16 Go minimum (32 Go recommandé)
- Stockage : 200 Go SSD minimum
- Réseau : 1 carte réseau (Ethernet)

**Vérifier la virtualisation dans le BIOS :**
- Intel : chercher "Intel VT-x" ou "Intel Virtualization Technology" → Enabled
- AMD : chercher "AMD-V" ou "SVM Mode" → Enabled

### 1.2 Téléchargement et création de la clé USB

```bash
# Télécharger l'ISO Proxmox VE 8.x depuis :
# https://www.proxmox.com/en/downloads/proxmox-virtual-environment/iso

# Créer la clé USB bootable (Linux/Mac) :
dd if=proxmox-ve_8.x.iso of=/dev/sdX bs=4M status=progress
# Remplacer /dev/sdX par votre clé USB (attention : efface tout !)

# Sous Windows : utiliser Rufus (https://rufus.ie)
# Mode : DD Image
```

### 1.3 Installation de Proxmox

1. Booter sur la clé USB
2. Choisir **"Install Proxmox VE (Graphical)"**
3. Accepter la licence EULA
4. Sélectionner le disque cible (attention : tout sera effacé)
5. **Configurer le réseau :**
   - Hostname : `pve.slipconnect.local`
   - IP Address : `192.168.1.10/24` (adapter à votre réseau)
   - Gateway : `192.168.1.1`
   - DNS : `8.8.8.8`
6. Définir un mot de passe root fort
7. Lancer l'installation (5-10 minutes)
8. Rebooter sans la clé USB

### 1.4 Premier accès à l'interface web

Depuis un autre PC sur le même réseau :
```
https://192.168.1.10:8006
```
- Login : `root`
- Password : celui défini à l'installation
- Accepter le certificat auto-signé (normal)

> **Note :** L'interface affiche un avertissement "No valid subscription". C'est normal en mode gratuit. Cliquer "OK" pour continuer.

### 1.5 Désactiver le dépôt Enterprise (évite les erreurs apt)

Dans l'interface Proxmox → **Node pve → Shell** :
```bash
# Désactiver le dépôt enterprise (payant)
sed -i 's/^deb/#deb/' /etc/apt/sources.list.d/pve-enterprise.list
sed -i 's/^deb/#deb/' /etc/apt/sources.list.d/ceph.list 2>/dev/null || true

# Ajouter le dépôt gratuit (no-subscription)
echo "deb http://download.proxmox.com/debian/pve bookworm pve-no-subscription" \
  > /etc/apt/sources.list.d/pve-no-subscription.list

# Mettre à jour
apt update && apt upgrade -y
```

---

## PARTIE 2 — Création des VMs dans Proxmox

### 2.1 Télécharger l'ISO Debian 12

Dans Proxmox → **Storage local → ISO Images → Download from URL** :
```
https://cdimage.debian.org/debian-cd/current/amd64/iso-cd/debian-12.x.x-amd64-netinst.iso
```

Ou depuis le shell Proxmox :
```bash
wget -P /var/lib/vz/template/iso/ \
  https://cdimage.debian.org/debian-cd/current/amd64/iso-cd/debian-12.5.0-amd64-netinst.iso
```

### 2.2 Créer vm-docker (VM principale IoT)

**Dans l'interface Proxmox → Create VM :**

| Paramètre | Valeur |
|---|---|
| VM ID | 100 |
| Name | vm-docker |
| OS | Debian 12 ISO |
| CPU | 4 vCPU |
| RAM | 8192 Mo (8 Go) |
| Disk | 80 Go, virtio, thin |
| Network | vmbr0, virtio |

**Depuis le shell Proxmox (alternative en ligne de commande) :**
```bash
qm create 100 \
  --name vm-docker \
  --memory 8192 \
  --cores 4 \
  --net0 virtio,bridge=vmbr0 \
  --scsi0 local-lvm:80 \
  --cdrom local:iso/debian-12.5.0-amd64-netinst.iso \
  --boot order=scsi0;ide2 \
  --ostype l26

qm start 100
```

### 2.3 Installer Debian 12 dans vm-docker

1. Ouvrir la console : **Proxmox → VM 100 → Console**
2. Suivre l'installateur Debian (installation standard)
3. Paramètres recommandés :
   - Partitionnement : LVM guidé, tout sur une partition
   - Pas de bureau graphique (décocher "Debian desktop environment")
   - Cocher "SSH server" et "standard system utilities"
4. Hostname : `vm-docker`
5. Créer un utilisateur `deploy` (en plus de root)

### 2.4 Créer vm-bdd (optionnel pour la maquette)

Même procédure avec :
- VM ID : 101, Name : vm-bdd, RAM : 4 Go, Disk : 50 Go

> Pour la maquette, la BDD peut aussi tourner dans Docker sur vm-docker. C'est déjà configuré dans le docker-compose.yml.

### 2.5 Configuration réseau post-install (vm-docker)

Connexion SSH depuis votre machine :
```bash
ssh root@<IP-de-vm-docker>
```

```bash
# Mettre à jour le système
apt update && apt upgrade -y

# Installer les outils de base
apt install -y curl wget git htop vim ufw fail2ban
```

---

## PARTIE 3 — Installation de Docker sur vm-docker

```bash
# Installer Docker via le script officiel
curl -fsSL https://get.docker.com | sh

# Ajouter l'utilisateur deploy au groupe docker
usermod -aG docker deploy

# Activer Docker au démarrage
systemctl enable docker
systemctl start docker

# Vérifier
docker --version
docker compose version
```

---

## PARTIE 4 — Déploiement de la stack IoT (Zone B)

### 4.1 Cloner le dépôt

```bash
ssh deploy@<IP-de-vm-docker>

git clone https://github.com/<votre-repo>/SL1PCONNECT.git
cd SL1PCONNECT/maquette-zone-b
```

### 4.2 Créer les secrets

```bash
mkdir -p secrets

# Mot de passe base de données
openssl rand -base64 32 > secrets/db_password.txt

# Utilisateur BDD
echo -n "slipconnect_app" > secrets/db_user.txt

# Clé secrète API
openssl rand -hex 64 > secrets/api_secret_key.txt

# Clé JWT
openssl rand -hex 64 > secrets/jwt_secret.txt

# Permissions restrictives
chmod 600 secrets/*.txt

# Vérification
ls -la secrets/
```

### 4.3 Configurer les variables d'environnement

```bash
cp .env.example .env
vim .env
```

Contenu minimal pour la maquette :
```bash
ENV=dev
DB_NAME=slipconnect_iot
GRAFANA_USER=admin
# REGISTRY= (laisser vide pour build local)
TAG=latest
```

### 4.4 Builder et démarrer les services

```bash
# Builder toutes les images localement
docker compose build

# Démarrer en arrière-plan
docker compose up -d

# Suivre les logs en temps réel
docker compose logs -f
```

> Premier démarrage : 3-5 minutes le temps de construire les images.

### 4.5 Vérifier que tout fonctionne

```bash
# Voir l'état de tous les services
docker compose ps

# Le résultat attendu :
# NAME                STATUS              PORTS
# thread-api          Up (healthy)
# tailor-panel        Up (healthy)
# stitch-processor    Up (healthy)
# fabric-watch        Up (healthy)
# db-velvet           Up (healthy)
# traefik             Up (healthy)        0.0.0.0:80->80/tcp, 0.0.0.0:443->443/tcp
# prometheus          Up (healthy)
# grafana             Up (healthy)
# loki                Up (healthy)
# promtail            Up
```

---

## PARTIE 5 — Vérifications de sécurité

### 5.1 Aucun service ne tourne en root

```bash
# Vérifier l'utilisateur de chaque conteneur
docker compose ps -q | xargs -I{} docker inspect {} \
  --format '{{.Name}}: user={{.Config.User}}'

# Résultat attendu : tous affichent "1001" ou "appuser"
# JAMAIS "root" ou "" (vide) pour les services métier
```

### 5.2 Les secrets ne sont pas dans les variables d'env

```bash
# Vérifier que le mot de passe BDD n'est PAS en variable d'env
docker exec thread-api env | grep -i password
# Doit retourner vide

# Vérifier que le secret est accessible via /run/secrets/
docker exec thread-api cat /run/secrets/db_password
# Doit afficher le mot de passe
```

### 5.3 Isolation réseau

```bash
# tailor-panel NE doit PAS pouvoir joindre db-velvet directement
docker exec tailor-panel ping db-velvet
# Doit échouer (network unreachable)

# thread-api DOIT pouvoir joindre db-velvet
docker exec thread-api ping db-velvet
# Doit réussir
```

### 5.4 docker.sock non monté

```bash
# Aucun conteneur ne doit avoir accès à docker.sock
for c in $(docker compose ps -q); do
  name=$(docker inspect $c --format '{{.Name}}')
  sock=$(docker inspect $c --format '{{range .Mounts}}{{if eq .Source "/var/run/docker.sock"}}DANGER{{end}}{{end}}')
  echo "$name: ${sock:-OK}"
done
# Tous doivent afficher "OK"
```

---

## PARTIE 6 — Accès aux interfaces

### Grafana (supervision)

```
http://<IP-vm-docker>:3000
Login : admin
Password : valeur dans secrets/api_secret_key.txt
```

Tableaux de bord disponibles après provisioning :
- IoT Services Overview
- Docker Containers
- Node Exporter Full

### Prometheus

```
http://<IP-vm-docker>:9091
```

Vérifier que tous les targets sont en état "UP" :
```
http://<IP-vm-docker>:9091/targets
```

### Traefik Dashboard

Accessible uniquement en local ou VPN :
```
http://<IP-vm-docker>:8080
```

> En production, le dashboard est protégé par auth basique et accessible uniquement depuis le réseau d'administration.

---

## PARTIE 7 — Proxmox Backup Server (sauvegardes)

### 7.1 Installation de PBS sur la même machine (VM dédiée)

```bash
# Sur Proxmox, créer une VM "vm-pbs" (Debian 12, 2 vCPU, 4 Go RAM, 200 Go disque)
# Puis dans la VM :
curl -fsSL https://enterprise.proxmox.com/debian/proxmox-release-bookworm.gpg \
  -o /etc/apt/trusted.gpg.d/proxmox-release-bookworm.gpg

echo "deb http://download.proxmox.com/debian/pbs bookworm pve-no-subscription" \
  > /etc/apt/sources.list.d/pbs-no-subscription.list

apt update && apt install -y proxmox-backup-server
```

### 7.2 Configurer les sauvegardes automatiques

Dans l'interface Proxmox → **Datacenter → Backup → Add** :
- Schedule : `0 2 * * *` (tous les jours à 2h)
- Storage : sélectionner le PBS
- Mode : Snapshot
- Compression : ZSTD
- Encrypt : cocher (AES-256)
- Max Backups : 7 (garder 7 jours)

### 7.3 Sauvegarde des volumes Docker

```bash
# Sur vm-docker, installer restic
apt install -y restic

# Initialiser le dépôt de sauvegarde
restic init --repo /backup/docker-volumes

# Sauvegarder les volumes
docker compose stop
restic -r /backup/docker-volumes backup /var/lib/docker/volumes/
docker compose start

# Planifier via cron
echo "0 3 * * * root docker compose -f /home/deploy/SL1PCONNECT/maquette-zone-b/docker-compose.yml stop && restic -r /backup/docker-volumes backup /var/lib/docker/volumes/ && docker compose -f /home/deploy/SL1PCONNECT/maquette-zone-b/docker-compose.yml start" \
  >> /etc/crontab
```

---

## PARTIE 8 — Commandes utiles au quotidien

```bash
# Redémarrer un service
docker compose restart thread-api

# Mettre à jour un service (rebuild + redeploy)
docker compose build thread-api
docker compose up -d --no-deps thread-api

# Voir les logs d'un service
docker compose logs -f --tail=100 thread-api

# Inspecter un conteneur
docker inspect thread-api

# Statistiques CPU/RAM en temps réel
docker compose stats

# Snapshot Proxmox d'une VM (depuis le shell Proxmox)
qm snapshot 100 snap-$(date +%Y%m%d) --description "Snapshot avant mise a jour"

# Lister les snapshots
qm listsnapshot 100

# Restaurer un snapshot
qm rollback 100 snap-20260101
```

---

## PARTIE 9 — Démo en soutenance

### Scénario 1 : Déploiement pipeline (simulé)

```bash
# Simuler un nouveau déploiement via rebuild + rolling restart
docker compose build thread-api
docker compose up -d --no-deps thread-api

# Observer le redémarrage sans interruption
watch -n1 'docker compose ps thread-api'
```

### Scénario 2 : Preuve d'isolation réseau

```bash
# Montrer que tailor-panel ne peut pas contacter db-velvet
docker exec tailor-panel ping -c 3 db-velvet || echo "ISOLE : OK"
```

### Scénario 3 : Gestion des secrets

```bash
# Montrer l'absence de secrets en variables d'env
docker exec thread-api env | grep -iE "password|secret|key" || echo "Aucun secret en env"

# Montrer l'accès via /run/secrets
docker exec thread-api ls /run/secrets/
```

### Scénario 4 : Supervision

1. Ouvrir Grafana : `http://<IP>:3000`
2. Montrer le dashboard IoT (métriques fabric-watch)
3. Dans Prometheus : montrer les alertes configurées

### Scénario 5 : Snapshot et restauration Proxmox

```bash
# Dans l'interface Proxmox :
# 1. VM 100 → Snapshots → Take Snapshot
# 2. Nommer "demo-soutenance"
# 3. Montrer la liste des snapshots
# 4. Optionnel : montrer qu'on peut rollback en 30 secondes
```

---

## Résolution des problèmes courants

| Problème | Cause probable | Solution |
|---|---|---|
| Service "unhealthy" | App pas encore démarrée | Attendre 30-60s, `docker compose logs <service>` |
| Port 80/443 refusé | Firewall vm-docker | `ufw allow 80 && ufw allow 443` |
| BDD inaccessible | Secrets mal générés | Vérifier `secrets/db_password.txt` non vide |
| Traefik erreur TLS | DNS pas configuré | En local, utiliser HTTP ou certificat self-signed |
| Proxmox WebUI inaccessible | IP mal configurée | Accéder via console directe + `ip a` pour vérifier |
| VM ne démarre pas | VT-x non activé | Activer dans le BIOS et rebooter |
