///|
fn audit_test_program() -> @assay.AssayProgram {
  {
    assay_id: "audit-analyte",
    unit: "unit/L",
    precision: 2,
    levels: [
      { id: "L1", mean: 10000L, standard_deviation: 100L, required: true, },
    ],
    rule_policies: [
      { rule: @assay.Rule12s, disposition: @assay.Warning, },
      { rule: @assay.Rule13s, disposition: @assay.Disabled, },
      { rule: @assay.Rule22s, disposition: @assay.Disabled, },
      { rule: @assay.RuleR4s, disposition: @assay.Disabled, },
      { rule: @assay.Rule41s, disposition: @assay.Disabled, },
      { rule: @assay.Rule10x, disposition: @assay.Disabled, },
    ],
  }
}

///|
fn audit_test_runs() -> Array[@run.QCRun] {
  let epoch : @epoch.QCEpoch = {
    id: "lot,\"a\"",
    reagent_lot: "reagent-a",
    control_lot: "control-a",
    calibration_id: "cal-a",
    program_version: "v1",
  }
  let next_epoch : @epoch.QCEpoch = {
    id: "lot-b",
    reagent_lot: "reagent-b",
    control_lot: "control-a",
    calibration_id: "cal-b",
    program_version: "v1",
  }
  [
    {
      run_id: "sample,\"run\"",
      epoch,
      sequence: 1L,
      timestamp: "2026-09-27T08:00:00Z",
      observations: [{ control_level_id: "L1", value: 10201L, precision: 2, }],
    },
    {
      run_id: "run-2",
      epoch,
      sequence: 2L,
      timestamp: "2026-09-27T08:05:00Z",
      observations: [{ control_level_id: "L1", value: 10000L, precision: 2, }],
    },
    {
      run_id: "run-3",
      epoch: next_epoch,
      sequence: 1L,
      timestamp: "2026-09-27T08:10:00Z",
      observations: [{ control_level_id: "L1", value: 10000L, precision: 2, }],
    },
  ]
}

///|
fn audit_test_trajectory() -> @evidence.Trajectory {
  let evidence : @evidence.EvidencePoint = {
    run_id: "sample,\"run\"",
    epoch_id: "lot,\"a\"",
    sequence: 1L,
    timestamp: "2026-09-27T08:00:00Z",
    control_level_id: "L1",
    value: 10201L,
    precision: 2,
    unit: "unit/L",
    mean: 10000L,
    standard_deviation: 100L,
    threshold: 200L,
    direction: @evidence.Above,
  }
  let hit : @evidence.RuleHit = {
    rule: @assay.Rule12s,
    scope: @evidence.SingleObservation,
    evidence: [evidence],
    reason: "test warning signal",
  }
  {
    assessments: [
      {
        run_id: "sample,\"run\"",
        sequence: 1L,
        status: @evidence.Warning,
        hits: [hit],
        input_issues: [],
      },
      {
        run_id: "run-2",
        sequence: 2L,
        status: @evidence.InControl,
        hits: [],
        input_issues: [],
      },
      {
        run_id: "run-3",
        sequence: 1L,
        status: @evidence.InControl,
        hits: [],
        input_issues: [],
      },
    ],
    input_issues: [],
  }
}

///|
test "audit JSON is deterministic, versioned, and contains provenance and summary" {
  let program = audit_test_program()
  let runs = audit_test_runs()
  let trajectory = audit_test_trajectory()
  let json = @io.render_audit_json(program, runs, trajectory)
  assert_eq(json, @io.render_audit_json(program, runs, trajectory))
  assert_true(json.contains("\"schema_version\": 1"))
  assert_true(json.contains("\"assay_id\": \"audit-analyte\""))
  assert_true(json.contains("\"observations\""))
  assert_true(json.contains("\"value_scaled\": 10201"))
  assert_true(json.contains("\"epoch_run_counts\""))
  assert_true(json.contains("\"run_count\": 2"))
  assert_true(json.contains("\"run_count\": 1"))
  assert_true(json.contains("\"control_rule_hit_counts\""))
  assert_true(json.contains("\"control_observation_coverage\""))
  assert_true(json.contains("\"expected_runs\": 2"))
  assert_true(json.contains("\"observed_runs\": 2"))
  assert_true(json.contains("\"missing_runs\": 0"))
  assert_true(json.contains("\"expected\": 3"))
  assert_true(json.contains("\"observed\": 3"))
  assert_true(json.contains("\"control_level_id\": \"L1\""))
  assert_true(json.contains("\"Warning\": 1"))
  assert_true(json.contains("\"InControl\": 2"))
  assert_true(json.contains("\"total_rule_hits\": 1"))
  assert_true(json.contains("\"rule\": \"1_2s\""))
  let manifest = @io.render_audit_manifest(program, runs, trajectory)
  assert_eq(manifest, @io.render_audit_manifest(program, runs, trajectory))
  assert_true(manifest.contains("\"schema_version\": 1"))
  assert_true(manifest.contains("\"input_runs\": 3"))
  assert_true(manifest.contains("\"epoch_count\": 2"))
  assert_true(manifest.contains("\"epoch_rule_hit_counts\""))
  assert_true(manifest.contains("\"control_level_id\": \"L1\""))
  assert_true(manifest.contains("\"expected_control_observations\": 3"))
  assert_true(manifest.contains("\"missing_control_observations\": 0"))
  assert_true(manifest.contains("\"RequiresReview\": 0"))
  assert_true(manifest.contains("\"path\": \"report.html\""))
  assert_true(!manifest.contains("timestamp"))
  assert_true(!manifest.contains("source_path"))
}

///|
test "audit CSV preserves quoted identifiers and emits assessment evidence and summary" {
  let program = audit_test_program()
  let runs = audit_test_runs()
  let trajectory = audit_test_trajectory()
  let csv = @io.render_audit_csv(program, runs, trajectory)
  assert_true(csv.has_prefix("record_type,assay_id,program_unit"))
  assert_true(csv.contains("\"sample,\"\"run\"\"\""))
  assert_true(csv.contains("\"observation\""))
  assert_true(csv.contains("\"evidence\""))
  assert_true(csv.contains("\"1_2s\""))
  assert_true(csv.contains("\"10201\""))
  let markdown = @io.render_audit_markdown(program, runs, trajectory)
  assert_true(markdown.contains("Input runs: 3; assessed: 3"))
  assert_true(markdown.contains("Warning 1"))
  assert_true(markdown.contains("InControl 2"))
  assert_true(markdown.contains("Rule hits: 1_2s 1"))
  assert_true(markdown.contains("lot,\"a\" 2 run(s)"))
  assert_true(markdown.contains("lot-b 1 run(s)"))
  assert_true(markdown.contains("Epoch rule hits: lot,\"a\" 1_2s 1"))
  assert_true(markdown.contains("Epoch/control rule hits: lot,\"a\" L1/1_2s 1"))
}

///|
test "offline HTML audit report is deterministic and combines summary chart and evidence" {
  let program = audit_test_program()
  let runs = audit_test_runs()
  let trajectory = audit_test_trajectory()
  let html = @io.render_audit_html(program, runs, trajectory)
  assert_eq(html, @io.render_audit_html(program, runs, trajectory))
  assert_true(html.has_prefix("<!doctype html>"))
  assert_true(html.contains("<html lang=\"en\">"))
  assert_true(html.contains("Offline QC audit report · schema version 1"))
  assert_true(html.contains("Input runs<strong>3</strong>"))
  assert_true(html.contains("Warning<strong>1</strong>"))
  assert_true(html.contains("<details class=\"run\" id=\"run-0\">"))
  assert_true(html.contains("href=\"#run-0\">sample,&quot;run&quot;</a>"))
  assert_true(html.contains("href=\"#run-2\">Open first run</a>"))
  assert_true(html.contains("<th>Requires review</th><th>Incomplete</th>"))
  assert_true(html.contains("Control rule hit counts"))
  assert_true(html.contains("Rule signals by epoch and control"))
  assert_true(html.contains("<th>Rule hits</th><th>Navigate</th>"))
  assert_true(
    html.contains(
      "<tr><td>lot,&quot;a&quot;</td><td>L1</td><td>1_2s</td><td>1</td><td>warning</td><td><a href=\"#run-0\">Open first signal</a></td></tr>",
    ),
  )
  assert_true(html.contains("href=\"#run-0\">Open first signal</a>"))
  assert_true(html.contains("Control observation coverage"))
  assert_true(html.contains("<th>Expected runs</th><th>Observed runs</th>"))
  assert_true(html.contains("<a href=\"#run-0\">Open first signal</a>"))
  assert_true(html.contains("Rule signals and evidence"))
  assert_true(html.contains("test warning signal"))
  assert_true(html.contains("102.01 unit/L"))
  assert_true(html.contains("lot-b"))
  assert_true(html.contains("<svg xmlns=\"http://www.w3.org/2000/svg\""))
  assert_true(html.contains("class=\"control-panel\""))
  assert_true(!html.contains("<script"))
  assert_true(!html.contains("<link"))
  assert_true(!html.contains("https://"))
}

///|
test "coverage separates absent and wrong-precision control observations" {
  let base_program = audit_test_program()
  let program : @assay.AssayProgram = {
    assay_id: base_program.assay_id,
    unit: base_program.unit,
    precision: base_program.precision,
    levels: base_program.levels +
    [{ id: "L2", mean: 20000L, standard_deviation: 200L, required: false, }],
    rule_policies: base_program.rule_policies,
  }
  let original_runs = audit_test_runs()
  let runs : Array[@run.QCRun] = [
    original_runs[0],
    {
      run_id: original_runs[1].run_id,
      epoch: original_runs[1].epoch,
      sequence: original_runs[1].sequence,
      timestamp: original_runs[1].timestamp,
      observations: [],
    },
    {
      run_id: original_runs[2].run_id,
      epoch: original_runs[2].epoch,
      sequence: original_runs[2].sequence,
      timestamp: original_runs[2].timestamp,
      observations: [{ control_level_id: "L1", value: 10000L, precision: 1, }],
    },
  ]
  let trajectory : @evidence.Trajectory = {
    assessments: [
      audit_test_trajectory().assessments[0],
      {
        run_id: runs[1].run_id,
        sequence: runs[1].sequence,
        status: @evidence.Incomplete,
        hits: [],
        input_issues: [
          {
            code: @evidence.MissingRequiredControl,
            run_id: Some(runs[1].run_id),
            message: "required control L1 is missing",
          },
        ],
      },
      {
        run_id: runs[2].run_id,
        sequence: runs[2].sequence,
        status: @evidence.Incomplete,
        hits: [],
        input_issues: [
          {
            code: @evidence.PrecisionMismatch,
            run_id: Some(runs[2].run_id),
            message: "control precision does not match the assay program",
          },
        ],
      },
    ],
    input_issues: [],
  }
  let json = @io.render_audit_json(program, runs, trajectory)
  assert_true(json.contains("\"missing_runs\": 1"))
  assert_true(json.contains("\"precision_mismatch_runs\": 1"))
  assert_true(json.contains("\"required_missing\": 1"))
  assert_true(json.contains("\"missing\": 4"))
  assert_true(json.contains("\"required\": false"))
  assert_true(json.contains("\"precision_mismatch\": 1"))
  let html = @io.render_audit_html(program, runs, trajectory)
  assert_true(html.contains("Open first missing run</a>"))
  assert_true(html.contains("href=\"#run-1\">Open first missing run</a>"))
  assert_true(
    html.contains("href=\"#run-2\">Open first precision mismatch</a>"),
  )
  let manifest = @io.render_audit_manifest(program, runs, trajectory)
  assert_true(manifest.contains("\"missing_control_observations\": 4"))
  assert_true(manifest.contains("\"required_missing_control_observations\": 1"))
  assert_true(
    manifest.contains("\"precision_mismatch_control_observations\": 1"),
  )
}

///|
test "HTML escaping protects report text and quoted values" {
  let dangerous = "<script>alert('x') & \"y\"</script>"
  let base = audit_test_program()
  let program : @assay.AssayProgram = {
    assay_id: dangerous,
    unit: "unit<&",
    precision: base.precision,
    levels: base.levels,
    rule_policies: base.rule_policies,
  }
  let epoch : @epoch.QCEpoch = {
    id: dangerous,
    reagent_lot: "reagent-a",
    control_lot: "control-a",
    calibration_id: "cal-a",
    program_version: "v1",
  }
  let runs : Array[@run.QCRun] = [
    {
      run_id: dangerous,
      epoch,
      sequence: 1L,
      timestamp: "2026-09-27T08:00:00Z",
      observations: [{ control_level_id: "L1", value: 10000L, precision: 2, }],
    },
  ]
  let trajectory : @evidence.Trajectory = { assessments: [], input_issues: [], }
  let html = @io.render_audit_html(program, runs, trajectory)
  assert_true(
    html.contains(
      "&lt;script&gt;alert(&#39;x&#39;) &amp; &quot;y&quot;&lt;/script&gt;",
    ),
  )
  assert_true(html.contains("unit&lt;&amp;"))
  assert_true(!html.contains(dangerous))
  assert_true(!html.contains("<script>alert"))
}

///|
test "HTML run details preserve positional snapshots through an invalid duplicate" {
  let program = audit_test_program()
  let first = audit_test_runs()[0]
  let duplicate : @run.QCRun = {
    run_id: first.run_id,
    epoch: first.epoch,
    sequence: first.sequence,
    timestamp: "duplicate timestamp",
    observations: [{ control_level_id: "L1", value: 12345L, precision: 2, }],
  }
  let runs = [first, duplicate]
  let duplicate_issue : @evidence.InputIssue = {
    code: @evidence.DuplicateRunId,
    run_id: Some(first.run_id),
    message: "duplicate run id in track",
  }
  let trajectory : @evidence.Trajectory = {
    assessments: [
      {
        run_id: first.run_id,
        sequence: first.sequence,
        status: @evidence.InControl,
        hits: [],
        input_issues: [],
      },
      {
        run_id: duplicate.run_id,
        sequence: duplicate.sequence,
        status: @evidence.Incomplete,
        hits: [],
        input_issues: [duplicate_issue],
      },
    ],
    input_issues: [duplicate_issue],
  }
  let html = @io.render_audit_html(program, runs, trajectory)
  assert_true(html.contains("123.45 unit/L"))
  assert_true(html.contains("duplicate timestamp"))
  assert_true(html.contains("duplicate run id in track"))
}
