///|
fn test_epoch(id : String) -> QCEpoch {
  {
    id,
    reagent_lot: "reagent-" + id,
    control_lot: "control-" + id,
    calibration_id: "cal-" + id,
    program_version: "v1",
  }
}

///|
fn test_program_one(
  mean : Int64,
  standard_deviation : Int64,
  precision : Int,
) -> AssayProgram {
  {
    assay_id: "test-assay",
    unit: "unit",
    precision,
    levels: [{ id: "L1", mean, standard_deviation, required: true }],
    rule_policies: default_rule_policies(),
  }
}

///|
fn test_program_two() -> AssayProgram {
  {
    assay_id: "test-assay",
    unit: "unit",
    precision: 0,
    levels: [
      { id: "L1", mean: 100L, standard_deviation: 10L, required: true },
      { id: "L2", mean: 200L, standard_deviation: 20L, required: true },
    ],
    rule_policies: default_rule_policies(),
  }
}

///|
fn test_run(
  epoch : QCEpoch,
  run_id : String,
  sequence : Int64,
  observations : Array[ControlPoint],
) -> QCRun {
  { run_id, epoch, sequence, timestamp: "2026-09-25T08:00:00Z", observations }
}

///|
fn test_single_run(
  run_id : String,
  sequence : Int64,
  value : Int64,
  precision : Int,
) -> QCRun {
  test_run(test_epoch("epoch-a"), run_id, sequence, [
    { control_level_id: "L1", value, precision },
  ])
}

///|
fn contains_rule(assessment : RunAssessment, rule : Rule) -> Bool {
  for hit in assessment.hits {
    if hit.rule == rule {
      return true
    }
  }
  false
}

///|
test "1_2s and 1_3s use strict positive and negative thresholds" {
  let program = test_program_one(100L, 10L, 0)
  let exact_positive = evaluate_run(
    program,
    test_single_run("a", 1L, 120L, 0),
    [],
  )
  let exact_negative = evaluate_run(program, test_single_run("b", 1L, 80L, 0), [])
  let warning_positive = evaluate_run(
    program,
    test_single_run("c", 1L, 121L, 0),
    [],
  )
  let exact_3sd = evaluate_run(
    program,
    test_single_run("exact-3sd", 1L, 130L, 0),
    [],
  )
  let review_positive = evaluate_run(
    program,
    test_single_run("d", 1L, 131L, 0),
    [],
  )
  let review_negative = evaluate_run(
    program,
    test_single_run("e", 1L, 69L, 0),
    [],
  )
  assert_true(!contains_rule(exact_positive, @assay.Rule12s))
  assert_true(!contains_rule(exact_negative, @assay.Rule12s))
  assert_true(contains_rule(warning_positive, @assay.Rule12s))
  assert_true(!contains_rule(warning_positive, @assay.Rule13s))
  assert_true(contains_rule(exact_3sd, @assay.Rule12s))
  assert_true(!contains_rule(exact_3sd, @assay.Rule13s))
  assert_true(contains_rule(review_positive, @assay.Rule13s))
  assert_true(contains_rule(review_negative, @assay.Rule13s))
  assert_true(warning_positive.status == @evidence.Warning)
  assert_true(review_positive.status == @evidence.RequiresReview)
}

///|
test "2_2s requires both latest observations strictly beyond 2 SD on one side" {
  let program = test_program_one(0L, 10L, 0)
  let exact = test_run(test_epoch("epoch-a"), "a", 1L, [
    { control_level_id: "L1", value: 20L, precision: 0 },
  ])
  let beyond = test_single_run("b", 2L, 21L, 0)
  let exact_window = evaluate_run(program, beyond, [exact])
  assert_true(!contains_rule(exact_window, @assay.Rule22s))
  let first = test_single_run("c", 1L, 21L, 0)
  let second = test_single_run("d", 2L, 22L, 0)
  let triggered = evaluate_run(program, second, [first])
  assert_true(contains_rule(triggered, @assay.Rule22s))
  let opposite = evaluate_run(
    program,
    test_single_run("opposite", 2L, -21L, 0),
    [first],
  )
  assert_true(!contains_rule(opposite, @assay.Rule22s))
  let negative_first = test_single_run("negative-first", 1L, -21L, 0)
  let negative_second = evaluate_run(
    program,
    test_single_run("negative-second", 2L, -22L, 0),
    [negative_first],
  )
  assert_true(contains_rule(negative_second, @assay.Rule22s))
}

///|
test "4_1s and 10x detect exact window lengths and reset at the mean" {
  let program = test_program_one(0L, 10L, 0)
  let epoch = test_epoch("epoch-a")
  let one_at_boundary = test_single_run("a", 1L, 10L, 0)
  let after_boundary = test_single_run("b", 2L, 11L, 0)
  let no_41 = evaluate_run(program, test_single_run("d", 4L, 11L, 0), [
    one_at_boundary,
    after_boundary,
    test_single_run("c", 3L, 11L, 0),
  ])
  assert_true(!contains_rule(no_41, @assay.Rule41s))
  let values = [11L, 12L, 13L, 14L]
  let four : Array[QCRun] = []
  for i in 0..<values.length() {
    four.push(
      test_single_run(
        "four-" + (i + 1).to_string(),
        (i + 1).to_int64(),
        values[i],
        0,
      ),
    )
  }
  let hit_41 = evaluate_run(program, four[3], [four[0], four[1], four[2]])
  assert_true(contains_rule(hit_41, @assay.Rule41s))
  let negative_four : Array[QCRun] = []
  for i in 0..<4 {
    negative_four.push(
      test_single_run(
        "negative-four-" + (i + 1).to_string(),
        (i + 1).to_int64(),
        -11L - i.to_int64(),
        0,
      ),
    )
  }
  let hit_negative_41 = evaluate_run(program, negative_four[3], [
    negative_four[0],
    negative_four[1],
    negative_four[2],
  ])
  assert_true(contains_rule(hit_negative_41, @assay.Rule41s))
  let ten : Array[QCRun] = []
  for i in 0..<10 {
    ten.push(
      test_single_run("ten-" + (i + 1).to_string(), (i + 1).to_int64(), 1L, 0),
    )
  }
  let hit_10x = evaluate_run(program, ten[9], ten[0:9].to_owned())
  assert_true(contains_rule(hit_10x, @assay.Rule10x))
  let negative_ten : Array[QCRun] = []
  for i in 0..<10 {
    negative_ten.push(
      test_single_run(
        "negative-ten-" + (i + 1).to_string(),
        (i + 1).to_int64(),
        -1L,
        0,
      ),
    )
  }
  let hit_negative_10x = evaluate_run(
    program,
    negative_ten[9],
    negative_ten[0:9].to_owned(),
  )
  assert_true(contains_rule(hit_negative_10x, @assay.Rule10x))
  let at_mean = test_single_run("at-mean", 10L, 0L, 0)
  let broken_ten = evaluate_run(program, at_mean, ten[0:9].to_owned())
  assert_true(!contains_rule(broken_ten, @assay.Rule10x))
  assert_true(epoch.id == "epoch-a")
}

///|
test "R_4s compares different controls within the same run" {
  let program = test_program_two()
  let epoch = test_epoch("epoch-a")
  let beyond = test_run(epoch, "r4-hit", 1L, [
    { control_level_id: "L1", value: 121L, precision: 0 },
    { control_level_id: "L2", value: 159L, precision: 0 },
  ])
  let exact = test_run(epoch, "r4-edge", 2L, [
    { control_level_id: "L1", value: 120L, precision: 0 },
    { control_level_id: "L2", value: 160L, precision: 0 },
  ])
  let flipped = test_run(epoch, "r4-flipped", 3L, [
    { control_level_id: "L1", value: 79L, precision: 0 },
    { control_level_id: "L2", value: 241L, precision: 0 },
  ])
  let missing = test_run(epoch, "r4-missing", 4L, [
    { control_level_id: "L1", value: 121L, precision: 0 },
  ])
  let missing_and_review = test_run(epoch, "r4-review-missing", 5L, [
    { control_level_id: "L1", value: 131L, precision: 0 },
  ])
  assert_true(contains_rule(evaluate_run(program, beyond, []), @assay.RuleR4s))
  assert_true(!contains_rule(evaluate_run(program, exact, []), @assay.RuleR4s))
  assert_true(contains_rule(evaluate_run(program, flipped, []), @assay.RuleR4s))
  let incomplete = evaluate_run(program, missing, [])
  assert_true(!contains_rule(incomplete, @assay.RuleR4s))
  assert_true(incomplete.status == @evidence.Incomplete)
  let review = evaluate_run(program, missing_and_review, [])
  assert_true(review.status == @evidence.RequiresReview)
  assert_true(review.input_issues.length() > 0)
}

///|
test "missing values break only their control level window and stage changes reset history" {
  let program = test_program_one(0L, 10L, 0)
  let epoch_a = test_epoch("epoch-a")
  let epoch_b = test_epoch("epoch-b")
  let first = test_run(epoch_a, "first", 1L, [
    { control_level_id: "L1", value: 21L, precision: 0 },
  ])
  let gap = test_run(epoch_a, "gap", 2L, [])
  let after_gap = test_run(epoch_a, "after-gap", 3L, [
    { control_level_id: "L1", value: 22L, precision: 0 },
  ])
  let after_gap_track = replay_track(program, [first, gap, after_gap])
  assert_true(!contains_rule(after_gap_track.assessments[2], @assay.Rule22s))
  assert_true(after_gap_track.assessments[1].status == @evidence.Incomplete)
  let old_stage : Array[QCRun] = []
  let new_stage : Array[QCRun] = []
  for i in 0..<6 {
    old_stage.push(
      test_run(epoch_a, "old-" + (i + 1).to_string(), (i + 1).to_int64(), [
        { control_level_id: "L1", value: 15L, precision: 0 },
      ]),
    )
  }
  for i in 0..<4 {
    new_stage.push(
      test_run(epoch_b, "new-" + (i + 1).to_string(), (i + 1).to_int64(), [
        { control_level_id: "L1", value: 15L, precision: 0 },
      ]),
    )
  }
  let switched = replay_track(program, old_stage + new_stage)
  assert_true(!contains_rule(switched.assessments[9], @assay.Rule10x))
}

///|
test "replay reports duplicate, unordered, and reused epoch input without sorting" {
  let program = test_program_one(0L, 10L, 0)
  let epoch_a = test_epoch("epoch-a")
  let epoch_b = test_epoch("epoch-b")
  let first = test_run(epoch_a, "first", 2L, [
    { control_level_id: "L1", value: 0L, precision: 0 },
  ])
  let lower = test_run(epoch_a, "lower", 1L, [
    { control_level_id: "L1", value: 0L, precision: 0 },
  ])
  let unordered = replay_track(program, [first, lower])
  assert_true(unordered.input_issues.length() == 1)
  assert_true(unordered.input_issues[0].code == @evidence.NonIncreasingSequence)
  assert_true(unordered.assessments.length() == 2)
  let duplicate = replay_track(program, [first, first])
  assert_true(duplicate.input_issues[0].code == @evidence.DuplicateRunId)
  let returned = replay_track(program, [
    first,
    test_run(epoch_b, "other", 1L, [
      { control_level_id: "L1", value: 0L, precision: 0 },
    ]),
    test_run(epoch_a, "return", 3L, [
      { control_level_id: "L1", value: 0L, precision: 0 },
    ]),
  ])
  assert_true(returned.input_issues[0].code == @evidence.RepeatedEpoch)
  let changed_snapshot : QCEpoch = {
    id: "epoch-a",
    reagent_lot: "changed-lot",
    control_lot: "control-epoch-a",
    calibration_id: "cal-epoch-a",
    program_version: "v1",
  }
  let changed = test_run(changed_snapshot, "changed", 3L, [
    { control_level_id: "L1", value: 0L, precision: 0 },
  ])
  let snapshot_track = replay_track(program, [first, changed])
  assert_true(
    snapshot_track.input_issues[0].code == @evidence.EpochSnapshotMismatch,
  )
}

///|
test "program and observations reject zero negative SD unknown levels and precision mismatch" {
  let zero_sd = validate_program(test_program_one(0L, 0L, 0))
  let negative_sd = validate_program(test_program_one(0L, -1L, 0))
  let bad_precision = validate_program(test_program_one(0L, 10L, 19))
  assert_true(!zero_sd.is_valid())
  assert_true(!negative_sd.is_valid())
  assert_true(!bad_precision.is_valid())
  let program = test_program_one(0L, 10L, 0)
  let unknown = test_run(test_epoch("epoch-a"), "unknown", 1L, [
    { control_level_id: "L9", value: 1L, precision: 0 },
  ])
  let precision = test_single_run("precision", 1L, 1L, 1)
  let blank_id = test_single_run("   ", 1L, 1L, 0)
  assert_true(
    evaluate_run(program, unknown, []).input_issues[0].code ==
    @evidence.UnknownControlLevel,
  )
  assert_true(
    evaluate_run(program, precision, []).input_issues[0].code ==
    @evidence.PrecisionMismatch,
  )
  assert_true(
    evaluate_run(program, blank_id, []).input_issues[0].code ==
    @evidence.InvalidRunId,
  )
}

///|
test "integer overflow is reported and never becomes a rule hit" {
  let program = test_program_one(0L, 5000000000000000000L, 0)
  let run = test_single_run("overflow", 1L, 1L, 0)
  let assessment = evaluate_run(program, run, [])
  assert_true(assessment.status == @evidence.Incomplete)
  assert_true(assessment.input_issues.length() > 0)
  assert_true(assessment.input_issues[0].code == @evidence.ArithmeticOverflow)
  assert_true(!contains_rule(assessment, @assay.Rule12s))
}

///|
test "CSV parsing preserves quotes, exact decimal precision, empty values, and deterministic JSON" {
  let program : AssayProgram = {
    assay_id: "csv-test",
    unit: "unit",
    precision: 2,
    levels: [
      { id: "L1", mean: 125L, standard_deviation: 10L, required: true },
      { id: "L2", mean: 20000L, standard_deviation: 2000L, required: true },
    ],
    rule_policies: default_rule_policies(),
  }
  let csv =
    #|epoch_id,reagent_lot,control_lot,calibration_id,program_version,run_id,sequence,timestamp,control_level_id,value
    #|"epoch,one",reagent,control,cal,1,"run ""one""",1,2026-09-25T08:00:00Z,L1,1.25
    #|"epoch,one",reagent,control,cal,1,"run ""one""",1,2026-09-25T08:00:00Z,L2,
    #|
  let parsed = parse_qc_csv(program, csv)
  assert_true(parsed.issues.length() == 0)
  assert_true(parsed.runs.length() == 1)
  assert_true(parsed.runs[0].run_id == "run \"one\"")
  assert_true(parsed.runs[0].observations[0].value == 125L)
  let trajectory = replay_track(program, parsed.runs)
  assert_true(trajectory.assessments[0].status == @evidence.Incomplete)
  let json_a = render_trajectory_json(trajectory)
  let json_b = render_trajectory_json(trajectory)
  assert_true(json_a == json_b)
  let bad_precision = parse_qc_csv(
    program,
    csv.replace(old="1.25", new="1.250"),
  )
  assert_true(bad_precision.issues.length() > 0)
  let malformed = parse_qc_csv(
    program,
    csv.replace(old="\"run \"\"one\"\"\"", new="\"unfinished"),
  )
  assert_true(malformed.issues.length() > 0)
}
