# Rule semantics and boundaries

`clinical-lab-qc` implements a deterministic rule engine for internal quality-control observations. A `RuleHit` is a review signal with evidence; it is not a patient-result release decision or a universal laboratory protocol.

## Numeric model

An `AssayProgram` supplies one decimal precision for the target mean, standard deviation, and every observation. Values are signed `Int64` scaled integers. For precision `2`, the decimal value `100.25` is represented as `10025`. The engine does not convert comparisons to floating point. A threshold is crossed only when the absolute difference is strictly greater than the threshold; equality does not trigger. Arithmetic overflow is reported as an input issue.

## Implemented rules

| Rule | Window in this implementation | Trigger | Default disposition |
| --- | --- | --- | --- |
| `1_2s` | One observed control level | One value is strictly outside mean ± 2 SD | Warning |
| `1_3s` | One observed control level | One value is strictly outside mean ± 3 SD | Requires review |
| `2_2s` | Latest two runs, same epoch and control level | Both values are strictly beyond 2 SD on the same side of the mean | Requires review |
| `R_4s` | One run, two different observed control levels | One value is above +2 SD and another is below −2 SD | Requires review |
| `4_1s` | Latest four runs, same epoch and control level | All four values are strictly beyond 1 SD on the same side of the mean | Requires review |
| `10x` | Latest ten runs, same epoch and control level | All ten values are on the same side of the mean; a value at the mean breaks the window | Requires review |

This release accepts at most one observation for each control level in a run. `2_2s`, `4_1s`, and `10x` therefore inspect same-level observations across runs. `R_4s` compares different levels in the same run. It is skipped when a required control level is missing. A missing observation is not imputed and breaks only that level's rolling window. A new `QCEpoch` clears all rolling windows.

Each rule is evaluated independently when enabled. This release does not implement a classic warning-gated multirule protocol, select rules from method performance or sigma metrics, or combine repeated measurements of one level within a run. Rule choice and review disposition must be assessed for the intended assay and local laboratory procedure. The [Westgard overview](https://www.westgard.com/westgard-rules.html) describes variants and context-dependent use; this project does not claim that its defaults fit every method.

## Status precedence

The run status is selected in this order: `RequiresReview`, `Incomplete`, `Warning`, then `InControl`. Missing required controls produce `Incomplete`, unless an evaluable rule already requires review. The assessment retains both the signal and any missing-control issue.

## Intended use

The library is an analysis and review aid for synthetic or laboratory-provided QC data. It does not diagnose, store patient data, connect to instruments or hospital systems, replace a laboratory SOP, or automatically release patient results. Do not treat the demo values or default policies as validated operational limits.
