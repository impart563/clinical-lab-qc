///|
priv struct RuleHitCount {
  rule : @assay.Rule
  count : Int
}

///|
priv struct EpochRunCount {
  epoch : @epoch.QCEpoch
  count : Int
}

///|
priv struct AuditSummary {
  input_runs : Int
  assessed_runs : Int
  in_control : Int
  warning : Int
  requires_review : Int
  incomplete : Int
  total_rule_hits : Int
  rule_hits : Array[RuleHitCount]
  epoch_runs : Array[EpochRunCount]
  track_issues : Int
}

///|
fn audit_rule_order() -> Array[@assay.Rule] {
  [
    @assay.Rule12s,
    @assay.Rule13s,
    @assay.Rule22s,
    @assay.RuleR4s,
    @assay.Rule41s,
    @assay.Rule10x,
  ]
}

///|
fn audit_rule_disposition_name(disposition : @assay.RuleDisposition) -> String {
  match disposition {
    @assay.Disabled => "disabled"
    @assay.Warning => "warning"
    @assay.RequiresReview => "requires_review"
  }
}

///|
fn audit_summary(
  runs : Array[@run.QCRun],
  trajectory : @evidence.Trajectory,
) -> AuditSummary {
  let mut in_control = 0
  let mut warning = 0
  let mut requires_review = 0
  let mut incomplete = 0
  let mut total_rule_hits = 0
  let rule_hits : Array[RuleHitCount] = audit_rule_order().map(fn(rule) {
    let mut count = 0
    for assessment in trajectory.assessments {
      for hit in assessment.hits {
        if hit.rule == rule {
          count = count + 1
        }
      }
    }
    total_rule_hits = total_rule_hits + count
    { rule, count }
  })
  for assessment in trajectory.assessments {
    match assessment.status {
      @evidence.InControl => in_control = in_control + 1
      @evidence.Warning => warning = warning + 1
      @evidence.RequiresReview => requires_review = requires_review + 1
      @evidence.Incomplete => incomplete = incomplete + 1
    }
  }
  let epochs : Array[EpochRunCount] = []
  for run in runs {
    let mut match_index : Int? = None
    for index, entry in epochs {
      if entry.epoch.has_same_metadata(run.epoch) {
        match_index = Some(index)
        break
      }
    }
    match match_index {
      Some(index) =>
        epochs[index] = {
          epoch: epochs[index].epoch,
          count: epochs[index].count + 1,
        }
      None => epochs.push({ epoch: run.epoch, count: 1 })
    }
  }
  {
    input_runs: runs.length(),
    assessed_runs: trajectory.assessments.length(),
    in_control,
    warning,
    requires_review,
    incomplete,
    total_rule_hits,
    rule_hits,
    epoch_runs: epochs,
    track_issues: trajectory.input_issues.length(),
  }
}

///|
fn audit_json_epoch(epoch : @epoch.QCEpoch) -> Json {
  let fields : Map[String, Json] = Map([])
  fields["id"] = Json::string(epoch.id)
  fields["reagent_lot"] = Json::string(epoch.reagent_lot)
  fields["control_lot"] = Json::string(epoch.control_lot)
  fields["calibration_id"] = Json::string(epoch.calibration_id)
  fields["program_version"] = Json::string(epoch.program_version)
  Json::object(fields)
}

///|
fn audit_json_run(run : @run.QCRun) -> Json {
  let fields : Map[String, Json] = Map([])
  fields["run_id"] = Json::string(run.run_id)
  fields["sequence"] = json_number(run.sequence)
  fields["timestamp"] = Json::string(run.timestamp)
  fields["epoch"] = audit_json_epoch(run.epoch)
  fields["observations"] = Json::array(
    run.observations.map(fn(point) {
      let point_fields : Map[String, Json] = Map([])
      point_fields["control_level_id"] = Json::string(point.control_level_id)
      point_fields["value_scaled"] = json_number(point.value)
      point_fields["precision"] = Json::number(point.precision.to_double())
      Json::object(point_fields)
    }),
  )
  Json::object(fields)
}

///|
fn audit_json_program(program : @assay.AssayProgram) -> Json {
  let fields : Map[String, Json] = Map([])
  fields["assay_id"] = Json::string(program.assay_id)
  fields["unit"] = Json::string(program.unit)
  fields["precision"] = Json::number(program.precision.to_double())
  fields["control_levels"] = Json::array(
    program.levels.map(fn(level) {
      let level_fields : Map[String, Json] = Map([])
      level_fields["id"] = Json::string(level.id)
      level_fields["mean_scaled"] = json_number(level.mean)
      level_fields["standard_deviation_scaled"] = json_number(
        level.standard_deviation,
      )
      level_fields["required"] = Json::boolean(level.required)
      Json::object(level_fields)
    }),
  )
  fields["rule_dispositions"] = Json::array(
    audit_rule_order().map(fn(rule) {
      let rule_fields : Map[String, Json] = Map([])
      rule_fields["rule"] = Json::string(rule.name())
      rule_fields["disposition"] = Json::string(
        audit_rule_disposition_name(program.disposition_for(rule)),
      )
      Json::object(rule_fields)
    }),
  )
  Json::object(fields)
}

///|
fn audit_json_summary(summary : AuditSummary) -> Json {
  let fields : Map[String, Json] = Map([])
  fields["input_runs"] = Json::number(summary.input_runs.to_double())
  fields["assessed_runs"] = Json::number(summary.assessed_runs.to_double())
  fields["status_counts"] = Json::object({
    "InControl": Json::number(summary.in_control.to_double()),
    "Warning": Json::number(summary.warning.to_double()),
    "RequiresReview": Json::number(summary.requires_review.to_double()),
    "Incomplete": Json::number(summary.incomplete.to_double()),
  })
  fields["total_rule_hits"] = Json::number(summary.total_rule_hits.to_double())
  fields["rule_hit_counts"] = Json::array(
    summary.rule_hits.map(fn(entry) {
      let rule_fields : Map[String, Json] = Map([])
      rule_fields["rule"] = Json::string(entry.rule.name())
      rule_fields["count"] = Json::number(entry.count.to_double())
      Json::object(rule_fields)
    }),
  )
  fields["epoch_run_counts"] = Json::array(
    summary.epoch_runs.map(fn(entry) {
      let epoch_fields = match audit_json_epoch(entry.epoch) {
        Object(value) => value
        _ => Map([])
      }
      epoch_fields["run_count"] = Json::number(entry.count.to_double())
      Json::object(epoch_fields)
    }),
  )
  fields["track_issue_count"] = Json::number(summary.track_issues.to_double())
  Json::object(fields)
}

///|
/// Render a versioned JSON audit report containing the assay configuration,
/// epoch snapshots, assessments, issues, and reconciliable track summaries.
pub fn render_audit_json(
  program : @assay.AssayProgram,
  runs : Array[@run.QCRun],
  trajectory : @evidence.Trajectory,
) -> String {
  let fields : Map[String, Json] = Map([])
  fields["schema_version"] = Json::number(1.0)
  fields["program"] = audit_json_program(program)
  let summary = audit_summary(runs, trajectory)
  fields["runs"] = Json::array(runs.map(audit_json_run))
  fields["epochs"] = Json::array(
    summary.epoch_runs.map(fn(entry) { audit_json_epoch(entry.epoch) }),
  )
  fields["summary"] = audit_json_summary(summary)
  fields["assessments"] = Json::array(
    trajectory.assessments.map(json_assessment),
  )
  fields["input_issues"] = Json::array(trajectory.input_issues.map(json_issue))
  Json::object(fields).stringify(indent=2)
}

///|
fn audit_csv_quote(value : String) -> String {
  let output = StringBuilder()
  output.write_char('"')
  for character in value.to_array() {
    if character == '"' {
      output.write_string("\"\"")
    } else {
      output.write_char(character)
    }
  }
  output.write_char('"')
  output.to_string()
}

///|
fn audit_csv_row(values : Array[String]) -> String {
  let output = StringBuilder()
  for index, value in values {
    if index > 0 {
      output.write_char(',')
    }
    output.write_string(audit_csv_quote(value))
  }
  output.to_string()
}

///|
fn audit_csv_headers() -> Array[String] {
  [
    "record_type", "assay_id", "program_unit", "program_precision", "run_id", "sequence",
    "status", "epoch_id", "reagent_lot", "control_lot", "calibration_id", "program_version",
    "rule", "scope", "reason", "issue_code", "issue_message", "point_run_id", "point_sequence",
    "point_timestamp", "control_level_id", "value_scaled", "mean_scaled", "standard_deviation_scaled",
    "threshold_scaled", "direction", "precision", "unit",
  ]
}

///|
fn audit_csv_base(
  program : @assay.AssayProgram,
  record_type : String,
  assessment : @evidence.RunAssessment?,
  run : @run.QCRun?,
) -> Array[String] {
  let epoch = match run {
    Some(value) => Some(value.epoch)
    None => None
  }
  let run_id = match assessment {
    Some(value) => value.run_id
    None =>
      match run {
        Some(value) => value.run_id
        None => ""
      }
  }
  let sequence = match assessment {
    Some(value) => value.sequence.to_string()
    None =>
      match run {
        Some(value) => value.sequence.to_string()
        None => ""
      }
  }
  let status = match assessment {
    Some(value) => value.status.name()
    None => ""
  }
  let (epoch_id, reagent_lot, control_lot, calibration_id, program_version) = match
    epoch {
    Some(value) =>
      (
        value.id,
        value.reagent_lot,
        value.control_lot,
        value.calibration_id,
        value.program_version,
      )
    None => ("", "", "", "", "")
  }
  [
    record_type,
    program.assay_id,
    program.unit,
    program.precision.to_string(),
    run_id,
    sequence,
    status,
    epoch_id,
    reagent_lot,
    control_lot,
    calibration_id,
    program_version,
  ] +
  Array::make(16, "")
}

///|
fn audit_csv_evidence(
  program : @assay.AssayProgram,
  assessment : @evidence.RunAssessment,
  run : @run.QCRun?,
  hit : @evidence.RuleHit,
  evidence : @evidence.EvidencePoint,
) -> Array[String] {
  let values = audit_csv_base(program, "evidence", Some(assessment), run)
  values[12] = hit.rule.name()
  values[13] = scope_name(hit.scope)
  values[14] = hit.reason
  values[17] = evidence.run_id
  values[18] = evidence.sequence.to_string()
  values[19] = evidence.timestamp
  values[20] = evidence.control_level_id
  values[21] = evidence.value.to_string()
  values[22] = evidence.mean.to_string()
  values[23] = evidence.standard_deviation.to_string()
  values[24] = evidence.threshold.to_string()
  values[25] = direction_name(evidence.direction)
  values[26] = evidence.precision.to_string()
  values[27] = evidence.unit
  values
}

///|
fn audit_csv_observation(
  program : @assay.AssayProgram,
  run : @run.QCRun,
  point : @run.ControlPoint,
) -> Array[String] {
  let values = audit_csv_base(program, "observation", None, Some(run))
  values[17] = run.run_id
  values[18] = run.sequence.to_string()
  values[19] = run.timestamp
  values[20] = point.control_level_id
  values[21] = point.value.to_string()
  values[26] = point.precision.to_string()
  values[27] = program.unit
  for level in program.levels {
    if level.id == point.control_level_id {
      values[22] = level.mean.to_string()
      values[23] = level.standard_deviation.to_string()
    }
  }
  values
}

///|
fn audit_csv_issue(
  program : @assay.AssayProgram,
  assessment : @evidence.RunAssessment?,
  run : @run.QCRun?,
  issue : @evidence.InputIssue,
  record_type : String,
) -> Array[String] {
  let values = audit_csv_base(program, record_type, assessment, run)
  values[15] = issue.code.name()
  values[16] = issue.message
  values
}

///|
/// Render one CSV row for each assessment, observation, evidence point, and issue.
/// Scaled measurement columns remain exact integers; `precision` states the scale.
pub fn render_audit_csv(
  program : @assay.AssayProgram,
  runs : Array[@run.QCRun],
  trajectory : @evidence.Trajectory,
) -> String {
  let output = StringBuilder()
  output.write_string(audit_csv_headers().join(","))
  output.write_char('\n')
  for index, run in runs {
    let assessment : @evidence.RunAssessment? = trajectory.assessments.get(
      index,
    )
    match assessment {
      Some(value) => {
        output.write_string(
          audit_csv_row(
            audit_csv_base(program, "assessment", Some(value), Some(run)),
          ),
        )
        output.write_char('\n')
      }
      None => ()
    }
    for point in run.observations {
      output.write_string(
        audit_csv_row(audit_csv_observation(program, run, point)),
      )
      output.write_char('\n')
    }
    match assessment {
      Some(value) => {
        for hit in value.hits {
          for evidence in hit.evidence {
            output.write_string(
              audit_csv_row(
                audit_csv_evidence(program, value, Some(run), hit, evidence),
              ),
            )
            output.write_char('\n')
          }
        }
        for issue in value.input_issues {
          output.write_string(
            audit_csv_row(
              audit_csv_issue(
                program,
                Some(value),
                Some(run),
                issue,
                "input_issue",
              ),
            ),
          )
          output.write_char('\n')
        }
      }
      None => ()
    }
  }
  for issue in trajectory.input_issues {
    let mut issue_run : @run.QCRun? = None
    for run in runs {
      if issue.run_id == Some(run.run_id) {
        issue_run = Some(run)
        break
      }
    }
    output.write_string(
      audit_csv_row(
        audit_csv_issue(program, None, issue_run, issue, "track_issue"),
      ),
    )
    output.write_char('\n')
  }
  output.to_string()
}

///|
/// Render Markdown with status, rule, and epoch counts before run evidence.
pub fn render_audit_markdown(
  program : @assay.AssayProgram,
  runs : Array[@run.QCRun],
  trajectory : @evidence.Trajectory,
) -> String {
  let summary = audit_summary(runs, trajectory)
  let output = StringBuilder()
  output.write_string("# QC replay — ")
  output.write_string(program.assay_id)
  output.write_string("\n\n## Summary\n\n")
  output.write_string("- Input runs: ")
  output.write_string(summary.input_runs.to_string())
  output.write_string("; assessed: ")
  output.write_string(summary.assessed_runs.to_string())
  output.write_string("\n- Statuses: InControl ")
  output.write_string(summary.in_control.to_string())
  output.write_string(", Warning ")
  output.write_string(summary.warning.to_string())
  output.write_string(", RequiresReview ")
  output.write_string(summary.requires_review.to_string())
  output.write_string(", Incomplete ")
  output.write_string(summary.incomplete.to_string())
  output.write_string("\n- Rule hits: ")
  if summary.total_rule_hits == 0 {
    output.write_string("none")
  } else {
    let mut first = true
    for entry in summary.rule_hits {
      if entry.count > 0 {
        if !first {
          output.write_string(", ")
        }
        output.write_string(entry.rule.name())
        output.write_char(' ')
        output.write_string(entry.count.to_string())
        first = false
      }
    }
  }
  output.write_string("\n- Epochs: ")
  if summary.epoch_runs.length() == 0 {
    output.write_string("none")
  } else {
    for index, entry in summary.epoch_runs {
      if index > 0 {
        output.write_string("; ")
      }
      output.write_string(entry.epoch.id)
      output.write_string(" ")
      output.write_string(entry.count.to_string())
      output.write_string(" run(s)")
    }
  }
  output.write_string("\n- Track issues: ")
  output.write_string(summary.track_issues.to_string())
  output.write_string("\n\n## Assessments\n\n")
  output.write_string(render_assessment_details_markdown(trajectory))
  output.to_string()
}
