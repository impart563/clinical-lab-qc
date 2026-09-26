///|
test "a separate module can consume the public QC API" {
  let program = downstream_program()
  let runs = downstream_runs()
  let trajectory = @qc.replay_track(program, runs)
  let json = @qc.render_audit_json(program, runs, trajectory)
  assert_eq(trajectory.assessments.length(), 2)
  assert_true(json.contains("\"assessed_runs\": 2"))
  assert_true(json.contains("\"total_rule_hits\": 0"))
}
