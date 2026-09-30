///|
pub(all) enum Rule {
  Rule12s
  Rule13s
  Rule22s
  RuleR4s
  Rule41s
  Rule10x
} derive(Eq, Debug)

///|
pub fn Rule::name(self : Rule) -> String {
  match self {
    Rule12s => "1_2s"
    Rule13s => "1_3s"
    Rule22s => "2_2s"
    RuleR4s => "R_4s"
    Rule41s => "4_1s"
    Rule10x => "10x"
  }
}

///|
pub fn Rule::default_disposition(self : Rule) -> RuleDisposition {
  match self {
    Rule12s => Warning
    _ => RequiresReview
  }
}

///|
pub(all) enum RuleDisposition {
  Disabled
  Warning
  RequiresReview
} derive(Eq, Debug)

///|
pub(all) struct RulePolicy {
  rule : Rule
  disposition : RuleDisposition
} derive(Debug)

///|
pub(all) struct ControlLevel {
  id : String
  mean : Int64
  standard_deviation : Int64
  required : Bool
} derive(Debug)

///|
pub(all) struct AssayProgram {
  assay_id : String
  unit : String
  precision : Int
  levels : Array[ControlLevel]
  rule_policies : Array[RulePolicy]
} derive(Debug)

///|
pub(all) struct ValidationResult {
  issues : Array[String]
} derive(Debug)

///|
pub extend Rule with Eq::{not_equal, equal}

///|
pub extend Rule with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend RuleDisposition with Eq::{not_equal, equal}

///|
pub extend RuleDisposition with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend RulePolicy with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend ControlLevel with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend AssayProgram with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend ValidationResult with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub fn ValidationResult::is_valid(self : ValidationResult) -> Bool {
  self.issues.length() == 0
}

///|
pub fn default_rule_policies() -> Array[RulePolicy] {
  [
    { rule: Rule12s, disposition: Warning, },
    { rule: Rule13s, disposition: RequiresReview, },
    { rule: Rule22s, disposition: RequiresReview, },
    { rule: RuleR4s, disposition: RequiresReview, },
    { rule: Rule41s, disposition: RequiresReview, },
    { rule: Rule10x, disposition: RequiresReview, },
  ]
}

///|
pub fn AssayProgram::disposition_for(
  self : AssayProgram,
  rule : Rule,
) -> RuleDisposition {
  for policy in self.rule_policies {
    if policy.rule == rule {
      return policy.disposition
    }
  }
  rule.default_disposition()
}

///|
pub fn validate_program(program : AssayProgram) -> ValidationResult {
  let issues : Array[String] = []
  if program.assay_id.trim().is_empty() {
    issues.push("assay_id must not be empty")
  }
  if program.unit.trim().is_empty() {
    issues.push("unit must not be empty")
  }
  if program.precision < 0 || program.precision > 18 {
    issues.push("precision must be between 0 and 18")
  }
  if program.levels.length() == 0 {
    issues.push("at least one control level is required")
  }
  for i, level in program.levels {
    if level.id.trim().is_empty() {
      issues.push("control level id must not be empty")
    }
    if level.standard_deviation <= 0L {
      issues.push("standard deviation must be positive for level " + level.id)
    }
    for j in 0..<i {
      if program.levels[j].id == level.id {
        issues.push("duplicate control level id: " + level.id)
      }
    }
  }
  for i, policy in program.rule_policies {
    for j in 0..<i {
      if program.rule_policies[j].rule == policy.rule {
        issues.push("duplicate rule policy: " + policy.rule.name())
      }
    }
  }
  { issues, }
}
