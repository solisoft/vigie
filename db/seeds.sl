# `soli db:seed`. In production: the Solisoft page and one component per
# production app (ProductionSetup). Elsewhere: the demo with synthetic history
# (DemoSeed). Both are idempotent.
if getenv("APP_ENV") == "production"
  summary = ProductionSetup.run
  print("Vigie : page /s/#{summary["page"]}, #{summary["monitors"]} sondes")
  if summary["user"].nil?
    print("Aucun compte créé (VIGIE_ADMIN_EMAIL / VIGIE_ADMIN_PASSWORD absents) : /signup crée le premier")
  else
    print("Admin : #{summary["user"]}")
  end
else
  summary = DemoSeed.run(DateTime.utc.to_unix)
  print("Vigie : page /s/#{summary["page"]}, #{summary["monitors"]} sondes")
  print("#{summary["rollups"]} journées d'historique synthétique")
  print("Admin : #{summary["user"]} / mot de passe VIGIE_DEMO_PASSWORD (par défaut : #{DEMO_PASSWORD})")
end
