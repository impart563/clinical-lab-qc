///|
pub(all) struct CsvParseResult {
  runs : Array[@run.QCRun]
  issues : Array[@evidence.InputIssue]
} derive(Debug)

///|
priv struct CsvTable {
  rows : Array[Array[String]]
  error : String?
}

///|
priv struct CsvRecord {
  epoch : @epoch.QCEpoch
  run_id : String
  sequence : Int64
  timestamp : String
  control_level_id : String
  value : Int64?
}

///|
priv enum ScaledParse {
  Parsed(Int64)
  Missing
  Invalid(String)
}

///|
fn parse_csv_table(text : String) -> CsvTable {
  let chars = text.to_array()
  let rows : Array[Array[String]] = []
  let mut fields : Array[String] = []
  let field = StringBuilder()
  let mut quoted = false
  let mut after_quote = false
  let mut error : String? = None
  let mut saw_character = false
  let mut i = 0
  while i < chars.length() {
    let ch = chars[i]
    saw_character = true
    if quoted {
      if ch == '"' {
        if i + 1 < chars.length() && chars[i + 1] == '"' {
          field.write_char('"')
          i = i + 1
        } else {
          quoted = false
          after_quote = true
        }
      } else {
        field.write_char(ch)
      }
    } else if after_quote {
      if ch == ',' {
        fields.push(field.to_string())
        field.reset()
        after_quote = false
      } else if ch == '\n' || ch == '\r' {
        fields.push(field.to_string())
        field.reset()
        if !(fields.length() == 1 && fields[0].is_empty()) {
          rows.push(fields)
        }
        fields = []
        after_quote = false
        saw_character = false
        if ch == '\r' && i + 1 < chars.length() && chars[i + 1] == '\n' {
          i = i + 1
        }
      } else {
        error = Some("unexpected character after a quoted CSV field")
      }
    } else if ch == '"' {
      if field.is_empty() {
        quoted = true
      } else {
        error = Some("quote inside an unquoted CSV field")
      }
    } else if ch == ',' {
      fields.push(field.to_string())
      field.reset()
    } else if ch == '\n' || ch == '\r' {
      fields.push(field.to_string())
      field.reset()
      if !(fields.length() == 1 && fields[0].is_empty()) {
        rows.push(fields)
      }
      fields = []
      saw_character = false
      if ch == '\r' && i + 1 < chars.length() && chars[i + 1] == '\n' {
        i = i + 1
      }
    } else {
      field.write_char(ch)
    }
    i = i + 1
  }
  if error is None && quoted {
    error = Some("unterminated quoted CSV field")
  }
  if error is None && saw_character {
    fields.push(field.to_string())
    if !(fields.length() == 1 && fields[0].is_empty()) {
      rows.push(fields)
    }
  }
  { rows, error }
}

///|
fn checked_mul10(value : Int64) -> Int64? {
  let result = value * 10L
  if result / 10L == value {
    Some(result)
  } else {
    None
  }
}

///|
fn checked_add(a : Int64, b : Int64) -> Int64? {
  let result = a + b
  if (b > 0L && result < a) || (b < 0L && result > a) {
    None
  } else {
    Some(result)
  }
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
fn parse_scaled(text : String, precision : Int) -> ScaledParse {
  if precision < 0 || precision > 18 {
    return Invalid("precision must be between 0 and 18")
  }
  let value = text.trim().to_owned()
  if value.is_empty() {
    return Missing
  }
  let chars = value.to_array()
  let negative = chars[0] == '-'
  let positive_sign = chars[0] == '+'
  let start = if negative || positive_sign { 1 } else { 0 }
  if start == chars.length() {
    return Invalid("sign without digits")
  }
  let mut accumulator = 0L
  let mut fraction_digits = 0
  let mut seen_decimal = false
  let mut seen_digit = false
  for i in start..<chars.length() {
    let ch = chars[i]
    if ch == '.' {
      if seen_decimal {
        return Invalid("more than one decimal point")
      }
      seen_decimal = true
    } else if ch.is_ascii_digit() {
      seen_digit = true
      if seen_decimal {
        fraction_digits = fraction_digits + 1
        if fraction_digits > precision {
          return Invalid("more fractional digits than the declared precision")
        }
      }
      let digit = (ch.to_int() - '0'.to_int()).to_int64()
      match checked_mul10(accumulator) {
        None => return Invalid("scaled value overflow")
        Some(scaled) => {
          let next = if negative {
            checked_sub(scaled, digit)
          } else {
            checked_add(scaled, digit)
          }
          match next {
            None => return Invalid("scaled value overflow")
            Some(next) => accumulator = next
          }
        }
      }
    } else {
      return Invalid("value must use a plain decimal number")
    }
  }
  if !seen_digit {
    return Invalid("value must contain a digit")
  }
  for _ in fraction_digits..<precision {
    match checked_mul10(accumulator) {
      None => return Invalid("scaled value overflow")
      Some(scaled) => accumulator = scaled
    }
  }
  Parsed(accumulator)
}

///|
fn csv_issue(
  code : @evidence.InputIssueCode,
  run_id : String?,
  message : String,
) -> @evidence.InputIssue {
  { code, run_id, message }
}

///|
fn contains_level(values : Array[String], value : String) -> Bool {
  for item in values {
    if item == value {
      return true
    }
  }
  false
}

///|
pub fn parse_qc_csv(
  program : @assay.AssayProgram,
  text : String,
) -> CsvParseResult {
  let table = parse_csv_table(text)
  let issues : Array[@evidence.InputIssue] = []
  match table.error {
    Some(message) => {
      issues.push(csv_issue(@evidence.CsvMalformed, None, message))
      return { runs: [], issues }
    }
    None => ()
  }
  let expected = [
    "epoch_id", "reagent_lot", "control_lot", "calibration_id", "program_version",
    "run_id", "sequence", "timestamp", "control_level_id", "value",
  ]
  if table.rows.length() == 0 || table.rows[0] != expected {
    issues.push(
      csv_issue(
        @evidence.CsvHeader,
        None,
        "CSV header must be the documented ten-column long format",
      ),
    )
    return { runs: [], issues }
  }
  let records : Array[CsvRecord] = []
  for row_index in 1..<table.rows.length() {
    let row = table.rows[row_index]
    if row.length() != expected.length() {
      issues.push(
        csv_issue(
          @evidence.CsvMalformed,
          None,
          "row " + row_index.to_string() + " has the wrong number of columns",
        ),
      )
    } else {
      let epoch = @epoch.QCEpoch::{
        id: row[0],
        reagent_lot: row[1],
        control_lot: row[2],
        calibration_id: row[3],
        program_version: row[4],
      }
      let run_id = row[5]
      match parse_scaled(row[6], 0) {
        Parsed(sequence) =>
          if sequence <= 0L {
            issues.push(
              csv_issue(
                @evidence.CsvMalformed,
                Some(run_id),
                "run sequence must be positive",
              ),
            )
          } else if !epoch.is_valid() ||
            run_id.trim().is_empty() ||
            row[7].trim().is_empty() {
            issues.push(
              csv_issue(
                @evidence.CsvMalformed,
                Some(run_id),
                "epoch metadata, run id, and timestamp must not be empty",
              ),
            )
          } else {
            match parse_scaled(row[9], program.precision) {
              Parsed(value) =>
                records.push({
                  epoch,
                  run_id,
                  sequence,
                  timestamp: row[7],
                  control_level_id: row[8],
                  value: Some(value),
                })
              Missing =>
                records.push({
                  epoch,
                  run_id,
                  sequence,
                  timestamp: row[7],
                  control_level_id: row[8],
                  value: None,
                })
              Invalid(message) =>
                issues.push(
                  csv_issue(
                    @evidence.CsvPrecision,
                    Some(run_id),
                    "row " + row_index.to_string() + ": " + message,
                  ),
                )
            }
          }
        Missing =>
          issues.push(
            csv_issue(
              @evidence.CsvMalformed,
              Some(run_id),
              "run sequence is required",
            ),
          )
        Invalid(message) =>
          issues.push(
            csv_issue(
              @evidence.CsvMalformed,
              Some(run_id),
              "row " + row_index.to_string() + ": " + message,
            ),
          )
      }
    }
  }
  let runs : Array[@run.QCRun] = []
  let mut index = 0
  while index < records.length() {
    let first = records[index]
    let observations : Array[@run.ControlPoint] = []
    let seen_levels : Array[String] = []
    let mut next_index = index
    while next_index < records.length() &&
          records[next_index].run_id == first.run_id {
      let record = records[next_index]
      if !first.epoch.has_same_metadata(record.epoch) ||
        first.sequence != record.sequence ||
        first.timestamp != record.timestamp {
        issues.push(
          csv_issue(
            @evidence.CsvMalformed,
            Some(first.run_id),
            "metadata must be identical across rows for one run",
          ),
        )
      } else if contains_level(seen_levels, record.control_level_id) {
        issues.push(
          csv_issue(
            @evidence.DuplicateControlPoint,
            Some(first.run_id),
            "duplicate row for control level " + record.control_level_id,
          ),
        )
      } else {
        seen_levels.push(record.control_level_id)
        match record.value {
          Some(value) =>
            observations.push({
              control_level_id: record.control_level_id,
              value,
              precision: program.precision,
            })
          None => ()
        }
      }
      next_index = next_index + 1
    }
    runs.push({
      run_id: first.run_id,
      epoch: first.epoch,
      sequence: first.sequence,
      timestamp: first.timestamp,
      observations,
    })
    index = next_index
  }
  { runs, issues }
}
