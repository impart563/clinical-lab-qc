///|
test "public API quickstart replays every run deterministically" {
  let program = example_program()
  let runs = example_runs()
  let first = @qc.replay_track(program, runs)
  let second = @qc.replay_track(program, runs)
  assert_true(first.assessments.length() == runs.length())
  assert_true(first.assessments.length() == 2)
  assert_true(first.input_issues.length() == 0)
  assert_true(
    @qc.render_trajectory_json(first) == @qc.render_trajectory_json(second),
  )
  let markdown = @qc.render_audit_markdown(program, runs, first)
  let json = @qc.render_audit_json(program, runs, first)
  let csv = @qc.render_audit_csv(program, runs, first)
  let svg = @qc.render_levey_jennings_svg(program, runs, first)
  assert_true(markdown == @qc.render_audit_markdown(program, runs, second))
  assert_true(json == @qc.render_audit_json(program, runs, second))
  assert_true(csv == @qc.render_audit_csv(program, runs, second))
  assert_true(svg == @qc.render_levey_jennings_svg(program, runs, second))
  assert_true(markdown.contains("Input runs: 2; assessed: 2"))
  assert_true(json.contains("\"schema_version\": 1"))
  assert_true(csv.contains("assessment"))
  assert_true(svg.has_prefix("<svg xmlns=\"http://www.w3.org/2000/svg\""))
  for assessment in first.assessments {
    assert_true(assessment.status.name() == "InControl")
  }
}
