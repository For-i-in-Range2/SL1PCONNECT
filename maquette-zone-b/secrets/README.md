# Gestion des secrets — SL1PCONNECT Zone B

## Principe

Les secrets ne sont JAMAIS commités dans Git.
Ce dossier contient uniquement ce fichier README.

## Création des secrets (première installation)

```bash
# Mot de passe BDD
openssl rand -base64 32 > db_password.txt

# Utilisateur BDD
echo -n "slipconnect_app" > db_user.txt

# Clé secrète API
openssl rand -hex 64 > api_secret_key.txt

# Clé JWT
openssl rand -hex 64 > jwt_secret.txt

# Définir les permissions restrictives
chmod 600 *.txt
```

## Rotation des secrets

1. Générer les nouveaux secrets (commandes ci-dessus)
2. Mettre à jour les secrets Docker : `docker compose up -d` (rechargement automatique)
3. Vérifier que les services redémarrent correctement
4. Supprimer les anciens secrets après validation

## Migration vers Vault (Phase 2)

À implémenter dans les 6 mois suivant le déploiement initial :
- HashiCorp Vault avec injection dynamique
- Rotation automatique des credentials BDD
- Audit log de chaque accès aux secrets
