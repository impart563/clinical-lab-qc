///|
fn issue(
  code : @evidence.InputIssueCode,
  run_id : String?,
  message : String,
) -> @evidence.InputIssue {
  { code, run_id, message }
}

///|
fn has_point(run : @run.QCRun, level_id : String) -> Bool {
  for point in run.observations {
    if point.control_level_id == level_id {
      return true
    }
  }
  false
}

///|
fn contains_string(values : Array[String], value : String) -> Bool {
  for item in values {
    if item == value {
      return true
    }
  }
  false
}

///|
fn make_empty_assessment(
  run : @run.QCRun,
  issues : Array[@evidence.InputIssue],
) -> @evidence.RunAssessment {
  {
    run_id: run.run_id,
    sequence: run.sequence,
    status: @evidence.Incomplete,
    hits: [],
    input_issues: issues,
  }
}

///|
fn is_structural_issue(issue : @evidence.InputIssue) -> Bool {
  issue.code != @evidence.MissingRequiredControl
}

///|
fn determine_status(
  program : @assay.AssayProgram,
  hits : Array[@evidence.RuleHit],
  issues : Array[@evidence.InputIssue],
) -> @evidence.AssessmentStatus {
  let mut requires_review = false
  let mut warning = false
  for hit in hits {
    match program.disposition_for(hit.rule) {
      @assay.RequiresReview => requires_review = true
      @assay.Warning => warning = true
      @assay.Disabled => ()
    }
  }
  if requires_review {
    @evidence.RequiresReview
  } else if issues.length() > 0 {
    @evidence.Incomplete
  } else if warning {
    @evidence.Warning
  } else {
    @evidence.InControl
  }
}

///|
pub fn evaluate_run(
  program : @assay.AssayProgram,
  run : @run.QCRun,
  history : Array[@run.QCRun],
) -> @evidence.RunAssessment {
  let issues : Array[@evidence.InputIssue] = []
  let program_validation = @assay.validate_program(program)
  for message in program_validation.issues {
    issues.push(issue(@evidence.InvalidProgram, Some(run.run_id), message))
  }
  if !run.epoch.is_valid() {
    issues.push(
      issue(
        @evidence.InvalidEpoch,
        Some(run.run_id),
        "epoch id and metadata fields must not be empty",
      ),
    )
  }
  if run.run_id.trim().is_empty() {
    issues.push(
      issue(
        @evidence.InvalidRunId,
        Some(run.run_id),
        "run_id must not be empty",
      ),
    )
  }
  for i, previous in history {
    if previous.run_id == run.run_id {
      issues.push(
        issue(
          @evidence.DuplicateRunId,
          Some(run.run_id),
          "run id is already present in history",
        ),
      )
    }
    if previous.epoch.id != run.epoch.id ||
      !previous.epoch.has_same_metadata(run.epoch) {
      issues.push(
        issue(
          @evidence.EpochSnapshotMismatch,
          Some(run.run_id),
          "history must contain only the current epoch snapshot",
        ),
      )
    }
    if i > 0 && previous.sequence <= history[i - 1].sequence {
      issues.push(
        issue(
          @evidence.NonIncreasingSequence,
          Some(previous.run_id),
          "history run sequence must strictly increase",
        ),
      )
    }
    if i == history.length() - 1 && run.sequence <= previous.sequence {
      issues.push(
        issue(
          @evidence.NonIncreasingSequence,
          Some(run.run_id),
          "run sequence must strictly increase within an epoch",
        ),
      )
    }
    for j in 0..<i {
      if history[j].run_id == previous.run_id {
        issues.push(
          issue(
            @evidence.DuplicateRunId,
            Some(previous.run_id),
            "duplicate run id in history",
          ),
        )
      }
    }
  }
  for i, point in run.observations {
    let mut known = false
    for level in program.levels {
      if level.id == point.control_level_id {
        known = true
      }
    }
    if !known {
      issues.push(
        issue(
          @evidence.UnknownControlLevel,
          Some(run.run_id),
          "unknown control level: " + point.control_level_id,
        ),
      )
    }
    if point.precision != program.precision {
      issues.push(
        issue(
          @evidence.PrecisionMismatch,
          Some(run.run_id),
          "control point precision differs from assay precision",
        ),
      )
    }
    for j in 0..<i {
      if run.observations[j].control_level_id == point.control_level_id {
        issues.push(
          issue(
            @evidence.DuplicateControlPoint,
            Some(run.run_id),
            "duplicate observation for control level: " + point.control_level_id,
          ),
        )
      }
    }
  }
  for level in program.levels {
    if level.required && !has_point(run, level.id) {
      issues.push(
        issue(
          @evidence.MissingRequiredControl,
          Some(run.run_id),
          "required control level is missing: " + level.id,
        ),
      )
    }
  }
  let mut structural = false
  for current_issue in issues {
    if is_structural_issue(current_issue) {
      structural = true
    }
  }
  if structural {
    make_empty_assessment(run, issues)
  } else {
    let detected = @signals.detect_signals(program, run, history)
    for detected_issue in detected.issues {
      issues.push(detected_issue)
    }
    {
      run_id: run.run_id,
      sequence: run.sequence,
      status: determine_status(program, detected.hits, issues),
      hits: detected.hits,
      input_issues: issues,
    }
  }
}

///|
pub fn replay_track(
  program : @assay.AssayProgram,
  runs : Array[@run.QCRun],
) -> @evidence.Trajectory {
  let assessments : Array[@evidence.RunAssessment] = []
  let issues : Array[@evidence.InputIssue] = []
  let history : Array[@run.QCRun] = []
  let seen_run_ids : Array[String] = []
  let seen_epoch_ids : Array[String] = []
  let mut active_epoch_id : String? = None
  let mut active_epoch_snapshot : @run.QCRun? = None
  for run in runs {
    let mut fatal_issue : @evidence.InputIssue? = None
    if !run.epoch.is_valid() {
      fatal_issue = Some(
        issue(
          @evidence.InvalidEpoch,
          Some(run.run_id),
          "epoch id and metadata fields must not be empty",
        ),
      )
    } else if active_epoch_id is Some(active_id) && active_id == run.epoch.id {
      match active_epoch_snapshot {
        Some(previous_run) =>
          if !previous_run.epoch.has_same_metadata(run.epoch) {
            fatal_issue = Some(
              issue(
                @evidence.EpochSnapshotMismatch,
                Some(run.run_id),
                "epoch metadata changed without a new epoch id",
              ),
            )
          }
        None => ()
      }
    } else if contains_string(seen_epoch_ids, run.epoch.id) {
      fatal_issue = Some(
        issue(
          @evidence.RepeatedEpoch,
          Some(run.run_id),
          "an epoch id may appear in only one contiguous track segment",
        ),
      )
    }
    if fatal_issue is None && contains_string(seen_run_ids, run.run_id) {
      fatal_issue = Some(
        issue(
          @evidence.DuplicateRunId,
          Some(run.run_id),
          "duplicate run id in track",
        ),
      )
    }
    if fatal_issue is None &&
      active_epoch_id is Some(active_id) &&
      active_id == run.epoch.id {
      match active_epoch_snapshot {
        Some(previous_run) =>
          if run.sequence <= previous_run.sequence {
            fatal_issue = Some(
              issue(
                @evidence.NonIncreasingSequence,
                Some(run.run_id),
                "run sequence must strictly increase within an epoch",
              ),
            )
          }
        None => ()
      }
    }
    match fatal_issue {
      Some(fatal) => {
        issues.push(fatal)
        let current_issues = [fatal]
        assessments.push(make_empty_assessment(run, current_issues))
        break
      }
      None => {
        if active_epoch_id is None || active_epoch_id != Some(run.epoch.id) {
          history.clear()
          active_epoch_id = Some(run.epoch.id)
          seen_epoch_ids.push(run.epoch.id)
        }
        active_epoch_snapshot = Some(run)
        let assessment = evaluate_run(program, run, history)
        assessments.push(assessment)
        seen_run_ids.push(run.run_id)
        let mut structural = false
        for current_issue in assessment.input_issues {
          if is_structural_issue(current_issue) {
            structural = true
          }
        }
        if structural {
          history.clear()
        } else {
          history.push(run)
        }
      }
    }
  }
  { assessments, input_issues: issues }
}
