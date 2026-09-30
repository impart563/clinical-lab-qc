///|
fn downstream_program() -> @qc.AssayProgram {
  {
    assay_id: "downstream-analyte",
    unit: "unit/L",
    precision: 0,
    levels: [
      { id: "normal", mean: 100L, standard_deviation: 10L, required: true, },
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
      observations: [{ control_level_id: "normal", value: 100L, precision: 0, }],
    },
    {
      run_id: "consumer-run-2",
      epoch,
      sequence: 2L,
      timestamp: "2026-09-26T08:05:00Z",
      observations: [{ control_level_id: "normal", value: 104L, precision: 0, }],
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

  let csv = "epoch_id,reagent_lot,control_lot,calibration_id,program_version,run_id,sequence,timestamp,control_level_id,value\n" +
    "lot-a,reagent-a,control-a,cal-a,v1,registry-run,1,2026-09-30T08:00:00Z,normal,100\n"
  let batch = @qc.parse_qc_csv_batch_detailed(program, [
    { label: "daily export.csv", text: csv, },
  ])
  if batch.diagnostics.length() > 0 {
    panic()
  }
  let batch_trajectory = @qc.replay_track(
    program,
    batch.runs.map(fn(entry) { entry.run }),
  )
  let batch_report = @qc.render_audit_json_batch(
    program,
    batch.runs,
    batch_trajectory,
  )
  if !batch_report.contains("\"source_label\": \"daily export.csv\"") {
    panic()
  }
  println("Downstream batch API smoke passed")
}
