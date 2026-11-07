# Sends alerts: e-mail (Soli mailer, delivered by the job queue), generic JSON
# webhooks and Slack-compatible webhooks (Soli's Webhook queue: retried with
# backoff, HMAC-signed when SOLI_WEBHOOK_SECRET is set).
#
# Every (channel, event, subject) is sent once: the AlertDelivery key is that
# triple and inserting it twice fails, so a transition reached twice — a retried job, two workers — does
# not storm anybody.
const ALERT_EVENTS = {
  "incident.opened": "Incident ouvert",
  "incident.resolved": "Incident résolu",
  "tls.expiring": "Certificat bientôt expiré",
  "test": "Alerte de test"
}

class Alerts
  # → the number of channels actually alerted.
  static def dispatch(event, subject_id, details)
    sent = 0
    AlertChannel.where({"active": true}).all.each do |channel|
      # The insert is the lock: a second one with the same key fails.
      delivery = AlertDelivery.create(
        {
          "channel_id": channel._key,
          "event": event,
          "subject_id": subject_id,
          "summary": details["title"],
          "at": DateTime.utc.to_unix
        },
        {"key": Alerts.delivery_key(channel._key, event, subject_id)}
      )
      next if delivery._errors

      Alerts.deliver(channel, event, details)
      Metrics.increment("vigie.alerts", tags: {
        "channel": channel.kind,
        "event": event
      })
      sent = sent + 1
    end
    sent
  end

  static def delivery_key(channel_id, event, subject_id)
    "#{channel_id}_#{event.replace(".", "-")}_#{subject_id}"
  end

  static def deliver(channel, event, details)
    match channel.kind {
      "email" => Alerts.send_email(channel, event, details),
      "slack" => Webhook.enqueue(channel.target, Alerts.slack_payload(event, details), {"queue": "alerts"}),
      _ => Webhook.enqueue(channel.target, Alerts.json_payload(event, details), {"queue": "alerts"}),
    }
  end

  static def send_email(channel, event, details)
    AlertMailer.notify(channel.target, Alerts.subject_line(event, details), Alerts.text(event, details)).deliver_later
  end

  static def subject_line(event, details)
    "[Vigie] #{ALERT_EVENTS[event] ?? event} — #{details["title"]}"
  end

  static def text(event, details)
    lines = [
      "#{ALERT_EVENTS[event] ?? event} : #{details["title"]}",
      "Sonde : #{details["monitor"]} (#{details["target"]})"
    ]
    lines.push(details["detail"]) if details["detail"].present?
    incident_id = details["incident_id"]
    lines.push("Incident : #{Alerts.base_url}/admin/incidents/#{incident_id}") if incident_id.present?
    lines.join("\n")
  end

  static def json_payload(event, details)
    {
      "event": event,
      "title": details["title"],
      "monitor": details["monitor"],
      "target": details["target"],
      "detail": details["detail"],
      "incident_id": details["incident_id"],
      "sent_at": DateTime.utc.to_iso
    }
  end

  # Slack (and Mattermost, Rocket.Chat, Campfire…) read `text`.
  static def slack_payload(event, details)
    icon = event == "incident.resolved" ? ":white_check_mark:" : ":rotating_light:"
    {"text": "#{icon} *#{ALERT_EVENTS[event] ?? event}* — #{details["title"]}\n#{details["detail"].to_s}"}
  end

  static def base_url
    getenv("APP_URL").to_s.delete_suffix("/")
  end
end
