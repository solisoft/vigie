# What `soli db:seed` does under APP_ENV=production: the Solisoft status page
# with one component per production app (an HTTP monitor and a TLS
# certificate monitor each), plus the administrator account. No synthetic
# history, no demo account. Idempotent: what exists is kept, new sites added.
#
# The account comes from VIGIE_ADMIN_EMAIL and VIGIE_ADMIN_PASSWORD; without a
# password nothing is created and the first visit to /signup makes it.
#
# By default redirects are not followed: a 3xx (a sign-in redirect) answers
# "up". A site whose root only redirects is probed on the page that does the
# work (vv: /fr), or with redirects followed (vitaliseur.com). The sites behind
# Basic auth (401) and eui-data (404 at its root) get a wider range.
# lang.solisoft.net is left out: it answered 421 on 07/11/2026.
#
# The HTTP monitor of a listed site is kept in step with this list: a second
# run updates its URL, status range and redirect setting.
const PRODUCTION_SLUG = "solisoft"

# [component name, host, group, description, highest accepted status,
#  optional path (default "/"), optional follow_redirects (default false)]
const PRODUCTION_SITES = [
  ["Soli", "soli.solisoft.net", "Langage et outils", "Le site et la documentation du langage", 399],
  ["Score", "score.solisoft.net", "Langage et outils", "Le graveur de partitions", 399],
  ["EUI", "eui.solisoft.net", "Langage et outils", "Le protocole d'interface", 399],
  ["EUI data", "eui-data.solisoft.net", "Langage et outils", "Les données de démonstration d'EUI", 404],
  ["pdfx", "pdfx.fr", "Langage et outils", "Génération de PDF", 399],
  ["Ruby PDF", "ruby-pdf.solisoft.net", "Langage et outils", "PDF depuis Ruby", 399],
  ["MiniFusion", "minifusion.solisoft.net", "Langage et outils", "MiniFusion", 399],
  ["Proxy", "proxy.solisoft.net", "Plateforme", "soli-proxy", 399],
  ["SoliDB", "solidb.solisoft.net", "Plateforme", "La base de données", 399],
  ["SoliKV", "kv.solisoft.net", "Plateforme", "Le cache clé-valeur", 399],
  ["Event stream", "es.solisoft.net", "Plateforme", "Le flux d'événements", 399],
  ["One", "one.solisoft.net", "Plateforme", "Le cluster soli-one", 399],
  ["SFU", "sfu.solisoft.net", "Plateforme", "La visio", 399],
  ["Site Solisoft", "www.solisoft.net", "Applications", "solisoft.net", 399],
  ["Bonfire", "bonfire-app.pro", "Applications", "Gestion de projets", 399],
  ["CRM", "crm.solisoft.net", "Applications", "SoliCRM", 399],
  ["CRM Solisoft", "crm-solisoft.solisoft.net", "Applications", "Le CRM interne", 399],
  ["CRM démo (fr)", "crm-demo-fr.solisoft.net", "Applications", "Démonstration en français", 399],
  ["CRM démo (en)", "crm-demo-en.solisoft.net", "Applications", "Démonstration en anglais", 399],
  ["GRC", "grc.solisoft.net", "Applications", "SoliGRC", 399],
  ["Shop", "shop.solisoft.net", "Applications", "Comptoir", 399],
  ["Shop Solisoft", "shop-solisoft.solisoft.net", "Applications", "La boutique Solisoft", 399],
  ["Ember & Oak", "shop-ember-oak.solisoft.net", "Applications", "Boutique de démonstration", 399],
  ["Booking", "booking.solisoft.net", "Applications", "Escale", 399],
  ["DocRDV", "docrdv.solisoft.net", "Applications", "Rendez-vous médicaux", 399],
  ["Immo", "immo.solisoft.net", "Applications", "Programmes immobiliers neufs", 399],
  ["Loca", "loca.solisoft.net", "Applications", "Gestion locative", 399],
  ["soliAgri", "agri.solisoft.net", "Applications", "Le carnet des exploitations", 399],
  ["Pattes & Sabots", "pattes-et-sabots.solisoft.net", "Applications", "Le carnet de santé des animaux", 399],
  ["Boussole", "boussole.solisoft.net", "Applications", "Boussole", 399],
  ["Diététique", "dietetique.solisoft.net", "Applications", "Diététique", 399],
  ["Villa Vladimir", "vv.solisoft.net", "Clients", "Le site de la villa", 399, "/fr"],
  ["CSW admin", "csw-admin.solisoft.net", "Applications", "CSW, administration (accès protégé)", 401],
  ["CSW B2B", "csw-b2b.solisoft.net", "Applications", "CSW, boutique B2B (accès protégé)", 401],
  ["CSW B2C", "csw-b2c.solisoft.net", "Applications", "CSW, boutique B2C (accès protégé)", 401],
  ["Epiks properties", "properties.epiks.net", "Clients", "Epiks", 399],
  ["Le Télégraphe", "v2.letelegraphe.org", "Clients", "Le Télégraphe", 399],
  ["Privatisation Télégraphe", "privatisation.letelegraphe.org", "Clients", "Le Télégraphe, privatisation", 399],
  ["Vitaliseur", "vitaliseur.com", "Clients", "Redirige vers vitaliseurdemarion.fr", 399, "/", true],
  ["95 degrés", "95degres.com", "Clients", "95degres.com", 399],
  ["Batitel", "batitel.com", "Clients", "Le site de Batitel", 399],
  ["Batitel web", "batitelweb.com", "Clients", "batitelweb.com", 399],
  ["Batitel gestion", "gestion.batitel.com", "Clients", "L'outil de gestion de Batitel", 399]
]

class ProductionSetup
  static def run
    user = ProductionSetup.admin
    pairs = PRODUCTION_SITES.map do |site|
      ProductionSetup.site_monitors(site)
    end
    page = ProductionSetup.page(pairs)
    {
      "user": user&.email,
      "page": page.slug,
      "monitors": pairs.length * 2
    }
  end

  static def admin(email = getenv("VIGIE_ADMIN_EMAIL"), password = getenv("VIGIE_ADMIN_PASSWORD"))
    return nil if email.blank? || password.blank?

    existing = User.find_by("email", email)
    return existing unless existing.nil?

    user = User.new()
    user.email = email
    user.role = "admin"
    user.set_password(password)
    user.save
    user
  end

  # One HTTP monitor and one TLS certificate monitor per site.
  static def site_monitors(site)
    http = ProductionSetup.sync_monitor({
      "name": site[0],
      "kind": "http",
      "url": "https://#{site[1]}#{site.length > 5 ? site[5] : "/"}",
      "interval_s": 60,
      "degraded_ms": 1500,
      "failure_threshold": 2,
      "follow_redirects": site.length > 6 ? site[6] : false,
      "status_min": 200,
      "status_max": site[4]
    })
    tls = ProductionSetup.ensure_monitor({
      "name": "Certificat #{site[1]}",
      "kind": "tls",
      "host": site[1],
      "port": 443,
      "interval_s": 3600,
      "tls_warn_days": 14
    })
    [http, tls]
  end

  static def ensure_monitor(definition)
    Monitor.find_by("name", definition["name"]) ?? Monitor.create(definition)
  end

  # Like ensure_monitor, but an existing HTTP monitor takes the list's URL,
  # status range and redirect setting (and is probed again at once).
  static def sync_monitor(definition)
    monitor = Monitor.find_by("name", definition["name"])
    return Monitor.create(definition) if monitor.nil?

    changed = ["url", "status_max", "follow_redirects"].any? do |field|
      monitor[field] != definition[field]
    end
    return monitor unless changed

    ["url", "status_max", "follow_redirects"].each do |field|
      monitor[field] = definition[field]
    end
    monitor.next_check_at = 0
    monitor.save
    monitor
  end

  # The page, created once; components are added for sites it lacks.
  static def page(pairs)
    page = StatusPage.find_by("slug", PRODUCTION_SLUG)
    if page.nil?
      page = StatusPage.create({
        "slug": PRODUCTION_SLUG,
        "title": "Solisoft",
        "description": "État des services Solisoft, mis à jour en direct",
        "published": true,
        "listed": false
      })
    end
    PRODUCTION_SITES.each_with_index do |site, position|
      ProductionSetup.ensure_component(page, site, position, pairs[position])
    end
    page
  end

  static def ensure_component(page, site, position, pair)
    existing = Component.where({
      "page_id": page._key,
      "name": site[0]
    }).first
    return existing unless existing.nil?

    monitor_ids = pair.map do |monitor|
      monitor._key
    end
    Component.create({
      "page_id": page._key,
      "group_name": site[2],
      "name": site[0],
      "description": "#{site[3]} · #{site[1]}",
      "position": position,
      "monitor_ids": monitor_ids
    })
  end
end
