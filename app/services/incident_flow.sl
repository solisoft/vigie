# The incident state machine for automatic incidents.
#
#   up ──(N failures in a row)──► down: open an incident, alert "incident.opened"
#   down ──(one success)────────► up:   resolve it,       alert "incident.resolved"
#
# Inside a maintenance window a failing monitor opens nothing and alerts no
# one; if it still fails once the window closes, the next check opens the
# incident. Alerts are deduplicated per transition by Alerts.dispatch.
class IncidentFlow
  static def after_check(monitor, result, in_maintenance, now)
    open_incident = Incident.open_auto_for(monitor._key)
    if result["status"] != "down"
      IncidentFlow.resolve(open_incident, monitor, result, now) unless open_incident.nil?
    elsif monitor.status == "down" && open_incident.nil? && !in_maintenance
      IncidentFlow.open(monitor, result, now)
    end
    IncidentFlow.watch_certificate(monitor, result, in_maintenance)
  end

  static def open(monitor, result, now)
    incident = Incident.create({
      "title": "#{monitor.name} est indisponible",
      "kind": "auto",
      "status": "investigating",
      "impact": "outage",
      "monitor_ids": [monitor._key],
      "started_at": monitor.failing_since || now
    })
    message = "Vigie a constaté #{monitor.consecutive_failures} échecs consécutifs : #{result["error"]}"
    IncidentUpdate.create({"incident_id": incident._key, "status": "investigating", "message": message, "at": now})
    Alerts.dispatch("incident.opened", incident._key, {
      "title": incident.title,
      "monitor": monitor.name,
      "target": monitor.target_label,
      "detail": result["error"],
      "incident_id": incident._key
    })
    Metrics.increment("vigie.incidents.opened", tags: {"kind": monitor.kind})
    incident
  end

  static def resolve(incident, monitor, result, now)
    duration = Probe.duration_label(now - incident.started_at.to_i)
    latency = result["latency_ms"].nil? ? "" : " (#{result["latency_ms"]} ms)"
    incident.post_update("resolved", "Le service répond de nouveau#{latency}. Durée de l'incident : #{duration}.", now)
    Alerts.dispatch("incident.resolved", incident._key, {
      "title": incident.title,
      "monitor": monitor.name,
      "target": monitor.target_label,
      "detail": "Rétabli après #{duration}",
      "incident_id": incident._key
    })
    incident
  end

  # One alert per certificate (its not_after date is in the key): a renewed
  # certificate that nears expiry again alerts again.
  static def watch_certificate(monitor, result, in_maintenance)
    days_left = result["tls_days_left"]
    return nil if days_left.nil? || in_maintenance
    return nil if days_left >= monitor.tls_warn_days

    Alerts.dispatch("tls.expiring", "#{monitor._key}_#{result["tls_not_after"].to_s.substring(0, 10)}", {
      "title": "Certificat de #{monitor.host} : #{days_left} j restants",
      "monitor": monitor.name,
      "target": monitor.target_label,
      "detail": "Expire le #{result["tls_not_after"].to_s.substring(0, 10)}",
      "incident_id": nil
    })
  end
end
