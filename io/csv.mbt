///|
pub(all) struct CsvParseResult {
  runs : Array[@run.QCRun]
  issues : Array[@evidence.InputIssue]
} derive(Debug)

///|
/// A CSV problem with machine-readable source coordinates when the parser can
/// identify them. `line`, `column`, and `field` are one-based physical CSV
/// positions; track-integrity issues are reported separately by replay.
pub(all) struct CsvDiagnostic {
  issue : @evidence.InputIssue
  line : Int?
  column : Int?
  field : String?
} derive(Debug)

///|
/// Detailed CSV parsing result. The compatibility API `parse_qc_csv` returns
/// the same runs and issues without source coordinates.
pub(all) struct CsvParseDetailedResult {
  runs : Array[@run.QCRun]
  diagnostics : Array[CsvDiagnostic]
} derive(Debug)

///|
priv struct CsvTable {
  rows : Array[Array[String]]
  row_lines : Array[Int]
  error : String?
  error_line : Int?
  error_column : Int?
}

///|
priv struct CsvRecord {
  epoch : @epoch.QCEpoch
  run_id : String
  sequence : Int64
  timestamp : String
  control_level_id : String
  value : Int64?
  line : Int
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
  let row_lines : Array[Int] = []
  let mut fields : Array[String] = []
  let field = StringBuilder()
  let mut quoted = false
  let mut after_quote = false
  let mut error : String? = None
  let mut error_line : Int? = None
  let mut error_column : Int? = None
  let mut saw_character = false
  let mut line = 1
  let mut column = 1
  let mut row_start_line = 1
  let mut previous_cr = false
  let mut i = 0
  while i < chars.length() {
    let ch = chars[i]
    let mut skipped_character = false
    saw_character = true
    if quoted {
      if ch == '"' {
        if i + 1 < chars.length() && chars[i + 1] == '"' {
          field.write_char('"')
          i = i + 1
          skipped_character = true
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
          row_lines.push(row_start_line)
        }
        fields = []
        after_quote = false
        saw_character = false
        row_start_line = line + 1
        if ch == '\r' && i + 1 < chars.length() && chars[i + 1] == '\n' {
          i = i + 1
          skipped_character = true
        }
      } else if error is None {
        error = Some("unexpected character after a quoted CSV field")
        error_line = Some(line)
        error_column = Some(column)
      }
    } else if ch == '"' {
      if field.is_empty() {
        quoted = true
      } else if error is None {
        error = Some("quote inside an unquoted CSV field")
        error_line = Some(line)
        error_column = Some(column)
      }
    } else if ch == ',' {
      fields.push(field.to_string())
      field.reset()
    } else if ch == '\n' || ch == '\r' {
      fields.push(field.to_string())
      field.reset()
      if !(fields.length() == 1 && fields[0].is_empty()) {
        rows.push(fields)
        row_lines.push(row_start_line)
      }
      fields = []
      saw_character = false
      row_start_line = line + 1
      if ch == '\r' && i + 1 < chars.length() && chars[i + 1] == '\n' {
        i = i + 1
        skipped_character = true
      }
    } else {
      field.write_char(ch)
    }
    if ch == '\r' {
      line = line + 1
      column = 1
      previous_cr = true
    } else if ch == '\n' {
      if previous_cr {
        column = 1
        previous_cr = false
      } else {
        line = line + 1
        column = 1
      }
    } else {
      previous_cr = false
      column = column + (if skipped_character { 2 } else { 1 })
    }
    i = i + 1
  }
  if error is None && quoted {
    error = Some("unterminated quoted CSV field")
    error_line = Some(line)
    error_column = Some(column)
  }
  if error is None && saw_character {
    fields.push(field.to_string())
    if !(fields.length() == 1 && fields[0].is_empty()) {
      rows.push(fields)
      row_lines.push(row_start_line)
    }
  }
  { rows, row_lines, error, error_line, error_column }
}

///|
fn csv_line_location(line : Int) -> String {
  "line " + line.to_string()
}

///|
fn csv_field_location(line : Int, field : String, column : Int) -> String {
  csv_line_location(line) +
  ", field '" +
  field +
  "' (column " +
  column.to_string() +
  ")"
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
fn csv_diagnostic(
  code : @evidence.InputIssueCode,
  run_id : String?,
  message : String,
  line : Int?,
  column : Int?,
  field : String?,
) -> CsvDiagnostic {
  { issue: csv_issue(code, run_id, message), line, column, field }
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
  let detailed = parse_qc_csv_detailed(program, text)
  {
    runs: detailed.runs,
    issues: detailed.diagnostics.map(fn(diagnostic) { diagnostic.issue }),
  }
}

///|
/// Parse the documented long-form QC CSV while retaining structured physical
/// line, column, and field information for each CSV diagnostic.
pub fn parse_qc_csv_detailed(
  program : @assay.AssayProgram,
  text : String,
) -> CsvParseDetailedResult {
  let table = parse_csv_table(text)
  let diagnostics : Array[CsvDiagnostic] = []
  match table.error {
    Some(message) => {
      let location = match (table.error_line, table.error_column) {
        (Some(line), Some(column)) =>
          "line " + line.to_string() + ", column " + column.to_string() + ": "
        _ => "CSV input: "
      }
      diagnostics.push(
        csv_diagnostic(
          @evidence.CsvMalformed,
          None,
          location + message,
          table.error_line,
          table.error_column,
          None,
        ),
      )
      return { runs: [], diagnostics }
    }
    None => ()
  }
  let expected = [
    "epoch_id", "reagent_lot", "control_lot", "calibration_id", "program_version",
    "run_id", "sequence", "timestamp", "control_level_id", "value",
  ]
  if table.rows.length() == 0 || table.rows[0] != expected {
    diagnostics.push(
      csv_diagnostic(
        @evidence.CsvHeader,
        None,
        "CSV header must be the documented ten-column long format",
        Some(1),
        Some(1),
        None,
      ),
    )
    return { runs: [], diagnostics }
  }
  let records : Array[CsvRecord] = []
  for row_index in 1..<table.rows.length() {
    let row = table.rows[row_index]
    let physical_line = table.row_lines[row_index]
    if row.length() != expected.length() {
      diagnostics.push(
        csv_diagnostic(
          @evidence.CsvMalformed,
          None,
          csv_line_location(physical_line) +
          ": expected 10 columns but found " +
          row.length().to_string(),
          Some(physical_line),
          None,
          None,
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
            diagnostics.push(
              csv_diagnostic(
                @evidence.CsvMalformed,
                Some(run_id),
                csv_field_location(physical_line, "sequence", 7) +
                ": run sequence must be positive",
                Some(physical_line),
                Some(7),
                Some("sequence"),
              ),
            )
          } else if !epoch.is_valid() ||
            run_id.trim().is_empty() ||
            row[7].trim().is_empty() {
            let (field, column) = if row[0].trim().is_empty() {
              ("epoch_id", 1)
            } else if row[1].trim().is_empty() {
              ("reagent_lot", 2)
            } else if row[2].trim().is_empty() {
              ("control_lot", 3)
            } else if row[3].trim().is_empty() {
              ("calibration_id", 4)
            } else if row[4].trim().is_empty() {
              ("program_version", 5)
            } else if run_id.trim().is_empty() {
              ("run_id", 6)
            } else {
              ("timestamp", 8)
            }
            diagnostics.push(
              csv_diagnostic(
                @evidence.CsvMalformed,
                Some(run_id),
                csv_field_location(physical_line, field, column) +
                ": field must not be empty",
                Some(physical_line),
                Some(column),
                Some(field),
              ),
            )
          } else {
            if !contains_level(
                program.levels.map(fn(level) { level.id }),
                row[8],
              ) {
              diagnostics.push(
                csv_diagnostic(
                  @evidence.UnknownControlLevel,
                  Some(run_id),
                  csv_field_location(physical_line, "control_level_id", 9) +
                  ": unknown control level '" +
                  row[8] +
                  "'",
                  Some(physical_line),
                  Some(9),
                  Some("control_level_id"),
                ),
              )
            }
            match parse_scaled(row[9], program.precision) {
              Parsed(value) =>
                records.push({
                  epoch,
                  run_id,
                  sequence,
                  timestamp: row[7],
                  control_level_id: row[8],
                  value: Some(value),
                  line: physical_line,
                })
              Missing =>
                records.push({
                  epoch,
                  run_id,
                  sequence,
                  timestamp: row[7],
                  control_level_id: row[8],
                  value: None,
                  line: physical_line,
                })
              Invalid(message) =>
                diagnostics.push(
                  csv_diagnostic(
                    @evidence.CsvPrecision,
                    Some(run_id),
                    csv_field_location(physical_line, "value", 10) +
                    ": " +
                    message,
                    Some(physical_line),
                    Some(10),
                    Some("value"),
                  ),
                )
            }
          }
        Missing =>
          diagnostics.push(
            csv_diagnostic(
              @evidence.CsvMalformed,
              Some(run_id),
              csv_field_location(physical_line, "sequence", 7) +
              ": run sequence is required",
              Some(physical_line),
              Some(7),
              Some("sequence"),
            ),
          )
        Invalid(message) =>
          diagnostics.push(
            csv_diagnostic(
              @evidence.CsvMalformed,
              Some(run_id),
              csv_field_location(physical_line, "sequence", 7) + ": " + message,
              Some(physical_line),
              Some(7),
              Some("sequence"),
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
        diagnostics.push(
          csv_diagnostic(
            @evidence.CsvMalformed,
            Some(first.run_id),
            csv_line_location(record.line) +
            ": metadata must be identical across rows for one run",
            Some(record.line),
            None,
            None,
          ),
        )
      } else if contains_level(seen_levels, record.control_level_id) {
        diagnostics.push(
          csv_diagnostic(
            @evidence.DuplicateControlPoint,
            Some(first.run_id),
            csv_field_location(record.line, "control_level_id", 9) +
            ": duplicate row for control level " +
            record.control_level_id,
            Some(record.line),
            Some(9),
            Some("control_level_id"),
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
  { runs, diagnostics }
}
