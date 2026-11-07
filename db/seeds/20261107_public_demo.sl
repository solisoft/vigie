# One-off (07/11/2026): the public demo of vigie.solisoft.net. The landing
# page's « Démo en direct » showed the Solisoft page: it now shows /s/demo
# (DemoSeed.showcase: no account, no alert channels, no heartbeat), and the
# Solisoft page leaves the landing page — still public at /s/solisoft.
# Run with `soli db:seed db/seeds/20261107_public_demo.sl`. Idempotent.
summary = DemoSeed.showcase(DateTime.utc.to_unix)
print("Démo : page /s/#{summary["page"]}, #{summary["monitors"]} sondes, #{summary["rollups"]} journées d'historique")
solisoft = StatusPage.find_by("slug", "solisoft")
unless solisoft.nil?
  solisoft.listed = false
  solisoft.save
end
print("Page Solisoft masquée de l'accueil : #{solisoft.nil? ? "absente" : "ok"}")
