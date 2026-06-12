#!/usr/bin/env python3
"""Run the optional orthology-reference bundle orchestration wrapper.

This script is deliberately an orchestration adapter. It can invoke an external
bundle-generator command and validate the emitted manifest, but it does not
generate chains, nets, HAL alignments, or callable masks itself.
"""

from __future__ import annotations

import argparse
import csv
import shlex
import shutil
import subprocess
import sys
from collections import Counter
from pathlib import Path


BUNDLE_MANIFEST = "orthology_reference_bundle.tsv"
VALIDATION_REPORT = "orthology_reference_bundle_validation.tsv"
WARNINGS_REPORT = "orthology_reference_bundle_warnings.tsv"
SUMMARY_REPORT = "orthology_reference_prepare_summary.tsv"
OUTPUTS_MANIFEST = "orthology_reference_prepare_outputs_manifest.tsv"
COMMAND_LOG = "orthology_reference_prepare_command.log"
EXIT_CODE_FILE = "orthology_reference_prepare_exit_code.txt"

VALIDATION_FIELDS = [
    "severity",
    "bundle_id",
    "source_species",
    "target_species",
    "asset_role",
    "field",
    "status",
    "path",
    "message",
]
SUMMARY_FIELDS = ["metric", "value"]
OUTPUT_FIELDS = ["path", "description"]
BUNDLE_FIELDS = [
    "schema_version",
    "bundle_id",
    "bundle_source",
    "source_species",
    "target_species",
    "source_assembly",
    "target_assembly",
    "asset_role",
    "asset_path",
    "asset_format",
    "orthology_lift_tool",
    "validation_status",
    "tool_versions",
    "params_hash",
    "input_hashes",
    "created_at",
    "created_by",
    "notes",
]


def parse_bool(value: object) -> bool:
    return str(value).strip().lower() in {"1", "true", "t", "yes", "y"}


def write_tsv(path: Path, fields: list[str], rows: list[dict[str, str]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="") as handle:
        writer = csv.DictWriter(
            handle,
            fieldnames=fields,
            delimiter="\t",
            extrasaction="ignore",
            lineterminator="\n",
        )
        writer.writeheader()
        writer.writerows(rows)


def read_tsv(path: Path) -> list[dict[str, str]]:
    if not path.exists():
        return []
    with path.open(newline="") as handle:
        return list(csv.DictReader(handle, delimiter="\t"))


def add_validation(
    rows: list[dict[str, str]],
    severity: str,
    field: str,
    status: str,
    path: str,
    message: str,
) -> None:
    rows.append(
        {
            "severity": severity,
            "bundle_id": "",
            "source_species": "",
            "target_species": "",
            "asset_role": "",
            "field": field,
            "status": status,
            "path": path,
            "message": message,
        }
    )


def write_outputs_manifest(outdir: Path, command_log_written: bool) -> None:
    rows = [
        {"path": "bundle", "description": "Generated or stub orthology reference bundle directory"},
        {"path": f"bundle/{BUNDLE_MANIFEST}", "description": "Bundle manifest produced by the external generator or header-only stub"},
        {"path": VALIDATION_REPORT, "description": "Manifest validation records"},
        {"path": WARNINGS_REPORT, "description": "Manifest validation warnings"},
        {"path": SUMMARY_REPORT, "description": "Stage summary and orchestration status"},
        {"path": EXIT_CODE_FILE, "description": "Runner exit code; nonzero means the wrapper or manifest validation failed"},
    ]
    if command_log_written:
        rows.append({"path": COMMAND_LOG, "description": "External bundle-generator command log"})
    write_tsv(outdir / OUTPUTS_MANIFEST, OUTPUT_FIELDS, rows)


def write_summary(outdir: Path, rows: list[tuple[str, object]]) -> None:
    write_tsv(outdir / SUMMARY_REPORT, SUMMARY_FIELDS, [{"metric": key, "value": str(value)} for key, value in rows])


def write_stub_outputs(outdir: Path) -> int:
    bundle_dir = outdir / "bundle"
    bundle_dir.mkdir(parents=True, exist_ok=True)
    write_tsv(bundle_dir / BUNDLE_MANIFEST, BUNDLE_FIELDS, [])
    validation_rows: list[dict[str, str]] = []
    add_validation(
        validation_rows,
        "INFO",
        "orthology_reference_prepare",
        "STUB",
        str(bundle_dir / BUNDLE_MANIFEST),
        "Stub mode wrote a header-only bundle manifest and did not invoke external synteny or chain/net generation.",
    )
    write_tsv(outdir / VALIDATION_REPORT, VALIDATION_FIELDS, validation_rows)
    write_tsv(outdir / WARNINGS_REPORT, VALIDATION_FIELDS, [])
    write_summary(
        outdir,
        [
            ("mode", "stub"),
            ("status", "STUB"),
            ("bundle_manifest", f"bundle/{BUNDLE_MANIFEST}"),
            ("validation_errors", 0),
            ("validation_warnings", 0),
            ("external_command_exit_code", "na"),
            ("boundary", "CAME orchestration only; no synteny reconstruction implemented"),
        ],
    )
    write_outputs_manifest(outdir, command_log_written=False)
    return 0


def write_error_outputs(
    outdir: Path,
    mode: str,
    field: str,
    status: str,
    message: str,
    exit_code: int,
    command_exit_code: object = "na",
) -> int:
    validation_rows: list[dict[str, str]] = []
    add_validation(validation_rows, "ERROR", field, status, "", message)
    write_tsv(outdir / VALIDATION_REPORT, VALIDATION_FIELDS, validation_rows)
    write_tsv(outdir / WARNINGS_REPORT, VALIDATION_FIELDS, [])
    write_summary(
        outdir,
        [
            ("mode", mode),
            ("status", "ERROR"),
            ("bundle_manifest", f"bundle/{BUNDLE_MANIFEST}"),
            ("validation_errors", 1),
            ("validation_warnings", 0),
            ("external_command_exit_code", command_exit_code),
            ("boundary", "CAME orchestration only; no synteny reconstruction implemented"),
        ],
    )
    write_outputs_manifest(outdir, command_log_written=(outdir / COMMAND_LOG).exists())
    print(f"ERROR\t{field}\t{message}", file=sys.stderr)
    return exit_code


def run_external_command(args: argparse.Namespace, outdir: Path, bundle_dir: Path, log_path: Path) -> tuple[int, bool]:
    command = args.command.strip()
    if not command:
        return write_error_outputs(outdir, "external", "command", "MISSING", "--command is required when --stub false.", 2), True
    if not args.run_dir.strip():
        return write_error_outputs(outdir, "external", "run_dir", "MISSING", "--run-dir is required when --stub false.", 2), True

    run_dir = Path(args.run_dir).resolve()
    if not run_dir.exists():
        return write_error_outputs(outdir, "external", "run_dir", "MISSING", f"Run directory does not exist: {run_dir}", 2), True

    try:
        command_parts = shlex.split(command)
    except ValueError as exc:
        return write_error_outputs(outdir, "external", "command", "ERROR", f"Could not parse command prefix: {exc}", 2), True
    if not command_parts:
        return write_error_outputs(outdir, "external", "command", "MISSING", "--command parsed to an empty command.", 2), True

    full_command = command_parts + ["--run-dir", str(run_dir), "--out-dir", str(bundle_dir)]
    if args.created_at.strip():
        full_command.extend(["--created-at", args.created_at.strip()])

    with log_path.open("w") as log:
        log.write("command_label: orthology_reference_bundle_generator\n")
        log.write(f"run_dir: {run_dir}\n")
        log.write(f"out_dir: {bundle_dir}\n")
        log.write(f"created_at_passed: {'yes' if args.created_at.strip() else 'no'}\n")
        log.write("boundary: CAME orchestration only; synteny reconstruction remains external\n")
        log.write("command: " + shlex.join(full_command) + "\n")
        log.flush()
        try:
            completed = subprocess.run(full_command, stdout=log, stderr=subprocess.STDOUT, text=True)
            return_code = completed.returncode
        except OSError as exc:
            log.write(f"invocation_error: {exc}\n")
            return_code = 127
        log.write(f"exit_code: {return_code}\n")
    return return_code, False


def run_validator(args: argparse.Namespace, outdir: Path, bundle_manifest: Path) -> int:
    validator = Path(__file__).resolve().parent / "validate_orthology_reference_bundle.py"
    command = [
        sys.executable,
        str(validator),
        "--manifest",
        str(bundle_manifest),
        "--outdir",
        str(outdir),
        "--check-paths",
        "true" if parse_bool(args.check_paths) else "false",
    ]
    completed = subprocess.run(command, text=True)
    return completed.returncode


def summarize_validation(outdir: Path, mode: str, command_exit_code: object, validator_exit_code: int) -> int:
    validation_rows = read_tsv(outdir / VALIDATION_REPORT)
    counts = Counter(row.get("severity", "") for row in validation_rows)
    status = "ERROR" if counts.get("ERROR", 0) else "OK"
    write_summary(
        outdir,
        [
            ("mode", mode),
            ("status", status),
            ("bundle_manifest", f"bundle/{BUNDLE_MANIFEST}"),
            ("validation_errors", counts.get("ERROR", 0)),
            ("validation_warnings", counts.get("WARNING", 0)),
            ("validation_info", counts.get("INFO", 0)),
            ("external_command_exit_code", command_exit_code),
            ("validator_exit_code", validator_exit_code),
            ("boundary", "CAME orchestration only; no synteny reconstruction implemented"),
        ],
    )
    write_outputs_manifest(outdir, command_log_written=(outdir / COMMAND_LOG).exists())
    return validator_exit_code


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output-dir", required=True)
    parser.add_argument("--stub", default="true")
    parser.add_argument("--command", default="")
    parser.add_argument("--run-dir", default="")
    parser.add_argument("--created-at", default="")
    parser.add_argument("--check-paths", default="true")
    parser.add_argument("--fail-on-error", default="true")
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    outdir = Path(args.output_dir)
    outdir.mkdir(parents=True, exist_ok=True)
    for name in [
        "bundle",
        VALIDATION_REPORT,
        WARNINGS_REPORT,
        SUMMARY_REPORT,
        OUTPUTS_MANIFEST,
        COMMAND_LOG,
        EXIT_CODE_FILE,
        "seqname_concordance",
        "seqname_reference_manifest.tsv",
    ]:
        child = outdir / name
        if child.is_dir():
            shutil.rmtree(child)
        elif child.exists():
            child.unlink()

    if parse_bool(args.stub):
        result = write_stub_outputs(outdir)
    else:
        bundle_dir = outdir / "bundle"
        bundle_dir.mkdir(parents=True, exist_ok=True)
        log_path = outdir / COMMAND_LOG
        command_exit, preflight_handled = run_external_command(args, outdir, bundle_dir, log_path)
        if command_exit != 0:
            if preflight_handled:
                result = command_exit
            else:
                result = write_error_outputs(
                    outdir,
                    "external",
                    "external_command",
                    "ERROR",
                    f"External orthology reference bundle command exited {command_exit}; inspect {COMMAND_LOG}.",
                    1,
                    command_exit,
                )
        else:
            bundle_manifest = bundle_dir / BUNDLE_MANIFEST
            if not bundle_manifest.exists():
                result = write_error_outputs(
                    outdir,
                    "external",
                    "bundle_manifest",
                    "MISSING",
                    f"External command completed but did not write {bundle_manifest}.",
                    10,
                    command_exit,
                )
            else:
                validator_exit = run_validator(args, outdir, bundle_manifest)
                result = summarize_validation(outdir, "external", command_exit, validator_exit)

    (outdir / EXIT_CODE_FILE).write_text(f"{result}\n")
    return result if parse_bool(args.fail_on_error) else 0


if __name__ == "__main__":
    sys.exit(main())
