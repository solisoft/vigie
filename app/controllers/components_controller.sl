# Components of a status page: a name, a group, the monitors behind it.
class ComponentsController < AdminController
  # POST /admin/pages/:id/composants
  def create
    page = StatusPage.find(params["id"])
    component = Component.create(@_attributes.merge({"page_id": page._key}))
    if component._errors
      flash("alert", "Composant refusé : #{component._errors.map { |error| error["message"] }.join(", ")}")
    else
      flash("notice", "Composant « #{component.name} » ajouté.")
    end
    redirect("/admin/pages/#{page._key}")
  end

  # GET /admin/composants/:id
  def edit
    @component = Component.find(params["id"])
    @page = StatusPage.find(@component.page_id)
    @monitor_choices = @_monitor_choices
    @nav = "pages"
    @title = "Composant « #{@component.name} »"
    @description = "Un composant de la page #{@page.title}"
  end

  # PATCH /admin/composants/:id
  def update
    @component = Component.find(params["id"])
    @_attributes.each do |field, value|
      @component[field] = value
    end
    @component.save
    if @component._errors.length > 0
      @page = StatusPage.find(@component.page_id)
      @monitor_choices = @_monitor_choices
      @nav = "pages"
      @title = "Composant « #{@component.name} »"
      return render("components/edit", {}, {"status": 422})
    end

    flash("notice", "Composant enregistré.")
    redirect("/admin/pages/#{@component.page_id}")
  end

  # DELETE /admin/composants/:id
  def destroy
    component = Component.find(params["id"])
    component.delete
    flash("notice", "Composant retiré.")
    redirect("/admin/pages/#{component.page_id}")
  end

  private

  def _attributes
    attributes = permit(params, {"name": true, "description": true, "group_name": true, "position": true, "monitor_ids": []})
    attributes["monitor_ids"] = @_selected_ids(params["monitor_ids"])
    attributes["position"] = attributes["position"].to_s.to_i
    attributes
  end
end
