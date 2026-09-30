///|
/// Reduce caller-provided labels to display names before writing an artifact.
fn report_source_label(label : String) -> String {
  let normalized = label.replace_all(old="\\", new="/")
  let parts = normalized.split("/").collect()
  let candidate = match parts.get(parts.length() - 1) {
    Some(value) => value.to_owned()
    None => "input"
  }
  candidate.replace(old="\r", new=" ").replace(old="\n", new=" ")
}

///|
fn report_markdown_label(label : String) -> String {
  report_source_label(label).replace(old="|", new="\\|")
}

///|
fn sourced_run_values(
  sourced_runs : Array[SourcedQCRun],
) -> (Array[@run.QCRun], Array[String]) {
  (
    sourced_runs.map(fn(entry) { entry.run }),
    sourced_runs.map(fn(entry) { entry.source_label }),
  )
}

///|
/// Render Markdown with an explicit run-to-file provenance table.
pub fn render_audit_markdown_batch(
  program : @assay.AssayProgram,
  sourced_runs : Array[SourcedQCRun],
  trajectory : @evidence.Trajectory,
) -> String {
  let (runs, _) = sourced_run_values(sourced_runs)
  let output = StringBuilder()
  output.write_string(render_audit_markdown(program, runs, trajectory))
  output.write_string(
    "\n\n## Input sources\n\n| Run | Source file |\n|---|---|\n",
  )
  for entry in sourced_runs {
    output.write_string("|")
    output.write_string(entry.run.run_id.replace(old="|", new="\\|"))
    output.write_string("|")
    output.write_string(report_markdown_label(entry.source_label))
    output.write_string("|\n")
  }
  output.to_string()
}

///|
/// Render an offline HTML report with run-to-file provenance.
pub fn render_audit_html_batch(
  program : @assay.AssayProgram,
  sourced_runs : Array[SourcedQCRun],
  trajectory : @evidence.Trajectory,
) -> String {
  let (runs, _) = sourced_run_values(sourced_runs)
  let source_section = StringBuilder()
  source_section.write_string(
    "<section class=\"panel\"><h2>Input sources</h2><table><thead><tr><th>Run</th><th>Source file</th></tr></thead><tbody>\n",
  )
  for entry in sourced_runs {
    source_section.write_string("<tr><td>")
    source_section.write_string(html_escape(entry.run.run_id))
    source_section.write_string("</td><td>")
    source_section.write_string(
      html_escape(report_source_label(entry.source_label)),
    )
    source_section.write_string("</td></tr>\n")
  }
  source_section.write_string("</tbody></table></section>\n")
  render_audit_html(program, runs, trajectory).replace(
    old="</main></body></html>",
    new=source_section.to_string() + "</main></body></html>",
  )
}

///|
/// Render an offline Levey–Jennings SVG with source provenance in its
/// machine-readable metadata block.
pub fn render_levey_jennings_svg_batch(
  program : @assay.AssayProgram,
  sourced_runs : Array[SourcedQCRun],
  trajectory : @evidence.Trajectory,
) -> String {
  let (runs, _) = sourced_run_values(sourced_runs)
  let metadata = StringBuilder()
  metadata.write_string("<metadata><qc-sources>\n")
  for entry in sourced_runs {
    metadata.write_string("<run id=\"")
    metadata.write_string(svg_escape(entry.run.run_id))
    metadata.write_string("\" source=\"")
    metadata.write_string(svg_escape(report_source_label(entry.source_label)))
    metadata.write_string("\"/>\n")
  }
  metadata.write_string("</qc-sources></metadata>\n")
  render_levey_jennings_svg(program, runs, trajectory).replace(
    old="</svg>",
    new=metadata.to_string() + "</svg>",
  )
}
