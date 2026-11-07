def alerts_reset
  [AlertChannel, AlertDelivery].each do |model|
    model.all.each do |record|
      record.delete
    end
  end
end

alerts_details = {
  "title": "API est indisponible",
  "monitor": "API",
  "target": "https://api.example.com",
  "detail": "HTTP 503",
  "incident_id": "inc-1"
}

describe("Alerts.dispatch") do
  before_each() do
    alerts_reset()
    Metrics.reset
  end

  test("sends once per channel, event and subject, whatever the number of calls") do
    AlertChannel.create({
      "name": "Hook",
      "kind": "webhook",
      "target": "https://hooks.example.com/a"
    })
    AlertChannel.create({
      "name": "Slack",
      "kind": "slack",
      "target": "https://hooks.slack.example.com/b"
    })
    assert_eq(Alerts.dispatch("incident.opened", "inc-1", alerts_details), 2)
    assert_eq(Alerts.dispatch("incident.opened", "inc-1", alerts_details), 0)
    assert_eq(Alerts.dispatch("incident.resolved", "inc-1", alerts_details), 2)
    assert_eq(AlertDelivery.count, 4)
    assert_eq(Metrics.value(
      "vigie.alerts",
      {"channel": "slack", "event": "incident.opened"}
    ), 1)
  end

  test("skips inactive channels") do
    AlertChannel.create({
      "name": "Off",
      "kind": "webhook",
      "target": "https://hooks.example.com/a",
      "active": false
    })
    assert_eq(Alerts.dispatch("incident.opened", "inc-2", alerts_details), 0)
    assert_eq(AlertDelivery.count, 0)
  end
end

describe("Alert payloads") do
  test("a generic webhook gets the whole event as JSON") do
    payload = Alerts.json_payload("incident.opened", alerts_details)
    assert_eq(payload["event"], "incident.opened")
    assert_eq(payload["title"], "API est indisponible")
    assert_eq(payload["incident_id"], "inc-1")
    assert_not_null(payload["sent_at"])
  end

  test("Slack gets a text line with an icon per kind of event") do
    opened = Alerts.slack_payload("incident.opened", alerts_details)
    assert_contains(opened["text"], ":rotating_light: *Incident ouvert*")
    resolved = Alerts.slack_payload("incident.resolved", alerts_details)
    assert_contains(resolved["text"], ":white_check_mark:")
  end

  test("the mail subject and text name the event, the monitor and the incident link") do
    assert_eq(
      Alerts.subject_line("tls.expiring", alerts_details),
      "[Vigie] Certificat bientôt expiré — API est indisponible"
    )
    text = Alerts.text("incident.opened", alerts_details)
    assert_contains(text, "Sonde : API (https://api.example.com)")
    assert_contains(text, "HTTP 503")
    assert_contains(text, "/admin/incidents/inc-1")
  end

  test("the delivery key holds channel, event and subject") do
    assert_eq(Alerts.delivery_key("c1", "incident.opened", "i9"), "c1_incident-opened_i9")
  end
end
