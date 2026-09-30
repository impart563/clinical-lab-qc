#!/usr/bin/env python3
"""Run the repository's reproducible closeout checks from any working directory."""

from __future__ import annotations

import csv
import io
import json
import re
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ET
from collections import Counter
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SVG_NS = "{http://www.w3.org/2000/svg}"


def command(
    args: list[str],
    *,
    expected: int = 0,
    cwd: Path = ROOT,
) -> subprocess.CompletedProcess[str]:
    result = subprocess.run(
        args,
        cwd=cwd,
        check=False,
        capture_output=True,
        text=True,
        encoding="utf-8",
    )
    if result.returncode != expected:
        rendered = " ".join(args)
        raise RuntimeError(
            f"{rendered!r} exited {result.returncode}, expected {expected}\n"
            f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
        )
    return result


def moon(*args: str) -> str:
    return command(["moon", *args]).stdout


def require(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


def verify_scenario(name: str) -> None:
    print(f"Verify scenario: {name}")
    outputs: dict[str, str] = {}
    for output_format in ("markdown", "json", "csv", "svg", "html"):
        args = [
            "moon",
            "run",
            "--target",
            "native",
            "cmd/demo",
            "--",
            "--scenario",
            name,
            "--format",
            output_format,
        ]
        first = command(args).stdout
        second = command(args).stdout
        require(first == second, f"{name}/{output_format} output changed between replays")
        outputs[output_format] = first

    report = json.loads(outputs["json"])
    summary = report["summary"]
    status_counts = summary["status_counts"]
    require(summary["input_runs"] == 12, f"{name}: expected 12 input runs")
    require(summary["assessed_runs"] == 12, f"{name}: expected 12 assessments")
    require(summary["track_issue_count"] == 0, f"{name}: unexpected replay issue")
    require(
        len(summary["epoch_run_counts"]) == (2 if name == "step-shift" else 1),
        f"{name}: unexpected epoch count",
    )
    if name == "step-shift":
        epoch_counts = {
            entry["id"]: entry["run_count"] for entry in summary["epoch_run_counts"]
        }
        require(epoch_counts == {"lot-a": 6, "lot-b": 6}, "step-shift: epoch run counts changed")
        epoch_statuses = {
            entry["id"]: entry["status_counts"]
            for entry in summary["epoch_run_counts"]
        }
        require(
            all(statuses == {"InControl": 6, "Warning": 0, "RequiresReview": 0, "Incomplete": 0}
                for statuses in epoch_statuses.values()),
            "step-shift: per-epoch status counts changed",
        )

    expected_nonzero: dict[str, int]
    expected_statuses: dict[str, int]
    expected_rules: dict[str, int]
    if name in ("stable", "step-shift"):
        expected_statuses = {"InControl": 12}
        expected_rules = {}
        expected_nonzero = {}
    else:
        expected_statuses = {"InControl": 6, "RequiresReview": 6}
        expected_rules = {"1_2s": 1, "4_1s": 6, "10x": 2}
        expected_nonzero = expected_rules

    actual_statuses = {key: value for key, value in status_counts.items() if value}
    actual_rules = {
        entry["rule"]: entry["count"]
        for entry in summary["rule_hit_counts"]
        if entry["count"]
    }
    require(actual_statuses == expected_statuses, f"{name}: unexpected status counts {actual_statuses}")
    epoch_status_totals = Counter()
    for entry in summary["epoch_run_counts"]:
        epoch_status_totals.update(entry["status_counts"])
    require(
        dict(epoch_status_totals) == status_counts,
        f"{name}: per-epoch statuses do not reconcile with track totals",
    )
    require(actual_rules == expected_rules, f"{name}: unexpected rule counts {actual_rules}")
    epoch_rule_totals = Counter()
    epoch_control_rule_totals = Counter()
    for entry in summary["epoch_run_counts"]:
        epoch_rule_totals.update(
            {
                hit["rule"]: hit["count"]
                for hit in entry["rule_hit_counts"]
            }
        )
        epoch_control_rule_totals.update(
            {
                (hit["control_level_id"], hit["rule"]): hit["count"]
                for hit in entry["control_rule_hit_counts"]
            }
        )
    require(
        dict(epoch_rule_totals) == actual_rules,
        f"{name}: per-epoch rule hits do not reconcile with track totals",
    )
    require(summary["total_rule_hits"] == sum(expected_nonzero.values()), f"{name}: unexpected hit total")
    expected_control_rules = (
        {("L1", "1_2s"): 1, ("L1", "4_1s"): 6, ("L1", "10x"): 2}
        if name == "gradual-drift"
        else {}
    )
    actual_control_rules = {
        (entry["control_level_id"], entry["rule"]): entry["count"]
        for entry in summary["control_rule_hit_counts"]
    }
    require(
        actual_control_rules == expected_control_rules,
        f"{name}: unexpected control-level hit counts {actual_control_rules}",
    )
    require(
        dict(epoch_control_rule_totals) == actual_control_rules,
        f"{name}: per-epoch/control rule hits do not reconcile with track totals",
    )
    coverage = summary["control_observation_coverage"]
    require(
        len(coverage) == 2 * len(summary["epoch_run_counts"]),
        f"{name}: expected one coverage row per epoch and control level",
    )
    require(
        all(
            row["expected_runs"] == row["observed_runs"]
            and row["missing_runs"] == 0
            and row["precision_mismatch_runs"] == 0
            for row in coverage
        ),
        f"{name}: complete demo track reported a coverage gap",
    )
    control_observations = summary["control_observation_counts"]
    require(
        control_observations["expected"] == 24
        and control_observations["observed"] == 24
        and control_observations["missing"] == 0
        and control_observations["precision_mismatch"] == 0,
        f"{name}: demo coverage totals changed: {control_observations}",
    )

    csv_rows = list(csv.DictReader(io.StringIO(outputs["csv"])))
    assessments = [row for row in csv_rows if row["record_type"] == "assessment"]
    require(len(assessments) == 12, f"{name}: CSV should contain 12 assessments")
    csv_statuses = Counter(row["status"] for row in assessments)
    require(dict(csv_statuses) == expected_statuses, f"{name}: CSV and JSON status counts disagree")
    csv_evidence = Counter(
        row["rule"] for row in csv_rows if row["record_type"] == "evidence"
    )
    expected_evidence = (
        {"1_2s": 1, "4_1s": 24, "10x": 20} if name == "gradual-drift" else {}
    )
    require(dict(csv_evidence) == expected_evidence, f"{name}: CSV and JSON evidence disagree")
    require(len([row for row in csv_rows if row["record_type"] == "track_issue"]) == 0, f"{name}: CSV has track issues")

    svg_root = ET.fromstring(outputs["svg"])
    require(svg_root.tag == f"{SVG_NS}svg", f"{name}: invalid SVG root")
    svg_classes = Counter(element.attrib.get("class", "") for element in svg_root.iter())
    require(svg_classes["control-panel"] == 2, f"{name}: expected one SVG panel per control level")
    require(
        svg_classes["epoch-boundary"] == (2 if name == "step-shift" else 0),
        f"{name}: unexpected SVG epoch boundaries",
    )
    require(
        (svg_classes["rule-evidence"] > 0) == (name == "gradual-drift"),
        f"{name}: unexpected SVG rule evidence markers",
    )

    html_report = outputs["html"]
    require(html_report.startswith("<!doctype html>"), f"{name}: HTML doctype missing")
    require('<html lang="en">' in html_report, f"{name}: HTML language missing")
    require('<svg xmlns="http://www.w3.org/2000/svg"' in html_report, f"{name}: embedded SVG missing")
    require('class="control-panel"' in html_report, f"{name}: embedded chart panels missing")
    require("Run assessments" in html_report, f"{name}: run details missing")
    require("Control observation coverage" in html_report, f"{name}: HTML coverage summary missing")
    run_targets = set(re.findall(r'<details class="run" id="([^"]+)"', html_report))
    run_links = re.findall(r'href="#([^"]+)"', html_report)
    require(len(run_targets) == 12, f"{name}: expected one HTML anchor per assessment")
    require(
        all(target in run_targets for target in run_links),
        f"{name}: an HTML navigation link does not resolve to a run",
    )
    require("<script" not in html_report.lower(), f"{name}: report unexpectedly contains a script")
    require("<link" not in html_report.lower(), f"{name}: report unexpectedly links an external resource")
    require("https://" not in html_report.lower(), f"{name}: report unexpectedly references an external URL")
    svg_start = html_report.find("<svg ")
    svg_end = html_report.find("</svg>", svg_start) + len("</svg>")
    require(svg_start >= 0 and svg_end > svg_start, f"{name}: embedded SVG is incomplete")
    ET.fromstring(html_report[svg_start:svg_end])
    for status, label in (
        ("InControl", "In control"),
        ("Warning", "Warning"),
        ("RequiresReview", "Requires review"),
        ("Incomplete", "Incomplete"),
    ):
        require(
            f"{label}<strong>{status_counts.get(status, 0)}</strong>" in html_report,
            f"{name}: HTML and JSON {status} counts disagree",
        )

    require("# QC replay" in outputs["markdown"], f"{name}: Markdown report header missing")
    require("Track issues: 0" in outputs["markdown"], f"{name}: Markdown reports a track issue")
    if name == "stable":
        require("Statuses: InControl 12" in outputs["markdown"], "stable: Markdown status summary changed")
        require("Rule hits: none" in outputs["markdown"], "stable: Markdown should report no rule hits")
    elif name == "step-shift":
        require("lot-a 6 run(s); lot-b 6 run(s)" in outputs["markdown"], "step-shift: epoch summary changed")
    else:
        require(
            "Statuses: InControl 6, Warning 0, RequiresReview 6, Incomplete 0"
            in outputs["markdown"],
            "gradual-drift: Markdown status summary changed",
        )
        require("Rule hits: 1_2s 1, 4_1s 6, 10x 2" in outputs["markdown"], "gradual-drift: rule summary changed")
        require("Rule signals and evidence" in html_report, "gradual-drift: HTML evidence details missing")


def verify_input_preflight() -> None:
    print("Verify CSV preflight")
    source = (ROOT / "examples" / "synthetic-iqc.csv").read_text(encoding="utf-8")
    program = str(ROOT / "examples" / "demo-program.json")

    def check_format(
        content: str,
        output_format: str,
        *,
        expected: int = 0,
    ) -> subprocess.CompletedProcess[str]:
        with tempfile.NamedTemporaryFile(
            mode="w", encoding="utf-8", suffix=".csv", delete=False
        ) as csv_file:
            csv_file.write(content)
            csv_path = Path(csv_file.name)
        try:
            return command(
                [
                    "moon",
                    "run",
                    "--target",
                    "native",
                    "cmd/demo",
                    "--",
                    "--check-input",
                    "--input",
                    str(csv_path),
                    "--program",
                    program,
                    "--format",
                    output_format,
                ],
                expected=expected,
            )
        finally:
            csv_path.unlink(missing_ok=True)

    valid = check_format(source, "text")
    require("Input preflight: valid" in valid.stdout, "valid CSV preflight failed")
    require("Input runs: 3" in valid.stdout, "preflight run count changed")
    require("QC rule signals are not used" in valid.stdout, "preflight scope was not explained")

    valid_json = command(
        [
            "moon",
            "run",
            "--target",
            "native",
            "cmd/demo",
            "--",
            "--check-input",
            "--input",
            str(ROOT / "examples" / "synthetic-iqc.csv"),
            "--program",
            program,
            "--format",
            "json",
        ]
    )
    json_report = json.loads(valid_json.stdout)
    require(json_report["valid"] is True, "valid JSON preflight changed")
    require(json_report["input_runs"] == 3, "JSON preflight run count changed")
    require(json_report["errors"] == [], "valid preflight reported errors")

    missing_control = "\n".join(
        line for line in source.splitlines() if ",L2," not in line
    ) + "\n"
    incomplete = json.loads(check_format(missing_control, "json").stdout)
    require(incomplete["valid"] is True, "missing observations should not be parse errors")
    require(incomplete["warning_count"] == 3, "missing required controls should be warnings")
    require(
        all(issue["severity"] == "warning" for issue in incomplete["warnings"]),
        "missing-control diagnostics should carry warning severity",
    )
    require(
        all(issue["location"] is None for issue in incomplete["warnings"]),
        "missing-control replay warnings should not claim a CSV field location",
    )

    bad_precision = source.replace(",L1,100\n", ",L1,100.1\n", 1)
    invalid_precision_json = json.loads(
        check_format(bad_precision, "json", expected=2).stdout
    )
    diagnostic = invalid_precision_json["errors"][0]
    require(diagnostic["severity"] == "error", "structured CSV error severity missing")
    require(diagnostic["code"] == "csv_precision", "structured CSV issue code changed")
    require(
        diagnostic["location"] == {"line": 2, "column": 10, "field": "value"},
        f"structured CSV location missing: {diagnostic['location']}",
    )
    invalid_precision = check_format(bad_precision, "text", expected=2)
    require("Input preflight: invalid" in invalid_precision.stdout, "invalid precision passed preflight")
    require("line 2, field 'value' (column 10)" in invalid_precision.stdout, "CSV location was missing")

    bad_sequence = source.replace("sample-2,2,", "sample-2,1,")
    invalid_track = json.loads(
        check_format(bad_sequence, "json", expected=2).stdout
    )
    require(invalid_track["valid"] is False, "non-increasing sequence passed preflight")
    require(
        any(issue["code"] == "non_increasing_sequence" for issue in invalid_track["errors"]),
        f"track sequence diagnostic was missing: {invalid_track['errors']}",
    )
    require(
        invalid_track["errors"][0]["location"] is None,
        "track-integrity issue should not claim a CSV field position",
    )

    unknown_level = source.replace(",L1,100\n", ",LX,100\n", 1)
    unknown = json.loads(check_format(unknown_level, "json", expected=2).stdout)
    require(
        unknown["errors"][0]["code"] == "unknown_control_level",
        "unknown CSV control level code changed",
    )
    require(
        unknown["errors"][0]["location"]
        == {"line": 2, "column": 9, "field": "control_level_id"},
        "unknown control level location missing",
    )

    qc_signal_only = source.replace(",L1,100\n", ",L1,1000\n", 1)
    signal_report = json.loads(check_format(qc_signal_only, "json").stdout)
    require(signal_report["valid"] is True, "QC rule signals must not invalidate file structure")


def verify_observation_coverage() -> None:
    print("Verify missing observation coverage")
    source = (ROOT / "examples" / "synthetic-iqc.csv").read_text(encoding="utf-8")
    missing_l2 = "\n".join(
        line.rsplit(",", 1)[0] + "," if ",L2," in line else line
        for line in source.splitlines()
    ) + "\n"
    program = str(ROOT / "examples" / "demo-program.json")
    with tempfile.NamedTemporaryFile(
        mode="w", encoding="utf-8", suffix=".csv", delete=False
    ) as csv_file:
        csv_file.write(missing_l2)
        csv_path = Path(csv_file.name)
    try:
        base_args = [
            "moon",
            "run",
            "--target",
            "native",
            "cmd/demo",
            "--",
            "--input",
            str(csv_path),
            "--program",
            program,
        ]
        report = json.loads(command(base_args + ["--format", "json"]).stdout)
        counts = report["summary"]["control_observation_counts"]
        require(counts == {
            "expected": 6,
            "observed": 3,
            "missing": 3,
            "precision_mismatch": 0,
            "required_missing": 3,
        }, f"missing L2 observations were not summarized correctly: {counts}")
        coverage = {
            row["control_level_id"]: row
            for row in report["summary"]["control_observation_coverage"]
        }
        require(coverage["L1"]["missing_runs"] == 0, "present L1 controls marked missing")
        require(coverage["L2"]["missing_runs"] == 3, "missing L2 count changed")
        html = command(base_args + ["--format", "html"]).stdout
        require("href=\"#run-0\">Open first missing run</a>" in html, "missing-control navigation missing")
        with tempfile.TemporaryDirectory(prefix="clinical lab qc coverage ") as bundle_root:
            bundle_dir = Path(bundle_root) / "review"
            command(base_args + ["--bundle", str(bundle_dir)])
            manifest = json.loads((bundle_dir / "manifest.json").read_text(encoding="utf-8"))
            require(
                manifest["counts"]["missing_control_observations"] == 3
                and manifest["counts"]["required_missing_control_observations"] == 3,
                "bundle manifest omitted missing-observation counts",
            )
    finally:
        csv_path.unlink(missing_ok=True)


def verify_downstream_consumer() -> None:
    print("Verify separate downstream module consumer")
    output = command(
        ["moon", "run", "--target", "native", "."],
        cwd=ROOT / "examples" / "downstream-consumer",
    ).stdout
    require(
        "Downstream consumer smoke passed" in output,
        "separate downstream consumer did not run through the public API",
    )


def verify_report_file_output() -> None:
    print("Verify report file output")
    with tempfile.TemporaryDirectory(prefix="clinical lab qc ") as directory:
        for output_format in ("html", "json"):
            output_path = Path(directory) / f"demo report.{output_format}"
            output_path.write_text("stale content", encoding="utf-8")
            args = [
                "moon",
                "run",
                "--target",
                "native",
                "cmd/demo",
                "--",
                "--scenario",
                "gradual-drift",
                "--format",
                output_format,
            ]
            written = command(args + ["--output", str(output_path)])
            saved = output_path.read_text(encoding="utf-8")
            direct = command(args).stdout
            require(
                written.stdout.strip() == f"Report written to '{output_path}'",
                f"{output_format}: output confirmation missing",
            )
            require(saved != "stale content", f"{output_format}: existing file was not overwritten")
            require(direct.startswith(saved), f"{output_format}: file and stdout reports disagree")

        missing_parent = Path(directory) / "missing" / "report.html"
        failed_write = command(
            [
                "moon",
                "run",
                "--target",
                "native",
                "cmd/demo",
                "--",
                "--scenario",
                "stable",
                "--format",
                "html",
                "--output",
                str(missing_parent),
            ],
            expected=2,
        )
        require("unable to write report file" in failed_write.stdout, "write failure message was unclear")


def verify_review_bundle() -> None:
    print("Verify deterministic offline review bundle")
    expected_names = {"report.html", "audit.json", "audit.csv", "chart.svg", "manifest.json"}
    with tempfile.TemporaryDirectory(prefix="clinical lab qc bundle ") as directory:
        base = Path(directory)
        first_dir = base / "first bundle"
        second_dir = base / "second bundle"
        first_dir.mkdir()
        (first_dir / "report.html").write_text("stale", encoding="utf-8")
        for output_dir in (first_dir, second_dir):
            written = command(
                [
                    "moon",
                    "run",
                    "--target",
                    "native",
                    "cmd/demo",
                    "--",
                    "--scenario",
                    "gradual-drift",
                    "--bundle",
                    str(output_dir),
                ]
            )
            require(
                written.stdout.strip() == f"Review bundle written to '{output_dir}'",
                "bundle completion message missing",
            )
        first_files = {path.name: path.read_bytes() for path in first_dir.iterdir()}
        second_files = {path.name: path.read_bytes() for path in second_dir.iterdir()}
        require(set(first_files) == expected_names, f"unexpected bundle files: {set(first_files)}")
        require(first_files == second_files, "bundle artifacts changed between identical replays")
        manifest = json.loads(first_files["manifest.json"].decode("utf-8"))
        require(manifest["schema_version"] == 1, "manifest version changed")
        require(manifest["report_schema_version"] == 1, "report schema version missing")
        require(manifest["counts"]["input_runs"] == 12, "manifest run count changed")
        require(manifest["counts"]["epoch_count"] == 1, "manifest epoch count changed")
        require(
            manifest["counts"]["status_counts"]
            == {"InControl": 6, "Warning": 0, "RequiresReview": 6, "Incomplete": 0},
            "manifest status summary changed",
        )
        require("timestamp" not in manifest, "manifest should not add a volatile timestamp")
        html_report = first_files["report.html"].decode("utf-8")
        require("https://" not in html_report.lower(), "bundle HTML must remain offline")
        invalid_options = command(
            [
                "moon",
                "run",
                "--target",
                "native",
                "cmd/demo",
                "--",
                "--bundle",
                str(base / "invalid bundle"),
                "--format",
                "json",
            ],
            expected=2,
        )
        require(
            "--bundle exports every supported format" in invalid_options.stdout,
            "conflicting bundle format options were accepted",
        )


def verify_batch_replay() -> None:
    print("Verify ordered multi-file replay and source provenance")
    inputs = [
        ROOT / "examples" / "daily-qc-2026-09-28.csv",
        ROOT / "examples" / "daily-qc-2026-09-29.csv",
        ROOT / "examples" / "daily-qc-2026-09-30.csv",
    ]
    prefix = [
        "moon",
        "run",
        "--target",
        "native",
        "cmd/demo",
        "--",
        "--program",
        "examples/demo-program.json",
    ]
    input_args = [argument for path in inputs for argument in ("--input", str(path))]
    outputs: dict[str, str] = {}
    for output_format in ("markdown", "json", "csv", "svg", "html"):
        args = prefix + input_args + ["--format", output_format]
        first = command(args).stdout
        second = command(args).stdout
        require(first == second, f"batch/{output_format} changed between identical replays")
        outputs[output_format] = first

    report = json.loads(outputs["json"])
    require(report["schema_version"] == 2, "batch JSON schema version changed")
    runs = report["runs"]
    require(len(runs) == 30, f"batch should contain 30 runs, got {len(runs)}")
    require([run["sequence"] for run in runs] == list(range(1, 31)), "input file order was not preserved")
    require(
        [runs[index]["source_label"] for index in (0, 10, 20)]
        == [path.name for path in inputs],
        "run source labels were not carried into JSON",
    )
    summary = report["summary"]
    require(summary["track_issue_count"] == 0, "synthetic daily batch has track issues")
    require(summary["input_runs"] == 30, "batch summary run count changed")
    require(len(summary["epoch_run_counts"]) == 2, "lot transition should create two epochs")
    require(
        summary["control_observation_counts"]
        == {"expected": 60, "observed": 60, "missing": 0, "precision_mismatch": 0, "required_missing": 0},
        "daily sample should contain two controls for each run",
    )
    require(
        any(hit["rule"] == "10x" and hit["count"] > 0 for hit in summary["rule_hit_counts"]),
        "10x evidence did not cross the first-to-second file boundary",
    )
    for artifact in outputs.values():
        require(str(ROOT) not in artifact, "batch report leaked a local absolute path")
    require("daily-qc-2026-09-29.csv" in outputs["markdown"], "Markdown omitted source provenance")
    require("source_label" in outputs["csv"], "batch CSV omitted source column")
    csv_records = list(csv.DictReader(io.StringIO(outputs["csv"])))
    source_by_run = {
        record["run_id"]: record["source_label"]
        for record in csv_records
        if record["record_type"] == "assessment"
    }
    require(
        source_by_run["qc-001"] == inputs[0].name
        and source_by_run["qc-011"] == inputs[1].name
        and source_by_run["qc-021"] == inputs[2].name,
        "batch CSV source column was not associated with the correct runs",
    )
    require("daily-qc-2026-09-30.csv" in outputs["html"], "HTML omitted source provenance")
    require("daily-qc-2026-09-28.csv" in outputs["svg"], "SVG omitted source metadata")
    ET.fromstring(outputs["svg"])

    preflight = json.loads(command(prefix + input_args + ["--check-input", "--format", "json"]).stdout)
    require(preflight["valid"] is True and preflight["input_runs"] == 30, "batch preflight failed")

    with tempfile.TemporaryDirectory(prefix="clinical lab qc batch ") as directory:
        root = Path(directory)
        first_bundle = root / "first bundle"
        second_bundle = root / "second bundle"
        for bundle in (first_bundle, second_bundle):
            command(prefix + input_args + ["--bundle", str(bundle)])
        first_files = {path.name: path.read_bytes() for path in first_bundle.iterdir()}
        second_files = {path.name: path.read_bytes() for path in second_bundle.iterdir()}
        require(first_files == second_files, "batch review bundle was not deterministic")
        manifest = json.loads(first_files["manifest.json"].decode("utf-8"))
        require(manifest["report_schema_version"] == 2, "batch manifest did not declare schema 2")
        require(manifest["source_labels"] == [path.name for path in inputs], "manifest sources changed")

        invalid_csv = root / "bad input.csv"
        invalid_csv.write_text("not-a-qc-csv\n", encoding="utf-8")
        bad_precision_csv = root / "bad precision.csv"
        bad_precision_csv.write_text(
            "epoch_id,reagent_lot,control_lot,calibration_id,program_version,run_id,sequence,timestamp,control_level_id,value\n"
            "lot-a,R-1,C-1,CAL-1,v1,bad-precision,1,2026-09-30T08:00:00Z,L1,100.1\n",
            encoding="utf-8",
        )
        missing_csv = root / "missing 零.csv"
        failed_batch = command(
            prefix
            + [
                "--input",
                str(invalid_csv),
                "--input",
                str(bad_precision_csv),
                "--input",
                str(missing_csv),
                "--format",
                "json",
            ],
            expected=2,
        )
        require("bad input.csv" in failed_batch.stdout, "parse error omitted source filename")
        require("bad precision.csv" in failed_batch.stdout, "second parse error was not accumulated")
        require("missing 零.csv" in failed_batch.stdout, "read error omitted source filename")
        require(str(root) not in failed_batch.stdout, "batch diagnostic leaked an absolute path")
        require("Users\\" not in failed_batch.stdout, "batch diagnostic leaked a path component")
        require("schema_version" not in failed_batch.stdout, "invalid batch emitted a QC report")

        input_preflight = command(
            prefix
            + [
                "--input",
                str(bad_precision_csv),
                "--input",
                str(invalid_csv),
                "--check-input",
                "--format",
                "json",
            ],
            expected=2,
        )
        preflight_errors = json.loads(input_preflight.stdout)
        require(preflight_errors["error_count"] == 2, "batch preflight did not accumulate parse errors")
        locations = [entry["location"] for entry in preflight_errors["errors"]]
        require(
            any(
                location["source_file"] == bad_precision_csv.name
                and location["line"] == 2
                and location["column"] == 10
                for location in locations
            ),
            "batch preflight omitted source file or CSV coordinates",
        )

        print("Verify generated 200-run batch replay")
        generated_files: list[Path] = []
        header = "epoch_id,reagent_lot,control_lot,calibration_id,program_version,run_id,sequence,timestamp,control_level_id,value"
        for file_index in range(5):
            rows = [header]
            for index in range(40):
                sequence = file_index * 40 + index + 1
                run_id = f"generated-{sequence:03d}"
                timestamp = f"2026-09-30T{sequence // 60:02d}:{sequence % 60:02d}:00Z"
                values = (99 + sequence % 3, 199 + sequence % 3)
                for level, value in zip(("L1", "L2"), values):
                    rows.append(
                        f"lot-scale,R-scale,C-scale,CAL-scale,v1,{run_id},{sequence},{timestamp},{level},{value}"
                    )
            generated = root / f"generated-{file_index + 1}.csv"
            generated.write_text("\n".join(rows) + "\n", encoding="utf-8")
            generated_files.append(generated)
        generated_args = [arg for path in generated_files for arg in ("--input", str(path))]
        generated_command = prefix + generated_args + ["--format", "json"]
        generated_first = command(generated_command).stdout
        generated_second = command(generated_command).stdout
        require(generated_first == generated_second, "generated batch output was not deterministic")
        generated_report = json.loads(generated_first)
        require(generated_report["summary"]["input_runs"] == 200, "generated batch run count changed")
        require(generated_report["summary"]["track_issue_count"] == 0, "generated batch has track issues")

    conflicting = command(prefix + input_args[:2] + ["--scenario", "stable"], expected=2)
    require("choose either --input or --scenario" in conflicting.stdout, "scenario conflict was accepted")


def main() -> int:
    print("Refresh the MoonBit package registry index")
    moon("update")
    version_lines = command(["moon", "version"]).stdout.splitlines()
    require(bool(version_lines), "MoonBit toolchain version was not reported")
    print(f"MoonBit toolchain: {version_lines[0]}")

    print("Run MoonBit checks, build, tests, quickstart, and package")
    moon("check", "--deny-warn", "--target", "all")
    moon("build", "--target", "native", "cmd/demo")
    test_output = moon("test", "--deny-warn", "--target", "all")
    for line in test_output.splitlines():
        if line.startswith("Total tests:"):
            print(line)
    moon("run", "--target", "native", "examples/quickstart")
    verify_downstream_consumer()

    for scenario in ("stable", "step-shift", "gradual-drift"):
        verify_scenario(scenario)

    print("Verify custom program input and CLI failures")
    validation = moon(
        "run",
        "--target",
        "native",
        "cmd/demo",
        "--",
        "--program",
        "examples/demo-program.json",
        "--check-program",
    )
    require(validation.startswith("valid: "), "custom assay program did not validate")
    custom_report = moon(
        "run",
        "--target",
        "native",
        "cmd/demo",
        "--",
        "--program",
        "examples/demo-program.json",
        "--input",
        "examples/synthetic-iqc.csv",
        "--format",
        "json",
    )
    custom_data = json.loads(custom_report)
    require(custom_data["summary"]["input_runs"] == 3, "custom CSV replay should contain three runs")
    require(custom_data["summary"]["track_issue_count"] == 0, "custom CSV replay has track issues")

    invalid_format = command(
        ["moon", "run", "--target", "native", "cmd/demo", "--", "--format", "yaml"],
        expected=2,
    )
    require("unknown format 'yaml'" in invalid_format.stdout, "invalid format error was not clear")
    with tempfile.NamedTemporaryFile(
        mode="w",
        encoding="utf-8",
        suffix=".csv",
        delete=False,
    ) as invalid_csv:
        invalid_csv.write("not-a-qc-csv\n")
        invalid_csv_path = Path(invalid_csv.name)
    try:
        bad_csv = command(
            [
                "moon",
                "run",
                "--target",
                "native",
                "cmd/demo",
                "--",
                "--input",
                str(invalid_csv_path),
            ],
            expected=2,
        )
        require("QC batch input has 1 error" in bad_csv.stdout, "malformed CSV error was not clear")
    finally:
        invalid_csv_path.unlink(missing_ok=True)

    verify_batch_replay()
    verify_input_preflight()
    verify_observation_coverage()
    verify_report_file_output()
    verify_review_bundle()

    print("Build Moon package archive")
    moon("-C", str(ROOT), "package")
    package_entries = moon("-C", str(ROOT), "package", "--list").splitlines()
    require(
        "moon.work" not in package_entries
        and not any(
            item.replace("\\", "/").startswith("examples/downstream-consumer/")
            for item in package_entries
        ),
        "local workspace consumer fixture leaked into the published module archive",
    )
    print("Acceptance checks passed.")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (AssertionError, RuntimeError, json.JSONDecodeError, ET.ParseError) as error:
        print(f"Acceptance check failed: {error}", file=sys.stderr)
        raise SystemExit(1)
