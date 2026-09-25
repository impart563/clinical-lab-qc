///|
fn example_trajectory() -> @qc.Trajectory {
  let program : @qc.AssayProgram = {
    assay_id: "example-analyte",
    unit: "unit/L",
    precision: 0,
    levels: [
      { id: "normal", mean: 100L, standard_deviation: 10L, required: true },
    ],
    rule_policies: @qc.default_rule_policies(),
  }
  let epoch = @qc.QCEpoch::{
    id: "lot-2026-a",
    reagent_lot: "reagent-a",
    control_lot: "control-a",
    calibration_id: "calibration-a",
    program_version: "v1",
  }
  let runs : Array[@qc.QCRun] = [
    {
      run_id: "run-1",
      epoch,
      sequence: 1L,
      timestamp: "2026-09-25T08:00:00Z",
      observations: [{ control_level_id: "normal", value: 100L, precision: 0 }],
    },
    {
      run_id: "run-2",
      epoch,
      sequence: 2L,
      timestamp: "2026-09-25T08:05:00Z",
      observations: [{ control_level_id: "normal", value: 104L, precision: 0 }],
    },
  ]
  @qc.replay_track(program, runs)
}

///|
fn main {
  println(@qc.render_trajectory_markdown(example_trajectory()))
}
