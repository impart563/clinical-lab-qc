///|
test "CLI defaults to the stable Markdown scenario" {
  match parse_cli_args([]) {
    Ok(options) => {
      assert_true(options.scenario == "stable")
      assert_true(options.format == "markdown")
      assert_true(options.input_path is None)
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
test "CLI rejects unknown arguments formats and conflicting inputs" {
  assert_true(parse_cli_args(["--unknown"]) is Err(_))
  assert_true(parse_cli_args(["--format", "yaml"]) is Err(_))
  assert_true(
    parse_cli_args([
      "--input", "examples/synthetic-iqc.csv", "--scenario", "stable",
    ])
    is Err(_),
  )
}
