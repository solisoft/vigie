# One-off (07/11/2026): stop watching vv.solisoft.net. Removes its component
# from the Solisoft page, its two monitors with their checks and rollups, and
# the incidents that concerned only them (with their updates), so no open
# incident is left pointing at a monitor that no longer exists.
# Run with `soli db:seed db/seeds/20261107_unwatch_vv.sl`. Idempotent.
removed = []
Component.where({"name": "Villa Vladimir"}).all.each do |component|
  component.delete
  removed.push("composant #{component.name}")
end
["Villa Vladimir", "Certificat vv.solisoft.net"].each do |name|
  monitor = Monitor.find_by("name", name)
  next if monitor.nil?

  Incident.where("@id IN doc.monitor_ids", {"id": monitor._key}).all.each do |incident|
    next if incident.monitor_ids.length > 1

    IncidentUpdate.where({"incident_id": incident._key}).delete_all
    incident.delete
    removed.push("incident « #{incident.title} »")
  end
  Check.where({"monitor_id": monitor._key}).delete_all
  DailyRollup.where({"monitor_id": monitor._key}).delete_all
  monitor.delete
  removed.push("sonde #{name}")
end
print("Retiré : #{removed.length > 0 ? removed.join(", ") : "rien (déjà fait)"}")
