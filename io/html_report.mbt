///|
fn html_escape(value : String) -> String {
  let output = StringBuilder()
  for character in value.to_array() {
    match character {
      '&' => output.write_string("&amp;")
      '<' => output.write_string("&lt;")
      '>' => output.write_string("&gt;")
      '"' => output.write_string("&quot;")
      '\'' => output.write_string("&#39;")
      _ => output.write_char(character)
    }
  }
  output.to_string()
}

///|
fn html_status_class(status : @evidence.AssessmentStatus) -> String {
  match status {
    @evidence.InControl => "in-control"
    @evidence.Warning => "warning"
    @evidence.RequiresReview => "requires-review"
    @evidence.Incomplete => "incomplete"
  }
}

///|
fn html_find_run(runs : Array[@run.QCRun], run_index : Int) -> @run.QCRun? {
  runs.get(run_index)
}

///|
fn html_find_first_assessment(
  trajectory : @evidence.Trajectory,
  status : @evidence.AssessmentStatus,
) -> Int? {
  for index, assessment in trajectory.assessments {
    if assessment.status == status {
      return Some(index)
    }
  }
  None
}

///|
fn html_find_epoch_run_index(
  runs : Array[@run.QCRun],
  epoch : @epoch.QCEpoch,
) -> Int? {
  for index, run in runs {
    if run.epoch.has_same_metadata(epoch) {
      return Some(index)
    }
  }
  None
}

///|
fn html_find_evidence_run_index(
  runs : Array[@run.QCRun],
  evidence : @evidence.EvidencePoint,
) -> Int? {
  for index, run in runs {
    if run.run_id == evidence.run_id &&
      run.sequence == evidence.sequence &&
      run.epoch.id == evidence.epoch_id {
      return Some(index)
    }
  }
  None
}

///|
fn html_append_status_card(
  output : StringBuilder,
  label : String,
  count : Int,
  status : @evidence.AssessmentStatus,
  trajectory : @evidence.Trajectory,
) -> Unit {
  output.write_string("<div class=\"card\">")
  match html_find_first_assessment(trajectory, status) {
    Some(index) => {
      output.write_string("<a href=\"#run-")
      output.write_string(index.to_string())
      output.write_string("\">")
    }
    None => ()
  }
  output.write_string(label)
  output.write_string("<strong>")
  output.write_string(count.to_string())
  output.write_string("</strong>")
  match html_find_first_assessment(trajectory, status) {
    Some(_) => output.write_string("</a>")
    None => ()
  }
  output.write_string("</div>\n")
}

///|
fn html_append_evidence(
  output : StringBuilder,
  evidence : @evidence.EvidencePoint,
  runs : Array[@run.QCRun],
) -> Unit {
  output.write_string("<tr><td>")
  match html_find_evidence_run_index(runs, evidence) {
    Some(index) => {
      output.write_string("<a href=\"#run-")
      output.write_string(index.to_string())
      output.write_string("\">")
      output.write_string(html_escape(evidence.run_id))
      output.write_string("</a>")
    }
    None => output.write_string(html_escape(evidence.run_id))
  }
  output.write_string(
    "</td><td>" +
    html_escape(evidence.control_level_id) +
    "</td><td>" +
    format_scaled(evidence.value, evidence.precision) +
    " " +
    html_escape(evidence.unit) +
    "</td><td>" +
    format_scaled(evidence.mean, evidence.precision) +
    "</td><td>" +
    format_scaled(evidence.standard_deviation, evidence.precision) +
    "</td><td>" +
    format_scaled(evidence.threshold, evidence.precision) +
    "</td><td>" +
    direction_name(evidence.direction) +
    "</td></tr>\n",
  )
}

///|
fn html_append_assessment(
  output : StringBuilder,
  program : @assay.AssayProgram,
  run_index : Int,
  assessment : @evidence.RunAssessment,
  runs : Array[@run.QCRun],
) -> Unit {
  output.write_string("<details class=\"run\" id=\"run-")
  output.write_string(run_index.to_string())
  output.write_string("\"><summary><span class=\"badge ")
  output.write_string(html_status_class(assessment.status))
  output.write_string("\">")
  output.write_string(assessment.status.name())
  output.write_string("</span><strong>Run ")
  output.write_string(html_escape(assessment.run_id))
  output.write_string("</strong><span>sequence ")
  output.write_string(assessment.sequence.to_string())
  output.write_string("</span></summary><div class=\"run-body\">\n")
  match html_find_run(runs, run_index) {
    Some(run) => {
      output.write_string("<dl class=\"run-meta\"><dt>Timestamp</dt><dd>")
      output.write_string(html_escape(run.timestamp))
      output.write_string("</dd><dt>Epoch</dt><dd>")
      output.write_string(html_escape(run.epoch.id))
      output.write_string("</dd><dt>Reagent lot</dt><dd>")
      output.write_string(html_escape(run.epoch.reagent_lot))
      output.write_string("</dd><dt>Control lot</dt><dd>")
      output.write_string(html_escape(run.epoch.control_lot))
      output.write_string("</dd><dt>Calibration</dt><dd>")
      output.write_string(html_escape(run.epoch.calibration_id))
      output.write_string("</dd><dt>Program version</dt><dd>")
      output.write_string(html_escape(run.epoch.program_version))
      output.write_string("</dd></dl>\n")
      output.write_string(
        "<h4>Observations</h4>\n<table><thead><tr><th>Control</th><th>Value</th><th>Precision</th></tr></thead><tbody>\n",
      )
      if run.observations.length() == 0 {
        output.write_string("<tr><td colspan=\"3\">No observations</td></tr>\n")
      } else {
        for point in run.observations {
          output.write_string(
            "<tr><td>" +
            html_escape(point.control_level_id) +
            "</td><td>" +
            format_scaled(point.value, point.precision) +
            " " +
            html_escape(program.unit) +
            "</td><td>" +
            point.precision.to_string() +
            "</td></tr>\n",
          )
        }
      }
      output.write_string("</tbody></table>\n")
    }
    None => output.write_string("<p>Run snapshot unavailable.</p>\n")
  }
  if assessment.hits.length() == 0 {
    output.write_string("<p>No rule hits.</p>\n")
  } else {
    output.write_string("<h4>Rule signals and evidence</h4>\n")
    for hit in assessment.hits {
      output.write_string("<section class=\"signal\"><h5>")
      output.write_string(hit.rule.name())
      output.write_string(" <span class=\"muted\">")
      output.write_string(scope_name(hit.scope))
      output.write_string("</span></h5><p>")
      output.write_string(html_escape(hit.reason))
      output.write_string("</p>\n")
      if hit.evidence.length() > 0 {
        output.write_string(
          "<table><thead><tr><th>Run</th><th>Control</th><th>Observed</th><th>Mean</th><th>SD</th><th>Threshold distance</th><th>Direction</th></tr></thead><tbody>\n",
        )
        for evidence in hit.evidence {
          html_append_evidence(output, evidence, runs)
        }
        output.write_string("</tbody></table>\n")
      }
      output.write_string("</section>\n")
    }
  }
  for issue in assessment.input_issues {
    output.write_string("<p class=\"issue\"><strong>Input issue [")
    output.write_string(issue.code.name())
    output.write_string("]:</strong> ")
    output.write_string(html_escape(issue.message))
    output.write_string("</p>\n")
  }
  output.write_string("</div></details>\n")
}

///|
/// Render a deterministic, self-contained HTML audit report with an embedded
/// Levey–Jennings chart. The document has no scripts, external styles, or
/// network dependencies and can be opened offline.
pub fn render_audit_html(
  program : @assay.AssayProgram,
  runs : Array[@run.QCRun],
  trajectory : @evidence.Trajectory,
) -> String {
  let summary = audit_summary(runs, trajectory)
  let output = StringBuilder()
  output.write_string(
    "<!doctype html>\n<html lang=\"en\"><head><meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">\n<title>QC audit report — ",
  )
  output.write_string(html_escape(program.assay_id))
  output.write_string("</title><style>\n")
  output.write_string(
    " :root{color-scheme:light;--ink:#172033;--muted:#596579;--line:#d9e0ea;--panel:#f6f8fb;--green:#166534;--green-bg:#dcfce7;--amber:#92400e;--amber-bg:#fef3c7;--red:#991b1b;--red-bg:#fee2e2;--gray:#374151;--gray-bg:#e5e7eb}*{box-sizing:border-box}body{margin:0;background:#eef2f7;color:var(--ink);font:15px/1.55 system-ui,-apple-system,Segoe UI,sans-serif}main{max-width:1200px;margin:0 auto;padding:28px 20px 56px}header,.panel{background:#fff;border:1px solid var(--line);border-radius:12px;padding:22px;margin-bottom:18px}header p,.muted,small{color:var(--muted)}h1{font-size:clamp(1.6rem,4vw,2.3rem);margin:.2rem 0}h2{font-size:1.35rem;margin:0 0 16px}h3{font-size:1.05rem;margin:24px 0 10px}h4{margin:18px 0 8px}h5{margin:0 0 4px}.cards{display:grid;grid-template-columns:repeat(auto-fit,minmax(145px,1fr));gap:10px}.card{border:1px solid var(--line);border-radius:9px;padding:13px;background:var(--panel)}.card strong{display:block;font-size:1.5rem}.badge{display:inline-block;border-radius:99px;padding:2px 9px;font-size:.8rem;font-weight:700;margin-right:10px}.in-control{color:var(--green);background:var(--green-bg)}.warning{color:var(--amber);background:var(--amber-bg)}.requires-review{color:var(--red);background:var(--red-bg)}.incomplete{color:var(--gray);background:var(--gray-bg)}table{width:100%;border-collapse:collapse;margin:8px 0 18px;font-size:.9rem}th,td{text-align:left;vertical-align:top;padding:8px;border-bottom:1px solid var(--line);overflow-wrap:anywhere}th{background:var(--panel)}.chart{overflow-x:auto}.chart svg{display:block;max-width:100%;height:auto}.run{border:1px solid var(--line);border-radius:9px;margin:10px 0;background:#fff}.run summary{cursor:pointer;padding:12px;display:flex;gap:12px;align-items:center;flex-wrap:wrap}.run-body{padding:4px 16px 16px;border-top:1px solid var(--line)}.run-meta{display:grid;grid-template-columns:minmax(120px,180px) 1fr;gap:4px 14px}.run-meta dt{font-weight:650}.run-meta dd{margin:0;overflow-wrap:anywhere}.signal{border-left:3px solid #f59e0b;padding:8px 12px;margin:12px 0;background:#fffbeb}.issue{border-left:3px solid #dc2626;padding:9px 12px;background:#fef2f2;overflow-wrap:anywhere}.empty{color:var(--muted);font-style:italic}footer{color:var(--muted);font-size:.9rem;margin-top:24px}@media print{body{background:white}main{max-width:none;padding:0}.panel,header{break-inside:avoid}.run{break-inside:avoid}.chart{overflow:visible}.run:not([open]) .run-body{display:block}}\n",
  )
  output.write_string(
    "</style></head><body><main>\n<header><p>Offline QC audit report · schema version 1</p><h1>",
  )
  output.write_string(html_escape(program.assay_id))
  output.write_string("</h1><p>Measurement unit: ")
  output.write_string(html_escape(program.unit))
  output.write_string(" · Decimal precision: ")
  output.write_string(program.precision.to_string())
  output.write_string("</p></header>\n")

  output.write_string(
    "<section class=\"panel\"><h2>Summary</h2><div class=\"cards\">\n",
  )
  output.write_string("<div class=\"card\">Input runs<strong>")
  output.write_string(summary.input_runs.to_string())
  output.write_string(
    "</strong></div><div class=\"card\">Assessed runs<strong>",
  )
  output.write_string(summary.assessed_runs.to_string())
  output.write_string("</strong></div>\n")
  html_append_status_card(
    output,
    "In control",
    summary.in_control,
    @evidence.InControl,
    trajectory,
  )
  html_append_status_card(
    output,
    "Warning",
    summary.warning,
    @evidence.Warning,
    trajectory,
  )
  html_append_status_card(
    output,
    "Requires review",
    summary.requires_review,
    @evidence.RequiresReview,
    trajectory,
  )
  html_append_status_card(
    output,
    "Incomplete",
    summary.incomplete,
    @evidence.Incomplete,
    trajectory,
  )
  output.write_string("<div class=\"card\">Rule hits<strong>")
  output.write_string(summary.total_rule_hits.to_string())
  output.write_string("</strong></div><div class=\"card\">Track issues<strong>")
  output.write_string(summary.track_issues.to_string())
  output.write_string("</strong></div></div><h3>Rule hit counts</h3>\n")
  if summary.total_rule_hits == 0 {
    output.write_string("<p class=\"empty\">No rule hits.</p>\n")
  } else {
    output.write_string(
      "<table><thead><tr><th>Rule</th><th>Count</th><th>Disposition</th></tr></thead><tbody>\n",
    )
    for hit in summary.rule_hits {
      if hit.count > 0 {
        output.write_string("<tr><td>")
        output.write_string(hit.rule.name())
        output.write_string("</td><td>")
        output.write_string(hit.count.to_string())
        output.write_string("</td><td>")
        output.write_string(
          audit_rule_disposition_name(program.disposition_for(hit.rule)),
        )
        output.write_string("</td></tr>\n")
      }
    }
    output.write_string("</tbody></table>\n")
  }
  output.write_string("</section>\n")

  output.write_string(
    "<section class=\"panel\"><h2>Assay configuration</h2><p>Program: <strong>",
  )
  output.write_string(html_escape(program.assay_id))
  output.write_string("</strong>; unit: ")
  output.write_string(html_escape(program.unit))
  output.write_string("; precision: ")
  output.write_string(program.precision.to_string())
  output.write_string(
    "</p><table><thead><tr><th>Control</th><th>Mean</th><th>Standard deviation</th><th>Required</th></tr></thead><tbody>\n",
  )
  for level in program.levels {
    output.write_string("<tr><td>")
    output.write_string(html_escape(level.id))
    output.write_string("</td><td>")
    output.write_string(format_scaled(level.mean, program.precision))
    output.write_string("</td><td>")
    output.write_string(
      format_scaled(level.standard_deviation, program.precision),
    )
    output.write_string("</td><td>")
    output.write_string(if level.required { "Yes" } else { "No" })
    output.write_string("</td></tr>\n")
  }
  output.write_string("</tbody></table><h3>Rule dispositions</h3>\n")
  output.write_string(
    "<table><thead><tr><th>Rule</th><th>Disposition</th></tr></thead><tbody>\n",
  )
  for rule in audit_rule_order() {
    output.write_string("<tr><td>")
    output.write_string(rule.name())
    output.write_string("</td><td>")
    output.write_string(
      audit_rule_disposition_name(program.disposition_for(rule)),
    )
    output.write_string("</td></tr>\n")
  }
  output.write_string("</tbody></table><h3>QC epochs</h3>\n")
  if summary.epoch_runs.length() == 0 {
    output.write_string("<p class=\"empty\">No epochs.</p>\n")
  } else {
    output.write_string(
      "<table><thead><tr><th>Epoch</th><th>Reagent lot</th><th>Control lot</th><th>Calibration</th><th>Program version</th><th>Runs</th><th>Navigate</th></tr></thead><tbody>\n",
    )
    for entry in summary.epoch_runs {
      output.write_string("<tr><td>")
      output.write_string(html_escape(entry.epoch.id))
      output.write_string("</td><td>")
      output.write_string(html_escape(entry.epoch.reagent_lot))
      output.write_string("</td><td>")
      output.write_string(html_escape(entry.epoch.control_lot))
      output.write_string("</td><td>")
      output.write_string(html_escape(entry.epoch.calibration_id))
      output.write_string("</td><td>")
      output.write_string(html_escape(entry.epoch.program_version))
      output.write_string("</td><td>")
      output.write_string(entry.count.to_string())
      output.write_string("</td><td>")
      match html_find_epoch_run_index(runs, entry.epoch) {
        Some(index) => {
          output.write_string("<a href=\"#run-")
          output.write_string(index.to_string())
          output.write_string("\">Open first run</a>")
        }
        None => output.write_string("No run detail")
      }
      output.write_string("</td></tr>\n")
    }
    output.write_string("</tbody></table>\n")
  }
  output.write_string("</section>\n")

  output.write_string(
    "<section class=\"panel chart\"><h2>Levey–Jennings chart</h2><figure>",
  )
  output.write_string(render_levey_jennings_svg(program, runs, trajectory))
  output.write_string(
    "<figcaption>Control observations, target mean, ±1/2/3 SD lines, epoch boundaries, and rule evidence.</figcaption></figure></section>\n",
  )

  output.write_string("<section class=\"panel\"><h2>Run assessments</h2>")
  if trajectory.assessments.length() == 0 {
    output.write_string("<p class=\"empty\">No run assessments.</p>\n")
  } else {
    for index, assessment in trajectory.assessments {
      html_append_assessment(output, program, index, assessment, runs)
    }
  }
  output.write_string("</section>\n")

  if trajectory.input_issues.length() > 0 {
    output.write_string("<section class=\"panel\"><h2>Track issues</h2>\n")
    for issue in trajectory.input_issues {
      output.write_string("<p class=\"issue\"><strong>")
      output.write_string(issue.code.name())
      output.write_string("</strong>")
      match issue.run_id {
        Some(run_id) => {
          output.write_string(" · run ")
          output.write_string(html_escape(run_id))
        }
        None => ()
      }
      output.write_string(": ")
      output.write_string(html_escape(issue.message))
      output.write_string("</p>\n")
    }
    output.write_string("</section>\n")
  }
  output.write_string(
    "<footer>This report is an offline review aid. It does not diagnose, replace a laboratory SOP, or authorize release of patient results. All conclusions require qualified laboratory review.</footer></main></body></html>\n",
  )
  output.to_string()
}
