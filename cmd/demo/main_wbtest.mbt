///|
test "CLI defaults to the stable Markdown scenario" {
  match parse_cli_args([]) {
    Ok(options) => {
      assert_true(options.scenario == "stable")
      assert_true(options.format == "markdown")
      assert_true(options.input_path is None)
      assert_true(options.program_path is None)
      assert_true(!options.check_program)
    }
    Err(_) => fail("default CLI options should parse")
  }
}

///|
test "CLI accepts a CSV path and JSON format" {
  match
    parse_cli_args(["--input", "examples/synthetic-iqc.csv", "--format", "json"]) {
    Ok(options) => {
      assert_true(options.input_path == Some("examples/synthetic-iqc.csv"))
      assert_true(options.format == "json")
    }
    Err(_) => fail("CSV and JSON options should parse")
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
      assert_true(options.input_path == Some("examples/synthetic-iqc.csv"))
      assert_true(!options.check_program)
    }
    Err(_) => fail("custom program CSV replay options should parse")
  }
}

///|
test "CLI rejects unknown arguments formats and conflicting inputs" {
  assert_true(parse_cli_args(["--unknown"]) is Err(_))
  assert_true(parse_cli_args(["--format", "yaml"]) is Err(_))
  assert_true(
    parse_cli_args(["--program", "examples/demo-program.json"]) is Err(_),
  )
  assert_true(parse_cli_args(["--check-program"]) is Err(_))
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
