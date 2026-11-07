# Something Vigie watches: an HTTP(S) endpoint, a TLS certificate, or a
# heartbeat that a cron job sends to a secret URL.
#
# Fields: name, kind ("http" | "tls" | "heartbeat"), url, http_method,
# status_min, status_max, keyword, follow_redirects, timeout_s, degraded_ms,
# host, port, tls_warn_days, heartbeat_token, grace_s, interval_s,
# failure_threshold, paused.
# State written by the checker: status, consecutive_failures, last_checked_at,
# next_check_at, last_latency_ms, last_http_status, last_error,
# last_heartbeat_at, tls_days_left, tls_not_after.
const MONITOR_KINDS = [
  "http",
  "tls",
  "heartbeat"
]
const HTTP_METHODS = [
  "GET",
  "HEAD",
  "POST"
]
const MIN_INTERVAL_S = 30
const MAX_INTERVAL_S = 3600

class Monitor < Model
  validates("name", {"custom": "_validate"})
  before_save("normalize")

  def normalize
    @name = @name.to_s.trim
    @kind = "http" if @kind.blank?
    @interval_s = (@interval_s ?? 60).to_i
    @failure_threshold = (@failure_threshold ?? 2).to_i
    @timeout_s = (@timeout_s ?? 10).to_i
    @http_method = (@http_method || "GET").to_s.upcase
    @status_min = (@status_min ?? 200).to_i
    @status_max = (@status_max ?? 399).to_i
    @port = (@port ?? 443).to_i
    @tls_warn_days = (@tls_warn_days ?? 14).to_i
    @grace_s = (@grace_s ?? 60).to_i
    @degraded_ms = @degraded_ms.to_i
    @follow_redirects = @follow_redirects != false
    @paused = @paused == true
    @status ||= "pending"
    @consecutive_failures ||= 0
    @next_check_at ||= 0
    @created_unix ||= DateTime.utc.to_unix
    @heartbeat_token = Crypto.random_hex(16) if @kind == "heartbeat" && @heartbeat_token.blank?
    @url = @url.to_s.trim
    @host = @host.to_s.trim.downcase
    true
  end

  # The address a person reads: the URL, host:port, or the ping path.
  def target_label
    return "#{this.host}:#{this.port}" if @kind == "tls"
    return "/ping/#{this.heartbeat_token}" if @kind == "heartbeat"

    @url
  end

  def kind_label
    Monitor.label_for_kind(@kind)
  end

  def due?(now)
    !@paused && @next_check_at.to_i <= now
  end

  static def label_for_kind(kind)
    match kind {
      "tls" => "Certificat TLS",
      "heartbeat" => "Heartbeat",
      _ => "HTTP(S)",
    }
  end

  # Deletes the monitor with its checks and daily rollups, and takes it off
  # the services (components) that showed it.
  def remove_with_history
    key = @_key
    Check.where({"monitor_id": key}).delete_all
    DailyRollup.where({"monitor_id": key}).delete_all
    Component.where("@id IN doc.monitor_ids", {"id": key}).all.each do |component|
      component.monitor_ids = component.monitor_ids.filter do |id|
        id != key
      end
      component.save
    end
    @delete
  end

  # The services (components) a monitor stands behind.
  def components
    Component.where("@id IN doc.monitor_ids", {"id": @_key}).all
  end

  static def active
    Monitor.where({"paused": false}).order("name").all
  end

  # Form values arrive as strings: convert them before validation.
  static def from_form(attributes)
    cleaned = attributes.merge({})
    [
      "interval_s",
      "failure_threshold",
      "timeout_s",
      "status_min",
      "status_max",
      "port",
      "tls_warn_days",
      "grace_s",
      "degraded_ms"
    ].each do |field|
      next unless cleaned.has_key(field)

      if cleaned[field].to_s.trim.present?
        cleaned[field] = cleaned[field].to_s.trim.to_i
      else
        cleaned.delete(field)
      end
    end
    cleaned["follow_redirects"] = cleaned["follow_redirects"].to_s == "true"
    cleaned["paused"] = cleaned["paused"].to_s == "true"
    cleaned
  end

  private

  def _validate
    @normalize
    errors = []
    if @name.to_s.trim.blank?
      errors.push({"field": "name", "message": "est obligatoire"})
    end
    if @name.to_s.length > 80
      errors.push({"field": "name", "message": "80 caractères au plus"})
    end
    unless MONITOR_KINDS.includes?(@kind.to_s)
      errors.push({"field": "kind", "message": "type inconnu"})
    end
    interval = @interval_s.to_i
    if interval < MIN_INTERVAL_S || interval > MAX_INTERVAL_S
      errors.push({"field": "interval_s", "message": "entre 30 s et 1 h (3600 s)"})
    end
    threshold = @failure_threshold.to_i
    if threshold < 1 || threshold > 10
      errors.push({"field": "failure_threshold", "message": "entre 1 et 10"})
    end
    errors = errors + @_kind_errors
    @_errors = (@_errors ?? []) + errors
    true
  end

  def _kind_errors
    return @_http_errors if @kind == "http"
    return @_tls_errors if @kind == "tls"

    []
  end

  def _http_errors
    errors = []
    refusal = TargetGuard.url_refusal(@url.to_s.trim, TargetGuard.allow_private?)
    unless refusal.nil?
      errors.push({"field": "url", "message": refusal})
    end
    unless HTTP_METHODS.includes?(@http_method.to_s.upcase)
      errors.push({"field": "http_method", "message": "GET, HEAD ou POST"})
    end
    timeout = @timeout_s.to_i
    if timeout < 1 || timeout > 60
      errors.push({"field": "timeout_s", "message": "entre 1 et 60 s"})
    end
    low = @status_min.to_i
    high = @status_max.to_i
    if low < 100 || high > 599 || low > high
      errors.push({"field": "status_max", "message": "plage de statuts invalide"})
    end
    errors
  end

  def _tls_errors
    errors = []
    refusal = TargetGuard.host_refusal(@host.to_s.trim.downcase, TargetGuard.allow_private?)
    unless refusal.nil?
      errors.push({"field": "host", "message": refusal})
    end
    port = @port.to_i
    if port < 1 || port > 65535
      errors.push({"field": "port", "message": "port invalide"})
    end
    errors
  end
end
