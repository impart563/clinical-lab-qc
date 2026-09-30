///|
test "Levey-Jennings SVG is deterministic and includes limits epochs and evidence" {
  let program = audit_test_program()
  let runs = audit_test_runs()
  let trajectory = audit_test_trajectory()
  let svg = @io.render_levey_jennings_svg(program, runs, trajectory)
  assert_eq(svg, @io.render_levey_jennings_svg(program, runs, trajectory))
  assert_true(svg.has_prefix("<svg xmlns=\"http://www.w3.org/2000/svg\""))
  assert_true(svg.contains("data-sigma=\"-3\""))
  assert_true(svg.contains("data-sigma=\"3\""))
  assert_true(svg.contains("class=\"epoch-boundary\""))
  assert_true(svg.contains("class=\"rule-evidence\" data-rule=\"1_2s\""))
  assert_true(svg.contains("sample,&quot;run&quot;"))
}

///|
test "Levey-Jennings SVG breaks a line at a missing control observation" {
  let program = audit_test_program()
  let epoch : @epoch.QCEpoch = {
    id: "epoch-a",
    reagent_lot: "reagent-a",
    control_lot: "control-a",
    calibration_id: "cal-a",
    program_version: "v1",
  }
  let runs : Array[@run.QCRun] = [
    {
      run_id: "run<&\"1",
      epoch,
      sequence: 1L,
      timestamp: "t1",
      observations: [{ control_level_id: "L1", value: 10000L, precision: 2, }],
    },
    {
      run_id: "run-2",
      epoch,
      sequence: 2L,
      timestamp: "t2",
      observations: [{ control_level_id: "L1", value: 10100L, precision: 2, }],
    },
    { run_id: "run-3", epoch, sequence: 3L, timestamp: "t3", observations: [], },
    {
      run_id: "run-4",
      epoch,
      sequence: 4L,
      timestamp: "t4",
      observations: [{ control_level_id: "L1", value: 9900L, precision: 2, }],
    },
    {
      run_id: "run-5",
      epoch,
      sequence: 5L,
      timestamp: "t5",
      observations: [{ control_level_id: "L1", value: 10000L, precision: 2, }],
    },
  ]
  let trajectory : @evidence.Trajectory = { assessments: [], input_issues: [], }
  let svg = @io.render_levey_jennings_svg(program, runs, trajectory)
  assert_true(svg.contains("data-segment=\"1\""))
  assert_true(svg.contains("data-segment=\"2\""))
  assert_true(!svg.contains("data-segment=\"3\""))
  assert_true(svg.contains("data-run-id=\"run&lt;&amp;&quot;1\""))
}
