# Status pages and their components.
class PagesController < AdminController
  # GET /admin/pages
  def index
    @pages = StatusPage.order("title").all
    @nav = "pages"
    @title = "Pages de statut"
    @description = "Les pages publiques et leurs composants"
  end

  # GET /admin/pages/nouvelle
  def new
    @page = StatusPage.new({"published": true})
    @_form_page("Nouvelle page")
  end

  # POST /admin/pages
  def create
    @page = StatusPage.create(@_permitted)
    return @_render_form("new", "Nouvelle page") if @page._errors

    flash("notice", "Page créée. Ajoutez-lui des composants.")
    redirect("/admin/pages/#{this.page._key}")
  end

  # GET /admin/pages/:id — the page's settings and components
  def edit
    @page = StatusPage.find(params["id"])
    @_form_page("Page « #{this.page.title} »")
  end

  # PATCH /admin/pages/:id
  def update
    @page = StatusPage.find(params["id"])
    @_permitted.each do |field, value|
      @page[field] = value
    end
    if StatusPage.slug_taken?(@page.slug.to_s.trim.downcase, @page._key)
      @page._errors = [{"field": "slug", "message": "déjà utilisé"}]
      return @_render_form("edit", "Page « #{this.page.title} »")
    end

    @page.save
    return @_render_form("edit", "Page « #{this.page.title} »") if @page._errors.length > 0

    flash("notice", "Page enregistrée.")
    redirect("/admin/pages/#{this.page._key}")
  end

  # DELETE /admin/pages/:id — the page and its components
  def destroy
    page = StatusPage.find(params["id"])
    Component.where({"page_id": page._key}).delete_all
    page.delete
    flash("notice", "Page supprimée.")
    redirect("/admin/pages")
  end

  private

  def _permitted
    attributes = permit(
      params,
      {
        "title": true,
        "slug": true,
        "description": true,
        "logo_url": true,
        "published": true
      }
    )
    attributes["published"] = attributes["published"].to_s == "true"
    attributes
  end

  def _form_page(title)
    @nav = "pages"
    @title = title
    @description = "Réglages d'une page de statut"
    @components = @page._key.nil? ? [] : @page.components
    @monitor_choices = @_monitor_choices
    @monitor_names = @monitor_choices.index_by("id")
    @component = Component.new({"position": @components.length})
  end

  def _render_form(view, title)
    @_form_page(title)
    render("pages/#{view}", {}, {"status": 422})
  end
end
