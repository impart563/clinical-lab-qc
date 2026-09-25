///|
priv struct ProgramConfigFile {
  schema_version : Int
  assay_id : String
  unit : String
  precision : Int
  levels : Array[ControlLevelConfigFile]
  rules : Array[RulePolicyConfigFile]
} derive(FromJson)

///|
priv struct ControlLevelConfigFile {
  id : String
  mean : String
  standard_deviation : String
  required : Bool
} derive(FromJson)

///|
priv struct RulePolicyConfigFile {
  rule : String
  disposition : String
} derive(FromJson)

///|
pub(all) struct ProgramConfigResult {
  program : @assay.AssayProgram?
  issues : Array[String]
} derive(Debug)

///|
fn config_contains(values : Array[String], value : String) -> Bool {
  for item in values {
    if item == value {
      return true
    }
  }
  false
}

///|
fn config_unknown_fields(
  value : Json,
  allowed : Array[String],
  path : String,
  issues : Array[String],
) -> Unit {
  match value {
    Object(fields) =>
      for key, _ in fields {
        if !config_contains(allowed, key) {
          issues.push("unsupported field " + path + "." + key)
        }
      }
    _ => ()
  }
}

///|
fn validate_config_fields(value : Json, issues : Array[String]) -> Unit {
  match value {
    Object(fields) => {
      config_unknown_fields(
        value,
        ["schema_version", "assay_id", "unit", "precision", "levels", "rules"],
        "$",
        issues,
      )
      match fields.get("levels") {
        Some(Array(levels)) =>
          for index, level in levels {
            config_unknown_fields(
              level,
              ["id", "mean", "standard_deviation", "required"],
              "$.levels[" + index.to_string() + "]",
              issues,
            )
          }
        _ => ()
      }
      match fields.get("rules") {
        Some(Array(rules)) =>
          for index, rule in rules {
            config_unknown_fields(
              rule,
              ["rule", "disposition"],
              "$.rules[" + index.to_string() + "]",
              issues,
            )
          }
        _ => ()
      }
    }
    _ => ()
  }
}

///|
fn config_rule(name : String) -> @assay.Rule? {
  match name {
    "1_2s" => Some(@assay.Rule12s)
    "1_3s" => Some(@assay.Rule13s)
    "2_2s" => Some(@assay.Rule22s)
    "R_4s" => Some(@assay.RuleR4s)
    "4_1s" => Some(@assay.Rule41s)
    "10x" => Some(@assay.Rule10x)
    _ => None
  }
}

///|
fn config_disposition(name : String) -> @assay.RuleDisposition? {
  match name {
    "disabled" => Some(@assay.Disabled)
    "warning" => Some(@assay.Warning)
    "requires_review" => Some(@assay.RequiresReview)
    _ => None
  }
}

///|
/// Parse a versioned JSON assay configuration and validate the resulting program.
/// Decimal values are strings so conversion to the program's scaled Int64 values
/// never passes through floating-point arithmetic.
pub fn parse_assay_program_json(text : String) -> ProgramConfigResult {
  let json = @json.parse(text) catch {
    error =>
      return { program: None, issues: ["invalid JSON: " + error.to_string()] }
  }
  let shape_issues : Array[String] = []
  validate_config_fields(json, shape_issues)
  if shape_issues.length() > 0 {
    return { program: None, issues: shape_issues }
  }
  let config : ProgramConfigFile = @json.from_json(json) catch {
    error =>
      return {
        program: None,
        issues: ["invalid program configuration: " + error.to_string()],
      }
  }
  if config.schema_version != 1 {
    return {
      program: None,
      issues: [
        "unsupported schema_version " +
        config.schema_version.to_string() +
        "; supported version is 1",
      ],
    }
  }
  let issues : Array[String] = []
  if config.precision < 0 || config.precision > 18 {
    issues.push("precision must be between 0 and 18")
  }
  let levels : Array[@assay.ControlLevel] = []
  for index, level in config.levels {
    let mean = match parse_scaled(level.mean, config.precision) {
      Parsed(value) => Some(value)
      Missing => {
        issues.push("levels[" + index.to_string() + "].mean must not be empty")
        None
      }
      Invalid(message) => {
        issues.push("levels[" + index.to_string() + "].mean: " + message)
        None
      }
    }
    let standard_deviation = match
      parse_scaled(level.standard_deviation, config.precision) {
      Parsed(value) => Some(value)
      Missing => {
        issues.push(
          "levels[" +
          index.to_string() +
          "].standard_deviation must not be empty",
        )
        None
      }
      Invalid(message) => {
        issues.push(
          "levels[" + index.to_string() + "].standard_deviation: " + message,
        )
        None
      }
    }
    if mean is Some(mean_value) && standard_deviation is Some(sd_value) {
      levels.push({
        id: level.id,
        mean: mean_value,
        standard_deviation: sd_value,
        required: level.required,
      })
    }
  }
  let rule_policies : Array[@assay.RulePolicy] = []
  for index, policy in config.rules {
    let rule = config_rule(policy.rule)
    let disposition = config_disposition(policy.disposition)
    if rule is None {
      issues.push(
        "rules[" + index.to_string() + "].rule is unknown: " + policy.rule,
      )
    }
    if disposition is None {
      issues.push(
        "rules[" +
        index.to_string() +
        "].disposition is unknown: " +
        policy.disposition,
      )
    }
    match (rule, disposition) {
      (Some(rule_value), Some(disposition_value)) =>
        rule_policies.push({ rule: rule_value, disposition: disposition_value })
      _ => ()
    }
  }
  if issues.length() > 0 {
    return { program: None, issues }
  }
  let program : @assay.AssayProgram = {
    assay_id: config.assay_id,
    unit: config.unit,
    precision: config.precision,
    levels,
    rule_policies,
  }
  let validation = @assay.validate_program(program)
  if validation.issues.length() > 0 {
    for issue in validation.issues {
      issues.push(issue)
    }
    return { program: None, issues }
  }
  { program: Some(program), issues }
}
