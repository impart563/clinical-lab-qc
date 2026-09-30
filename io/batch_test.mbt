///|
fn batch_test_csv(run_id : String, sequence : Int) -> String {
  "epoch_id,reagent_lot,control_lot,calibration_id,program_version,run_id,sequence,timestamp,control_level_id,value\n" +
  "lot-a,reagent-a,control-a,cal-a,v1," +
  run_id +
  "," +
  sequence.to_string() +
  ",2026-09-30T08:00:00Z,L1,100.00\n"
}

///|
test "batch CSV parsing preserves source order and rejects partial replay" {
  let program = audit_test_program()
  let parsed = @io.parse_qc_csv_batch_detailed(program, [
    { label: "2026-09-28 Morning.csv", text: batch_test_csv("run-1", 1), },
    { label: "第二份.csv", text: batch_test_csv("run-2", 2), },
  ])
  assert_eq(parsed.diagnostics.length(), 0)
  assert_eq(parsed.runs.length(), 2)
  assert_eq(parsed.runs[0].source_label, "2026-09-28 Morning.csv")
  assert_eq(parsed.runs[0].run.run_id, "run-1")
  assert_eq(parsed.runs[1].source_label, "第二份.csv")
  assert_eq(parsed.runs[1].run.sequence, 2L)

  let invalid = @io.parse_qc_csv_batch_detailed(program, [
    { label: "valid.csv", text: batch_test_csv("run-3", 3), },
    { label: "bad file.csv", text: "not,a,qc,header\n", },
    {
      label: "另一个坏文件.csv",
      text: batch_test_csv("run-4", 4).replace(old=",100.00", new=",100.001"),
    },
  ])
  assert_eq(invalid.runs.length(), 0)
  assert_eq(invalid.diagnostics.length(), 2)
  assert_eq(invalid.diagnostics[0].source_label, "bad file.csv")
  assert_eq(invalid.diagnostics[0].diagnostic.line, Some(1))
  assert_eq(invalid.diagnostics[1].source_label, "另一个坏文件.csv")
  assert_eq(invalid.diagnostics[1].diagnostic.column, Some(10))
}

///|
test "batch report formats retain source names without file system paths" {
  let program = audit_test_program()
  let runs = audit_test_runs()
  let sourced : Array[@io.SourcedQCRun] = []
  for index, run in runs {
    sourced.push({
      source_label: "C:\\Users\\private\\控制品 " +
      (index + 1).to_string() +
      ".csv",
      run,
    })
  }
  let trajectory = audit_test_trajectory()
  let json = @io.render_audit_json_batch(program, sourced, trajectory)
  let csv = @io.render_audit_csv_batch(program, sourced, trajectory)
  let markdown = @io.render_audit_markdown_batch(program, sourced, trajectory)
  let html = @io.render_audit_html_batch(program, sourced, trajectory)
  let svg = @io.render_levey_jennings_svg_batch(program, sourced, trajectory)
  let manifest = @io.render_audit_manifest_batch(program, sourced, trajectory)
  assert_true(json.contains("\"schema_version\": 2"))
  assert_true(json.contains("\"source_label\": \"控制品 1.csv\""))
  assert_true(csv.contains("source_label"))
  assert_true(csv.contains("控制品 1.csv"))
  assert_true(markdown.contains("控制品 1.csv"))
  assert_true(html.contains("<h2>Input sources</h2>"))
  assert_true(html.contains("控制品 2.csv"))
  assert_true(svg.contains("<qc-sources>"))
  assert_true(svg.contains("source=\"控制品 3.csv\""))
  assert_true(manifest.contains("\"report_schema_version\": 2"))
  assert_true(manifest.contains("控制品 1.csv"))
  for artifact in [json, csv, markdown, html, svg, manifest] {
    assert_true(!artifact.contains("C:\\\\Users"))
    assert_true(!artifact.contains("private"))
  }
}
