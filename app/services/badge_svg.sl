# A flat two-part SVG badge — "API | opérationnel" — for READMEs and
# dashboards. The status is in the text, not only the colour.
const BADGE_COLORS = {"up": "#1f7a4d", "degraded": "#a15c07", "down": "#b42318", "maintenance": "#2f5fb3", "pending": "#6b7280"}

class BadgeSvg
  static def render(label, status, status_text)
    color = BADGE_COLORS[status] ?? BADGE_COLORS["pending"]
    left = BadgeSvg.text_width(label) + 12
    right = BadgeSvg.text_width(status_text) + 12
    width = left + right
    safe_label = BadgeSvg.escape(label)
    safe_status = BadgeSvg.escape(status_text)
    parts = [
      "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"#{width}\" height=\"20\" role=\"img\" aria-label=\"#{safe_label} : #{safe_status}\">",
      "<title>#{safe_label} : #{safe_status}</title>",
      "<rect width=\"#{left}\" height=\"20\" rx=\"3\" fill=\"#14213d\"/>",
      "<rect x=\"#{left}\" width=\"#{right}\" height=\"20\" rx=\"3\" fill=\"#{color}\"/>",
      "<rect x=\"#{left}\" width=\"4\" height=\"20\" fill=\"#{color}\"/>",
      "<g fill=\"#fff\" font-family=\"Verdana,DejaVu Sans,sans-serif\" font-size=\"11\">",
      "<text x=\"6\" y=\"14\">#{safe_label}</text><text x=\"#{left + 6}\" y=\"14\">#{safe_status}</text></g></svg>"
    ]
    parts.join("")
  end

  # Verdana 11px averages ~6.6px a character; good enough for a badge.
  static def text_width(text)
    (text.chars.length * 6.6).round.to_i
  end

  static def escape(text)
    text.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;").replace("\"", "&quot;")
  end
end
