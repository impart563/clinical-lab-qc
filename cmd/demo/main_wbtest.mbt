///|
test "CLI defaults to the stable Markdown scenario" {
  match parse_cli_args([]) {
    Ok(options) => {
      assert_true(options.scenario == "stable")
      assert_true(options.format == "markdown")
      assert_true(options.input_paths.length() == 0)
      assert_true(options.program_path is None)
      assert_true(options.output_path is None)
      assert_true(!options.check_program)
      assert_true(!options.check_input)
    }
    Err(_) => fail("default CLI options should parse")
  }
}

///|
test "CLI supports text and JSON CSV preflight with a selected program" {
  match
    parse_cli_args([
      "--check-input", "--input", "samples.csv", "--format", "json",
    ]) {
    Ok(options) => {
      assert_true(options.check_input)
      assert_true(options.input_paths == ["samples.csv"])
      assert_true(options.format == "json")
      assert_true(!options.check_program)
    }
    Err(_) => fail("CSV preflight should accept JSON output")
  }
  match
    parse_cli_args([
      "--program", "assay.json", "--check-input", "--input", "samples.csv",
    ]) {
    Ok(options) => {
      assert_true(options.check_input)
      assert_true(options.program_path == Some("assay.json"))
    }
    Err(_) => fail("CSV preflight should accept a custom assay program")
  }
}

///|
test "CLI accepts a CSV path and JSON format" {
  match
    parse_cli_args(["--input", "examples/synthetic-iqc.csv", "--format", "json"]) {
    Ok(options) => {
      assert_true(options.input_paths == ["examples/synthetic-iqc.csv"])
      assert_true(options.format == "json")
    }
    Err(_) => fail("CSV and JSON options should parse")
  }
}

///|
test "CLI accepts a report output path including spaces" {
  match
    parse_cli_args([
      "--scenario", "stable", "--format", "html", "--output", "reports/demo report.html",
    ]) {
    Ok(options) => {
      assert_true(options.output_path == Some("reports/demo report.html"))
      assert_true(options.format == "html")
    }
    Err(_) => fail("report output path should be accepted")
  }
}

///|
test "CLI accepts CSV report output" {
  match parse_cli_args(["--scenario", "stable", "--format", "csv"]) {
    Ok(options) => assert_true(options.format == "csv")
    Err(_) => fail("CSV report format should parse")
  }
}

///|
test "CLI accepts SVG chart output" {
  match parse_cli_args(["--scenario", "gradual-drift", "--format", "svg"]) {
    Ok(options) => assert_true(options.format == "svg")
    Err(_) => fail("SVG chart format should parse")
  }
}

///|
test "CLI accepts a program for validation or CSV replay" {
  match
    parse_cli_args([
      "--program", "examples/demo-program.json", "--check-program",
    ]) {
    Ok(options) => {
      assert_true(options.program_path == Some("examples/demo-program.json"))
      assert_true(options.check_program)
    }
    Err(_) => fail("program validation options should parse")
  }
  match
    parse_cli_args([
      "--program", "examples/demo-program.json", "--input", "examples/synthetic-iqc.csv",
    ]) {
    Ok(options) => {
      assert_true(options.program_path == Some("examples/demo-program.json"))
      assert_true(options.input_paths == ["examples/synthetic-iqc.csv"])
      assert_true(!options.check_program)
    }
    Err(_) => fail("custom program CSV replay options should parse")
  }
}

///|
test "CLI rejects unknown arguments formats and conflicting inputs" {
  assert_true(parse_cli_args(["--unknown"]) is Err(_))
  match
    parse_cli_args([
      "--input", "first.csv", "--input", "第二 份.csv", "--program", "p.json",
    ]) {
    Ok(options) =>
      assert_true(options.input_paths == ["first.csv", "第二 份.csv"])
    Err(_) => fail("repeated --input options should preserve argument order")
  }
  assert_true(parse_cli_args(["--format", "yaml"]) is Err(_))
  assert_true(
    parse_cli_args(["--program", "examples/demo-program.json"]) is Err(_),
  )
  assert_true(parse_cli_args(["--check-program"]) is Err(_))
  assert_true(
    parse_cli_args([
      "--program", "assay.json", "--check-program", "--output", "valid.txt",
    ])
    is Err(_),
  )
  assert_true(parse_cli_args(["--check-input"]) is Err(_))
  assert_true(
    parse_cli_args([
      "--check-input", "--input", "samples.csv", "--format", "csv",
    ])
    is Err(_),
  )
  assert_true(
    parse_cli_args([
      "--check-input", "--input", "samples.csv", "--scenario", "stable",
    ])
    is Err(_),
  )
  assert_true(
    parse_cli_args([
      "--input", "examples/synthetic-iqc.csv", "--scenario", "stable",
    ])
    is Err(_),
  )
  assert_true(
    parse_cli_args([
      "--program", "examples/demo-program.json", "--check-program", "--input", "examples/synthetic-iqc.csv",
    ])
    is Err(_),
  )
}
