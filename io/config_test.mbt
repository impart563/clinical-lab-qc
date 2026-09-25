///|
fn sample_program_config(
  precision : String,
  mean : String,
  extra_field : String,
  schema_version : String,
) -> String {
  "{\"schema_version\":" +
  schema_version +
  ",\"assay_id\":\"analyte-a\",\"unit\":\"unit/L\",\"precision\":" +
  precision +
  ",\"levels\":[{\"id\":\"L1\",\"mean\":\"" +
  mean +
  "\",\"standard_deviation\":\"2.50\",\"required\":true}],\"rules\":[{\"rule\":\"1_2s\",\"disposition\":\"warning\"}]" +
  extra_field +
  "}"
}

///|
test "assay program JSON preserves exact decimal values" {
  let parsed = parse_assay_program_json(
    sample_program_config("2", "100.25", "", "1"),
  )
  assert_eq(parsed.issues.length(), 0)
  match parsed.program {
    Some(program) => {
      assert_eq(program.assay_id, "analyte-a")
      assert_eq(program.precision, 2)
      assert_eq(program.levels[0].mean, 10025L)
      assert_eq(program.levels[0].standard_deviation, 250L)
      assert_eq(program.disposition_for(@assay.Rule12s), @assay.Warning)
    }
    None => fail("valid program configuration should produce a program")
  }
}

///|
test "assay program JSON rejects unknown fields and unsupported versions" {
  let unknown = parse_assay_program_json(
    sample_program_config("2", "100.25", ",\"precison\":2", "1"),
  )
  assert_true(unknown.program is None)
  assert_true(unknown.issues[0].contains("unsupported field $.precison"))
  let unsupported = parse_assay_program_json(
    sample_program_config("2", "100.25", "", "2"),
  )
  assert_true(unsupported.program is None)
  assert_true(unsupported.issues[0].contains("supported version is 1"))
}

///|
test "assay program JSON reports decimal and rule errors" {
  let bad_decimal = parse_assay_program_json(
    sample_program_config("2", "100.251", "", "1"),
  )
  assert_true(bad_decimal.program is None)
  assert_true(bad_decimal.issues[0].contains("levels[0].mean"))
  let overflow = parse_assay_program_json(
    sample_program_config("0", "9223372036854775808", "", "1"),
  )
  assert_true(overflow.program is None)
  assert_true(overflow.issues[0].contains("overflow"))
  let bad_rule = parse_assay_program_json(
    "{\"schema_version\":1,\"assay_id\":\"a\",\"unit\":\"u\",\"precision\":0,\"levels\":[{\"id\":\"L1\",\"mean\":\"1\",\"standard_deviation\":\"1\",\"required\":true}],\"rules\":[{\"rule\":\"unknown\",\"disposition\":\"urgent\"}]}",
  )
  assert_true(bad_rule.program is None)
  assert_eq(bad_rule.issues.length(), 2)
}

///|
test "assay program JSON reports structural and semantic validation errors" {
  let malformed = parse_assay_program_json("{not-json")
  assert_true(malformed.program is None)
  assert_true(malformed.issues[0].has_prefix("invalid JSON:"))
  let invalid = parse_assay_program_json(
    "{\"schema_version\":1,\"assay_id\":\"a\",\"unit\":\"u\",\"precision\":0,\"levels\":[{\"id\":\"L1\",\"mean\":\"1\",\"standard_deviation\":\"0\",\"required\":true}],\"rules\":[]}",
  )
  assert_true(invalid.program is None)
  assert_true(invalid.issues[0].contains("standard deviation must be positive"))
}
