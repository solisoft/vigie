# The Atom feed of a status page's incidents, built with Soli's Xml builder
# (escaping is the builder's job, never string concatenation).
class AtomFeed
  static def build(board, base_url)
    page = board["page"]
    page_url = "#{base_url}/s/#{page.slug}"
    incidents = board["open_incidents"] + board["history"]
    updated = incidents.length > 0 ? AtomFeed.latest_change(incidents) : board["generated_at"]
    feed = Xml.build(
      "feed",
      {"xmlns": "http://www.w3.org/2005/Atom", "xml:lang": "fr"}
    ) do |root|
      root.add("id", "#{page_url}/incidents.atom")
      root.add("title", "#{page.title} — incidents")
      root.add("subtitle", "Incidents et maintenances publiés par Vigie")
      root.add("updated", AtomFeed.iso(updated))
      root.add("link", nil, {"rel": "self", "href": "#{page_url}/incidents.atom"})
      root.add("link", nil, {"rel": "alternate", "href": page_url})
      root.add("generator", "Vigie (Soli)")
      incidents.each do |incident|
        root.add("entry") do |entry|
          entry.add("id", "#{page_url}/incidents/#{incident["id"]}")
          entry.add("title", "[#{incident["status_label"]}] #{incident["title"]}")
          entry.add("link", nil, {
            "rel": "alternate",
            "href": "#{page_url}/incidents/#{incident["id"]}"
          })
          entry.add("published", AtomFeed.iso(incident["started_at"]))
          entry.add("updated", AtomFeed.iso(AtomFeed.latest_change([incident])))
          entry.add("author") do |author|
            author.add("name", page.title)
          end
          entry.add("content", AtomFeed.summary(incident), {"type": "text"})
        end
      end
    end
    feed.to_xml(indent: 2)
  end

  static def summary(incident)
    lines = incident["updates"].map do |update|
      "#{AtomFeed.iso(update["at"])} — #{update["status_label"]} : #{update["message"]}"
    end
    "#{incident["impact_label"]}. " + lines.join("\n")
  end

  static def latest_change(incidents)
    stamps = incidents.map do |incident|
      [incident["resolved_at"].to_i, incident["started_at"].to_i]
      + incident["updates"].map do |update|
        update["at"].to_i
      end
    end
    stamps.flatten.max
  end

  static def iso(unix)
    DateTime.from_unix(unix.to_i).to_iso.substring(0, 19) + "Z"
  end
end
