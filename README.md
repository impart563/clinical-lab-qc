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
moon run --target native cmd/demo -- --scenario gradual-drift --format svg > gradual-drift.svg
moon run --target native cmd/demo -- --scenario gradual-drift --format html > gradual-drift.html
moon run --target native cmd/demo -- --input examples/synthetic-iqc.csv --format json
moon run --target native cmd/demo -- --input examples/synthetic-iqc.csv --format csv
moon run --target native cmd/demo -- --check-input --input examples/synthetic-iqc.csv
moon run --target native cmd/demo -- --check-input --input examples/synthetic-iqc.csv --program examples/demo-program.json --format json
moon run --target native cmd/demo -- --program examples/demo-program.json --check-program
moon run --target native cmd/demo -- --program examples/demo-program.json --input examples/synthetic-iqc.csv --format json
moon run --target native examples/quickstart
python scripts/acceptance.py
```

The default Markdown output starts with track totals and then lists each run, triggered rule, evidence point, comparison distance, and input issue. JSON output is a deterministic `schema_version: 1` audit envelope with the program, original runs and observations, epoch snapshots, assessments, issues, and summary counts. CSV output is a detail table with typed `assessment`, `observation`, `evidence`, `input_issue`, and `track_issue` rows; scaled measurement columns remain integer strings and include their precision.

- `stable` shows a stable synthetic track without rule hits.
- `step-shift` shows two QC epochs. The new lot and calibration start fresh rule windows.
- `gradual-drift` shows consecutive-run signals and the points that support them.
- `--input` replays a long-form CSV using the demo assay program. CSV files with parse issues fail with a nonzero process status.
- `--program` loads a custom assay profile from versioned JSON; combine it with `--input` to replay the CSV using that profile. `--check-program` validates a profile without replaying data.
- `--check-input` validates CSV parsing and run/epoch track integrity without producing a QC assessment report. It accepts an optional `--program`; the default text report or `--format json` returns diagnostics. Syntax and track errors fail with exit code 2; missing required controls are reported as warnings. QC rule signals do not decide input validity.
- `--format csv` exports the audit details as a result table; `--format json` includes status, rule-hit, and epoch-run summaries.
- `--format html` writes a single offline review report with the assay configuration, status and rule summaries, epoch metadata, an embedded Levey–Jennings SVG, and expandable per-run observations and evidence. Status cards, epoch rows, and evidence rows link directly to matching runs. It has no scripts or external assets; open the saved `.html` file in a browser.
- `examples/quickstart` is a small downstream-style program that constructs the public API types, replays data, and renders Markdown and SVG through the root package.

Assay profile JSON uses `schema_version: 1`; unknown fields are rejected. Control `mean` and `standard_deviation` values are decimal strings (for example, `"100.25"`) so they are converted exactly at the declared precision. Rule names are `1_2s`, `1_3s`, `2_2s`, `R_4s`, `4_1s`, and `10x`; dispositions are `disabled`, `warning`, or `requires_review`. Rules omitted from the `rules` array keep their built-in default dispositions. See [the example profile](examples/demo-program.json). The public parser is `parse_assay_program_json`.

## Public API

The root package exports `validate_program`, `parse_assay_program_json`, `evaluate_run`, `replay_track`, `render_levey_jennings_svg`, and `render_audit_html`, plus the domain types `AssayProgram`, `QCEpoch`, `QCRun`, `ControlPoint`, `RuleHit`, `RunAssessment`, and `Trajectory`.

The compiled [quickstart example](examples/quickstart/main.mbt) shows the complete API path: configure an assay and QC epoch, construct ordered runs, replay them, and render a report. Exact rule windows and implementation limits are documented in [Rule semantics](docs/rule-semantics.md).

`render_levey_jennings_svg(program, runs, trajectory)` returns a standalone offline SVG chart with one panel per control level, mean and ±1/2/3 SD lines, run-sequence labels, and hover details for observations. Missing values and epoch changes break the plotted line; epoch changes are marked with a vertical boundary. Rule evidence uses a distinct marker for warning, review-required, or disabled dispositions.

`render_audit_html(program, runs, trajectory)` returns a deterministic, self-contained HTML review report. It embeds the SVG chart and inline CSS, escapes report data as HTML, and includes run observations, status, rule evidence, input issues, and QC epoch metadata without contacting a network resource.

The reviewer-facing [project one-pager](docs/project-one-pager.md), [acceptance evidence map](docs/acceptance.md), [design decisions](docs/design-decisions.md), and [changelog](CHANGELOG.md) explain the project scope, development history, and how to reproduce its main results.

An `AssayProgram` declares an assay, measurement unit, decimal precision, control levels with target means and positive standard deviations, required levels, and rule policies. Values are signed `Int64` scaled integers: with precision `2`, `100.25` is represented as `10025`. Comparisons never convert to floating point. Arithmetic overflow is returned as an input issue.

The default rule policy treats `1_2s` as a warning. `1_3s`, `2_2s`, `R_4s`, `4_1s`, and `10x` require review. A program can disable rules or change their disposition. Rule detection is kept separate from that disposition policy.

`QCRun` carries a complete `QCEpoch` snapshot. Runs must arrive in input order, their sequence numbers must strictly increase within an epoch, and an epoch ID cannot be reused after the track leaves it. Replay never sorts data. It retains completed assessments and reports a track issue at the first invalid sequence or epoch boundary. A missing required observation makes the run `Incomplete`; if another evaluable signal requires review, `RequiresReview` takes precedence while retaining the missing-value issue. Missing values are not imputed and break that control level's rolling window.

Rule thresholds are strict: equality does not trigger. `2_2s` and `4_1s` require every point in the window to exceed the threshold on the same side of the mean. A point exactly at the mean breaks `10x`. `R_4s` compares different control levels from the same run.

## CSV input

`parse_qc_csv(program, text)` accepts a long-form CSV with one control observation per row and this exact header order:

```csv
epoch_id,reagent_lot,control_lot,calibration_id,program_version,run_id,sequence,timestamp,control_level_id,value
```

Epoch and run metadata repeat on each row for that run. A blank `value` represents a missing observation, not zero. Numeric values must use a plain decimal with no more fractional digits than the program precision; the parser never rounds. Quoted fields and escaped quotes follow CSV quoting rules. The parser preserves input order and reports malformed rows, duplicate control rows, and invalid decimal precision with physical line and field positions when available. Quoted multiline fields retain their physical line accounting.

## Checks

Run the same checks used by CI:

```powershell
moon check --target all
moon build --target native
moon test --target all
moon package
python scripts/acceptance.py
```

`python scripts/acceptance.py` runs the same all-target checks, build, tests, public quickstart, deterministic scenario checks, cross-format consistency checks, CLI error cases, and package build locally. CI invokes this script and records the installed MoonBit CLI version in its log.

The tests cover strict threshold boundaries, all six rules, stage isolation, missing-value window resets, input validation, overflow reporting, CSV parsing and escaping, stable versioned reports and charts, offline HTML escaping and determinism, chart gaps and epoch markers, exact demo outcomes, and all public report renderers.

## License

Apache-2.0. See [LICENSE](LICENSE).
