# One-off (07/11/2026): "VV" becomes "Villa Vladimir", probed on /fr (its root
# only redirects). Renames the monitor and its component so the production
# seed then finds and updates them instead of adding a second pair.
monitor = Monitor.find_by("name", "VV")
unless monitor.nil?
  monitor.name = "Villa Vladimir"
  monitor.save
end
Component.where({"name": "VV"}).all.each do |component|
  component.name = "Villa Vladimir"
  component.group_name = "Clients"
  component.description = "Le site de la villa · vv.solisoft.net"
  component.save
end
print("VV renommé : #{monitor.nil? ? "rien à faire" : "ok"}")
