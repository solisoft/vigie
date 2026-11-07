# The public JSON API.
class ApiController < Controller
  # GET /api/v1/status — every published page (or ?page=<slug>), its overall
  # status, components with uptime, open incidents and maintenance
  # @tag Statut
  # @response 200 {"pages": [{"slug": "demo", "status": {"level": "ok"}}]}
  def status
    now = DateTime.utc.to_unix
    pages = StatusPage.where({"published": true}).order("title").all
    pages = pages.filter { |page| page.slug == params["page"] } if params["page"].present?
    return render_json({"error": "page inconnue"}, 404) if pages.length == 0 && params["page"].present?

    payload = {
      "generated_at": DateTime.from_unix(now).to_iso,
      "pages": pages.map { |page| @_page_payload(StatusBoard.build(page, now)) }
    }
    {
      "status": 200,
      "headers": {"Content-Type": "application/json", "Cache-Control": "public, max-age=15", "Access-Control-Allow-Origin": "*"},
      "body": payload.to_json
    }
  end

  private

  def _page_payload(board)
    page = board["page"]
    {
      "slug": page.slug,
      "title": page.title,
      "url": "#{Alerts.base_url}/s/#{page.slug}",
      "status": board["status"],
      "components": board["components"].map { |row| row.except(["bars"]) },
      "incidents": board["open_incidents"],
      "maintenances": board["maintenances"]
    }
  end
end
