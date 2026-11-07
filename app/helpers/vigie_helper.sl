# Vigie view helpers: French dates, status icons and labels, percentages.
# (Helpers see builtins, not app classes: keep them self-contained.)

def french_month(month)
  ["janv.", "févr.", "mars", "avr.", "mai", "juin", "juil.", "août", "sept.", "oct.", "nov.", "déc."][month - 1]
end

# 1794045780 → "7 nov. 2026, 10:03 UTC"
def french_time(unix)
  return "—" if unix.nil? || unix.to_i == 0

  moment = DateTime.from_unix(unix.to_i)
  "#{moment.day} #{french_month(moment.month)} #{moment.year}, #{moment.format("%H:%M")} UTC"
end

def french_date(unix)
  return "—" if unix.nil? || unix.to_i == 0

  moment = DateTime.from_unix(unix.to_i)
  "#{moment.day} #{french_month(moment.month)} #{moment.year}"
end

def iso_time(unix)
  DateTime.from_unix(unix.to_i).format("%Y-%m-%dT%H:%M:%SZ")
end

# 99.95 → "99,95 %"; nil → "—"
def percent_label(value)
  return "—" if value.nil?

  shown = value >= 99.995 && value < 100 ? 99.99 : value.round(2)
  "#{shown.to_s.replace(".", ",")} %"
end

def latency_label(value)
  return "—" if value.nil?

  "#{value.round.to_i} ms"
end

# The status words, never the colour alone.
def status_text(status)
  match status {
    "up" => "Opérationnel",
    "degraded" => "Dégradé",
    "down" => "Panne",
    "maintenance" => "Maintenance",
    "paused" => "En pause",
    _ => "En attente"
  }
end

# A small inline SVG per status; aria-hidden because the text says it too.
def status_icon(status)
  path = match status {
    "up" => "<path d=\"M4 8.5l2.5 2.5L12 5.5\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2\" stroke-linecap=\"round\" stroke-linejoin=\"round\"/>",
    "ok" => "<path d=\"M4 8.5l2.5 2.5L12 5.5\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2\" stroke-linecap=\"round\" stroke-linejoin=\"round\"/>",
    "degraded" => "<path d=\"M8 4v5M8 11.5v.5\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2\" stroke-linecap=\"round\"/>",
    "partial" => "<path d=\"M8 4v5M8 11.5v.5\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2\" stroke-linecap=\"round\"/>",
    "down" => "<path d=\"M5 5l6 6M11 5l-6 6\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2\" stroke-linecap=\"round\"/>",
    "major" => "<path d=\"M5 5l6 6M11 5l-6 6\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2\" stroke-linecap=\"round\"/>",
    "maintenance" => "<path d=\"M5 11l4-4M9.5 4.5a2 2 0 102 2\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"1.8\" stroke-linecap=\"round\"/>",
    _ => "<path d=\"M8 4.5V8l2 1.5\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"1.8\" stroke-linecap=\"round\"/>"
  }
  "<svg class=\"icon\" viewBox=\"0 0 16 16\" width=\"16\" height=\"16\" aria-hidden=\"true\">#{path}</svg>"
end

def incident_status_text(status)
  match status {
    "identified" => "Identifié",
    "monitoring" => "Sous surveillance",
    "resolved" => "Résolu",
    _ => "Enquête en cours"
  }
end
