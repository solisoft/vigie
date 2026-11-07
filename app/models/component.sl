# A line on a status page ("API", "Site web"), grouped, backed by monitors.
# Fields: page_id, name, slug (from the name: /badge/<slug>.svg), description,
# group_name, position, monitor_ids (Array).
class Component < Model
  validates("name", {"custom": "_validate"})
  before_save("normalize")

  def normalize
    @name = @name.to_s.trim
    @group_name = @group_name.to_s.trim
    @slug = @name.slugify
    @position = @position.to_i
    @monitor_ids ||= []
    true
  end

  private

  def _validate
    errors = []
    errors.push({"field": "name", "message": "est obligatoire"}) if @name.to_s.trim.blank?
    errors.push({"field": "page_id", "message": "page obligatoire"}) if @page_id.blank?
    twin = Component.find_by("slug", @name.to_s.trim.slugify)
    errors.push({"field": "name", "message": "un composant porte déjà ce nom (badge)"}) if !twin.nil? && twin._key != @_key
    @_errors = (@_errors ?? []) + errors
    true
  end
end
