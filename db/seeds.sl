# Vigie demo seed — run with `soli db:seed`. Idempotent (see DemoSeed).
summary = DemoSeed.run(DateTime.utc.to_unix)
print("Vigie : page /s/#{summary["page"]}, #{summary["monitors"]} sondes, #{summary["rollups"]} jours d'historique synthétique")
print("Admin : #{summary["user"]} / mot de passe VIGIE_DEMO_PASSWORD (par défaut : #{DEMO_PASSWORD})")
