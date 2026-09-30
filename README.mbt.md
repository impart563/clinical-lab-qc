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
moon run --target native cmd/demo -- --scenario gradual-drift --format html --output gradual-drift.html
moon run --target native cmd/demo -- --scenario gradual-drift --bundle review-bundle
moon run --target native cmd/demo -- --input examples/synthetic-iqc.csv --format json
moon run --target native cmd/demo -- --input examples/synthetic-iqc.csv --format csv
moon run --target native cmd/demo -- --check-input --input examples/synthetic-iqc.csv
moon run --target native cmd/demo -- --check-input --input examples/synthetic-iqc.csv --program examples/demo-program.json --format json
moon run --target native cmd/demo -- --program examples/demo-program.json --check-program
moon run --target native cmd/demo -- --program examples/demo-program.json --input examples/synthetic-iqc.csv --format json
moon run --target native cmd/demo -- --program examples/demo-program.json --input examples/daily-qc-2026-09-28.csv --input examples/daily-qc-2026-09-29.csv --input examples/daily-qc-2026-09-30.csv --format json
moon run --target native examples/quickstart
moon -C examples/downstream-consumer run --target native .
python scripts/acceptance.py
```

The default Markdown output starts with track totals and then lists each run, triggered rule, evidence point, comparison distance, and input issue. Single-file JSON output remains a deterministic `schema_version: 1` audit envelope. Batch JSON uses `schema_version: 2` and adds a sanitized `source_label` to every run; batch CSV adds a `source_label` column, while Markdown, HTML, SVG metadata, and the bundle manifest retain the run-to-file source map. CSV output is a detail table with typed `assessment`, `observation`, `evidence`, `input_issue`, and `track_issue` rows; scaled measurement columns remain integer strings and include their precision.

- `stable` shows a stable synthetic track without rule hits.
- `step-shift` shows two QC epochs. The new lot and calibration start fresh rule windows.
- `gradual-drift` shows consecutive-run signals and the points that support them.
- `--input` replays a long-form CSV using the demo assay program. Repeat `--input <path>` to process several files as one ordered track with a separate header per file; file order is preserved. The CLI attempts every file, reports read and parse failures together, and returns no QC report if any source is invalid. Reports include each run's source filename, never its absolute path.
- `--program` loads a custom assay profile from versioned JSON; combine it with `--input` to replay the CSV using that profile. `--check-program` validates a profile without replaying data.
- `--check-input` validates one or more CSV files and run/epoch track integrity without producing a QC assessment report. It accepts an optional `--program`; the default text report or `--format json` returns diagnostics. JSON diagnostics include stable issue codes, severity, and a structured `location` (`line`, `column`, `field`, and, for batch parse errors, `source_file`). Track-integrity issues have `location: null`. Syntax and track errors fail with exit code 2; missing required controls are reported as warnings. QC rule signals do not decide input validity.
- `--format csv` exports the audit details as a result table; `--format json` includes status, rule-hit, and epoch-run summaries.
- `--format html` writes a single offline review report with the assay configuration, status and rule summaries, epoch metadata, control-observation coverage, an embedded Levey–Jennings SVG, and expandable per-run observations and evidence. Status cards, epoch rows, rule summaries, and coverage gaps link directly to matching runs. It has no scripts or external assets; open the saved `.html` file in a browser.
- `--output <path>` writes the selected report format directly to a file, replacing an existing file; without it, reports go to standard output. The output parent directory must already exist. Write failures return a clear error and nonzero exit status.
- `--bundle <directory>` creates an offline review package containing `report.html`, `audit.json`, `audit.csv`, `chart.svg`, and `manifest.json`. The manifest records schema versions, relative artifact paths, run/epoch totals, status counts, control-observation coverage, and (for batch inputs) display filenames; it omits source paths and timestamps so identical input produces identical files. Existing files in the selected directory are replaced.
- `examples/quickstart` is a small downstream-style program that constructs the public API types, replays data, and renders Markdown and SVG through the root package.
- `examples/downstream-consumer` is a separate MoonBit module pinned to the published `0.2.0` registry release. The acceptance script installs that exact version and calls the new batch parser and JSON renderer across the package boundary.

Assay profile JSON uses `schema_version: 1`; unknown fields are rejected. Control `mean` and `standard_deviation` values are decimal strings (for example, `"100.25"`) so they are converted exactly at the declared precision. Rule names are `1_2s`, `1_3s`, `2_2s`, `R_4s`, `4_1s`, and `10x`; dispositions are `disabled`, `warning`, or `requires_review`. Rules omitted from the `rules` array keep their built-in default dispositions. See [the example profile](examples/demo-program.json). The public parser is `parse_assay_program_json`.

## Public API

The root package exports `validate_program`, `parse_assay_program_json`, `parse_qc_csv`, `parse_qc_csv_detailed`, `parse_qc_csv_batch_detailed`, `evaluate_run`, `replay_track`, the report renderers, and the domain types `AssayProgram`, `QCEpoch`, `QCRun`, `ControlPoint`, `RuleHit`, `RunAssessment`, and `Trajectory`. `parse_qc_csv_detailed` returns the same parsed runs with diagnostics that expose the issue, physical line, column, and field as typed values. `parse_qc_csv_batch_detailed` accepts an ordered array of `{ label, text }` inputs and returns source-tagged runs and diagnostics; if any file has a CSV error, its `runs` array is empty to prevent partial replay. The batch renderers accept those sourced runs and a single trajectory.

The compiled [quickstart example](examples/quickstart/main.mbt) shows the complete API path: configure an assay and QC epoch, construct ordered runs, replay them, and render a report. Exact rule windows and implementation limits are documented in [Rule semantics](docs/rule-semantics.md).

`render_levey_jennings_svg(program, runs, trajectory)` returns a standalone offline SVG chart with one panel per control level, mean and ±1/2/3 SD lines, run-sequence labels, and hover details for observations. Missing values and epoch changes break the plotted line; epoch changes are marked with a vertical boundary. Rule evidence uses a distinct marker for warning, review-required, or disabled dispositions.

`render_audit_html(program, runs, trajectory)` returns a deterministic, self-contained HTML review report. It embeds the SVG chart and inline CSS, escapes report data as HTML, and includes run observations, status, rule evidence, input issues, and QC epoch metadata without contacting a network resource.

The [acceptance evidence map](docs/acceptance.md), [design decisions](docs/design-decisions.md), and [changelog](CHANGELOG.md) explain the project scope, development history, and how to reproduce its main results.

An `AssayProgram` declares an assay, measurement unit, decimal precision, control levels with target means and positive standard deviations, required levels, and rule policies. Values are signed `Int64` scaled integers: with precision `2`, `100.25` is represented as `10025`. Comparisons never convert to floating point. Arithmetic overflow is returned as an input issue.

The default rule policy treats `1_2s` as a warning. `1_3s`, `2_2s`, `R_4s`, `4_1s`, and `10x` require review. A program can disable rules or change their disposition. Rule detection is kept separate from that disposition policy.

`QCRun` carries a complete `QCEpoch` snapshot. Runs must arrive in input order, their sequence numbers must strictly increase within an epoch, and an epoch ID cannot be reused after the track leaves it. Replay never sorts data. It retains completed assessments and reports a track issue at the first invalid sequence or epoch boundary. A missing required observation makes the run `Incomplete`; if another evaluable signal requires review, `RequiresReview` takes precedence while retaining the missing-value issue. Missing values are not imputed and break that control level's rolling window.

Rule thresholds are strict: equality does not trigger. `2_2s` and `4_1s` require every point in the window to exceed the threshold on the same side of the mean. A point exactly at the mean breaks `10x`. `R_4s` compares different control levels from the same run.

## CSV input

`parse_qc_csv(program, text)` accepts a long-form CSV with one control observation per row and this exact header order. `parse_qc_csv_batch_detailed(program, inputs)` accepts the same header independently in each source and preserves the caller's input order:

```csv
epoch_id,reagent_lot,control_lot,calibration_id,program_version,run_id,sequence,timestamp,control_level_id,value
```

Epoch and run metadata repeat on each row for that run. A blank `value` represents a missing observation, not zero. Numeric values must use a plain decimal with no more fractional digits than the program precision; the parser never rounds. Quoted fields and escaped quotes follow CSV quoting rules. The parser preserves input order and reports malformed rows, duplicate control rows, unknown control levels, and invalid decimal precision with physical line and field positions when available. Quoted multiline fields retain their physical line accounting. Coverage counts expected run/control pairs separately as observed, missing, or precision-mismatched. Optional controls are shown with their required flag; blank observations are never imputed. `render_audit_manifest(program, runs, trajectory)` creates the same deterministic manifest used by `--bundle`.

The JSON summary and bundle manifest attribute rule hits to each epoch and, where evidence identifies a level, to each epoch/control pair. The offline HTML report shows these counts with the rule disposition and links each row to its first matching run. The Markdown summary lists per-epoch rule totals and per-epoch/control counts. These are traceability summaries of replay evidence; they do not change rule evaluation or clinical review decisions.

## Checks

Run the same checks used by CI:

```powershell
moon check --target all
moon build --target native
moon test --target all
moon package
python scripts/acceptance.py
```

`python scripts/acceptance.py` runs the same all-target checks, build, tests, public quickstart, separate downstream-consumer smoke test, deterministic scenario checks, cross-format consistency checks, CLI error cases, and package build locally. CI invokes this script and records the installed MoonBit CLI version in its log.

Acceptance also checks cold-start dependency resolution through `moon update`, structured CSV locations, epoch status and rule-hit summaries, per-epoch/control rule attribution, per-control observation coverage, missing-value navigation, and byte-for-byte deterministic single-file and multi-file review bundles. The multi-file fixture contains three synthetic daily exports with 10 runs and two control levels per file, a rule window that crosses a file boundary, and a lot/calibration epoch transition; it contains no real lab or patient data.

The tests cover strict threshold boundaries, all six rules, stage isolation, missing-value window resets, input validation, overflow reporting, CSV parsing and escaping, stable versioned reports and charts, offline HTML escaping and determinism, chart gaps and epoch markers, exact demo outcomes, and all public report renderers.

## License

Apache-2.0. See [LICENSE](LICENSE).
