# A latency sparkline as inline SVG: the line is latency, a red dot marks
# each failed check. Numbers only go into the markup — nothing to escape.
const SPARK_WIDTH = 120
const SPARK_HEIGHT = 28

class Sparkline
  # points: [{"latency_ms", "ok"}], oldest first.
  static def svg(points, label)
    return "" if points.length < 2

    measured = points.map { |point| point["latency_ms"].to_f }
    top = [measured.max, 1.0].max
    step = (SPARK_WIDTH - 2).to_f / (points.length - 1).to_f
    coords = points.each_with_index.map { |pair| Sparkline.coord(pair[1], pair[0]["latency_ms"].to_f, step, top) }
    line = coords.map { |xy| "#{xy[0]},#{xy[1]}" }.join(" ")
    area = "1,#{SPARK_HEIGHT} #{line} #{coords.last[0]},#{SPARK_HEIGHT}"
    failures = points.each_with_index.filter { |pair| pair[0]["ok"] != true }.map { |pair| Sparkline.dot(Sparkline.coord(pair[1], 0.0, step, top)) }
    "<svg class=\"spark\" viewBox=\"0 0 #{SPARK_WIDTH} #{SPARK_HEIGHT}\" role=\"img\" aria-label=\"#{Sparkline.clean(label)}\"><polygon class=\"area\" points=\"#{area}\"/><polyline class=\"line\" points=\"#{line}\"/>#{failures.join("")}</svg>"
  end

  static def coord(index, latency, step, top)
    x = (1 + index * step).round(1)
    y = (SPARK_HEIGHT - 2 - (latency / top) * (SPARK_HEIGHT - 6)).round(1)
    [x, y]
  end

  static def dot(xy)
    "<circle class=\"fail\" cx=\"#{xy[0]}\" cy=\"#{SPARK_HEIGHT - 3}\" r=\"2\"/>"
  end

  static def clean(text)
    text.replace("&", "et").replace("<", "").replace(">", "").replace("\"", "")
  end

  # monitor_id → points of the last `hours` hours, from one SDBQL read.
  static def recent(monitor_ids, now, hours)
    since = now - hours * 3600
    rows = @sdbql{
      FOR c IN checks
        FILTER c.at >= #{since} AND c.monitor_id IN #{monitor_ids}
        SORT c.at ASC
        RETURN { monitor_id: c.monitor_id, latency_ms: c.latency_ms, ok: c.ok }
    }
    Uptime.rows_or_raise(rows).group_by("monitor_id")
  end
end
