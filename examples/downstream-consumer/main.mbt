///|
fn downstream_program() -> @qc.AssayProgram {
  {
    assay_id: "downstream-analyte",
    unit: "unit/L",
    precision: 0,
    levels: [
      { id: "normal", mean: 100L, standard_deviation: 10L, required: true },
    ],
    rule_policies: @qc.default_rule_policies(),
  }
}

///|
fn downstream_runs() -> Array[@qc.QCRun] {
  let epoch : @qc.QCEpoch = {
    id: "lot-consumer-1",
    reagent_lot: "reagent-1",
    control_lot: "control-1",
    calibration_id: "calibration-1",
    program_version: "v1",
  }
  [
    {
      run_id: "consumer-run-1",
      epoch,
      sequence: 1L,
      timestamp: "2026-09-26T08:00:00Z",
      observations: [{ control_level_id: "normal", value: 100L, precision: 0 }],
    },
    {
      run_id: "consumer-run-2",
      epoch,
      sequence: 2L,
      timestamp: "2026-09-26T08:05:00Z",
      observations: [{ control_level_id: "normal", value: 104L, precision: 0 }],
    },
  ]
}

///|
fn main {
  let program = downstream_program()
  let runs = downstream_runs()
  let trajectory = @qc.replay_track(program, runs)
  println("Downstream consumer smoke passed")
  println(@qc.render_audit_markdown(program, runs, trajectory))
}
