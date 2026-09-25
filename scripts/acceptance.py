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


def command(args: list[str], *, expected: int = 0) -> subprocess.CompletedProcess[str]:
    result = subprocess.run(
        args,
        cwd=ROOT,
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
    require(actual_rules == expected_rules, f"{name}: unexpected rule counts {actual_rules}")
    require(summary["total_rule_hits"] == sum(expected_nonzero.values()), f"{name}: unexpected hit total")

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

    bad_precision = source.replace(",L1,100\n", ",L1,100.1\n", 1)
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

    qc_signal_only = source.replace(",L1,100\n", ",L1,1000\n", 1)
    signal_report = json.loads(check_format(qc_signal_only, "json").stdout)
    require(signal_report["valid"] is True, "QC rule signals must not invalidate file structure")


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


def main() -> int:
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
        require("CSV input has 1 issue" in bad_csv.stdout, "malformed CSV error was not clear")
    finally:
        invalid_csv_path.unlink(missing_ok=True)

    verify_input_preflight()
    verify_report_file_output()

    print("Build Moon package archive")
    moon("package")
    print("Acceptance checks passed.")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (AssertionError, RuntimeError, json.JSONDecodeError, ET.ParseError) as error:
        print(f"Acceptance check failed: {error}", file=sys.stderr)
        raise SystemExit(1)
