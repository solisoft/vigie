# Déployer Vigie sur vigie.solisoft.net

Comme bonfire : le code part par rsync dans `/home/rocky/sites/vigie.solisoft.net`
sur le serveur de soli-proxy, puis `restart.txt` fait redémarrer l'app.
`app.infos` et `.env` n'existent que sur le serveur ; le rsync ne les touche pas.

## Une seule fois, sur le serveur

1. Créer le dossier du site et y déposer `app.infos.production` sous le nom
   `app.infos` :

   ```
   ssh rocky@92.222.164.98 'mkdir -p sites/vigie.solisoft.net'
   scp deploy/app.infos.production rocky@92.222.164.98:sites/vigie.solisoft.net/app.infos
   ```

2. Créer la base `vigie` et un utilisateur SoliDB dédié sur la SoliDB du serveur,
   puis écrire `sites/vigie.solisoft.net/.env` à partir de `deploy/env.production.example`,
   avec ce mot de passe et un `SOLI_SESSION_SECRET` de 32 caractères ou plus.

3. Premier déploiement (depuis `~/Work/soli/proxy/sites`) :

   ```
   sh vigie_deploy.sh
   ```

   soli-proxy découvre le nouveau site (il surveille `sites/`), démarre l'app et
   obtient le certificat. La première visite de `/signup` crée le compte
   administrateur ; l'inscription se ferme ensuite.

**Ne pas lancer `soli db:seed` en production** : la démo crée un compte
`demo@vigie.example` au mot de passe connu.

## Ensuite

```
cd ~/Work/soli/proxy/sites && sh vigie_deploy.sh
```

Le serveur doit tourner sous Soli ≥ 2.32.0 (`soli_version` de `soli.toml`).
