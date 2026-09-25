///|
fn format_scaled(value : Int64, precision : Int) -> String {
  let raw = value.to_string()
  let negative = raw.has_prefix("-")
  let digits = if negative { raw.sub(start=1).to_owned() } else { raw }
  if precision == 0 {
    if negative {
      "-" + digits
    } else {
      digits
    }
  } else {
    let padded = digits.pad_start(precision + 1, '0')
    let split = padded.length() - precision
    let whole = padded.sub(end=split).to_owned()
    let fraction = padded.sub(start=split).to_owned()
    if negative {
      "-" + whole + "." + fraction
    } else {
      whole + "." + fraction
    }
  }
}

///|
fn direction_name(direction : @evidence.Direction) -> String {
  match direction {
    @evidence.Above => "above"
    @evidence.Below => "below"
    @evidence.SameSide => "same-side"
  }
}

///|
fn scope_name(scope : @evidence.RuleScope) -> String {
  match scope {
    @evidence.SingleObservation => "single-observation"
    @evidence.SameRun => "same-run"
    @evidence.ConsecutiveRuns => "consecutive-runs"
  }
}

///|
fn json_number(value : Int64) -> Json {
  Json::number(value.to_double(), repr=value.to_string())
}

///|
fn json_issue(issue : @evidence.InputIssue) -> Json {
  let fields : Map[String, Json] = Map([])
  fields["code"] = Json::string(issue.code.name())
  fields["run_id"] = match issue.run_id {
    Some(run_id) => Json::string(run_id)
    None => Json::null()
  }
  fields["message"] = Json::string(issue.message)
  Json::object(fields)
}

///|
fn json_evidence(point : @evidence.EvidencePoint) -> Json {
  let fields : Map[String, Json] = Map([])
  fields["run_id"] = Json::string(point.run_id)
  fields["epoch_id"] = Json::string(point.epoch_id)
  fields["sequence"] = json_number(point.sequence)
  fields["timestamp"] = Json::string(point.timestamp)
  fields["control_level_id"] = Json::string(point.control_level_id)
  fields["value"] = json_number(point.value)
  fields["mean"] = json_number(point.mean)
  fields["standard_deviation"] = json_number(point.standard_deviation)
  fields["threshold_distance"] = json_number(point.threshold)
  fields["direction"] = Json::string(direction_name(point.direction))
  fields["precision"] = Json::number(point.precision.to_double())
  fields["unit"] = Json::string(point.unit)
  Json::object(fields)
}

///|
fn json_hit(hit : @evidence.RuleHit) -> Json {
  let fields : Map[String, Json] = Map([])
  fields["rule"] = Json::string(hit.rule.name())
  fields["scope"] = Json::string(scope_name(hit.scope))
  fields["reason"] = Json::string(hit.reason)
  fields["evidence"] = Json::array(hit.evidence.map(json_evidence))
  Json::object(fields)
}

///|
fn json_assessment(assessment : @evidence.RunAssessment) -> Json {
  let fields : Map[String, Json] = Map([])
  fields["run_id"] = Json::string(assessment.run_id)
  fields["sequence"] = json_number(assessment.sequence)
  fields["status"] = Json::string(assessment.status.name())
  fields["hits"] = Json::array(assessment.hits.map(json_hit))
  fields["input_issues"] = Json::array(assessment.input_issues.map(json_issue))
  Json::object(fields)
}

///|
pub fn render_trajectory_json(trajectory : @evidence.Trajectory) -> String {
  let fields : Map[String, Json] = Map([])
  fields["assessments"] = Json::array(
    trajectory.assessments.map(json_assessment),
  )
  fields["input_issues"] = Json::array(trajectory.input_issues.map(json_issue))
  Json::object(fields).stringify(indent=2)
}

///|
fn render_assessment_details_markdown(
  trajectory : @evidence.Trajectory,
) -> String {
  let output = StringBuilder()
  for assessment in trajectory.assessments {
    output.write_string("## Run ")
    output.write_string(assessment.run_id)
    output.write_string(" (sequence ")
    output.write_string(assessment.sequence.to_string())
    output.write_string(") — ")
    output.write_string(assessment.status.name())
    output.write_string("\n\n")
    if assessment.hits.length() == 0 {
      output.write_string("No rule hits.\n\n")
    } else {
      for hit in assessment.hits {
        output.write_string("- **")
        output.write_string(hit.rule.name())
        output.write_string("** (")
        output.write_string(scope_name(hit.scope))
        output.write_string("): ")
        output.write_string(hit.reason)
        output.write_string("\n")
        for point in hit.evidence {
          output.write_string("  - ")
          output.write_string(point.run_id)
          output.write_string(" / ")
          output.write_string(point.control_level_id)
          output.write_string(": value ")
          output.write_string(format_scaled(point.value, point.precision))
          output.write_string(" ")
          output.write_string(point.unit)
          output.write_string("; mean ")
          output.write_string(format_scaled(point.mean, point.precision))
          output.write_string("; threshold distance ")
          output.write_string(format_scaled(point.threshold, point.precision))
          output.write_string(" (")
          output.write_string(direction_name(point.direction))
          output.write_string(")\n")
        }
      }
      output.write_string("\n")
    }
    for input_issue in assessment.input_issues {
      output.write_string("- Input issue [")
      output.write_string(input_issue.code.name())
      output.write_string("]: ")
      output.write_string(input_issue.message)
      output.write_string("\n")
    }
    if assessment.input_issues.length() > 0 {
      output.write_string("\n")
    }
  }
  for input_issue in trajectory.input_issues {
    output.write_string("- Track issue [")
    output.write_string(input_issue.code.name())
    output.write_string("]: ")
    output.write_string(input_issue.message)
    output.write_string("\n")
  }
  output.to_string()
}

///|
pub fn render_trajectory_markdown(trajectory : @evidence.Trajectory) -> String {
  "# QC replay\n\n" + render_assessment_details_markdown(trajectory)
}
