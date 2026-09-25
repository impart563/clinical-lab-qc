///|
pub fn demo_program() -> @lib.AssayProgram {
  {
    assay_id: "synthetic-analyte",
    unit: "unit/L",
    precision: 0,
    levels: [
      { id: "L1", mean: 100L, standard_deviation: 10L, required: true },
      { id: "L2", mean: 200L, standard_deviation: 20L, required: true },
    ],
    rule_policies: @lib.default_rule_policies(),
  }
}

///|
fn make_run(
  epoch : @lib.QCEpoch,
  run_id : String,
  sequence : Int64,
  value_l1 : Int64,
  value_l2 : Int64,
) -> @lib.QCRun {
  {
    run_id,
    epoch,
    sequence,
    timestamp: "2026-09-25T08:00:00Z",
    observations: [
      { control_level_id: "L1", value: value_l1, precision: 0 },
      { control_level_id: "L2", value: value_l2, precision: 0 },
    ],
  }
}

///|
fn stable_runs() -> Array[@lib.QCRun] {
  let epoch = @lib.QCEpoch::{
    id: "stable-epoch",
    reagent_lot: "reagent-a",
    control_lot: "control-a",
    calibration_id: "cal-a",
    program_version: "v1",
  }
  let l1 = [100L, 104L, 97L, 106L, 99L, 103L, 95L, 105L, 101L, 96L, 104L, 98L]
  let l2 = [
    200L, 207L, 194L, 210L, 198L, 204L, 190L, 208L, 202L, 196L, 206L, 198L,
  ]
  let runs : Array[@lib.QCRun] = []
  for i in 0..<l1.length() {
    runs.push(
      make_run(
        epoch,
        "stable-" + (i + 1).to_string(),
        (i + 1).to_int64(),
        l1[i],
        l2[i],
      ),
    )
  }
  runs
}

///|
fn step_shift_runs() -> Array[@lib.QCRun] {
  let before = @lib.QCEpoch::{
    id: "lot-a",
    reagent_lot: "reagent-a",
    control_lot: "control-a",
    calibration_id: "cal-a",
    program_version: "v1",
  }
  let after = @lib.QCEpoch::{
    id: "lot-b",
    reagent_lot: "reagent-b",
    control_lot: "control-a",
    calibration_id: "cal-b",
    program_version: "v1",
  }
  let runs : Array[@lib.QCRun] = []
  for i in 0..<6 {
    runs.push(
      make_run(
        before,
        "before-" + (i + 1).to_string(),
        (i + 1).to_int64(),
        105L,
        210L,
      ),
    )
  }
  for i in 0..<6 {
    runs.push(
      make_run(
        after,
        "after-" + (i + 1).to_string(),
        (i + 1).to_int64(),
        105L,
        210L,
      ),
    )
  }
  runs
}

///|
fn gradual_drift_runs() -> Array[@lib.QCRun] {
  let epoch = @lib.QCEpoch::{
    id: "drift-epoch",
    reagent_lot: "reagent-d",
    control_lot: "control-d",
    calibration_id: "cal-d",
    program_version: "v1",
  }
  let l1 = [
    98L, 103L, 107L, 111L, 112L, 113L, 114L, 115L, 116L, 117L, 118L, 122L,
  ]
  let l2 = [
    200L, 203L, 197L, 204L, 196L, 202L, 198L, 205L, 199L, 201L, 195L, 204L,
  ]
  let runs : Array[@lib.QCRun] = []
  for i in 0..<l1.length() {
    runs.push(
      make_run(
        epoch,
        "drift-" + (i + 1).to_string(),
        (i + 1).to_int64(),
        l1[i],
        l2[i],
      ),
    )
  }
  runs
}

///|
pub fn build_scenario(name : String) -> Array[@lib.QCRun]? {
  match name {
    "stable" => Some(stable_runs())
    "step-shift" => Some(step_shift_runs())
    "gradual-drift" => Some(gradual_drift_runs())
    _ => None
  }
}
