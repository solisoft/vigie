# One-off (07/11/2026): stop watching csw-config.solisoft.net. Removes its
# component from the Solisoft page and its two monitors with their checks and
# rollups. Run with `soli db:seed db/seeds/20261107_unwatch_csw_config.sl`.
removed = []
Component.where({"name": "CSW config"}).all.each do |component|
  component.delete
  removed.push("composant #{component.name}")
end
["CSW config", "Certificat csw-config.solisoft.net"].each do |name|
  monitor = Monitor.find_by("name", name)
  next if monitor.nil?

  Check.where({"monitor_id": monitor._key}).delete_all
  DailyRollup.where({"monitor_id": monitor._key}).delete_all
  monitor.delete
  removed.push("sonde #{name}")
end
print("Retiré : #{removed.length > 0 ? removed.join(", ") : "rien (déjà fait)"}")
