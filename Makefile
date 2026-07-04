# SL1PCONNECT – IaC Makefile
# Usage : make <cible>
#
# Prérequis :
#   - Docker Engine + Docker Swarm initialisé (VM1 manager)
#   - Trivy installé  : https://aquasecurity.github.io/trivy/
#   - Secrets créés   : make secrets

# ── Variables ─────────────────────────────────────────────────────────────────
REGISTRY    ?= 127.0.0.1:5000
STACK       ?= sl1p
COMPOSE_FILE = docker-compose.yml
STACK_FILE   = docker-stack.yml
SERVICES     = thread-api tailor-panel stitch-processor

# Tag = version sémantique + SHA court (reproductible, traçable)
VERSION     := $(shell git describe --tags --always --dirty 2>/dev/null || echo "0.1.0")
SHA         := $(shell git rev-parse --short HEAD 2>/dev/null || echo "local")
IMAGE_TAG   := $(VERSION)-$(SHA)

# Couleurs terminal
BOLD  := \033[1m
RESET := \033[0m
GREEN := \033[32m
RED   := \033[31m
CYAN  := \033[36m

.DEFAULT_GOAL := help
.PHONY: help build scan trivy push secrets secrets-init registry-insecure-hint hosts-hint dev deploy undeploy clean all

# ── Aide ──────────────────────────────────────────────────────────────────────
help:
	@printf "$(BOLD)SL1PCONNECT – Infrastructure as Code$(RESET)\n\n"
	@printf "$(CYAN)Développement local$(RESET)\n"
	@printf "  %-18s %s\n" "make dev"     "Lance la stack complète en local (docker compose)"
	@printf "  %-18s %s\n" "make dev-down" "Arrête et supprime les conteneurs locaux"
	@printf "\n$(CYAN)Pipeline build$(RESET)\n"
	@printf "  %-18s %s\n" "make build"   "Build les 3 images Docker"
	@printf "  %-18s %s\n" "make scan"    "Scan Trivy (CVE CRITICAL/HIGH) sur les images buildées"
	@printf "  %-18s %s\n" "make trivy"   "Alias de make scan"
	@printf "  %-18s %s\n" "make push"    "Pousse les images vers le registry local Swarm"
	@printf "\n$(CYAN)Production Swarm$(RESET)\n"
	@printf "  %-18s %s\n" "make secrets-init" "Génère les fichiers secrets/*.txt (1ère installation, idempotent)"
	@printf "  %-18s %s\n" "make secrets" "Crée les Docker Secrets (db_password, jwt_secret, grafana)"
	@printf "  %-18s %s\n" "make deploy"  "Déploie/met à jour le stack Swarm (rolling update)"
	@printf "  %-18s %s\n" "make undeploy" "Supprime le stack Swarm"
	@printf "\n$(CYAN)Aide-mémoire VM2 / VM3$(RESET)\n"
	@printf "  %-18s %s\n" "make registry-insecure-hint" "Affiche la config daemon.json à appliquer sur VM2"
	@printf "  %-18s %s\n" "make hosts-hint VM3_IP=x.x.x.x" "Affiche les entrées /etc/hosts pour tester sans DNS"
	@printf "\n$(CYAN)Utilitaires$(RESET)\n"
	@printf "  %-18s %s\n" "make all"     "build + scan + push + deploy (pipeline complet)"
	@printf "  %-18s %s\n" "make clean"   "Supprime les images locales buildées"
	@printf "\n$(BOLD)Tag courant :$(RESET) $(IMAGE_TAG)\n"

# ── Dev local ─────────────────────────────────────────────────────────────────
dev: _check-secrets-files
	@printf "$(GREEN)▶ Démarrage stack dev (compose)...$(RESET)\n"
	docker compose -f $(COMPOSE_FILE) up --build -d
	@printf "$(GREEN)✔ Stack dev disponible :$(RESET)\n"
	@printf "  thread-api      → http://localhost:8080/health\n"
	@printf "  tailor-panel    → http://localhost:8081\n"
	@printf "  stitch-processor→ http://localhost:8082/health\n"
	@printf "  fabric-watch    → http://localhost:9090\n"

dev-down:
	docker compose -f $(COMPOSE_FILE) down -v

# ── Build ─────────────────────────────────────────────────────────────────────
build:
	@printf "$(GREEN)▶ Build des images (tag: $(IMAGE_TAG))...$(RESET)\n"
	@for svc in $(SERVICES); do \
		printf "  → $$svc\n"; \
		docker build \
			--label "org.opencontainers.image.version=$(VERSION)" \
			--label "org.opencontainers.image.revision=$(SHA)" \
			--label "org.opencontainers.image.created=$$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
			-t $(REGISTRY)/sl1p/$$svc:$(IMAGE_TAG) \
			-t $(REGISTRY)/sl1p/$$svc:latest \
			./$$svc; \
	done
	@printf "$(GREEN)✔ Build terminé.$(RESET)\n"

# ── Scan Trivy ────────────────────────────────────────────────────────────────
trivy: scan

scan: _check-trivy
	@printf "$(GREEN)▶ Scan Trivy des images...$(RESET)\n"
	@FAIL=0; \
	for svc in $(SERVICES); do \
		printf "\n$(CYAN)── $$svc ──$(RESET)\n"; \
		trivy image \
			--exit-code 1 \
			--severity CRITICAL,HIGH \
			--ignore-unfixed \
			--no-progress \
			$(REGISTRY)/sl1p/$$svc:$(IMAGE_TAG) || FAIL=1; \
	done; \
	if [ $$FAIL -eq 1 ]; then \
		printf "$(RED)✖ Des vulnérabilités CRITICAL/HIGH ont été trouvées.$(RESET)\n"; \
		exit 1; \
	fi
	@printf "$(GREEN)✔ Aucune CVE critique. Images approuvées.$(RESET)\n"

# ── Push vers le registry local ───────────────────────────────────────────────
push:
	@printf "$(GREEN)▶ Push vers $(REGISTRY)...$(RESET)\n"
	@for svc in $(SERVICES); do \
		printf "  → $$svc:$(IMAGE_TAG)\n"; \
		docker push $(REGISTRY)/sl1p/$$svc:$(IMAGE_TAG); \
		docker push $(REGISTRY)/sl1p/$$svc:latest; \
	done
	@printf "$(GREEN)✔ Push terminé.$(RESET)\n"

# ── Génération des secrets locaux (1ère installation) ─────────────────────────
secrets-init: _check-openssl
	@mkdir -p ./secrets
	@for f in db_password jwt_secret grafana_admin_password; do \
		if [ -f "./secrets/$$f.txt" ]; then \
			printf "  ⚠  secrets/$$f.txt existe déjà, conservé.\n"; \
		else \
			openssl rand -base64 32 | tr -d '\n' > "./secrets/$$f.txt"; \
			chmod 600 "./secrets/$$f.txt"; \
			printf "  ✔  secrets/$$f.txt généré.\n"; \
		fi \
	done
	@printf "$(GREEN)✔ Secrets locaux prêts (./secrets/, jamais commités — voir .gitignore).$(RESET)\n"
	@printf "  Étape suivante : make secrets (crée les Docker Secrets dans le Swarm)\n"

# ── Secrets Swarm ─────────────────────────────────────────────────────────────
secrets: _check-secrets-files
	@printf "$(GREEN)▶ Création des Docker Secrets...$(RESET)\n"
	@for secret in db_password jwt_secret grafana_admin_password; do \
		if docker secret inspect $$secret >/dev/null 2>&1; then \
			printf "  ⚠  $$secret existe déjà, ignoré.\n"; \
		else \
			docker secret create $$secret ./secrets/$$secret.txt && \
			printf "  ✔  $$secret créé.\n"; \
		fi \
	done
	@printf "$(GREEN)✔ Secrets prêts.$(RESET)\n"

# ── Déploiement Swarm ─────────────────────────────────────────────────────────
deploy: _check-swarm
	@printf "$(GREEN)▶ Déploiement Swarm (stack: $(STACK), tag: $(IMAGE_TAG))...$(RESET)\n"
	IMAGE_TAG=$(IMAGE_TAG) REGISTRY=$(REGISTRY) \
		docker stack deploy -c $(STACK_FILE) --with-registry-auth $(STACK)
	@printf "$(GREEN)✔ Stack déployé. Convergence en cours...\n$(RESET)"
	@sleep 5
	@docker stack services $(STACK)

undeploy:
	@printf "$(RED)▶ Suppression du stack $(STACK)...$(RESET)\n"
	docker stack rm $(STACK)

# ── Aide-mémoire registry insecure (à exécuter sur VM2) ───────────────────────
registry-insecure-hint:
	@printf "$(BOLD)Sur VM2 (worker), avant le premier 'docker swarm join' / pull :$(RESET)\n\n"
	@printf "  1. Éditer /etc/docker/daemon.json :\n"
	@printf '     { "insecure-registries": ["$(REGISTRY)"] }\n\n'
	@printf "  2. sudo systemctl restart docker\n\n"
	@printf "  3. Vérifier depuis VM2 : curl -s http://$(REGISTRY)/v2/_catalog\n"
	@printf "     (doit répondre du JSON, pas une erreur de connexion TLS)\n"

# ── Aide-mémoire fichier hosts (test sans DNS, à exécuter sur le poste client) ─
hosts-hint:
	@if [ -z "$(VM3_IP)" ]; then \
		printf "$(RED)✖ Usage : make hosts-hint VM3_IP=<ip-du-reverse-proxy>$(RESET)\n"; \
		exit 1; \
	fi
	@printf "$(BOLD)Ajouter dans le fichier hosts du poste de test/démo :$(RESET)\n"
	@printf "  Linux/macOS : /etc/hosts\n"
	@printf "  Windows     : C:\\Windows\\System32\\drivers\\etc\\hosts\n\n"
	@printf "  $(VM3_IP)  api.sl1pconnect.local panel.sl1pconnect.local grafana.sl1pconnect.local\n\n"
	@printf "Toutes les entrées pointent vers VM3 (le reverse-proxy), jamais vers VM1/VM2.\n"

# ── Pipeline complet ──────────────────────────────────────────────────────────
all: build scan push deploy

# ── Nettoyage ─────────────────────────────────────────────────────────────────
clean:
	@printf "$(GREEN)▶ Suppression des images locales...$(RESET)\n"
	@for svc in $(SERVICES); do \
		docker rmi $(REGISTRY)/sl1p/$$svc:$(IMAGE_TAG) 2>/dev/null || true; \
		docker rmi $(REGISTRY)/sl1p/$$svc:latest 2>/dev/null || true; \
	done
	@printf "$(GREEN)✔ Nettoyage terminé.$(RESET)\n"

# ── Gardes internes ───────────────────────────────────────────────────────────
_check-trivy:
	@command -v trivy >/dev/null 2>&1 || \
		(printf "$(RED)✖ Trivy non installé. Voir https://aquasecurity.github.io/trivy/$(RESET)\n" && exit 1)

_check-openssl:
	@command -v openssl >/dev/null 2>&1 || \
		(printf "$(RED)✖ openssl non installé (requis pour générer les secrets).$(RESET)\n" && exit 1)

_check-swarm:
	@docker info --format '{{.Swarm.LocalNodeState}}' 2>/dev/null | grep -q active || \
		(printf "$(RED)✖ Ce nœud n'est pas dans un Swarm actif. Lancez : docker swarm init$(RESET)\n" && exit 1)

_check-secrets-files:
	@for f in db_password jwt_secret grafana_admin_password; do \
		if [ ! -f "./secrets/$$f.txt" ]; then \
			printf "$(RED)✖ Fichier manquant : secrets/$$f.txt$(RESET)\n"; \
			exit 1; \
		fi \
	done
