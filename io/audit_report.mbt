///|
priv struct RuleHitCount {
  rule : @assay.Rule
  count : Int
}

///|
priv struct EpochRunCount {
  epoch : @epoch.QCEpoch
  count : Int
  in_control : Int
  warning : Int
  requires_review : Int
  incomplete : Int
}

///|
priv struct ControlRuleHitCount {
  control_level_id : String
  rule : @assay.Rule
  count : Int
}

///|
priv struct EpochRuleHitCount {
  epoch : @epoch.QCEpoch
  rule : @assay.Rule
  count : Int
}

///|
priv struct EpochControlRuleHitCount {
  epoch : @epoch.QCEpoch
  control_level_id : String
  rule : @assay.Rule
  count : Int
}

///|
priv struct ControlCoverageCount {
  epoch : @epoch.QCEpoch
  control_level_id : String
  required : Bool
  expected_runs : Int
  observed_runs : Int
  missing_runs : Int
  precision_mismatch_runs : Int
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
  control_rule_hits : Array[ControlRuleHitCount]
  epoch_rule_hits : Array[EpochRuleHitCount]
  epoch_control_rule_hits : Array[EpochControlRuleHitCount]
  control_coverage : Array[ControlCoverageCount]
  expected_control_observations : Int
  observed_control_observations : Int
  missing_control_observations : Int
  precision_mismatch_control_observations : Int
  required_missing_control_observations : Int
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
fn audit_increment_epoch_rule_hit(
  counts : Array[EpochRuleHitCount],
  epoch : @epoch.QCEpoch,
  rule : @assay.Rule,
) -> Unit {
  let mut match_index : Int? = None
  for index, entry in counts {
    if entry.epoch.has_same_metadata(epoch) && entry.rule == rule {
      match_index = Some(index)
      break
    }
  }
  match match_index {
    Some(index) =>
      counts[index] = {
        epoch: counts[index].epoch,
        rule: counts[index].rule,
        count: counts[index].count + 1,
      }
    None => counts.push({ epoch, rule, count: 1, })
  }
}

///|
fn audit_increment_epoch_control_rule_hit(
  counts : Array[EpochControlRuleHitCount],
  epoch : @epoch.QCEpoch,
  control_level_id : String,
  rule : @assay.Rule,
) -> Unit {
  let mut match_index : Int? = None
  for index, entry in counts {
    if entry.epoch.has_same_metadata(epoch) &&
      entry.control_level_id == control_level_id &&
      entry.rule == rule {
      match_index = Some(index)
      break
    }
  }
  match match_index {
    Some(index) =>
      counts[index] = {
        epoch: counts[index].epoch,
        control_level_id: counts[index].control_level_id,
        rule: counts[index].rule,
        count: counts[index].count + 1,
      }
    None => counts.push({ epoch, control_level_id, rule, count: 1, })
  }
}

///|
fn audit_epoch_total_rule_hits(
  counts : Array[EpochRuleHitCount],
  epoch : @epoch.QCEpoch,
) -> Int {
  let mut total = 0
  for entry in counts {
    if entry.epoch.has_same_metadata(epoch) {
      total = total + entry.count
    }
  }
  total
}

///|
fn audit_summary(
  program : @assay.AssayProgram,
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
    { rule, count, }
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
  for run_index, run in runs {
    let (run_in_control, run_warning, run_requires_review, run_incomplete) = match
      trajectory.assessments.get(run_index) {
      Some(assessment) =>
        match assessment.status {
          @evidence.InControl => (1, 0, 0, 0)
          @evidence.Warning => (0, 1, 0, 0)
          @evidence.RequiresReview => (0, 0, 1, 0)
          @evidence.Incomplete => (0, 0, 0, 1)
        }
      None => (0, 0, 0, 0)
    }
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
          in_control: epochs[index].in_control + run_in_control,
          warning: epochs[index].warning + run_warning,
          requires_review: epochs[index].requires_review + run_requires_review,
          incomplete: epochs[index].incomplete + run_incomplete,
        }
      None =>
        epochs.push({
          epoch: run.epoch,
          count: 1,
          in_control: run_in_control,
          warning: run_warning,
          requires_review: run_requires_review,
          incomplete: run_incomplete,
        })
    }
  }
  let control_rule_hits : Array[ControlRuleHitCount] = []
  for assessment in trajectory.assessments {
    for hit in assessment.hits {
      let levels : Array[String] = []
      for point in hit.evidence {
        if !contains_level(levels, point.control_level_id) {
          levels.push(point.control_level_id)
        }
      }
      for level_id in levels {
        let mut match_index : Int? = None
        for index, entry in control_rule_hits {
          if entry.control_level_id == level_id && entry.rule == hit.rule {
            match_index = Some(index)
            break
          }
        }
        match match_index {
          Some(index) =>
            control_rule_hits[index] = {
              control_level_id: control_rule_hits[index].control_level_id,
              rule: control_rule_hits[index].rule,
              count: control_rule_hits[index].count + 1,
            }
          None =>
            control_rule_hits.push({
              control_level_id: level_id,
              rule: hit.rule,
              count: 1,
            })
        }
      }
    }
  }
  let epoch_rule_hits : Array[EpochRuleHitCount] = []
  let epoch_control_rule_hits : Array[EpochControlRuleHitCount] = []
  for assessment_index, assessment in trajectory.assessments {
    match runs.get(assessment_index) {
      Some(run) =>
        for hit in assessment.hits {
          audit_increment_epoch_rule_hit(epoch_rule_hits, run.epoch, hit.rule)
          let levels : Array[String] = []
          for point in hit.evidence {
            if !contains_level(levels, point.control_level_id) {
              levels.push(point.control_level_id)
            }
          }
          for level_id in levels {
            audit_increment_epoch_control_rule_hit(
              epoch_control_rule_hits,
              run.epoch,
              level_id,
              hit.rule,
            )
          }
        }
      None => ()
    }
  }
  let control_coverage : Array[ControlCoverageCount] = []
  for epoch_entry in epochs {
    for level in program.levels {
      let mut observed_runs = 0
      let mut missing_runs = 0
      let mut precision_mismatch_runs = 0
      for run in runs {
        if run.epoch.has_same_metadata(epoch_entry.epoch) {
          let mut point : @run.ControlPoint? = None
          for observation in run.observations {
            if observation.control_level_id == level.id && point is None {
              point = Some(observation)
            }
          }
          match point {
            Some(observation) if observation.precision != program.precision =>
              precision_mismatch_runs = precision_mismatch_runs + 1
            Some(_) => observed_runs = observed_runs + 1
            None => missing_runs = missing_runs + 1
          }
        }
      }
      control_coverage.push({
        epoch: epoch_entry.epoch,
        control_level_id: level.id,
        required: level.required,
        expected_runs: epoch_entry.count,
        observed_runs,
        missing_runs,
        precision_mismatch_runs,
      })
    }
  }
  let mut expected_control_observations = 0
  let mut observed_control_observations = 0
  let mut missing_control_observations = 0
  let mut precision_mismatch_control_observations = 0
  let mut required_missing_control_observations = 0
  for coverage in control_coverage {
    expected_control_observations = expected_control_observations +
      coverage.expected_runs
    observed_control_observations = observed_control_observations +
      coverage.observed_runs
    missing_control_observations = missing_control_observations +
      coverage.missing_runs
    precision_mismatch_control_observations = precision_mismatch_control_observations +
      coverage.precision_mismatch_runs
    if coverage.required {
      required_missing_control_observations = required_missing_control_observations +
        coverage.missing_runs
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
    control_rule_hits,
    epoch_rule_hits,
    epoch_control_rule_hits,
    control_coverage,
    expected_control_observations,
    observed_control_observations,
    missing_control_observations,
    precision_mismatch_control_observations,
    required_missing_control_observations,
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
fn audit_json_run(run : @run.QCRun, source_label : String?) -> Json {
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
  match source_label {
    Some(label) => fields["source_label"] = Json::string(label)
    None => ()
  }
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
fn audit_json_epoch_rule_hits(
  summary : AuditSummary,
  epoch : @epoch.QCEpoch,
) -> Json {
  let hits : Array[Json] = []
  for entry in summary.epoch_rule_hits {
    if entry.epoch.has_same_metadata(epoch) {
      hits.push(
        Json::object({
          "rule": Json::string(entry.rule.name()),
          "count": Json::number(entry.count.to_double()),
        }),
      )
    }
  }
  Json::array(hits)
}

///|
fn audit_json_epoch_control_rule_hits(
  summary : AuditSummary,
  epoch : @epoch.QCEpoch,
) -> Json {
  let hits : Array[Json] = []
  for entry in summary.epoch_control_rule_hits {
    if entry.epoch.has_same_metadata(epoch) {
      hits.push(
        Json::object({
          "control_level_id": Json::string(entry.control_level_id),
          "rule": Json::string(entry.rule.name()),
          "count": Json::number(entry.count.to_double()),
        }),
      )
    }
  }
  Json::array(hits)
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
      epoch_fields["status_counts"] = Json::object({
        "InControl": Json::number(entry.in_control.to_double()),
        "Warning": Json::number(entry.warning.to_double()),
        "RequiresReview": Json::number(entry.requires_review.to_double()),
        "Incomplete": Json::number(entry.incomplete.to_double()),
      })
      epoch_fields["rule_hit_counts"] = audit_json_epoch_rule_hits(
        summary,
        entry.epoch,
      )
      epoch_fields["control_rule_hit_counts"] = audit_json_epoch_control_rule_hits(
        summary,
        entry.epoch,
      )
      Json::object(epoch_fields)
    }),
  )
  fields["control_rule_hit_counts"] = Json::array(
    summary.control_rule_hits.map(fn(entry) {
      let control_fields : Map[String, Json] = Map([])
      control_fields["control_level_id"] = Json::string(entry.control_level_id)
      control_fields["rule"] = Json::string(entry.rule.name())
      control_fields["count"] = Json::number(entry.count.to_double())
      Json::object(control_fields)
    }),
  )
  fields["control_observation_coverage"] = Json::array(
    summary.control_coverage.map(fn(entry) {
      let coverage_fields = match audit_json_epoch(entry.epoch) {
        Object(value) => value
        _ => Map([])
      }
      coverage_fields["control_level_id"] = Json::string(entry.control_level_id)
      coverage_fields["required"] = Json::boolean(entry.required)
      coverage_fields["expected_runs"] = Json::number(
        entry.expected_runs.to_double(),
      )
      coverage_fields["observed_runs"] = Json::number(
        entry.observed_runs.to_double(),
      )
      coverage_fields["missing_runs"] = Json::number(
        entry.missing_runs.to_double(),
      )
      coverage_fields["precision_mismatch_runs"] = Json::number(
        entry.precision_mismatch_runs.to_double(),
      )
      Json::object(coverage_fields)
    }),
  )
  fields["control_observation_counts"] = Json::object({
    "expected": Json::number(summary.expected_control_observations.to_double()),
    "observed": Json::number(summary.observed_control_observations.to_double()),
    "missing": Json::number(summary.missing_control_observations.to_double()),
    "precision_mismatch": Json::number(
      summary.precision_mismatch_control_observations.to_double(),
    ),
    "required_missing": Json::number(
      summary.required_missing_control_observations.to_double(),
    ),
  })
  fields["track_issue_count"] = Json::number(summary.track_issues.to_double())
  Json::object(fields)
}

///|
/// Render a versioned JSON audit report containing the assay configuration,
/// epoch snapshots, assessments, issues, and reconciliable track summaries.
fn render_audit_json_inner(
  program : @assay.AssayProgram,
  runs : Array[@run.QCRun],
  trajectory : @evidence.Trajectory,
  source_labels : Array[String]?,
) -> String {
  let fields : Map[String, Json] = Map([])
  fields["schema_version"] = Json::number(
    if source_labels is Some(_) {
      2.0
    } else {
      1.0
    },
  )
  fields["program"] = audit_json_program(program)
  let summary = audit_summary(program, runs, trajectory)
  let run_json : Array[Json] = []
  for index, run in runs {
    let source_label = match source_labels {
      Some(labels) => labels.get(index).map(report_source_label)
      None => None
    }
    run_json.push(audit_json_run(run, source_label))
  }
  fields["runs"] = Json::array(run_json)
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
/// Render a versioned JSON audit report containing the assay configuration,
/// epoch snapshots, assessments, issues, and reconciliable track summaries.
pub fn render_audit_json(
  program : @assay.AssayProgram,
  runs : Array[@run.QCRun],
  trajectory : @evidence.Trajectory,
) -> String {
  render_audit_json_inner(program, runs, trajectory, None)
}

///|
/// Render a batch JSON report with a source label on every run and schema
/// version 2. Labels are reduced to display names so filesystem paths are not
/// written into review artifacts.
pub fn render_audit_json_batch(
  program : @assay.AssayProgram,
  sourced_runs : Array[SourcedQCRun],
  trajectory : @evidence.Trajectory,
) -> String {
  let runs = sourced_runs.map(fn(entry) { entry.run })
  let labels = sourced_runs.map(fn(entry) { entry.source_label })
  render_audit_json_inner(program, runs, trajectory, Some(labels))
}

///|
/// Render a deterministic manifest for the files produced by the offline
/// review bundle. The manifest contains no source path or wall-clock time.
fn render_audit_manifest_inner(
  program : @assay.AssayProgram,
  runs : Array[@run.QCRun],
  trajectory : @evidence.Trajectory,
  source_labels : Array[String]?,
) -> String {
  let summary = audit_summary(program, runs, trajectory)
  let fields : Map[String, Json] = Map([])
  fields["schema_version"] = Json::number(1.0)
  fields["report_schema_version"] = Json::number(
    if source_labels is Some(_) {
      2.0
    } else {
      1.0
    },
  )
  fields["assay_id"] = Json::string(program.assay_id)
  fields["counts"] = Json::object({
    "input_runs": Json::number(summary.input_runs.to_double()),
    "assessed_runs": Json::number(summary.assessed_runs.to_double()),
    "epoch_count": Json::number(summary.epoch_runs.length().to_double()),
    "track_issue_count": Json::number(summary.track_issues.to_double()),
    "rule_hit_count": Json::number(summary.total_rule_hits.to_double()),
    "expected_control_observations": Json::number(
      summary.expected_control_observations.to_double(),
    ),
    "observed_control_observations": Json::number(
      summary.observed_control_observations.to_double(),
    ),
    "missing_control_observations": Json::number(
      summary.missing_control_observations.to_double(),
    ),
    "precision_mismatch_control_observations": Json::number(
      summary.precision_mismatch_control_observations.to_double(),
    ),
    "required_missing_control_observations": Json::number(
      summary.required_missing_control_observations.to_double(),
    ),
    "status_counts": Json::object({
      "InControl": Json::number(summary.in_control.to_double()),
      "Warning": Json::number(summary.warning.to_double()),
      "RequiresReview": Json::number(summary.requires_review.to_double()),
      "Incomplete": Json::number(summary.incomplete.to_double()),
    }),
  })
  fields["epoch_rule_hit_counts"] = Json::array(
    summary.epoch_runs.map(fn(entry) {
      Json::object({
        "epoch_id": Json::string(entry.epoch.id),
        "run_count": Json::number(entry.count.to_double()),
        "rule_hit_counts": audit_json_epoch_rule_hits(summary, entry.epoch),
        "control_rule_hit_counts": audit_json_epoch_control_rule_hits(
          summary,
          entry.epoch,
        ),
      })
    }),
  )
  fields["artifacts"] = Json::array(
    [
      {
        "path": Json::string("report.html"),
        "media_type": Json::string("text/html"),
      },
      {
        "path": Json::string("audit.json"),
        "media_type": Json::string("application/json"),
      },
      {
        "path": Json::string("audit.csv"),
        "media_type": Json::string("text/csv"),
      },
      {
        "path": Json::string("chart.svg"),
        "media_type": Json::string("image/svg+xml"),
      },
      {
        "path": Json::string("manifest.json"),
        "media_type": Json::string("application/json"),
      },
    ].map(fn(artifact) { Json::object(artifact) }),
  )
  match source_labels {
    Some(labels) => {
      let unique_labels : Array[String] = []
      for label in labels {
        let safe_label = report_source_label(label)
        if !unique_labels.contains(safe_label) {
          unique_labels.push(safe_label)
        }
      }
      fields["source_labels"] = Json::array(unique_labels.map(Json::string))
    }
    None => ()
  }
  Json::object(fields).stringify(indent=2)
}

///|
/// Render a deterministic manifest for the files produced by the offline
/// review bundle. The manifest contains no source path or wall-clock time.
pub fn render_audit_manifest(
  program : @assay.AssayProgram,
  runs : Array[@run.QCRun],
  trajectory : @evidence.Trajectory,
) -> String {
  render_audit_manifest_inner(program, runs, trajectory, None)
}

///|
/// Render a deterministic batch manifest with sanitized source display names.
pub fn render_audit_manifest_batch(
  program : @assay.AssayProgram,
  sourced_runs : Array[SourcedQCRun],
  trajectory : @evidence.Trajectory,
) -> String {
  let runs = sourced_runs.map(fn(entry) { entry.run })
  let labels = sourced_runs.map(fn(entry) { entry.source_label })
  render_audit_manifest_inner(program, runs, trajectory, Some(labels))
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
fn audit_csv_headers(include_source : Bool) -> Array[String] {
  [
    "record_type", "assay_id", "program_unit", "program_precision", "run_id", "sequence",
    "status", "epoch_id", "reagent_lot", "control_lot", "calibration_id", "program_version",
    "rule", "scope", "reason", "issue_code", "issue_message", "point_run_id", "point_sequence",
    "point_timestamp", "control_level_id", "value_scaled", "mean_scaled", "standard_deviation_scaled",
    "threshold_scaled", "direction", "precision", "unit",
  ] +
  (if include_source { ["source_label"] } else { [] })
}

///|
fn audit_csv_row_with_source(
  values : Array[String],
  source_label : String?,
) -> Array[String] {
  match source_label {
    Some(label) => values + [report_source_label(label)]
    None => values
  }
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
fn render_audit_csv_inner(
  program : @assay.AssayProgram,
  runs : Array[@run.QCRun],
  trajectory : @evidence.Trajectory,
  source_labels : Array[String]?,
) -> String {
  let output = StringBuilder()
  output.write_string(audit_csv_headers(source_labels is Some(_)).join(","))
  output.write_char('\n')
  for index, run in runs {
    let source_label = match source_labels {
      Some(labels) => labels.get(index)
      None => None
    }
    let assessment : @evidence.RunAssessment? = trajectory.assessments.get(
      index,
    )
    match assessment {
      Some(value) => {
        output.write_string(
          audit_csv_row(
            audit_csv_row_with_source(
              audit_csv_base(program, "assessment", Some(value), Some(run)),
              source_label,
            ),
          ),
        )
        output.write_char('\n')
      }
      None => ()
    }
    for point in run.observations {
      output.write_string(
        audit_csv_row(
          audit_csv_row_with_source(
            audit_csv_observation(program, run, point),
            source_label,
          ),
        ),
      )
      output.write_char('\n')
    }
    match assessment {
      Some(value) => {
        for hit in value.hits {
          for evidence in hit.evidence {
            output.write_string(
              audit_csv_row(
                audit_csv_row_with_source(
                  audit_csv_evidence(program, value, Some(run), hit, evidence),
                  source_label,
                ),
              ),
            )
            output.write_char('\n')
          }
        }
        for issue in value.input_issues {
          output.write_string(
            audit_csv_row(
              audit_csv_row_with_source(
                audit_csv_issue(
                  program,
                  Some(value),
                  Some(run),
                  issue,
                  "input_issue",
                ),
                source_label,
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
    let mut issue_source : String? = None
    for index, run in runs {
      if issue.run_id == Some(run.run_id) {
        issue_run = Some(run)
        issue_source = match source_labels {
          Some(labels) => labels.get(index)
          None => None
        }
        break
      }
    }
    output.write_string(
      audit_csv_row(
        audit_csv_row_with_source(
          audit_csv_issue(program, None, issue_run, issue, "track_issue"),
          issue_source,
        ),
      ),
    )
    output.write_char('\n')
  }
  output.to_string()
}

///|
/// Render one CSV row for each assessment, observation, evidence point, and issue.
/// Scaled measurement columns remain exact integers; `precision` states the scale.
pub fn render_audit_csv(
  program : @assay.AssayProgram,
  runs : Array[@run.QCRun],
  trajectory : @evidence.Trajectory,
) -> String {
  render_audit_csv_inner(program, runs, trajectory, None)
}

///|
/// Render a batch CSV audit table with a `source_label` column on every
/// run-associated record.
pub fn render_audit_csv_batch(
  program : @assay.AssayProgram,
  sourced_runs : Array[SourcedQCRun],
  trajectory : @evidence.Trajectory,
) -> String {
  let runs = sourced_runs.map(fn(entry) { entry.run })
  let labels = sourced_runs.map(fn(entry) { entry.source_label })
  render_audit_csv_inner(program, runs, trajectory, Some(labels))
}

///|
/// Render Markdown with status, rule, and epoch counts before run evidence.
pub fn render_audit_markdown(
  program : @assay.AssayProgram,
  runs : Array[@run.QCRun],
  trajectory : @evidence.Trajectory,
) -> String {
  let summary = audit_summary(program, runs, trajectory)
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
  output.write_string("\n- Epoch rule hits: ")
  let mut has_epoch_rule_hit = false
  for entry in summary.epoch_rule_hits {
    if !has_epoch_rule_hit {
      has_epoch_rule_hit = true
    } else {
      output.write_string("; ")
    }
    output.write_string(entry.epoch.id)
    output.write_char(' ')
    output.write_string(entry.rule.name())
    output.write_char(' ')
    output.write_string(entry.count.to_string())
  }
  if !has_epoch_rule_hit {
    output.write_string("none")
  }
  output.write_string("\n- Epoch/control rule hits: ")
  let mut has_epoch_control_rule_hit = false
  for entry in summary.epoch_control_rule_hits {
    if !has_epoch_control_rule_hit {
      has_epoch_control_rule_hit = true
    } else {
      output.write_string("; ")
    }
    output.write_string(entry.epoch.id)
    output.write_char(' ')
    output.write_string(entry.control_level_id)
    output.write_char('/')
    output.write_string(entry.rule.name())
    output.write_char(' ')
    output.write_string(entry.count.to_string())
  }
  if !has_epoch_control_rule_hit {
    output.write_string("none")
  }
  output.write_string("\n- Track issues: ")
  output.write_string(summary.track_issues.to_string())
  output.write_string("\n\n## Assessments\n\n")
  output.write_string(render_assessment_details_markdown(trajectory))
  output.to_string()
}
