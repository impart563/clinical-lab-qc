///|
priv struct SvgChartBounds {
  low : Double
  high : Double
  left : Int
  right : Int
  top : Int
  bottom : Int
}

///|
fn svg_escape(value : String) -> String {
  let output = StringBuilder()
  for character in value.to_array() {
    match character {
      '&' => output.write_string("&amp;")
      '<' => output.write_string("&lt;")
      '>' => output.write_string("&gt;")
      '"' => output.write_string("&quot;")
      '\'' => output.write_string("&apos;")
      _ => output.write_char(character)
    }
  }
  output.to_string()
}

///|
fn svg_run_x(index : Int, run_count : Int, left : Int, right : Int) -> Int {
  if run_count <= 1 {
    (left + right) / 2
  } else {
    left + (right - left) * index / (run_count - 1)
  }
}

///|
fn svg_y(value : Double, bounds : SvgChartBounds) -> Int {
  let span = bounds.high - bounds.low
  let normalized = (value - bounds.low) / span
  bounds.bottom -
  (normalized * (bounds.bottom - bounds.top).to_double()).to_int()
}

///|
fn svg_color_for_level(index : Int) -> String {
  let colors = ["#2563eb", "#0f766e", "#9333ea", "#ea580c"]
  colors[index % colors.length()]
}

///|
fn svg_limit_color(sigma : Int) -> String {
  if sigma == 0 {
    "#1f2937"
  } else if sigma == 3 || sigma == -3 {
    "#dc2626"
  } else if sigma == 2 || sigma == -2 {
    "#d97706"
  } else {
    "#cbd5e1"
  }
}

///|
fn svg_limit_label(sigma : Int) -> String {
  if sigma == 0 {
    "mean"
  } else if sigma > 0 {
    "+" + sigma.to_string() + " SD"
  } else {
    sigma.to_string() + " SD"
  }
}

///|
fn svg_find_point(
  run : @run.QCRun,
  level_id : String,
  precision : Int,
) -> @run.ControlPoint? {
  for point in run.observations {
    if point.control_level_id == level_id {
      if point.precision == precision {
        return Some(point)
      }
      return None
    }
  }
  None
}

///|
fn svg_run_index(
  runs : Array[@run.QCRun],
  evidence : @evidence.EvidencePoint,
) -> Int? {
  for index, run in runs {
    if run.run_id == evidence.run_id && run.epoch.id == evidence.epoch_id {
      return Some(index)
    }
  }
  None
}

///|
fn svg_rule_offset(rule : @assay.Rule) -> Int {
  match rule {
    @assay.Rule12s => -9
    @assay.Rule13s => -6
    @assay.Rule22s => -3
    @assay.RuleR4s => 3
    @assay.Rule41s => 6
    @assay.Rule10x => 9
  }
}

///|
fn svg_disposition_color(disposition : @assay.RuleDisposition) -> String {
  match disposition {
    @assay.Disabled => "#6b7280"
    @assay.Warning => "#d97706"
    @assay.RequiresReview => "#dc2626"
  }
}

///|
fn svg_append_limit(
  output : StringBuilder,
  level : @assay.ControlLevel,
  bounds : SvgChartBounds,
  sigma : Int,
) -> Unit {
  let mean = level.mean.to_double()
  let sd = level.standard_deviation.to_double()
  let value = mean + sigma.to_double() * sd
  let y = svg_y(value, bounds)
  let color = svg_limit_color(sigma)
  let dash = if sigma == 0 { "" } else { " stroke-dasharray=\"5 4\"" }
  output.write_string(
    "<line class=\"control-limit\" data-sigma=\"" +
    sigma.to_string() +
    "\" x1=\"" +
    bounds.left.to_string() +
    "\" y1=\"" +
    y.to_string() +
    "\" x2=\"" +
    bounds.right.to_string() +
    "\" y2=\"" +
    y.to_string() +
    "\" stroke=\"" +
    color +
    "\" stroke-width=\"" +
    (if sigma == 0 { "2" } else { "1" }) +
    "\"" +
    dash +
    "/>\n",
  )
  output.write_string(
    "<text class=\"sigma-label\" x=\"" +
    (bounds.left - 8).to_string() +
    "\" y=\"" +
    (y + 4).to_string() +
    "\" text-anchor=\"end\">" +
    svg_limit_label(sigma) +
    "</text>\n",
  )
}

///|
fn svg_bounds(
  program : @assay.AssayProgram,
  level : @assay.ControlLevel,
  runs : Array[@run.QCRun],
  top : Int,
  bottom : Int,
) -> SvgChartBounds {
  let mean = level.mean.to_double()
  let sd = level.standard_deviation.to_double()
  let safe_sd = if sd > 0.0 { sd } else { 1.0 }
  let mut low = mean - 3.0 * safe_sd
  let mut high = mean + 3.0 * safe_sd
  for run in runs {
    match svg_find_point(run, level.id, program.precision) {
      Some(point) => {
        let value = point.value.to_double()
        if value < low {
          low = value
        }
        if value > high {
          high = value
        }
      }
      None => ()
    }
  }
  let mut span = high - low
  if span <= 0.0 {
    low = mean - 1.0
    high = mean + 1.0
    span = high - low
  }
  let padding = span * 0.05
  {
    low: low - padding,
    high: high + padding,
    left: 92,
    right: 1068,
    top,
    bottom,
  }
}

///|
fn svg_append_epoch_boundaries(
  output : StringBuilder,
  runs : Array[@run.QCRun],
  bounds : SvgChartBounds,
) -> Unit {
  for index in 1..<runs.length() {
    let previous = runs[index - 1]
    let current = runs[index]
    if !previous.epoch.has_same_metadata(current.epoch) {
      let x1 = svg_run_x(index - 1, runs.length(), bounds.left, bounds.right)
      let x2 = svg_run_x(index, runs.length(), bounds.left, bounds.right)
      let x = (x1 + x2) / 2
      output.write_string(
        "<line class=\"epoch-boundary\" x1=\"" +
        x.to_string() +
        "\" y1=\"" +
        bounds.top.to_string() +
        "\" x2=\"" +
        x.to_string() +
        "\" y2=\"" +
        bounds.bottom.to_string() +
        "\" stroke=\"#7c3aed\" stroke-width=\"2\" stroke-dasharray=\"7 5\"/>\n",
      )
      output.write_string(
        "<text class=\"epoch-label\" x=\"" +
        (x + 4).to_string() +
        "\" y=\"" +
        (bounds.top + 13).to_string() +
        "\">epoch: " +
        svg_escape(current.epoch.id) +
        "</text>\n",
      )
    }
  }
}

///|
fn svg_append_series_segment(
  output : StringBuilder,
  points : Array[String],
  level_id : String,
  segment_index : Int,
  color : String,
) -> Unit {
  if points.length() >= 2 {
    output.write_string(
      "<polyline class=\"qc-series\" data-control-level=\"" +
      svg_escape(level_id) +
      "\" data-segment=\"" +
      segment_index.to_string() +
      "\" points=\"" +
      points.join(" ") +
      "\" fill=\"none\" stroke=\"" +
      color +
      "\" stroke-width=\"2\" stroke-linejoin=\"round\"/>\n",
    )
  }
}

///|
fn svg_append_series(
  output : StringBuilder,
  program : @assay.AssayProgram,
  level : @assay.ControlLevel,
  level_index : Int,
  runs : Array[@run.QCRun],
  bounds : SvgChartBounds,
) -> Unit {
  let color = svg_color_for_level(level_index)
  let mut points : Array[String] = []
  let mut segment_index = 0
  for index, run in runs {
    if index > 0 && !runs[index - 1].epoch.has_same_metadata(run.epoch) {
      segment_index = segment_index + 1
      svg_append_series_segment(output, points, level.id, segment_index, color)
      points = []
    }
    match svg_find_point(run, level.id, program.precision) {
      Some(point) => {
        let x = svg_run_x(index, runs.length(), bounds.left, bounds.right)
        let y = svg_y(point.value.to_double(), bounds)
        points.push(x.to_string() + "," + y.to_string())
        output.write_string(
          "<circle class=\"qc-observation\" data-run-id=\"" +
          svg_escape(run.run_id) +
          "\" cx=\"" +
          x.to_string() +
          "\" cy=\"" +
          y.to_string() +
          "\" r=\"3\" fill=\"" +
          color +
          "\"><title>" +
          svg_escape(run.run_id) +
          " / " +
          svg_escape(level.id) +
          ": " +
          svg_escape(format_scaled(point.value, program.precision)) +
          " " +
          svg_escape(program.unit) +
          "</title></circle>\n",
        )
      }
      None => {
        segment_index = segment_index + 1
        svg_append_series_segment(
          output,
          points,
          level.id,
          segment_index,
          color,
        )
        points = []
      }
    }
  }
  segment_index = segment_index + 1
  svg_append_series_segment(output, points, level.id, segment_index, color)
}

///|
fn svg_append_evidence_markers(
  output : StringBuilder,
  program : @assay.AssayProgram,
  level : @assay.ControlLevel,
  runs : Array[@run.QCRun],
  trajectory : @evidence.Trajectory,
  bounds : SvgChartBounds,
) -> Unit {
  for assessment in trajectory.assessments {
    for hit in assessment.hits {
      let disposition = program.disposition_for(hit.rule)
      let color = svg_disposition_color(disposition)
      for evidence in hit.evidence {
        if evidence.control_level_id == level.id {
          match svg_run_index(runs, evidence) {
            Some(index) => {
              let base_x = svg_run_x(
                index,
                runs.length(),
                bounds.left,
                bounds.right,
              )
              let x = base_x + svg_rule_offset(hit.rule)
              let y = svg_y(evidence.value.to_double(), bounds)
              let common = " class=\"rule-evidence\" data-rule=\"" +
                svg_escape(hit.rule.name()) +
                "\" data-disposition=\"" +
                audit_rule_disposition_name(disposition) +
                "\""
              let tooltip = "<title>" +
                svg_escape(hit.rule.name()) +
                " / " +
                svg_escape(assessment.run_id) +
                " / " +
                svg_escape(level.id) +
                ": " +
                svg_escape(format_scaled(evidence.value, evidence.precision)) +
                " " +
                svg_escape(evidence.unit) +
                "</title>"
              match disposition {
                @assay.Warning =>
                  output.write_string(
                    "<circle" +
                    common +
                    " cx=\"" +
                    x.to_string() +
                    "\" cy=\"" +
                    y.to_string() +
                    "\" r=\"7\" fill=\"" +
                    color +
                    "\" stroke=\"#ffffff\" stroke-width=\"2\">" +
                    tooltip +
                    "</circle>\n",
                  )
                @assay.RequiresReview =>
                  output.write_string(
                    "<path" +
                    common +
                    " d=\"M " +
                    x.to_string() +
                    " " +
                    (y - 8).to_string() +
                    " L " +
                    (x + 8).to_string() +
                    " " +
                    y.to_string() +
                    " L " +
                    x.to_string() +
                    " " +
                    (y + 8).to_string() +
                    " L " +
                    (x - 8).to_string() +
                    " " +
                    y.to_string() +
                    " Z\" fill=\"" +
                    color +
                    "\" stroke=\"#ffffff\" stroke-width=\"2\">" +
                    tooltip +
                    "</path>\n",
                  )
                @assay.Disabled =>
                  output.write_string(
                    "<circle" +
                    common +
                    " cx=\"" +
                    x.to_string() +
                    "\" cy=\"" +
                    y.to_string() +
                    "\" r=\"7\" fill=\"#ffffff\" stroke=\"" +
                    color +
                    "\" stroke-width=\"2\">" +
                    tooltip +
                    "</circle>\n",
                  )
              }
            }
            None => ()
          }
        }
      }
    }
  }
}

///|
fn svg_append_x_axis(
  output : StringBuilder,
  runs : Array[@run.QCRun],
  bounds : SvgChartBounds,
) -> Unit {
  let stride = if runs.length() <= 16 { 1 } else { (runs.length() + 15) / 16 }
  for index, run in runs {
    if index % stride == 0 || index == runs.length() - 1 {
      let x = svg_run_x(index, runs.length(), bounds.left, bounds.right)
      output.write_string(
        "<text class=\"run-tick\" x=\"" +
        x.to_string() +
        "\" y=\"" +
        (bounds.bottom + 18).to_string() +
        "\" text-anchor=\"middle\">" +
        svg_escape(run.sequence.to_string()) +
        "</text>\n",
      )
    }
  }
}

///|
fn svg_append_legend(output : StringBuilder) -> Unit {
  output.write_string(
    "<g class=\"legend\" font-family=\"sans-serif\" font-size=\"12\">\n",
  )
  let mut x = 70
  for sigma in [-3, -2, -1, 0, 1, 2, 3] {
    let color = svg_limit_color(sigma)
    let dash = if sigma == 0 { "" } else { " stroke-dasharray=\"4 3\"" }
    output.write_string(
      "<line x1=\"" +
      x.to_string() +
      "\" y1=\"48\" x2=\"" +
      (x + 22).to_string() +
      "\" y2=\"48\" stroke=\"" +
      color +
      "\"" +
      dash +
      "/>\n<text x=\"" +
      (x + 27).to_string() +
      "\" y=\"52\">" +
      svg_limit_label(sigma) +
      "</text>\n",
    )
    x = x + 96
  }
  output.write_string(
    "<circle cx=\"770\" cy=\"48\" r=\"6\" fill=\"#d97706\"/><text x=\"782\" y=\"52\">Warning</text>\n",
  )
  output.write_string(
    "<path d=\"M 888 41 L 895 48 L 888 55 L 881 48 Z\" fill=\"#dc2626\"/><text x=\"901\" y=\"52\">Requires review</text>\n",
  )
  output.write_string(
    "<circle cx=\"1030\" cy=\"48\" r=\"6\" fill=\"#ffffff\" stroke=\"#6b7280\" stroke-width=\"2\"/><text x=\"1042\" y=\"52\">Disabled</text>\n",
  )
  output.write_string("</g>\n")
}

///|
/// Render a deterministic, offline Levey–Jennings SVG with epoch breaks,
/// missing-value gaps, and rule-evidence markers.
pub fn render_levey_jennings_svg(
  program : @assay.AssayProgram,
  runs : Array[@run.QCRun],
  trajectory : @evidence.Trajectory,
) -> String {
  let panel_height = 250
  let header_height = 76
  let width = 1120
  let height = header_height + program.levels.length() * panel_height + 20
  let output = StringBuilder()
  output.write_string(
    "<svg xmlns=\"http://www.w3.org/2000/svg\" role=\"img\" viewBox=\"0 0 " +
    width.to_string() +
    " " +
    height.to_string() +
    "\" width=\"" +
    width.to_string() +
    "\" height=\"" +
    height.to_string() +
    "\">\n",
  )
  output.write_string("<title>Levey-Jennings QC chart — ")
  output.write_string(svg_escape(program.assay_id))
  output.write_string(
    "</title>\n<desc>Offline chart of QC observations, control limits, epoch boundaries, and rule evidence.</desc>\n",
  )
  output.write_string(
    "<rect width=\"100%\" height=\"100%\" fill=\"#ffffff\"/>\n",
  )
  output.write_string(
    "<text x=\"24\" y=\"28\" font-family=\"sans-serif\" font-size=\"18\" font-weight=\"bold\">Levey-Jennings — ",
  )
  output.write_string(svg_escape(program.assay_id))
  output.write_string(" (")
  output.write_string(svg_escape(program.unit))
  output.write_string(")</text>\n")
  svg_append_legend(output)
  for level_index, level in program.levels {
    let panel_y = header_height + level_index * panel_height
    let bounds = svg_bounds(program, level, runs, panel_y + 40, panel_y + 190)
    output.write_string(
      "<g class=\"control-panel\" data-control-level=\"" +
      svg_escape(level.id) +
      "\">\n<rect x=\"34\" y=\"" +
      panel_y.to_string() +
      "\" width=\"1052\" height=\"230\" rx=\"4\" fill=\"#ffffff\" stroke=\"#d1d5db\"/>\n",
    )
    output.write_string(
      "<text x=\"52\" y=\"" +
      (panel_y + 23).to_string() +
      "\" font-family=\"sans-serif\" font-size=\"14\" font-weight=\"bold\">Control: " +
      svg_escape(level.id) +
      "</text>\n",
    )
    for sigma in -3..<4 {
      svg_append_limit(output, level, bounds, sigma)
    }
    svg_append_epoch_boundaries(output, runs, bounds)
    svg_append_series(output, program, level, level_index, runs, bounds)
    svg_append_evidence_markers(
      output, program, level, runs, trajectory, bounds,
    )
    svg_append_x_axis(output, runs, bounds)
    if runs.length() == 0 {
      output.write_string(
        "<text x=\"560\" y=\"" +
        (panel_y + 120).to_string() +
        "\" text-anchor=\"middle\" font-family=\"sans-serif\">No QC runs</text>\n",
      )
    }
    output.write_string("</g>\n")
  }
  output.write_string("</svg>\n")
  output.to_string()
}
