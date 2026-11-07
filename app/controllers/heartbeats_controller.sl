# The secret URL a cron job calls to say "I ran".
class HeartbeatsController < Controller
  # GET /ping/:token
  # POST /ping/:token — records the heartbeat; recovers a down monitor at once
  def ping
    monitor = Monitor.find_by("heartbeat_token", params["token"].to_s)
    halt(404, "Inconnu") if monitor.nil? || monitor.kind != "heartbeat"

    now = DateTime.utc.to_unix
    monitor.last_heartbeat_at = now
    monitor.save
    Checker.record(monitor, Probe.result("up", nil, nil, nil), now) unless ["up", "degraded"].includes?(monitor.status)
    Metrics.increment("vigie.heartbeats")
    render_text("OK")
  end
end
