# Migration: create_monitoring — the collections Vigie writes, and the indexes
# its hot queries need (due monitors, a monitor's recent checks, the 24 h scan,
# rollups by monitor/day, open incidents, a slug lookup).
const VIGIE_COLLECTIONS = ["monitors", "checks", "daily_rollups", "incidents", "incident_updates", "maintenances", "status_pages", "components", "alert_channels", "alert_deliveries"]

def up(db)
  VIGIE_COLLECTIONS.each do |name|
    db.create_collection(name)
  end
  db.create_index("monitors", "idx_monitors_due", ["paused", "next_check_at"], {})
  db.create_index("monitors", "idx_monitors_heartbeat", ["heartbeat_token"], {})
  db.create_index("checks", "idx_checks_monitor_at", ["monitor_id", "at"], {})
  db.create_index("checks", "idx_checks_at", ["at"], {})
  db.create_index("daily_rollups", "idx_rollups_monitor_day", ["monitor_id", "day"], {})
  db.create_index("incidents", "idx_incidents_status", ["status", "started_at"], {})
  db.create_index("incident_updates", "idx_incident_updates", ["incident_id", "at"], {})
  db.create_index("maintenances", "idx_maintenances_window", ["ends_at"], {})
  db.create_index("status_pages", "idx_status_pages_slug", ["slug"], {"unique": true})
  db.create_index("components", "idx_components_page", ["page_id", "position"], {})
end

def down(db)
  VIGIE_COLLECTIONS.each do |name|
    db.drop_collection(name)
  end
end
