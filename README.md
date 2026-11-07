# Vigie

Page de statut et surveillance de disponibilité, écrite en [Soli](https://soli.solisoft.net) sur SoliDB.

Vigie sonde vos services (HTTP(S), certificats TLS, tâches planifiées), ouvre et
ferme les incidents toute seule, calcule la disponibilité sur 24 h, 7, 30 et
90 jours, et publie une page de statut publique qui se met à jour en direct.

## Ce que l'application montre de Soli

| Fonction | Ce qui est utilisé |
|---|---|
| Sondes en tâche de fond | `static cron` (toutes les 15 s, `SchedulerJob`) qui confie chaque sonde due à un `CheckMonitorJob` : les sondes tournent en parallèle sur les workers de jobs (`SOLI_JOB_WORKERS`) |
| Sonde HTTP(S) bornée | `HTTP.stream` : le statut arrive sans lire le corps ; le corps n'est lu (ligne à ligne, 512 Kio au plus, jamais au-delà du délai) que si un mot-clé est attendu. `follow_redirects` par sonde |
| Certificat TLS | `X509.peer_certificate(host, port, timeout)` : expiré → panne, bientôt expiré → dégradé + alerte |
| Heartbeat | une URL secrète `/ping/<jeton>` ; sans appel pendant l'intervalle + la marge, la sonde passe en panne |
| Protection SSRF | refus des cibles privées / locales à l'enregistrement (`TargetGuard`), en plus de la garde SSRF intégrée à `HTTP` et `X509` |
| Incidents automatiques | ouverture après N échecs consécutifs (2 par défaut), résolution au premier succès, chronologie |
| Incidents manuels | statut (enquête, identifié, sous surveillance, résolu), impact, suivis publiés |
| Maintenances | une fenêtre suspend incidents et alertes pour ses sondes ; ses contrôles sont gardés mais exclus de la disponibilité |
| Disponibilité et SLA | agrégats SDBQL : `COLLECT … AGGREGATE`, `PERCENTILE` (p50/p95), et un seul `UPSERT` qui replie les contrôles bruts en cumuls quotidiens (`RollupJob`, toutes les 5 min). Les barres sur 90 jours ne lisent jamais les contrôles bruts, purgés au bout de 14 jours (`PurgeChecksJob`) |
| Lectures groupées | `grouped(fn() { … })` : la page de statut lit sondes, maintenances, incidents ouverts et historique en un aller-retour |
| Temps réel | `sse_subscribe` / `sse_broadcast` : chaque changement d'état pousse un évènement ; la page (et le tableau de bord) se rafraîchit sans recharger, et une région `aria-live` l'annonce |
| Flux Atom | construit avec `Xml.build` (l'échappement est celui du constructeur) |
| API JSON | `/api/v1/status` (toutes les pages, ou `?page=<adresse>`), CORS ouvert, cache 15 s |
| Badges SVG | `/badge/<composant>.svg` |
| Alertes | e-mail (mailer Soli, `deliver_later`), webhook JSON et webhook Slack (`Webhook.enqueue` : réessais avec backoff, signature HMAC avec `SOLI_WEBHOOK_SECRET`). Une alerte par transition : la clé de l'envoi est (canal, évènement, sujet), une deuxième insertion échoue |
| Observabilité | `Metrics.increment("vigie.checks", tags: …)`, `Metrics.histogram("vigie.check.latency", …)` (secondes), `Metrics.time("vigie.check.duration", {"kind": …}) do … end`, `Metrics.gauge("vigie.monitors.down", …)` → `/_metrics` ou DogStatsD |
| Admin | `soli generate auth` (traduit), le form builder pour les formulaires, un tableau de bord avec sparklines de latence en SVG |

Accessibilité : chaque état est dit en mots et par une icône, jamais par la
seule couleur ; les barres sur 90 jours se distinguent aussi par leur motif
(hachures pour les perturbations, encoche pour les pannes, points pour la
maintenance, trait court sans données). Thème clair et sombre, mise en page
mobile (30 jours affichés sur petit écran).

## Lancer la démo

Il faut le binaire `soli` 2.32.0 ou plus récent et un `solidb`.

```bash
# 1. Une SoliDB jetable, sur un port à part
mkdir -p /tmp/vigie-db
SOLIDB_ADMIN_PASSWORD=vigiepass123 \
  solidb --host 127.0.0.1 --port 6799 --data-dir /tmp/vigie-db/data --no-lua --dev > /tmp/vigie-db/log 2>&1 &

# 2. La configuration
cp .env.example .env          # puis SOLIDB_PASSWORD=vigiepass123

# 3. Le schéma, puis la démo : une page « Solisoft », cinq sondes, 90 jours
#    d'historique synthétique, trois incidents passés, une maintenance demain
soli db:migrate up
soli db:seed

# 4. Le serveur
soli serve . --dev --port 5099
```

Puis :

- page publique : <http://localhost:5099/s/demo>
- administration : <http://localhost:5099/admin> — `demo@vigie.example` / `vigie-demo-2026`
  (ou la valeur de `VIGIE_DEMO_PASSWORD` au moment du seed)
- flux Atom : <http://localhost:5099/s/demo/incidents.atom>
- API : <http://localhost:5099/api/v1/status>
- badge : <http://localhost:5099/badge/site-soli.svg>
- métriques : <http://localhost:5099/_metrics> (avec `SOLI_METRICS=1`)

Les sondes de démo visent https://soli.solisoft.net (page et certificat),
https://example.com, un heartbeat « Sauvegarde nocturne », et — parce que
`.env.example` met `VIGIE_ALLOW_PRIVATE_TARGETS=1` et
`SOLI_HTTP_ALLOW_HOSTS=127.0.0.1:5099` — Vigie elle-même (`/health`). En
production, laissez `VIGIE_ALLOW_PRIVATE_TARGETS=0`.

Le heartbeat attend un appel par heure ; sa page dans l'administration donne
l'URL à appeler, par exemple depuis cron :

```bash
0 * * * * /usr/local/bin/backup.sh && curl -fsS http://localhost:5099/ping/<jeton>
```

Sur une base vide, le premier compte se crée sur `/signup` ; les inscriptions
se ferment ensuite.

## Variables d'environnement

| Variable | Rôle | Défaut |
|---|---|---|
| `SOLIDB_HOST`, `SOLIDB_DATABASE`, `SOLIDB_USERNAME`, `SOLIDB_PASSWORD` | la base | — |
| `APP_URL` | adresse publique (liens des alertes, du flux, du partage) | — |
| `VIGIE_ALLOW_PRIVATE_TARGETS` | `1` autorise les cibles privées / locales (démo, labo). Soli les refuse encore tant qu'elles ne sont pas dans `SOLI_HTTP_ALLOW_HOSTS` | `0` |
| `SOLI_HTTP_ALLOW_HOSTS` | adresses privées que Soli laisse sortir, ex. `127.0.0.1:5099` | — |
| `VIGIE_RAW_RETENTION_DAYS` | conservation des contrôles bruts | `14` |
| `VIGIE_DEMO_PASSWORD` | mot de passe du compte de démo | `vigie-demo-2026` |
| `SOLI_JOB_WORKERS` | sondes en parallèle | `1` |
| `SOLI_JOBS_RETENTION_SECS` | conservation des jobs terminés (une sonde = un job) | `604800` |
| `SOLI_METRICS` | `1` expose `/_metrics` | — |
| `SOLI_SMTP_HOST`, `SOLI_SMTP_FROM`… | alertes e-mail (en `--dev`, `/__soli/inbox` les capture) | — |
| `SOLI_WEBHOOK_SECRET` | signe les webhooks sortants (`X-Webhook-Signature`) | — |
| `AUTH_ATTEMPTS_PER_IP` | tentatives de connexion par adresse et 5 minutes | `15` |

## Tests

Les specs tournent contre une SoliDB à part (voir `.env.test`) :

```bash
soli fmt && soli lint
soli test --coverage --coverage-min 95.0
```

Elles couvrent l'évaluation des sondes (statut, mot-clé, redirections, refus,
TLS, heartbeat), la machine à états des incidents, les maintenances, la
déduplication des alertes, les calculs de disponibilité et les cumuls en SDBQL,
le rendu de la page, du flux, de l'API et des badges, l'authentification et
l'administration.

## Organisation

```
app/services/probe.sl          une sonde : ce qu'elle voit, sans rien écrire
app/services/checker.sl        enregistre un contrôle, met la sonde à jour, métriques, direct
app/services/incident_flow.sl  la machine à états des incidents automatiques
app/services/alerts.sl         e-mail, webhook JSON, Slack — une fois par transition
app/services/rollup.sl         cumuls quotidiens (SDBQL) et purge
app/services/uptime.sl         disponibilité 24 h / 7 / 30 / 90 j, barres sur 90 jours
app/services/status_board.sl   tout ce qu'affiche une page (HTML, API et badges lisent la même chose)
app/jobs/                      SchedulerJob (15 s), CheckMonitorJob, RollupJob (5 min), PurgeChecksJob (nuit)
```

Les heures sont en UTC. Pour qui modifie le code : sur Soli 2.32,
`DateTime#format` rend l'heure locale du serveur ; Vigie lit donc dates et
heures dans `to_iso`.
