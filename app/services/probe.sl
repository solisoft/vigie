# Runs one probe and says what it saw — no database writes here.
#
# A result is a Hash: status ("up" | "degraded" | "down"), latency_ms,
# http_status, error (French, nil when up), tls_days_left, tls_not_after.
# A heartbeat that is not due yet answers nil: nothing to record.
const USER_AGENT = "Vigie/1.0 (+https://soli.solisoft.net; uptime monitor)"
const MAX_BODY_BYTES = 524288

class Probe
  static def run(monitor, now)
    match monitor.kind {
      "tls" => Probe.tls(monitor),
      "heartbeat" => Probe.heartbeat(monitor, now),
      _ => Probe.http(monitor),
    }
  end

  # HTTP(S): the body is streamed and read only when a keyword is expected,
  # never past MAX_BODY_BYTES nor past the monitor's timeout.
  static def http(monitor)
    refusal = TargetGuard.url_refusal(monitor.url, TargetGuard.allow_private?)
    return Probe.result("down", nil, nil, "Cible refusée : #{refusal}") unless refusal.nil?

    options = {
      "timeout": monitor.timeout_s,
      "follow_redirects": monitor.follow_redirects,
      "User-Agent": USER_AGENT
    }
    started = clock
    status_code = 0
    latency_ms = 0
    keyword_found = true
    try
      stream = HTTP.stream(monitor.http_method, monitor.url, options)
      status_code = stream.status
      latency_ms = Probe.elapsed_ms(started)
      wanted = monitor.keyword
      keyword_found = Probe.body_contains?(stream, wanted, started, monitor.timeout_s) if wanted.present?
    catch error
      return Probe.result(
        "down",
        Probe.elapsed_ms(started),
        nil,
        Probe.describe_error(error.to_s, monitor.timeout_s)
      )
    end
    Probe.evaluate_http(monitor, status_code, latency_ms, keyword_found)
  end

  static def evaluate_http(monitor, status_code, latency_ms, keyword_found)
    if status_code < monitor.status_min || status_code > monitor.status_max
      return Probe.result(
        "down",
        latency_ms,
        status_code,
        "HTTP #{status_code} (attendu #{monitor.status_min}–#{monitor.status_max})"
      )
    end

    missing = "Mot-clé « #{monitor.keyword} » absent de la réponse"
    return Probe.result("down", latency_ms, status_code, missing) unless keyword_found

    Probe.speed_verdict(monitor, latency_ms, status_code)
  end

  static def speed_verdict(monitor, latency_ms, status_code)
    slow = monitor.degraded_ms.to_i > 0 && latency_ms > monitor.degraded_ms
    if slow
      return Probe.result(
        "degraded",
        latency_ms,
        status_code,
        "Lent : #{latency_ms} ms (seuil #{monitor.degraded_ms} ms)"
      )
    end

    Probe.result("up", latency_ms, status_code, nil)
  end

  # Reads line by line until the keyword shows up, the cap, or the deadline.
  static def body_contains?(stream, keyword, started, timeout_s)
    read_bytes = 0
    line = stream.next_line
    while !line.nil?
      return true if line.includes?(keyword)

      read_bytes = read_bytes + line.length + 1
      return false if read_bytes > MAX_BODY_BYTES || clock - started > timeout_s

      line = stream.next_line
    end
    false
  end

  # TLS: a handshake, then the certificate's expiry. Expired → down, expiring
  # within tls_warn_days → degraded.
  static def tls(monitor)
    refusal = TargetGuard.host_refusal(monitor.host, TargetGuard.allow_private?)
    return Probe.result("down", nil, nil, "Cible refusée : #{refusal}") unless refusal.nil?

    started = clock
    peer = nil
    try
      peer = X509.peer_certificate(monitor.host, monitor.port, monitor.timeout_s)
    catch error
      return Probe.result(
        "down",
        Probe.elapsed_ms(started),
        nil,
        Probe.describe_error(error.to_s, monitor.timeout_s)
      )
    end
    Probe.evaluate_tls(monitor, peer, Probe.elapsed_ms(started))
  end

  static def evaluate_tls(monitor, peer, latency_ms)
    days_left = peer["days_left"]
    verdict = Probe.result("up", latency_ms, nil, nil)
    if peer["expired"] == true || days_left < 0
      verdict = Probe.result(
        "down",
        latency_ms,
        nil,
        "Certificat expiré depuis le #{peer["not_after"].to_s.substring(0, 10)}"
      )
    elsif days_left < monitor.tls_warn_days
      verdict = Probe.result("degraded", latency_ms, nil, "Le certificat expire dans #{days_left} j")
    end
    verdict["tls_days_left"] = days_left
    verdict["tls_not_after"] = peer["not_after"]
    verdict
  end

  # Heartbeat: down once interval + grace pass without a ping. A monitor that
  # has never been pinged gets that long from its creation.
  static def heartbeat(monitor, now)
    last_seen = monitor.last_heartbeat_at.to_i
    since = last_seen > 0 ? last_seen : monitor.created_unix.to_i
    silence = now - since
    deadline = monitor.interval_s + monitor.grace_s
    return Probe.result("up", nil, nil, nil) if last_seen > 0 && silence <= deadline
    return nil if last_seen == 0 && silence <= deadline

    Probe.result("down", nil, nil, "Aucun ping reçu depuis #{Probe.duration_label(silence)}")
  end

  static def result(status, latency_ms, http_status, error)
    {
      "status": status,
      "latency_ms": latency_ms,
      "http_status": http_status,
      "error": error
    }
  end

  static def elapsed_ms(started)
    ((clock - started) * 1000).round.to_i
  end

  # Transport errors, in words an on-call person reads at 3 am.
  static def describe_error(message, timeout_s)
    lowered = message.downcase
    if lowered.includes?("timed out") || lowered.includes?("timeout") || lowered.includes?("deadline")
      return "Délai dépassé (#{timeout_s} s)"
    end

    return "Cible refusée (adresse privée)" if lowered.includes?("ssrf")
    return "Résolution DNS impossible" if lowered.includes?("dns") || lowered.includes?("lookup")
    return "Connexion refusée" if lowered.includes?("refused")
    return "Trop de redirections" if lowered.includes?("redirect")
    return "Certificat TLS invalide" if lowered.includes?("certificate")
    return "Poignée de main TLS impossible" if lowered.includes?("handshake")

    message.truncate(160)
  end

  static def duration_label(seconds)
    return "#{seconds} s" if seconds < 120
    return "#{seconds / 60} min" if seconds < 7200
    return "#{seconds / 3600} h" if seconds < 172800

    "#{seconds / 86400} j"
  end
end
