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
      for assessment in trajectory.assessments {
        for hit in assessment.hits {
          assert_true(hit.rule != @lib.rule_10x())
        }
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
      let mut saw_41 = false
      let mut saw_10x = false
      for assessment in trajectory.assessments {
        for hit in assessment.hits {
          if hit.rule == @lib.rule_41s() && hit.evidence.length() == 4 {
            saw_41 = true
          }
          if hit.rule == @lib.rule_10x() && hit.evidence.length() == 10 {
            saw_10x = true
          }
        }
      }
      assert_true(saw_41)
      assert_true(saw_10x)
      assert_true(trajectory.assessments[10].status.name() == "RequiresReview")
      assert_true(trajectory.assessments[10].hits.length() > 0)
    }
  }
}
