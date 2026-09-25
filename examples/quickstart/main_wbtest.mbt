///|
test "public API quickstart replays every run deterministically" {
  let first = example_trajectory()
  let second = example_trajectory()
  assert_true(first.assessments.length() == 2)
  assert_true(first.input_issues.length() == 0)
  assert_true(
    @qc.render_trajectory_json(first) == @qc.render_trajectory_json(second),
  )
  for assessment in first.assessments {
    assert_true(assessment.status.name() == "InControl")
  }
}
