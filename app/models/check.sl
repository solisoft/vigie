# One probe of one monitor: what came back and how long it took.
#
# Fields: monitor_id, at (unix s), day ("YYYY-MM-DD", UTC), status
# ("up" | "degraded" | "down"), ok (Bool: up or degraded), latency_ms,
# http_status, error, maintenance (Bool: taken inside a maintenance window —
# kept, but left out of the uptime figures).
class Check < Model
  static def recent_for(monitor_id, limit)
    Check.where({"monitor_id": monitor_id}).order("at", "desc").limit(limit).all
  end
end
