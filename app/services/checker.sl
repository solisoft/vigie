# Records a probe result and drives everything that follows from it:
# the monitor's state, the incident state machine, alerts, metrics and the
# live push to open status pages.
#
#   probe result ──► Check row ──► monitor state ──► incident opened/resolved
#                                                 └─► alert (once per transition)
const LIVE_TOPIC = "vigie:status"

class Checker
  # Probes `monitor` now and records the result. nil when there was nothing
  # to record (a heartbeat still inside its first window).
  # The whole run — probe and bookkeeping — is timed as
  # vigie.check.duration (seconds; Metrics.time takes its tags positionally).
  static def run(monitor, now)
    recorded_check = nil
    Metrics.time("vigie.check.duration", {"kind": monitor.kind}) do
      result = Probe.run(monitor, now)
      recorded_check = Checker.record(monitor, result, now) unless result.nil?
    end
    recorded_check
  end

  static def record(monitor, result, now)
    in_maintenance = Maintenance.covering?(monitor._key, now)
    ok = result["status"] != "down"
    recorded_check = Check.create({
      "monitor_id": monitor._key,
      "at": now,
      "day": Checker.day_of(now),
      "status": result["status"],
      "ok": ok,
      "latency_ms": result["latency_ms"],
      "http_status": result["http_status"],
      "error": result["error"],
      "maintenance": in_maintenance
    })
    previous_status = monitor.status
    failures = ok ? 0 : monitor.consecutive_failures.to_i + 1
    new_status = Checker.next_status(previous_status, result["status"], failures, monitor.failure_threshold)
    monitor.status = new_status
    monitor.consecutive_failures = failures
    monitor.failing_since = ok ? nil : (monitor.failing_since || now)
    monitor.last_checked_at = now
    monitor.last_latency_ms = result["latency_ms"]
    monitor.last_http_status = result["http_status"]
    monitor.last_error = result["error"]
    monitor.tls_days_left = result["tls_days_left"] unless result["tls_days_left"].nil?
    monitor.tls_not_after = result["tls_not_after"] unless result["tls_not_after"].nil?
    monitor.save
    IncidentFlow.after_check(monitor, result, in_maintenance, now)
    Checker.emit_metrics(monitor, result)
    Checker.announce(monitor) if new_status != previous_status
    recorded_check
  end

  # A failure only turns a monitor "down" once `threshold` of them happened in
  # a row; one blip leaves it as it was. Any success ends it.
  static def next_status(previous_status, probe_status, failures, threshold)
    return probe_status unless probe_status == "down"
    return "down" if failures >= threshold || previous_status == "down"

    previous_status.blank? ? "pending" : previous_status
  end

  static def emit_metrics(monitor, result)
    tags = {"kind": monitor.kind, "status": result["status"]}
    Metrics.increment("vigie.checks", tags: tags)
    latency = result["latency_ms"]
    # Seconds, so the default histogram buckets (1 ms … 10 s) fit.
    Metrics.histogram("vigie.check.latency", latency / 1000.0, tags: {"kind": monitor.kind}) unless latency.nil?
  end

  # Pushes a small event to every open status page and dashboard (SSE).
  static def announce(monitor)
    sse_broadcast(LIVE_TOPIC, {"monitor_id": monitor._key, "status": monitor.status}.to_json, "status")
  end

  # The UTC day. (Read from to_iso: DateTime#format renders the server's
  # local time on Soli 2.32.)
  static def day_of(unix)
    DateTime.from_unix(unix).to_iso.substring(0, 10)
  end
end
