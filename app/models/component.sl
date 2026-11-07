# A line on a status page ("API", "Site web"), grouped, backed by monitors.
# Fields: page_id, name, description, group_name, position, monitor_ids (Array).
class Component < Model
  validates("name", {"custom": "_validate"})
  before_save("normalize")

  def normalize
    @name = @name.to_s.trim
    @group_name = @group_name.to_s.trim
    @position = @position.to_i
    @monitor_ids ||= []
    true
  end

  # Lowercase slug for /badge/<slug>.svg — unique enough within a demo.
  def badge_slug
    @name.slugify
  end

  private

  def _validate
    errors = []
    errors.push({"field": "name", "message": "est obligatoire"}) if @name.to_s.trim.blank?
    errors.push({"field": "page_id", "message": "page obligatoire"}) if @page_id.blank?
    @_errors = (@_errors ?? []) + errors
    true
  end
end
