///|
pub(all) struct SignalResult {
  hits : Array[@evidence.RuleHit]
  issues : Array[@evidence.InputIssue]
} derive(Debug)

///|
priv struct Sample {
  run : @run.QCRun
  point : @run.ControlPoint
}

///|
fn make_issue(run_id : String, message : String) -> @evidence.InputIssue {
  { code: @evidence.ArithmeticOverflow, run_id: Some(run_id), message }
}

///|
fn checked_sub(a : Int64, b : Int64) -> Int64? {
  let result = a - b
  if (b > 0L && result > a) || (b < 0L && result < a) {
    None
  } else {
    Some(result)
  }
}

///|
fn checked_mul_positive(a : Int64, b : Int64) -> Int64? {
  if b <= 0L {
    None
  } else {
    let result = a * b
    if result / b == a {
      Some(result)
    } else {
      None
    }
  }
}

///|
fn find_level(
  program : @assay.AssayProgram,
  id : String,
) -> @assay.ControlLevel? {
  for level in program.levels {
    if level.id == id {
      return Some(level)
    }
  }
  None
}

///|
fn find_point(run : @run.QCRun, id : String) -> @run.ControlPoint? {
  for point in run.observations {
    if point.control_level_id == id {
      return Some(point)
    }
  }
  None
}

///|
fn collect_samples(
  level_id : String,
  history : Array[@run.QCRun],
  current : @run.QCRun,
) -> Array[Sample] {
  let samples : Array[Sample] = []
  for previous in history {
    match find_point(previous, level_id) {
      Some(point) => samples.push({ run: previous, point })
      None => samples.clear()
    }
  }
  match find_point(current, level_id) {
    Some(point) => samples.push({ run: current, point })
    None => ()
  }
  samples
}

///|
fn evidence_point(
  sample : Sample,
  level : @assay.ControlLevel,
  unit : String,
  threshold : Int64,
  direction : @evidence.Direction,
) -> @evidence.EvidencePoint {
  {
    run_id: sample.run.run_id,
    epoch_id: sample.run.epoch.id,
    sequence: sample.run.sequence,
    timestamp: sample.run.timestamp,
    control_level_id: level.id,
    value: sample.point.value,
    precision: sample.point.precision,
    unit,
    mean: level.mean,
    standard_deviation: level.standard_deviation,
    threshold,
    direction,
  }
}

///|
fn deviation(value : Int64, mean : Int64) -> Int64? {
  checked_sub(value, mean)
}

///|
fn direction_for(delta : Int64) -> @evidence.Direction {
  if delta > 0L {
    @evidence.Above
  } else {
    @evidence.Below
  }
}

///|
fn add_single_rule_hits(
  program : @assay.AssayProgram,
  run : @run.QCRun,
  hits : Array[@evidence.RuleHit],
  issues : Array[@evidence.InputIssue],
) -> Unit {
  for point in run.observations {
    match find_level(program, point.control_level_id) {
      None => ()
      Some(level) => {
        add_point_rule(
          program,
          run,
          point,
          level,
          @assay.Rule12s,
          2L,
          hits,
          issues,
        )
        add_point_rule(
          program,
          run,
          point,
          level,
          @assay.Rule13s,
          3L,
          hits,
          issues,
        )
      }
    }
  }
}

///|
fn add_point_rule(
  program : @assay.AssayProgram,
  run : @run.QCRun,
  point : @run.ControlPoint,
  level : @assay.ControlLevel,
  rule : @assay.Rule,
  multiplier : Int64,
  hits : Array[@evidence.RuleHit],
  issues : Array[@evidence.InputIssue],
) -> Unit {
  if program.disposition_for(rule) != @assay.Disabled {
    match deviation(point.value, level.mean) {
      None =>
        issues.push(
          make_issue(
            run.run_id,
            "observation minus mean overflowed for " + level.id,
          ),
        )
      Some(delta) =>
        match checked_mul_positive(level.standard_deviation, multiplier) {
          None =>
            issues.push(
              make_issue(
                run.run_id,
                "threshold multiplication overflowed for " + level.id,
              ),
            )
          Some(threshold) => {
            let magnitude = if delta < 0L {
              checked_sub(0L, delta)
            } else {
              Some(delta)
            }
            match magnitude {
              None =>
                issues.push(
                  make_issue(
                    run.run_id,
                    "absolute deviation overflowed for " + level.id,
                  ),
                )
              Some(distance) =>
                if distance > threshold {
                  let evidence = evidence_point(
                    { run, point },
                    level,
                    program.unit,
                    threshold,
                    direction_for(delta),
                  )
                  let reason = "value is strictly beyond " +
                    rule.name() +
                    " for " +
                    level.id
                  hits.push({
                    rule,
                    scope: @evidence.SingleObservation,
                    evidence: [evidence],
                    reason,
                  })
                }
            }
          }
        }
    }
  }
}

///|
fn is_beyond_same_side(
  samples : Array[Sample],
  level : @assay.ControlLevel,
  unit : String,
  count : Int,
  multiplier : Int64,
) -> (Bool, Array[@evidence.EvidencePoint], Int64?) {
  if samples.length() < count {
    return (false, [], None)
  }
  let threshold = match
    checked_mul_positive(level.standard_deviation, multiplier) {
    Some(value) => value
    None => return (false, [], None)
  }
  let start = samples.length() - count
  let mut side : Int64? = None
  let evidence : Array[@evidence.EvidencePoint] = []
  for i in start..<samples.length() {
    let sample = samples[i]
    let delta = match deviation(sample.point.value, level.mean) {
      Some(value) => value
      None => return (false, [], None)
    }
    if delta == 0L || (side is Some(prior) && (prior > 0L) != (delta > 0L)) {
      return (false, [], Some(threshold))
    }
    let distance = if delta < 0L { checked_sub(0L, delta) } else { Some(delta) }
    match distance {
      None => return (false, [], None)
      Some(value) =>
        if value <= threshold {
          return (false, [], Some(threshold))
        }
    }
    side = Some(delta)
    evidence.push(
      evidence_point(sample, level, unit, threshold, direction_for(delta)),
    )
  }
  (true, evidence, Some(threshold))
}

///|
fn add_window_hits(
  program : @assay.AssayProgram,
  run : @run.QCRun,
  history : Array[@run.QCRun],
  hits : Array[@evidence.RuleHit],
  issues : Array[@evidence.InputIssue],
) -> Unit {
  for point in run.observations {
    match find_level(program, point.control_level_id) {
      None => ()
      Some(level) => {
        let samples = collect_samples(level.id, history, run)
        add_same_side_window_hit(
          program,
          run,
          level,
          samples,
          @assay.Rule22s,
          2,
          2L,
          hits,
          issues,
        )
        add_same_side_window_hit(
          program,
          run,
          level,
          samples,
          @assay.Rule41s,
          4,
          1L,
          hits,
          issues,
        )
        if program.disposition_for(@assay.Rule10x) != @assay.Disabled &&
          samples.length() >= 10 {
          let start = samples.length() - 10
          let first_delta = deviation(samples[start].point.value, level.mean)
          match first_delta {
            None =>
              issues.push(
                make_issue(
                  run.run_id,
                  "10x deviation overflowed for " + level.id,
                ),
              )
            Some(first) =>
              if first != 0L {
                let mut same_side = true
                let evidence : Array[@evidence.EvidencePoint] = []
                for i in start..<samples.length() {
                  let sample = samples[i]
                  match deviation(sample.point.value, level.mean) {
                    None => {
                      same_side = false
                      issues.push(
                        make_issue(
                          run.run_id,
                          "10x deviation overflowed for " + level.id,
                        ),
                      )
                    }
                    Some(delta) => {
                      if delta == 0L || (delta > 0L) != (first > 0L) {
                        same_side = false
                      }
                      evidence.push(
                        evidence_point(
                          sample,
                          level,
                          program.unit,
                          0L,
                          @evidence.SameSide,
                        ),
                      )
                    }
                  }
                }
                if same_side {
                  hits.push({
                    rule: @assay.Rule10x,
                    scope: @evidence.ConsecutiveRuns,
                    evidence,
                    reason: "last ten observations are on the same side of the mean for " +
                    level.id,
                  })
                }
              }
          }
        }
      }
    }
  }
}

///|
fn add_same_side_window_hit(
  program : @assay.AssayProgram,
  run : @run.QCRun,
  level : @assay.ControlLevel,
  samples : Array[Sample],
  rule : @assay.Rule,
  count : Int,
  multiplier : Int64,
  hits : Array[@evidence.RuleHit],
  issues : Array[@evidence.InputIssue],
) -> Unit {
  if program.disposition_for(rule) != @assay.Disabled {
    let (triggered, evidence, threshold) = is_beyond_same_side(
      samples,
      level,
      program.unit,
      count,
      multiplier,
    )
    if threshold is None && samples.length() >= count {
      issues.push(
        make_issue(
          run.run_id,
          "window threshold arithmetic overflowed for " + level.id,
        ),
      )
    } else if triggered {
      hits.push({
        rule,
        scope: @evidence.ConsecutiveRuns,
        evidence,
        reason: "last " +
        count.to_string() +
        " observations are beyond " +
        rule.name() +
        " on one side for " +
        level.id,
      })
    }
  }
}

///|
fn add_r4s_hits(
  program : @assay.AssayProgram,
  run : @run.QCRun,
  hits : Array[@evidence.RuleHit],
  issues : Array[@evidence.InputIssue],
) -> Unit {
  if program.disposition_for(@assay.RuleR4s) == @assay.Disabled {
    return
  }
  let points = run.observations
  for i in 0..<points.length() {
    for j in (i + 1)..<points.length() {
      let point_a = points[i]
      let point_b = points[j]
      match
        (
          find_level(program, point_a.control_level_id),
          find_level(program, point_b.control_level_id),
        ) {
        (Some(level_a), Some(level_b)) =>
          if level_a.id != level_b.id {
            let delta_a = deviation(point_a.value, level_a.mean)
            let delta_b = deviation(point_b.value, level_b.mean)
            let threshold_a = checked_mul_positive(
              level_a.standard_deviation,
              2L,
            )
            let threshold_b = checked_mul_positive(
              level_b.standard_deviation,
              2L,
            )
            match (delta_a, delta_b, threshold_a, threshold_b) {
              (Some(a), Some(b), Some(ta), Some(tb)) => {
                let below_distance = if b < 0L {
                  checked_sub(0L, b)
                } else {
                  Some(0L)
                }
                match below_distance {
                  Some(distance) =>
                    if a > ta && b < 0L && distance > tb {
                      hits.push({
                        rule: @assay.RuleR4s,
                        scope: @evidence.SameRun,
                        evidence: [
                          evidence_point(
                            { run, point: point_a },
                            level_a,
                            program.unit,
                            ta,
                            @evidence.Above,
                          ),
                          evidence_point(
                            { run, point: point_b },
                            level_b,
                            program.unit,
                            tb,
                            @evidence.Below,
                          ),
                        ],
                        reason: "same run has one control above +2 SD and another below -2 SD",
                      })
                    } else {
                      let above_distance = if a < 0L {
                        checked_sub(0L, a)
                      } else {
                        Some(0L)
                      }
                      match above_distance {
                        Some(distance_a) =>
                          if b > tb && a < 0L && distance_a > ta {
                            hits.push({
                              rule: @assay.RuleR4s,
                              scope: @evidence.SameRun,
                              evidence: [
                                evidence_point(
                                  { run, point: point_b },
                                  level_b,
                                  program.unit,
                                  tb,
                                  @evidence.Above,
                                ),
                                evidence_point(
                                  { run, point: point_a },
                                  level_a,
                                  program.unit,
                                  ta,
                                  @evidence.Below,
                                ),
                              ],
                              reason: "same run has one control above +2 SD and another below -2 SD",
                            })
                          }
                        None =>
                          issues.push(
                            make_issue(
                              run.run_id,
                              "R_4s absolute deviation overflowed",
                            ),
                          )
                      }
                    }
                  None =>
                    issues.push(
                      make_issue(
                        run.run_id,
                        "R_4s absolute deviation overflowed",
                      ),
                    )
                }
              }
              _ =>
                issues.push(
                  make_issue(
                    run.run_id,
                    "R_4s comparison arithmetic overflowed",
                  ),
                )
            }
          }
        _ => ()
      }
    }
  }
}

///|
pub fn detect_signals(
  program : @assay.AssayProgram,
  run : @run.QCRun,
  history : Array[@run.QCRun],
) -> SignalResult {
  let hits : Array[@evidence.RuleHit] = []
  let issues : Array[@evidence.InputIssue] = []
  let mut all_required_present = true
  for level in program.levels {
    if level.required && find_point(run, level.id) is None {
      all_required_present = false
    }
  }
  add_single_rule_hits(program, run, hits, issues)
  if all_required_present {
    add_r4s_hits(program, run, hits, issues)
  }
  add_window_hits(program, run, history, hits, issues)
  { hits, issues }
}
