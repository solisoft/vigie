probe_base = ""

def probe_monitor(attributes)
  defaults = {
    "name": "Probe",
    "kind": "http",
    "http_method": "GET",
    "status_min": 200,
    "status_max": 399,
    "timeout_s": 3,
    "follow_redirects": true,
    "degraded_ms": 0,
    "interval_s": 60,
    "grace_s": 60,
    "tls_warn_days": 14
  }
  Monitor.new(defaults.merge(attributes))
end

describe("Probe.http") do
  before_all() do
    port = mock_http_server_start()
    probe_base = "http://127.0.0.1:" + port.to_s
    mock_http_route("/probe/ok", 200, "<html><body>Bienvenue sur la page d'accueil</body></html>")
    mock_http_route("/probe/down", 503, "maintenance")
    mock_http_route("/probe/notfound", 404, "nope")
    mock_http_route("/probe/redirect", 301, "", {"Location": "/probe/ok"})
  end

  test("is up on a 2xx, with a latency and the status code") do
    result = Probe.http(probe_monitor({"url": probe_base + "/probe/ok"}))
    assert_eq(result["status"], "up")
    assert_eq(result["http_status"], 200)
    assert_null(result["error"])
    assert(result["latency_ms"] >= 0)
  end

  test("is down on a status outside the expected range, and says so") do
    result = Probe.http(probe_monitor({"url": probe_base + "/probe/down"}))
    assert_eq(result["status"], "down")
    assert_eq(result["http_status"], 503)
    assert_eq(result["error"], "HTTP 503 (attendu 200–399)")
  end

  test("accepts a custom range, e.g. a 404 that is expected") do
    result = Probe.http(probe_monitor({
      "url": probe_base + "/probe/notfound",
      "status_min": 404,
      "status_max": 404
    }))
    assert_eq(result["status"], "up")
  end

  test("finds a keyword in the body") do
    result = Probe.http(probe_monitor({
      "url": probe_base + "/probe/ok",
      "keyword": "Bienvenue"
    }))
    assert_eq(result["status"], "up")
  end

  test("is down when the keyword is missing") do
    result = Probe.http(probe_monitor({
      "url": probe_base + "/probe/ok",
      "keyword": "Erreur fatale absente"
    }))
    assert_eq(result["status"], "down")
    assert_contains(result["error"], "Erreur fatale absente")
  end

  test("follows redirects when asked to") do
    result = Probe.http(probe_monitor({
      "url": probe_base + "/probe/redirect",
      "keyword": "Bienvenue"
    }))
    assert_eq(result["status"], "up")
    assert_eq(result["http_status"], 200)
  end

  test("judges the 3xx itself when redirects are not followed") do
    stays = Probe.http(probe_monitor({
      "url": probe_base + "/probe/redirect",
      "follow_redirects": false
    }))
    assert_eq(stays["http_status"], 301)
    assert_eq(stays["status"], "up")
    strict = Probe.http(probe_monitor({
      "url": probe_base + "/probe/redirect",
      "follow_redirects": false,
      "status_max": 299
    }))
    assert_eq(strict["status"], "down")
  end

  test("reports a refused connection in words") do
    result = Probe.http(probe_monitor({"url": "http://127.0.0.1:1/"}))
    assert_eq(result["status"], "down")
    assert_eq(result["error"], "Connexion refusée")
  end

  test("refuses a private target unless the flag allows it") do
    monitor = probe_monitor({"url": "http://[::1]:1/"})
    assert_eq(TargetGuard.url_refusal(monitor.url, false), "adresse privée ou locale refusée")
    result = Probe.http(probe_monitor({"url": "ftp://example.com/"}))
    assert_eq(result["status"], "down")
    assert_contains(result["error"], "Cible refusée")
  end

  test("is degraded when slower than the threshold") do
    monitor = probe_monitor({"degraded_ms": 100})
    assert_eq(Probe.evaluate_http(monitor, 200, 250, true)["status"], "degraded")
    assert_eq(Probe.evaluate_http(monitor, 200, 50, true)["status"], "up")
    assert_contains(Probe.evaluate_http(monitor, 200, 250, true)["error"], "250 ms")
  end
end

describe("Probe.describe_error") do
  test("names the usual transport failures") do
    assert_eq(Probe.describe_error("operation timed out", 5), "Délai dépassé (5 s)")
    assert_eq(Probe.describe_error("error: deadline has elapsed", 5), "Délai dépassé (5 s)")
    assert_eq(Probe.describe_error("SSRF: host rejected", 5), "Cible refusée (adresse privée)")
    assert_eq(Probe.describe_error("dns error: failed to lookup address", 5), "Résolution DNS impossible")
    assert_eq(Probe.describe_error("tcp connect error: Connection refused", 5), "Connexion refusée")
    assert_eq(Probe.describe_error("too many redirects (max 10)", 5), "Trop de redirections")
    assert_eq(Probe.describe_error("invalid peer certificate: Expired", 5), "Certificat TLS invalide")
    assert_eq(Probe.describe_error("TLS handshake with x failed", 5), "Poignée de main TLS impossible")
    assert_eq(Probe.describe_error("something else", 5), "something else")
    reset = "error sending request for url (https://x/): client error (SendRequest): "
    + "connection error: connection reset at 34:21"
    assert_eq(Probe.describe_error(reset, 5), "Connexion interrompue par le serveur")
    assert_eq(
      Probe.describe_error("hyper: connection closed before message completed", 5),
      "Connexion fermée avant la réponse"
    )
    assert_eq(Probe.describe_error("HTTP.stream: no answer in 10 s at 34:21", 10), "Délai dépassé (10 s)")
    assert_eq(Probe.describe_error("weird failure at 12:7", 5), "weird failure")
    assert_eq(
      Probe.describe_error("HTTP 502 (attendu 200–399)", 5),
      "HTTP 502 (attendu 200–399)",
      "French stays as is"
    )
  end

  test("says how long a silence lasted") do
    assert_eq(Probe.duration_label(45), "45 s")
    assert_eq(Probe.duration_label(600), "10 min")
    assert_eq(Probe.duration_label(7200), "2 h")
    assert_eq(Probe.duration_label(259200), "3 j")
  end
end

describe("Probe.tls") do
  test("rates a certificate by its days left") do
    monitor = probe_monitor({
      "kind": "tls",
      "host": "example.com",
      "port": 443
    })
    fresh = Probe.evaluate_tls(monitor, {
      "days_left": 80,
      "expired": false,
      "not_after": "2027-01-26T00:00:00Z"
    }, 40)
    assert_eq(fresh["status"], "up")
    assert_eq(fresh["tls_days_left"], 80)
    soon = Probe.evaluate_tls(monitor, {
      "days_left": 5,
      "expired": false,
      "not_after": "2026-11-12T00:00:00Z"
    }, 40)
    assert_eq(soon["status"], "degraded")
    assert_eq(soon["error"], "Le certificat expire dans 5 j")
    gone = Probe.evaluate_tls(monitor, {
      "days_left": -2,
      "expired": true,
      "not_after": "2026-11-05T00:00:00Z"
    }, 40)
    assert_eq(gone["status"], "down")
    assert_eq(gone["error"], "Certificat expiré depuis le 2026-11-05")
  end

  test("is down when the handshake fails") do
    result = Probe.tls(probe_monitor({
      "kind": "tls",
      "host": "127.0.0.1",
      "port": 1,
      "timeout_s": 2
    }))
    assert_eq(result["status"], "down")
    assert_not_null(result["error"])
  end

  test("refuses a host with invalid characters") do
    result = Probe.tls(probe_monitor({
      "kind": "tls",
      "host": "bad host",
      "port": 443
    }))
    assert_contains(result["error"], "Cible refusée")
  end
end

describe("Probe.heartbeat") do
  test("is up while pings keep coming") do
    now = 1800000000
    monitor = probe_monitor({
      "kind": "heartbeat",
      "interval_s": 300,
      "grace_s": 60,
      "last_heartbeat_at": now - 200
    })
    assert_eq(Probe.heartbeat(monitor, now)["status"], "up")
  end

  test("is down once interval + grace pass in silence") do
    now = 1800000000
    monitor = probe_monitor({
      "kind": "heartbeat",
      "interval_s": 300,
      "grace_s": 60,
      "last_heartbeat_at": now - 400
    })
    result = Probe.heartbeat(monitor, now)
    assert_eq(result["status"], "down")
    assert_eq(result["error"], "Aucun ping reçu depuis 6 min")
  end

  test("gives a never-pinged monitor its first window, then calls it down") do
    now = 1800000000
    young = probe_monitor({
      "kind": "heartbeat",
      "interval_s": 300,
      "grace_s": 60,
      "created_unix": now - 100
    })
    assert_null(Probe.heartbeat(young, now))
    old = probe_monitor({
      "kind": "heartbeat",
      "interval_s": 300,
      "grace_s": 60,
      "created_unix": now - 1000
    })
    assert_eq(Probe.heartbeat(old, now)["status"], "down")
  end

  test("dispatches by kind") do
    now = 1800000000
    monitor = probe_monitor({
      "kind": "heartbeat",
      "interval_s": 300,
      "grace_s": 60,
      "last_heartbeat_at": now - 10
    })
    assert_eq(Probe.run(monitor, now)["status"], "up")
  end
end

describe("Probe.tcp and Probe.udp") do
  test("a TCP port that accepts connections is up; one that refuses them is down") do
    port = mock_http_server_start()
    open_port = Probe.run(probe_monitor({
      "kind": "tcp",
      "host": "127.0.0.1",
      "port": port
    }), DateTime.utc.to_unix)
    unless defined("TCP")
      assert_eq(open_port["status"], "down")
      assert_contains(open_port["error"], "Soli 2.33")
      return nil
    end

    assert_eq(open_port["status"], "up")
    assert_not_null(open_port["latency_ms"])
    closed = Probe.run(probe_monitor({
      "kind": "tcp",
      "host": "127.0.0.1",
      "port": 1
    }), DateTime.utc.to_unix)
    assert_eq(closed["status"], "down")
  end

  test("a UDP port nobody answers on is down, with the reason in words") do
    monitor = probe_monitor({
      "kind": "udp",
      "host": "127.0.0.1",
      "port": 9,
      "udp_payload": "ping",
      "timeout_s": 1
    })
    silent = Probe.run(monitor, DateTime.utc.to_unix)
    assert_eq(silent["status"], "down")
    if defined("UDP")
      assert(["Port injoignable", "Aucune réponse en 1 s"].includes?(silent["error"]), silent["error"])
    else
      assert_contains(silent["error"], "Soli 2.33")
    end
  end

  test("evaluates what TCP.check and UDP.check answer") do
    udp = probe_monitor({
      "kind": "udp",
      "host": "game.example.com",
      "port": 27015,
      "keyword": "ok",
      "degraded_ms": 500
    })
    up = Probe.evaluate_port(
      udp,
      {
        "open": true,
        "latency_ms": 12.6,
        "reply": "status ok",
        "error": nil
      }
    )
    assert_eq(up["status"], "up")
    assert_eq(up["latency_ms"], 13)
    wrong = Probe.evaluate_port(
      udp,
      {
        "open": true,
        "latency_ms": 12.0,
        "reply": "busy",
        "error": nil
      }
    )
    assert_eq(wrong["status"], "down")
    assert_eq(wrong["error"], "Réponse sans « ok »")
    slow = Probe.evaluate_port(
      udp,
      {
        "open": true,
        "latency_ms": 900.0,
        "reply": "ok",
        "error": nil
      }
    )
    assert_eq(slow["status"], "degraded")
    closed = Probe.evaluate_port(
      udp,
      {"open": false, "error": "port unreachable: x:1 answered ICMP port unreachable"}
    )
    assert_eq(closed["error"], "Port injoignable")
    silent = Probe.evaluate_port(
      udp,
      {"open": false, "error": "no reply from x:1 within 3.0s"}
    )
    assert_eq(silent["error"], "Aucune réponse en 3 s")
    tcp = probe_monitor({
      "kind": "tcp",
      "host": "db.example.com",
      "port": 5432,
      "keyword": "ignored"
    })
    assert_eq(Probe.evaluate_port(
      tcp,
      {"open": true, "latency_ms": 2.0}
    )["status"], "up", "TCP reads no reply")
  end

  test("a private target is refused when private targets are off") do
    monitor = probe_monitor({
      "kind": "tcp",
      "host": "bad host!",
      "port": 22
    })
    assert_contains(Probe.run(monitor, DateTime.utc.to_unix)["error"], "Cible refusée")
    monitor = probe_monitor({
      "kind": "udp",
      "host": "bad host!",
      "port": 53,
      "udp_payload": "x"
    })
    assert_contains(Probe.run(monitor, DateTime.utc.to_unix)["error"], "Cible refusée")
  end
end
