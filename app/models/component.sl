# A line on a status page ("API", "Site web"), grouped, backed by monitors.
# Fields: page_id, name, slug (from the name: /badge/<slug>.svg), description,
# group_name, position, monitor_ids (Array).
class Component < Model
  validates("name", {"custom": "_validate"})
  validates(
    "name",
    {"custom": "_name_free", "on": "create"}
  )
  before_save("normalize")

  def normalize
    @name = @name.to_s.trim
    @group_name = @group_name.to_s.trim
    @slug = @name.slugify
    @position = @position.to_i
    @monitor_ids ||= []
    true
  end

  static def name_taken?(name, own_key)
    twin = Component.find_by("slug", name.to_s.trim.slugify)
    !twin.nil? && twin._key != own_key
  end

  private

  def _name_free
    return "un composant porte déjà ce nom (badge)" if Component.name_taken?(@name, nil)

    true
  end

  def _validate
    errors = []
    if @name.to_s.trim.blank?
      errors.push({"field": "name", "message": "est obligatoire"})
    end
    if @page_id.blank?
      errors.push({"field": "page_id", "message": "page obligatoire"})
    end
    @_errors = (@_errors ?? []) + errors
    true
  end
end
