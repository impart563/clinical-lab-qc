///|
priv struct CliOptions {
  scenario : String
  format : String
  input_path : String?
  program_path : String?
  check_program : Bool
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
    ],
    options=[
      @argparse.OptionArg(
        "scenario",
        default_values=["stable"],
        about="demo scenario: stable, step-shift, or gradual-drift",
      ),
      @argparse.OptionArg("input", about="path to a long-form QC CSV file"),
      @argparse.OptionArg(
        "program",
        about="path to a versioned JSON assay program",
      ),
      @argparse.OptionArg(
        "format",
        default_values=["markdown"],
        about="output format: markdown, json, csv, or svg",
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
  let check_program = matches.flags.get("check-program") == Some(true)
  if format != "markdown" &&
    format != "text" &&
    format != "json" &&
    format != "csv" &&
    format != "svg" {
    return Err(
      "unknown format '" + format + "'; choose markdown, json, csv, or svg",
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
  if program_path is Some(_) && input_path is None && !check_program {
    return Err("--program requires --input or --check-program")
  }
  if check_program && matches.sources.get("scenario") is Some(@argparse.Argv) {
    return Err("--check-program cannot be combined with --scenario")
  }
  Ok({ scenario, format, input_path, program_path, check_program })
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
  let runs = match options.input_path {
    Some(path) => {
      let csv_text = @fs.read_file(path).text() catch {
        _ => cli_error("unable to read CSV file '" + path + "'")
      }
      let parsed = @lib.parse_qc_csv(program, csv_text)
      if parsed.issues.length() > 0 {
        cli_error(csv_issues_message(parsed.issues))
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
  let output = match options.format {
    "json" => @lib.render_audit_json(program, runs, trajectory)
    "csv" => @lib.render_audit_csv(program, runs, trajectory)
    "svg" => @lib.render_levey_jennings_svg(program, runs, trajectory)
    _ => @lib.render_audit_markdown(program, runs, trajectory)
  }
  println(output)
  if has_fatal_trajectory_issue(trajectory) {
    cli_error("replay encountered invalid QC input; see the report above")
  }
}
