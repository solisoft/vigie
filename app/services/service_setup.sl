# A service on a status page, the way a person thinks of it: a name and an
# address. Behind it, Vigie creates the HTTP monitor, the certificate monitor
# when the address is https (shared with any service on the same host), and
# the component that shows them. Nothing is left behind when a part is refused.
#
# The same defaults as ProductionSetup: probed every minute, slow above
# 1.5 s, an incident after 2 failures in a row.
class ServiceSetup
  # -> {"component": Component or nil, "errors": [{"field", "message"}]}
  static def add(page, name, url, group_name, position)
    name = name.to_s.trim
    url = url.to_s.trim
    errors = []
    if name.blank?
      errors.push({"field": "name", "message": "est obligatoire"})
    end
    if name.present? && Component.name_taken?(name, nil)
      errors.push({"field": "name", "message": "un service porte déjà ce nom"})
    end
    if url.blank?
      errors.push({"field": "url", "message": "est obligatoire"})
    end
    if errors.length > 0
      return {"component": nil, "errors": errors}
    end

    http = Monitor.create({
      "name": name,
      "kind": "http",
      "url": url,
      "interval_s": 60,
      "degraded_ms": 1500,
      "failure_threshold": 2,
      "follow_redirects": true
    })
    if http._errors
      return {"component": nil, "errors": http._errors}
    end

    monitor_ids = [http._key]
    certificate = ServiceSetup.certificate_for(url)
    monitor_ids.push(certificate._key) unless certificate.nil?
    component = Component.create({
      "page_id": page._key,
      "name": name,
      "group_name": group_name.to_s,
      "position": position.to_s.to_i,
      "monitor_ids": monitor_ids
    })
    if component._errors
      http.remove_with_history
      return {"component": nil, "errors": component._errors}
    end

    {"component": component, "errors": []}
  end

  # What the admin lists for a service: its address, its monitors and the
  # state they add up to (the worst, as on the public page).
  static def row(component, monitors_by_key)
    monitors = component.monitor_ids.map do |id|
      monitors_by_key[id]
    end.compact
    live = monitors.filter do |monitor|
      !monitor.paused
    end
    http = monitors.find do |monitor|
      monitor.kind == "http"
    end
    {
      "component": component,
      "address": http&.url,
      "status": StatusBoard.worst(live.map(&:status)),
      "monitors": monitors.length
    }
  end

  # The monitors list of the admin, as people read it: page by page, service
  # by service, then the monitors no service shows.
  # -> [{"title", "services": [{"component", "monitors": [Monitor]}]}]
  static def sections(pages, components, monitors)
    by_key = monitors.index_by("_key")
    shown = components.map(&:monitor_ids).flatten.uniq
    sections = pages.map do |page|
      services = components.filter do |component|
        component.page_id == page._key
      end.map do |component|
        {"component": component, "monitors": component.monitor_ids.map do |id|
          by_key[id]
        end.compact}
      end
      {
        "title": page.title,
        "services": services,
        "rows": ServiceSetup.rows(services)
      }
    end.filter do |section|
      section["services"].length > 0
    end
    orphans = monitors.filter do |monitor|
      !shown.includes?(monitor._key)
    end
    if orphans.length > 0
      services = [{"component": nil, "monitors": orphans}]
      sections.push({
        "title": "Sur aucune page",
        "services": services,
        "rows": ServiceSetup.rows(services)
      })
    end
    sections
  end

  # One table row per monitor; the service is named on its first row only.
  static def rows(services)
    services.map do |service|
      service["monitors"].each_with_index.map do |monitor, index|
        {
          "component": service["component"],
          "monitor": monitor,
          "first": index == 0
        }
      end
    end.flatten
  end

  # The certificate monitor of an https address's host: the existing one, or
  # a new one. nil for plain http.
  static def certificate_for(url)
    endpoint = ServiceSetup.tls_endpoint(url)
    return nil if endpoint.nil?

    existing = Monitor.where({
      "kind": "tls",
      "host": endpoint["host"],
      "port": endpoint["port"]
    }).first
    return existing unless existing.nil?

    certificate = Monitor.create({
      "name": "Certificat #{endpoint["host"]}",
      "kind": "tls",
      "host": endpoint["host"],
      "port": endpoint["port"],
      "interval_s": 3600,
      "tls_warn_days": 14
    })
    certificate._errors ? nil : certificate
  end

  # "https://exemple.fr:8443/sante" -> {"host": "exemple.fr", "port": 8443}
  static def tls_endpoint(url)
    text = url.to_s.trim
    return nil unless text.downcase.starts_with("https://")

    authority = text.substring(8, text.length).split("/")[0].split("?")[0].split("#")[0]
    authority = authority.split("@").last
    parts = authority.split(":")
    host = parts[0].downcase
    return nil if host.blank?

    port = parts.length > 1 ? parts[1].to_i : 443
    {"host": host, "port": port > 0 ? port : 443}
  end
end
