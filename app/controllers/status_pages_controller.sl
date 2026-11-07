# The public status page, its live channel, its Atom feed and incident pages.
class StatusPagesController < Controller
  static {
    this.layout = "status"
  }

  # GET /s/:slug — the status page (public, cacheable for 15 s)
  def show
    page = @_published_page
    @board = StatusBoard.build(page, DateTime.utc.to_unix)
    @page = page
    @title = page.title
    @description = "#{this.board["status"]["label"]} — état des services de #{page.title}"
    @live_url = "/s/#{page.slug}/live"
    @feed_url = "/s/#{page.slug}/incidents.atom"
    page_response = render("status_pages/show")
    page_response["headers"]["Cache-Control"] = "public, max-age=15"
    page_response
  end

  # GET /s/:slug/live — Server-Sent Events: a "status" event on every change
  def live
    @_published_page
    sse_subscribe(req, LIVE_TOPIC)
  end

  # GET /s/:slug/incidents.atom — Atom feed of the page's incidents
  def feed
    board = StatusBoard.build(@_published_page, DateTime.utc.to_unix)
    {
      "status": 200,
      "headers": {"Content-Type": "application/atom+xml; charset=utf-8", "Cache-Control": "public, max-age=60"},
      "body": AtomFeed.build(board, Alerts.base_url)
    }
  end

  # GET /s/:slug/incidents/:id — one incident and its timeline
  def incident
    page = @_published_page
    record = Incident.find(params["id"])
    @page = page
    @incident = StatusBoard.incident_row(record, {})
    @title = "#{record.title} — #{page.title}"
    @description = "#{record.status_label} : #{record.title}"
  end

  private

  def _published_page
    page = StatusPage.find_by("slug", params["slug"].to_s)
    halt(404, "Page de statut introuvable") if page.nil? || !page.published
    page
  end
end
