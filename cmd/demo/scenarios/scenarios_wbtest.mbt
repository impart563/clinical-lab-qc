///|
test "stable demo is in control and deterministic" {
  match build_scenario("stable") {
    None => fail("stable scenario is missing")
    Some(runs) => {
      let program = demo_program()
      let first = @lib.replay_track(program, runs)
      let second = @lib.replay_track(program, runs)
      assert_true(first.assessments.length() == runs.length())
      assert_true(
        @lib.render_trajectory_json(first) ==
        @lib.render_trajectory_json(second),
      )
      let report = @lib.render_audit_json(program, runs, first)
      assert_true(report.contains("\"input_runs\": 12"))
      assert_true(report.contains("\"InControl\": 12"))
      assert_true(report.contains("\"total_rule_hits\": 0"))
      for assessment in first.assessments {
        assert_true(assessment.status.name() == "InControl")
        assert_true(assessment.hits.length() == 0)
      }
    }
  }
}

///|
test "step-shift demo never carries a 10x window across the epoch boundary" {
  match build_scenario("step-shift") {
    None => fail("step-shift scenario is missing")
    Some(runs) => {
      let trajectory = @lib.replay_track(demo_program(), runs)
      assert_true(trajectory.assessments.length() == 12)
      assert_true(runs[5].epoch.id == "lot-a")
      assert_true(runs[6].epoch.id == "lot-b")
      let report = @lib.render_audit_json(demo_program(), runs, trajectory)
      assert_true(report.contains("\"InControl\": 12"))
      assert_true(report.contains("\"total_rule_hits\": 0"))
      assert_true(report.contains("\"run_count\": 6"))
      for assessment in trajectory.assessments {
        assert_true(assessment.status.name() == "InControl")
        assert_true(assessment.hits.length() == 0)
      }
    }
  }
}

///|
test "gradual-drift demo exposes cross-run evidence and review state" {
  match build_scenario("gradual-drift") {
    None => fail("gradual-drift scenario is missing")
    Some(runs) => {
      let trajectory = @lib.replay_track(demo_program(), runs)
      let report = @lib.render_audit_json(demo_program(), runs, trajectory)
      assert_true(report.contains("\"input_runs\": 12"))
      assert_true(report.contains("\"InControl\": 6"))
      assert_true(report.contains("\"RequiresReview\": 6"))
      assert_true(report.contains("\"total_rule_hits\": 9"))
      assert_true(report.contains("\"rule\": \"4_1s\",\n        \"count\": 6"))
      assert_true(report.contains("\"rule\": \"10x\",\n        \"count\": 2"))
      assert_true(trajectory.assessments[10].status.name() == "RequiresReview")
      assert_true(trajectory.assessments[10].hits.length() > 0)
    }
  }
}
