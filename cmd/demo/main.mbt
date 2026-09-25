///|
fn main {
  let args = @env.args()
  let mut scenario = "stable"
  let mut format = "markdown"
  for i in 0..<args.length() {
    if args[i] == "--scenario" && i + 1 < args.length() {
      scenario = args[i + 1]
    } else if args[i] == "--format" && i + 1 < args.length() {
      format = args[i + 1]
    }
  }
  match @scenarios.build_scenario(scenario) {
    None =>
      println("Unknown scenario. Choose stable, step-shift, or gradual-drift.")
    Some(runs) => {
      let trajectory = @lib.replay_track(@scenarios.demo_program(), runs)
      if format == "json" {
        println(@lib.render_trajectory_json(trajectory))
      } else if format == "markdown" || format == "text" {
        println(@lib.render_trajectory_markdown(trajectory))
      } else {
        println("Unknown format. Choose markdown or json.")
      }
    }
  }
}
