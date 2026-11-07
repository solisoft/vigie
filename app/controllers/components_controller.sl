# The services of a status page (components): what a visitor sees as one
# line, and the monitors that decide its state.
class ComponentsController < AdminController
  # POST /admin/pages/:id/composants — a new service from a name and an address
  def create
    page = StatusPage.find(params["id"])
    outcome = ServiceSetup.add(page, params["name"], params["url"], params["group_name"], params["position"])
    if outcome["errors"].length > 0
      messages = outcome["errors"].map do |error|
        error["message"]
      end
      flash("alert", "Service refusé : #{messages.join(", ")}")
      return redirect("/admin/pages/#{page._key}")
    end

    component = outcome["component"]
    flash("notice", "Service « #{component.name} » ajouté, avec #{component.monitor_ids.length} sonde(s).")
    redirect("/admin/composants/#{component._key}")
  end

  # GET /admin/composants/:id — the service, its monitors, what to add
  def edit
    @component = Component.find(params["id"])
    @_service_page
  end

  # PATCH /admin/composants/:id — name, group, order, description
  def update
    @component = Component.find(params["id"])
    @_attributes.each do |field, value|
      @component[field] = value
    end
    if Component.name_taken?(@component.name, @component._key)
      @component._errors = [{"field": "name", "message": "un service porte déjà ce nom (badge)"}]
    else
      @component.save
    end
    if @component._errors.length > 0
      @_service_page
      return render("components/edit", {}, {"status": 422})
    end

    flash("notice", "Service enregistré.")
    redirect("/admin/pages/#{this.component.page_id}")
  end

  # POST /admin/composants/:id/sondes — put an existing monitor behind it
  def attach
    component = Component.find(params["id"])
    monitor = Monitor.find(params["monitor_id"].to_s)
    unless component.monitor_ids.includes?(monitor._key)
      component.monitor_ids = component.monitor_ids + [monitor._key]
      component.save
    end
    flash("notice", "Sonde « #{monitor.name} » rattachée.")
    redirect("/admin/composants/#{component._key}")
  end

  # DELETE /admin/composants/:id/sondes/:monitor_id — take a monitor off it
  def detach
    component = Component.find(params["id"])
    monitor_id = params["monitor_id"].to_s
    component.monitor_ids = component.monitor_ids.filter do |id|
      id != monitor_id
    end
    component.save
    flash("notice", "Sonde détachée : elle continue de tourner, sans compter pour ce service.")
    redirect("/admin/composants/#{component._key}")
  end

  # DELETE /admin/composants/:id — the service, and the monitors only it used
  def destroy
    component = Component.find(params["id"])
    component.delete
    removed = Monitor.where("doc._key IN @ids", {"ids": component.monitor_ids}).all.filter do |monitor|
      monitor.components.length == 0
    end
    removed.each do |monitor|
      monitor.remove_with_history
    end
    flash("notice", "Service retiré, avec #{removed.length} sonde(s) qu'il était seul à utiliser.")
    redirect("/admin/pages/#{component.page_id}")
  end

  private

  def _service_page
    @page = StatusPage.find(@component.page_id)
    @monitors = Monitor.where("doc._key IN @ids", {"ids": @component.monitor_ids}).order("name").all
    @attachable = Monitor.order("name").all.filter do |monitor|
      !@component.monitor_ids.includes?(monitor._key)
    end
    @nav = "pages"
    @title = "Service « #{this.component.name} »"
    @description = "Un service de la page #{this.page.title}"
  end

  def _attributes
    attributes = permit(
      params,
      {
        "name": true,
        "description": true,
        "group_name": true,
        "position": true
      }
    )
    attributes["position"] = attributes["position"].to_s.to_i
    attributes
  end
end
