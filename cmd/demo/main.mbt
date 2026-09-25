///|
priv struct CliOptions {
  scenario : String
  format : String
  input_path : String?
  program_path : String?
  output_path : String?
  bundle_path : String?
  check_program : Bool
  check_input : Bool
}

///|
priv struct InputValidation {
  input_runs : Int
  errors : Array[@lib.InputIssue]
  warnings : Array[@lib.InputIssue]
  csv_diagnostics : Array[@lib.CsvDiagnostic]
}

///|
extern "c" fn process_exit(code : Int) -> Unit = "exit"

///|
fn[T] cli_error(message : String) -> T {
  println("error: " + message)
  process_exit(2)
  panic()
}

///|
fn cli_command() -> @argparse.Command {
  @argparse.Command(
    "clinical-lab-qc",
    about="Replay QC data or validate a versioned assay program.",
    flags=[
      @argparse.FlagArg(
        "check-program",
        action=@argparse.SetTrue,
        about="validate the selected program and exit",
      ),
      @argparse.FlagArg(
        "check-input",
        action=@argparse.SetTrue,
        about="validate CSV structure and track integrity without a QC report",
      ),
    ],
    options=[
      @argparse.OptionArg(
        "scenario",
        default_values=["stable"],
        about="demo scenario: stable, step-shift, or gradual-drift",
      ),
      @argparse.OptionArg("input", about="path to a long-form QC CSV file"),
      @argparse.OptionArg("output", about="write the report to this file path"),
      @argparse.OptionArg(
        "bundle",
        about="write an offline review bundle to this directory",
      ),
      @argparse.OptionArg(
        "program",
        about="path to a versioned JSON assay program",
      ),
      @argparse.OptionArg(
        "format",
        default_values=["markdown"],
        about="output format: markdown, json, csv, svg, or html",
      ),
    ],
  )
}

///|
fn parse_cli_args(args : Array[String]) -> Result[CliOptions, String] {
  let matches : @argparse.Matches = cli_command().parse(argv=args, env=Map([])) catch {
    error => return Err(error.to_string())
  }
  let scenario = match matches.values.get("scenario") {
    Some(values) if values.length() == 1 => values[0]
    _ => "stable"
  }
  let format = match matches.values.get("format") {
    Some(values) if values.length() == 1 => values[0]
    _ => "markdown"
  }
  let input_path = match matches.values.get("input") {
    Some(values) if values.length() == 1 => Some(values[0])
    _ => None
  }
  let program_path = match matches.values.get("program") {
    Some(values) if values.length() == 1 => Some(values[0])
    _ => None
  }
  let output_path = match matches.values.get("output") {
    Some(values) if values.length() == 1 => Some(values[0])
    _ => None
  }
  let bundle_path = match matches.values.get("bundle") {
    Some(values) if values.length() == 1 => Some(values[0])
    _ => None
  }
  let check_program = matches.flags.get("check-program") == Some(true)
  let check_input = matches.flags.get("check-input") == Some(true)
  if format != "markdown" &&
    format != "text" &&
    format != "json" &&
    format != "csv" &&
    format != "svg" &&
    format != "html" {
    return Err(
      "unknown format '" +
      format +
      "'; choose markdown, json, csv, svg, or html",
    )
  }
  if input_path is Some(_) &&
    matches.sources.get("scenario") is Some(@argparse.Argv) {
    return Err("choose either --input or --scenario, not both")
  }
  if input_path is None &&
    scenario != "stable" &&
    scenario != "step-shift" &&
    scenario != "gradual-drift" {
    return Err(
      "unknown scenario '" +
      scenario +
      "'; choose stable, step-shift, or gradual-drift",
    )
  }
  if check_program && program_path is None {
    return Err("--check-program requires --program <path>")
  }
  if check_program && input_path is Some(_) {
    return Err("--check-program cannot be combined with --input")
  }
  if check_input && input_path is None {
    return Err("--check-input requires --input <path>")
  }
  if check_input && check_program {
    return Err("--check-input cannot be combined with --check-program")
  }
  if check_input && matches.sources.get("scenario") is Some(@argparse.Argv) {
    return Err("--check-input cannot be combined with --scenario")
  }
  if check_input && format != "markdown" && format != "text" && format != "json" {
    return Err("--check-input supports only --format text or --format json")
  }
  if program_path is Some(_) && input_path is None && !check_program {
    return Err("--program requires --input or --check-program")
  }
  if check_program && matches.sources.get("scenario") is Some(@argparse.Argv) {
    return Err("--check-program cannot be combined with --scenario")
  }
  if check_program && output_path is Some(_) {
    return Err("--output cannot be combined with --check-program")
  }
  if bundle_path is Some(path) && path.trim().is_empty() {
    return Err("--bundle requires a non-empty directory path")
  }
  if bundle_path is Some(_) && output_path is Some(_) {
    return Err("--bundle cannot be combined with --output")
  }
  if bundle_path is Some(_) && (check_input || check_program) {
    return Err("--bundle cannot be combined with input or program preflight")
  }
  if bundle_path is Some(_) &&
    matches.sources.get("format") is Some(@argparse.Argv) {
    return Err("--bundle exports every supported format; omit --format")
  }
  if output_path is Some(path) && path.trim().is_empty() {
    return Err("--output requires a non-empty file path")
  }
  Ok({
    scenario,
    format,
    input_path,
    program_path,
    output_path,
    bundle_path,
    check_program,
    check_input,
  })
}

///|
fn csv_issues_message(issues : Array[@lib.InputIssue]) -> String {
  let message = StringBuilder()
  message.write_string("CSV input has ")
  message.write_string(issues.length().to_string())
  message.write_string(" issue(s):")
  for issue in issues {
    message.write_string("\n- [")
    message.write_string(issue.code.name())
    message.write_string("] ")
    message.write_string(issue.message)
  }
  message.to_string()
}

///|
fn program_issues_message(issues : Array[String]) -> String {
  let message = StringBuilder()
  message.write_string("program configuration has ")
  message.write_string(issues.length().to_string())
  message.write_string(" issue(s):")
  for issue in issues {
    message.write_string("\n- ")
    message.write_string(issue)
  }
  message.to_string()
}

///|
fn validation_contains_issue(
  issues : Array[@lib.InputIssue],
  candidate : @lib.InputIssue,
) -> Bool {
  for issue in issues {
    if issue.code == candidate.code &&
      issue.run_id == candidate.run_id &&
      issue.message == candidate.message {
      return true
    }
  }
  false
}

///|
fn validate_csv_input(
  program : @lib.AssayProgram,
  parsed : @lib.CsvParseDetailedResult,
) -> InputValidation {
  let errors : Array[@lib.InputIssue] = []
  for diagnostic in parsed.diagnostics {
    errors.push(diagnostic.issue)
  }
  let warnings : Array[@lib.InputIssue] = []
  if errors.length() > 0 {
    return {
      input_runs: parsed.runs.length(),
      errors,
      warnings,
      csv_diagnostics: parsed.diagnostics,
    }
  }
  let trajectory = @lib.replay_track(program, parsed.runs)
  for issue in trajectory.input_issues {
    errors.push(issue)
  }
  for assessment in trajectory.assessments {
    for issue in assessment.input_issues {
      if issue.code == @evidence.MissingRequiredControl {
        if !validation_contains_issue(warnings, issue) {
          warnings.push(issue)
        }
      } else if !validation_contains_issue(errors, issue) {
        errors.push(issue)
      }
    }
  }
  {
    input_runs: parsed.runs.length(),
    errors,
    warnings,
    csv_diagnostics: parsed.diagnostics,
  }
}

///|
fn find_csv_diagnostic(
  diagnostics : Array[@lib.CsvDiagnostic],
  issue : @lib.InputIssue,
) -> @lib.CsvDiagnostic? {
  for diagnostic in diagnostics {
    let candidate = diagnostic.issue
    if candidate.code == issue.code &&
      candidate.run_id == issue.run_id &&
      candidate.message == issue.message {
      return Some(diagnostic)
    }
  }
  None
}

///|
fn json_optional_int(value : Int?) -> Json {
  match value {
    Some(number) => Json::number(number.to_double())
    None => Json::null()
  }
}

///|
fn json_validation_issue(
  issue : @lib.InputIssue,
  severity : String,
  diagnostics : Array[@lib.CsvDiagnostic],
) -> Json {
  let fields : Map[String, Json] = Map([])
  fields["severity"] = Json::string(severity)
  fields["code"] = Json::string(issue.code.name())
  fields["run_id"] = match issue.run_id {
    Some(run_id) => Json::string(run_id)
    None => Json::null()
  }
  fields["message"] = Json::string(issue.message)
  fields["location"] = match find_csv_diagnostic(diagnostics, issue) {
    Some(diagnostic) => {
      let location : Map[String, Json] = Map([])
      location["line"] = json_optional_int(diagnostic.line)
      location["column"] = json_optional_int(diagnostic.column)
      location["field"] = match diagnostic.field {
        Some(name) => Json::string(name)
        None => Json::null()
      }
      Json::object(location)
    }
    None => Json::null()
  }
  Json::object(fields)
}

///|
fn input_validation_json(validation : InputValidation) -> String {
  let fields : Map[String, Json] = Map([])
  fields["schema_version"] = Json::number(1.0)
  fields["valid"] = Json::boolean(validation.errors.length() == 0)
  fields["input_runs"] = Json::number(validation.input_runs.to_double())
  fields["error_count"] = Json::number(validation.errors.length().to_double())
  fields["warning_count"] = Json::number(
    validation.warnings.length().to_double(),
  )
  fields["errors"] = Json::array(
    validation.errors.map(fn(issue) {
      json_validation_issue(issue, "error", validation.csv_diagnostics)
    }),
  )
  fields["warnings"] = Json::array(
    validation.warnings.map(fn(issue) {
      json_validation_issue(issue, "warning", validation.csv_diagnostics)
    }),
  )
  fields["scope"] = Json::string("input structure and track integrity")
  Json::object(fields).stringify(indent=2)
}

///|
fn append_validation_issues(
  output : StringBuilder,
  label : String,
  issues : Array[@lib.InputIssue],
) -> Unit {
  for issue in issues {
    output.write_string("\n- [")
    output.write_string(label)
    output.write_string(": ")
    output.write_string(issue.code.name())
    output.write_string("] ")
    match issue.run_id {
      Some(run_id) => {
        output.write_string("run '")
        output.write_string(run_id)
        output.write_string("': ")
      }
      None => ()
    }
    output.write_string(issue.message)
  }
}

///|
fn input_validation_text(validation : InputValidation) -> String {
  let output = StringBuilder()
  output.write_string(
    if validation.errors.length() == 0 {
      "Input preflight: valid\n"
    } else {
      "Input preflight: invalid\n"
    },
  )
  output.write_string("Input runs: ")
  output.write_string(validation.input_runs.to_string())
  output.write_string("\nErrors: ")
  output.write_string(validation.errors.length().to_string())
  output.write_string("\nWarnings: ")
  output.write_string(validation.warnings.length().to_string())
  append_validation_issues(output, "error", validation.errors)
  append_validation_issues(output, "warning", validation.warnings)
  output.write_string(
    "\nQC rule signals are not used to decide input validity. This preflight does not authorize result release.",
  )
  output.to_string()
}

///|
async fn emit_report(output_path : String?, content : String) -> Unit {
  match output_path {
    Some(path) => {
      @fs.write_file(path, content, create_mode=@fs.CreateOrTruncate) catch {
        _ =>
          cli_error(
            "unable to write report file '" +
            path +
            "'; check that the parent directory exists and is writable",
          )
      }
      println("Report written to '" + path + "'")
    }
    None => println(content)
  }
}

///|
async fn write_review_bundle(
  directory : String,
  program : @lib.AssayProgram,
  runs : Array[@lib.QCRun],
  trajectory : @lib.Trajectory,
) -> Unit {
  @fs.mkdir(directory, recursive=true) catch {
    _ => ()
  }
  let artifacts = [
    ("report.html", @lib.render_audit_html(program, runs, trajectory)),
    ("audit.json", @lib.render_audit_json(program, runs, trajectory)),
    ("audit.csv", @lib.render_audit_csv(program, runs, trajectory)),
    ("chart.svg", @lib.render_levey_jennings_svg(program, runs, trajectory)),
    ("manifest.json", @lib.render_audit_manifest(program, runs, trajectory)),
  ]
  for index in 0..<artifacts.length() {
    let (name, content) = artifacts[index]
    let path = directory + "/" + name
    @fs.write_file(path, content, create_mode=@fs.CreateOrTruncate) catch {
      _ =>
        cli_error(
          "unable to write review bundle file '" +
          path +
          "'; check that the directory exists and is writable",
        )
    }
  }
  println("Review bundle written to '" + directory + "'")
}

///|
async fn load_program(path : String) -> @lib.AssayProgram {
  let text = @fs.read_file(path).text() catch {
    _ => cli_error("unable to read program configuration '" + path + "'")
  }
  let parsed = @lib.parse_assay_program_json(text)
  if parsed.issues.length() > 0 {
    cli_error(program_issues_message(parsed.issues))
  }
  match parsed.program {
    Some(program) => program
    None => cli_error("program configuration is invalid")
  }
}

///|
fn has_fatal_trajectory_issue(trajectory : @lib.Trajectory) -> Bool {
  if trajectory.input_issues.length() > 0 {
    return true
  }
  for assessment in trajectory.assessments {
    for issue in assessment.input_issues {
      if issue.code.name() != "missing_required_control" {
        return true
      }
    }
  }
  false
}

///|
async fn main {
  let raw_args = @env.args()
  let args = if raw_args.length() > 0 { raw_args[1:].to_owned() } else { [] }
  let options = match parse_cli_args(args) {
    Ok(value) => value
    Err(message) => cli_error(message)
  }
  let program = match options.program_path {
    Some(path) => load_program(path)
    None => @scenarios.demo_program()
  }
  if options.check_program {
    println(
      "valid: " +
      program.assay_id +
      " (" +
      program.levels.length().to_string() +
      " control levels, precision " +
      program.precision.to_string() +
      ")",
    )
    return
  }
  if options.check_input {
    let path = match options.input_path {
      Some(value) => value
      None => cli_error("--check-input requires --input <path>")
    }
    let csv_text = @fs.read_file(path).text() catch {
      _ => cli_error("unable to read CSV file '" + path + "'")
    }
    let parsed = @lib.parse_qc_csv_detailed(program, csv_text)
    let validation = validate_csv_input(program, parsed)
    let output = if options.format == "json" {
      input_validation_json(validation)
    } else {
      input_validation_text(validation)
    }
    emit_report(options.output_path, output)
    if validation.errors.length() > 0 {
      process_exit(2)
    }
    return
  }
  let runs = match options.input_path {
    Some(path) => {
      let csv_text = @fs.read_file(path).text() catch {
        _ => cli_error("unable to read CSV file '" + path + "'")
      }
      let parsed = @lib.parse_qc_csv_detailed(program, csv_text)
      if parsed.diagnostics.length() > 0 {
        cli_error(
          csv_issues_message(
            parsed.diagnostics.map(fn(diagnostic) { diagnostic.issue }),
          ),
        )
      }
      parsed.runs
    }
    None =>
      match @scenarios.build_scenario(options.scenario) {
        Some(value) => value
        None => cli_error("unknown scenario '" + options.scenario + "'")
      }
  }
  let trajectory = @lib.replay_track(program, runs)
  match options.bundle_path {
    Some(directory) => write_review_bundle(directory, program, runs, trajectory)
    None => {
      let output = match options.format {
        "json" => @lib.render_audit_json(program, runs, trajectory)
        "csv" => @lib.render_audit_csv(program, runs, trajectory)
        "svg" => @lib.render_levey_jennings_svg(program, runs, trajectory)
        "html" => @lib.render_audit_html(program, runs, trajectory)
        _ => @lib.render_audit_markdown(program, runs, trajectory)
      }
      emit_report(options.output_path, output)
    }
  }
  if has_fatal_trajectory_issue(trajectory) {
    cli_error("replay encountered invalid QC input; see the report above")
  }
}
