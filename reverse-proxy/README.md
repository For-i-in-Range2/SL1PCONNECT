# Reverse-proxy externe (VM3)

Traefik tourne ici **hors du cluster Swarm**, sur une VM dédiée en DMZ. Il route le
trafic vers VM1/VM2 via le **routing mesh** de Swarm (n'importe quel nœud du cluster
répond sur le port publié, même s'il n'héberge pas le conteneur visé).

## Pourquoi une VM séparée plutôt que Traefik dans le Swarm ?

- **Isolation réseau stricte** : VM3 n'a aucun accès à l'API Docker/Swarm (pas de
  `docker.sock`, pas de socket-proxy). Si elle est compromise depuis Internet,
  l'attaquant n'a aucun chemin direct vers l'orchestrateur ni les données de santé.
- **Modèle DMZ classique** : seule VM3 est exposée sur Internet (ports 80/443).
  VM1/VM2 restent en réseau interne, jamais directement joignables depuis l'extérieur.
- **Cohérent avec l'historique** : reproduit le rôle de `web-cotton` (reverse-proxy
  exposé) dans l'infra existante, version durcie et orchestration-aware.

## Mise en service

1. Récupérer les IP de VM1 (manager) et VM2 (worker) dans le Swarm.
2. Éditer `dynamic.yml` : remplacer `VM1_IP` et `VM2_IP` par ces adresses.
3. Lancer :
   ```bash
   docker compose up -d
   ```
4. Vérifier : `curl -H 'Host: api.sl1pconnect.local' http://<IP_VM3>/health`

## Firewall requis

| Sens                | Ports          | Raison                                  |
|---------------------|----------------|------------------------------------------|
| Internet → VM3      | 80, 443        | Trafic public                            |
| VM3 → VM1, VM3 → VM2 | 8080, 8081, 9090 | Routing mesh Swarm (thread-api, tailor-panel, fabric-watch) |

VM3 n'a **jamais** besoin d'ouvrir les ports Swarm de contrôle (2377, 7946, 4789) :
ce ne sont que des ports applicatifs HTTP normaux côté VM3.

## Test local sans DNS

Pour accéder aux services depuis un poste de test/démo, ajouter dans le fichier
hosts local (`/etc/hosts` ou `C:\Windows\System32\drivers\etc\hosts`) :

```
<IP_VM3>  api.sl1pconnect.local panel.sl1pconnect.local grafana.sl1pconnect.local
```

Toutes les entrées pointent vers **VM3** (le reverse-proxy), jamais directement
vers VM1 ou VM2.
