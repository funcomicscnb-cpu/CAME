#!/usr/bin/env python3
"""CAME-I0: Summarize externally generated CEEG R2/R3 contract artifacts.

Reads CEEG R2 (came_overlay) and R3 (mapping_contract) output directories
and writes compact CAME-side summaries. Does not call CEEG validators.
Does not modify CEEG output directories.

Exit codes:
  0  Success (or no-op when no dirs supplied)
  1  At least one artifact recorded exit_code=1 and --fail-on-error is set
  2  At least one artifact recorded exit_code=2 and --fail-on-error is set
  3  Usage error
"""

from __future__ import annotations

import argparse
import csv
import json
import sys
from datetime import datetime, timezone
from pathlib import Path

HEADERS = {
    "ceeg_contract_summary.tsv": (
        "artifact_type\tartifact_path\tstatus\texit_code"
        "\tvalidator_name\tvalidator_version\trun_id\tmessage"
    ),
    "ceeg_mapping_summary.tsv": (
        "run_id\ttotal_features\tmapped_count\tambiguous_count\tfailed_count\tsource_artifact"
    ),
    "ceeg_unmapped_features.tsv": (
        "unmapped_id\tfeature_id\tfailure_reason\tnotes\tsource_artifact\tinterpretation_note"
    ),
    "ceeg_ambiguous_mappings.tsv": (
        "ambiguous_id\tfeature_id\tcandidate_count\tcandidate_ids\tnotes"
        "\tsource_artifact\tinterpretation_note"
    ),
    "ceeg_compatibility_warnings.tsv": "severity\tsource\tmessage",
    "ceeg_outputs_manifest.tsv": (
        "output_file\tartifact_type\trow_count\tsource_artifact\tgenerated_at"
    ),
}

NOTE_UNMAPPED = "failed mapping is not biological absence"
NOTE_AMBIGUOUS = "ambiguous mapping is not collapsed to one-to-one"


def _parse_args() -> argparse.Namespace:
    ap = argparse.ArgumentParser(
        description="Summarize externally generated CEEG R2/R3 contract artifacts for CAME."
    )
    ap.add_argument("--out-dir", required=True, type=Path,
                    help="Directory to write CAME-side output files.")
    ap.add_argument("--r2-dir", type=Path, default=None,
                    help="Path to an externally generated R2 CAME overlay output directory.")
    ap.add_argument("--r3-dir", type=Path, default=None,
                    help="Path to an externally generated R3 mapping-contract output directory.")
    ap.add_argument("--validation-mode", default="development",
                    choices=["development", "public_release", "benchmark_release"],
                    help="Mirrors the CEEG validation_mode for provenance recording.")
    ap.add_argument("--fail-on-error", action="store_true",
                    help="Exit non-zero when any artifact carries a non-zero CEEG exit_code.")
    ap.add_argument("--created-at", default=None,
                    help="Override the generated_at timestamp (UTC ISO-8601). Useful for deterministic tests.")
    return ap.parse_args()


def _now_utc() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def _write_tsv(path: Path, header: str, rows: list[dict]) -> int:
    cols = header.split("\t")
    lines = [header]
    for row in rows:
        lines.append("\t".join(str(row.get(c, "")) for c in cols))
    path.write_text("\n".join(lines) + "\n")
    return len(rows)


def _read_tsv(path: Path) -> list[dict]:
    with open(path, newline="") as fh:
        reader = csv.DictReader(fh, delimiter="\t")
        return list(reader)


# ---------------------------------------------------------------------------
# R2 parsing
# ---------------------------------------------------------------------------

def _parse_r2(r2_dir: Path, warnings: list[dict]) -> dict:
    """Parse came_overlay output directory into a contract-summary row."""
    manifest_path = r2_dir / "came_report_manifest.json"

    if not manifest_path.exists():
        warnings.append({
            "severity": "error",
            "source": f"r2_dir={r2_dir}",
            "message": "came_report_manifest.json not found in R2 output directory.",
        })
        return {
            "artifact_type": "r2_overlay",
            "artifact_path": str(r2_dir),
            "status": "missing_manifest",
            "exit_code": 2,
            "validator_name": "",
            "validator_version": "",
            "run_id": "",
            "message": "came_report_manifest.json not found",
        }

    try:
        manifest = json.loads(manifest_path.read_text())
    except Exception as exc:
        warnings.append({
            "severity": "error",
            "source": str(manifest_path),
            "message": f"Could not parse came_report_manifest.json: {exc}",
        })
        return {
            "artifact_type": "r2_overlay",
            "artifact_path": str(r2_dir),
            "status": "parse_error",
            "exit_code": 2,
            "validator_name": "",
            "validator_version": "",
            "run_id": "",
            "message": f"parse error: {exc}",
        }

    exit_code_raw = manifest.get("exit_code", "")
    try:
        exit_code = int(exit_code_raw)
    except (TypeError, ValueError):
        exit_code = exit_code_raw
    status = manifest.get("status", "")
    run_id = manifest.get("run_id", "") or ""
    validator_name = manifest.get("validator_name", "") or ""
    validator_version = manifest.get("validator_version", "") or ""

    message_parts = [f"status={status}"]

    compat_path = r2_dir / "compatibility_summary.json"
    if compat_path.exists():
        try:
            compat = json.loads(compat_path.read_text())
            compat_result = compat.get("compatibility_result", "")
            if compat_result:
                message_parts.append(f"compatibility_result={compat_result}")
        except Exception as exc:
            warnings.append({
                "severity": "warning",
                "source": str(compat_path),
                "message": f"Could not parse compatibility_summary.json: {exc}",
            })
    elif exit_code == 2:
        message_parts.append("fatal R2 run; compatibility_summary.json absent")
        warnings.append({
            "severity": "warning",
            "source": str(r2_dir),
            "message": "Fatal R2 run: compatibility_summary.json is absent (expected for exit_code=2).",
        })

    return {
        "artifact_type": "r2_overlay",
        "artifact_path": str(r2_dir),
        "status": status,
        "exit_code": exit_code,
        "validator_name": validator_name,
        "validator_version": validator_version,
        "run_id": run_id,
        "message": "; ".join(message_parts),
    }


# ---------------------------------------------------------------------------
# R3 parsing
# ---------------------------------------------------------------------------

def _parse_r3(
    r3_dir: Path,
    warnings: list[dict],
    mapping_rows: list[dict],
    unmapped_rows: list[dict],
    ambiguous_rows: list[dict],
) -> dict:
    """Parse mapping_contract output directory into a contract-summary row."""
    manifest_path = r3_dir / "mapping_report_manifest.json"

    if not manifest_path.exists():
        warnings.append({
            "severity": "error",
            "source": f"r3_dir={r3_dir}",
            "message": "mapping_report_manifest.json not found in R3 output directory.",
        })
        return {
            "artifact_type": "r3_mapping",
            "artifact_path": str(r3_dir),
            "status": "missing_manifest",
            "exit_code": 2,
            "validator_name": "",
            "validator_version": "",
            "run_id": "",
            "message": "mapping_report_manifest.json not found",
        }

    try:
        manifest = json.loads(manifest_path.read_text())
    except Exception as exc:
        warnings.append({
            "severity": "error",
            "source": str(manifest_path),
            "message": f"Could not parse mapping_report_manifest.json: {exc}",
        })
        return {
            "artifact_type": "r3_mapping",
            "artifact_path": str(r3_dir),
            "status": "parse_error",
            "exit_code": 2,
            "validator_name": "",
            "validator_version": "",
            "run_id": "",
            "message": f"parse error: {exc}",
        }

    exit_code_raw = manifest.get("exit_code", "")
    try:
        exit_code = int(exit_code_raw)
    except (TypeError, ValueError):
        exit_code = exit_code_raw
    status = manifest.get("status", "")
    run_id = manifest.get("run_id", "") or ""
    validator_name = manifest.get("validator_name", "") or ""
    validator_version = manifest.get("validator_version", "") or ""

    # mapping_summary.tsv
    mapping_path = r3_dir / "mapping_summary.tsv"
    if mapping_path.exists():
        try:
            for row in _read_tsv(mapping_path):
                mapping_rows.append({
                    "run_id": row.get("run_id", run_id),
                    "total_features": row.get("total_features", ""),
                    "mapped_count": row.get("mapped_count", ""),
                    "ambiguous_count": row.get("ambiguous_count", ""),
                    "failed_count": row.get("failed_count", ""),
                    "source_artifact": str(r3_dir),
                })
        except Exception as exc:
            warnings.append({
                "severity": "warning",
                "source": str(mapping_path),
                "message": f"Could not parse mapping_summary.tsv: {exc}",
            })
    else:
        warnings.append({
            "severity": "warning",
            "source": str(r3_dir),
            "message": "mapping_summary.tsv not found in R3 output directory.",
        })

    # unmapped_features.tsv
    unmapped_path = r3_dir / "unmapped_features.tsv"
    if unmapped_path.exists():
        try:
            for row in _read_tsv(unmapped_path):
                row["source_artifact"] = str(r3_dir)
                row["interpretation_note"] = NOTE_UNMAPPED
                unmapped_rows.append(row)
        except Exception as exc:
            warnings.append({
                "severity": "warning",
                "source": str(unmapped_path),
                "message": f"Could not parse unmapped_features.tsv: {exc}",
            })
    else:
        warnings.append({
            "severity": "warning",
            "source": str(r3_dir),
            "message": "unmapped_features.tsv not found in R3 output directory.",
        })

    # ambiguous_mappings.tsv
    ambiguous_path = r3_dir / "ambiguous_mappings.tsv"
    if ambiguous_path.exists():
        try:
            for row in _read_tsv(ambiguous_path):
                row["source_artifact"] = str(r3_dir)
                row["interpretation_note"] = NOTE_AMBIGUOUS
                ambiguous_rows.append(row)
        except Exception as exc:
            warnings.append({
                "severity": "warning",
                "source": str(ambiguous_path),
                "message": f"Could not parse ambiguous_mappings.tsv: {exc}",
            })
    else:
        warnings.append({
            "severity": "warning",
            "source": str(r3_dir),
            "message": "ambiguous_mappings.tsv not found in R3 output directory.",
        })

    return {
        "artifact_type": "r3_mapping",
        "artifact_path": str(r3_dir),
        "status": status,
        "exit_code": exit_code,
        "validator_name": validator_name,
        "validator_version": validator_version,
        "run_id": run_id,
        "message": f"mapping_contract_status={status}",
    }


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main() -> None:
    args = _parse_args()

    if not args.r2_dir and not args.r3_dir:
        sys.exit(0)

    args.out_dir.mkdir(parents=True, exist_ok=True)
    created_at = args.created_at or _now_utc()

    contract_rows: list[dict] = []
    mapping_rows: list[dict] = []
    unmapped_rows: list[dict] = []
    ambiguous_rows: list[dict] = []
    warning_rows: list[dict] = []

    max_exit_code = 0

    if args.r2_dir:
        row = _parse_r2(args.r2_dir, warning_rows)
        contract_rows.append(row)
        ec = row.get("exit_code")
        try:
            ec_int = int(ec)
            if ec_int > max_exit_code:
                max_exit_code = ec_int
        except (TypeError, ValueError):
            pass

    if args.r3_dir:
        row = _parse_r3(args.r3_dir, warning_rows, mapping_rows, unmapped_rows, ambiguous_rows)
        contract_rows.append(row)
        ec = row.get("exit_code")
        try:
            ec_int = int(ec)
            if ec_int > max_exit_code:
                max_exit_code = ec_int
        except (TypeError, ValueError):
            pass

    sources: list[str] = []
    if args.r2_dir:
        sources.append(str(args.r2_dir))
    if args.r3_dir:
        sources.append(str(args.r3_dir))
    source_artifact_str = ",".join(sources)

    manifest_rows: list[dict] = []

    def write_and_record(filename: str, rows: list[dict]) -> None:
        header = HEADERS[filename]
        count = _write_tsv(args.out_dir / filename, header, rows)
        manifest_rows.append({
            "output_file": filename,
            "artifact_type": "ceeg_compatibility",
            "row_count": count,
            "source_artifact": source_artifact_str,
            "generated_at": created_at,
        })

    write_and_record("ceeg_contract_summary.tsv", contract_rows)
    write_and_record("ceeg_mapping_summary.tsv", mapping_rows)
    write_and_record("ceeg_unmapped_features.tsv", unmapped_rows)
    write_and_record("ceeg_ambiguous_mappings.tsv", ambiguous_rows)
    write_and_record("ceeg_compatibility_warnings.tsv", warning_rows)

    manifest_header = HEADERS["ceeg_outputs_manifest.tsv"]
    _write_tsv(args.out_dir / "ceeg_outputs_manifest.tsv", manifest_header, manifest_rows)

    if args.fail_on_error and max_exit_code > 0:
        sys.exit(max_exit_code)


if __name__ == "__main__":
    main()
