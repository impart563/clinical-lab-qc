# clinical-lab-qc

An offline MoonBit library for replaying synthetic or laboratory-provided internal quality-control (IQC) observations. It evaluates configured Westgard-style rules, keeps each run inside its declared QC epoch, and returns evidence that can be inspected and reproduced.

This is an analysis and review aid. It does not diagnose, connect to instruments or hospital systems, store patient data, replace a laboratory SOP, or automatically release patient results. Laboratories remain responsible for reviewing their own rule and review-policy configuration. Demo data in this repository is synthetic.

## Run the demos

Install the MoonBit toolchain, then run from the repository root:

```powershell
moon run --target native cmd/demo -- --scenario stable
moon run --target native cmd/demo -- --scenario step-shift
moon run --target native cmd/demo -- --scenario gradual-drift
moon run --target native cmd/demo -- --scenario gradual-drift --format json
```

The default Markdown output lists the run status, each triggered rule, the evidence points, comparison distances, and input issues. JSON output uses exact integer values and a fixed field order. Replaying the same scenario produces the same output.

- `stable` shows a stable synthetic track without rule hits.
- `step-shift` shows two QC epochs. The new lot and calibration start fresh rule windows.
- `gradual-drift` shows consecutive-run signals and the points that support them.

## Public API

The root package exports `validate_program`, `evaluate_run`, and `replay_track`, plus the domain types `AssayProgram`, `QCEpoch`, `QCRun`, `ControlPoint`, `RuleHit`, `RunAssessment`, and `Trajectory`.

An `AssayProgram` declares an assay, measurement unit, decimal precision, control levels with target means and positive standard deviations, required levels, and rule policies. Values are signed `Int64` scaled integers: with precision `2`, `100.25` is represented as `10025`. Comparisons never convert to floating point. Arithmetic overflow is returned as an input issue.

The default rule policy treats `1_2s` as a warning. `1_3s`, `2_2s`, `R_4s`, `4_1s`, and `10x` require review. A program can disable rules or change their disposition. Rule detection is kept separate from that disposition policy.

`QCRun` carries a complete `QCEpoch` snapshot. Runs must arrive in input order, their sequence numbers must strictly increase within an epoch, and an epoch ID cannot be reused after the track leaves it. Replay never sorts data. It retains completed assessments and reports a track issue at the first invalid sequence or epoch boundary. A missing required observation makes the run `Incomplete`; if another evaluable signal requires review, `RequiresReview` takes precedence while retaining the missing-value issue. Missing values are not imputed and break that control level's rolling window.

Rule thresholds are strict: equality does not trigger. `2_2s` and `4_1s` require every point in the window to exceed the threshold on the same side of the mean. A point exactly at the mean breaks `10x`. `R_4s` compares different control levels from the same run.

## CSV input

`parse_qc_csv(program, text)` accepts a long-form CSV with one control observation per row and this exact header order:

```csv
epoch_id,reagent_lot,control_lot,calibration_id,program_version,run_id,sequence,timestamp,control_level_id,value
```

Epoch and run metadata repeat on each row for that run. A blank `value` represents a missing observation, not zero. Numeric values must use a plain decimal with no more fractional digits than the program precision; the parser never rounds. Quoted fields and escaped quotes follow CSV quoting rules. The parser preserves input order and reports malformed rows, duplicate control rows, and invalid decimal precision.

## Checks

Run the same checks used by CI:

```powershell
moon check --target all
moon build --target native
moon test --target all
```

The tests cover strict threshold boundaries, all six rules, stage isolation, missing-value window resets, input validation, overflow reporting, CSV parsing, stable JSON, and all demo scenarios.

## License

Apache-2.0. See [LICENSE](LICENSE).
