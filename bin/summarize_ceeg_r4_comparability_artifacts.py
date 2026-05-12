#!/usr/bin/env python3
"""CAME-I3: Summarize externally generated CEEG R4 comparability evidence artifacts.

Reads a CEEG R4 (comparability_contract) output directory and writes compact
CAME-side summaries. Does not call CEEG validators. Does not modify the CEEG
output directory. Does not infer biological comparability, conservation,
equivalence, or absence from R4 evidence state. R4 evidence-state status is
reported as evidence state, not as a biological verdict.

Exit codes:
  0  Success (or no-op when --r4-dir is not supplied)
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


SUMMARY_COLUMNS = [
    "artifact_type",
    "artifact_path",
    "validator_name",
    "validator_version",
    "validation_mode",
    "status",
    "exit_code",
    "created_at",
    "model_id",
    "context_id",
    "comparison_count",
    "comparison_id",
    "left_system_id",
    "right_system_id",
    "entity_scope",
    "comparability_status",
    "status_basis",
    "supporting_evidence_count",
    "weakening_evidence_count",
    "mixed_evidence_count",
    "unresolved_evidence_count",
    "ambiguity_count",
    "unknown_count",
    "unknown_unmappable_count",
    "absent_count",
    "limitations_count",
    "primary_limitation",
    "message",
]

LIMITATIONS_COLUMNS = [
    "comparison_id",
    "context_id",
    "limitation_id",
    "limitation_type",
    "severity",
    "affected_scope",
    "description",
    "recommended_interpretation",
]

EVIDENCE_OUTPUT_COLUMNS = [
    "evidence_id",
    "comparison_id",
    "context_id",
    "evidence_type",
    "evidence_class",
    "confidence",
    "notes",
    "source_artifact",
    "interpretation_note",
]

OUTPUTS_MANIFEST_COLUMNS = [
    "output_file",
    "artifact_type",
    "row_count",
    "source_artifact",
    "generated_at",
]

EVIDENCE_INTERPRETATION_NOTE = (
    "R4 evidence state is not biological comparability validation."
)

EVIDENCE_COUNT_KEYS = [
    "supporting_evidence_count",
    "weakening_evidence_count",
    "mixed_evidence_count",
    "unresolved_evidence_count",
    "ambiguity_count",
    "unknown_count",
    "unknown_unmappable_count",
    "absent_count",
]


def _parse_args() -> argparse.Namespace:
    ap = argparse.ArgumentParser(
        description=(
            "Summarize externally generated CEEG R4 comparability evidence "
            "artifacts for CAME (CAME-I3, read-only consumption)."
        )
    )
    ap.add_argument(
        "--out-dir",
        required=True,
        type=Path,
        help="Directory to write CAME-side R4 output files.",
    )
    ap.add_argument(
        "--r4-dir",
        type=Path,
        default=None,
        help="Path to an externally generated R4 comparability output directory.",
    )
    ap.add_argument(
        "--validation-mode",
        default="development",
        choices=["development", "public_release", "benchmark_release"],
        help="Mirrors the CEEG validation_mode for provenance recording.",
    )
    ap.add_argument(
        "--fail-on-error",
        action="store_true",
        help=(
            "Exit non-zero when the R4 manifest reports a non-zero exit_code "
            "(applied after artifacts are written)."
        ),
    )
    ap.add_argument(
        "--created-at",
        default=None,
        help=(
            "Override the generated_at timestamp (UTC ISO-8601). Useful for "
            "deterministic tests and reproducible fixtures."
        ),
    )
    return ap.parse_args()


def _now_utc() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def _safe_str(value: object) -> str:
    if value is None:
        return ""
    return str(value)


def _safe_int(value: object) -> int:
    if value is None or value == "":
        return 0
    try:
        return int(value)
    except (TypeError, ValueError):
        return 0


def _write_tsv(path: Path, columns: list[str], rows: list[dict]) -> int:
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, "w", newline="") as fh:
        fh.write("\t".join(columns) + "\n")
        for row in rows:
            fh.write("\t".join(_safe_str(row.get(c, "")) for c in columns) + "\n")
    return len(rows)


def _read_tsv(path: Path) -> tuple[list[str], list[dict]]:
    with open(path, newline="") as fh:
        reader = csv.DictReader(fh, delimiter="\t")
        fields = reader.fieldnames or []
        rows = [dict(row) for row in reader]
    return fields, rows


def _emit_header_only_outputs(out_dir: Path, generated_at: str, r4_dir: Path | None) -> None:
    summary_path = out_dir / "ceeg_r4_comparability_summary.tsv"
    limitations_path = out_dir / "ceeg_r4_comparability_limitations.tsv"
    evidence_path = out_dir / "ceeg_r4_comparability_evidence.tsv"
    manifest_path = out_dir / "ceeg_r4_outputs_manifest.tsv"
    _write_tsv(summary_path, SUMMARY_COLUMNS, [])
    _write_tsv(limitations_path, LIMITATIONS_COLUMNS, [])
    _write_tsv(evidence_path, EVIDENCE_OUTPUT_COLUMNS, [])
    source = _safe_str(r4_dir) if r4_dir is not None else ""
    _write_tsv(
        manifest_path,
        OUTPUTS_MANIFEST_COLUMNS,
        [
            {
                "output_file": "ceeg_r4_comparability_summary.tsv",
                "artifact_type": "r4_comparability_summary",
                "row_count": 0,
                "source_artifact": source,
                "generated_at": generated_at,
            },
            {
                "output_file": "ceeg_r4_comparability_limitations.tsv",
                "artifact_type": "r4_comparability_limitations",
                "row_count": 0,
                "source_artifact": source,
                "generated_at": generated_at,
            },
            {
                "output_file": "ceeg_r4_comparability_evidence.tsv",
                "artifact_type": "r4_comparability_evidence",
                "row_count": 0,
                "source_artifact": source,
                "generated_at": generated_at,
            },
        ],
    )


def _build_diagnostic_row(
    r4_dir: Path,
    manifest: dict,
    limitations_count: int,
    message: str,
) -> dict:
    """CAME-side diagnostic row for upstream R4 contract_error / fatal cases.

    Emitted when the manifest reports a non-zero exit_code (or status
    contract_error) and the upstream comparability_summary.tsv has no usable
    data rows (either header-only or absent in the F0e exit-2 shape). The row
    is a CAME-side derivation, not a mutation of the upstream artifact.
    """
    row = {col: "" for col in SUMMARY_COLUMNS}
    row.update(
        {
            "artifact_type": "r4_comparability_report",
            "artifact_path": str(r4_dir),
            "validator_name": _safe_str(manifest.get("validator_name")),
            "validator_version": _safe_str(manifest.get("validator_version")),
            "validation_mode": _safe_str(manifest.get("validation_mode")),
            "status": "contract_error",
            "exit_code": _safe_int(manifest.get("exit_code")),
            "created_at": _safe_str(manifest.get("created_at")),
            "model_id": _safe_str(manifest.get("model_id")),
            "context_id": _safe_str(manifest.get("context_id")),
            "comparison_count": _safe_int(manifest.get("comparison_count")),
            "comparability_status": "contract_error",
            "status_basis": "upstream_contract_error",
            "limitations_count": limitations_count,
            "primary_limitation": (
                "upstream_contract_error" if limitations_count > 0 else "not_applicable"
            ),
            "message": message,
        }
    )
    for key in EVIDENCE_COUNT_KEYS:
        row[key] = 0
    return row


def _build_missing_manifest_row(r4_dir: Path) -> dict:
    row = {col: "" for col in SUMMARY_COLUMNS}
    row.update(
        {
            "artifact_type": "r4_comparability_report",
            "artifact_path": str(r4_dir),
            "status": "missing_manifest",
            "exit_code": 2,
            "comparability_status": "contract_error",
            "status_basis": "missing_manifest",
            "limitations_count": 0,
            "primary_limitation": "not_applicable",
            "message": "comparability_report_manifest.json not found in R4 output directory.",
        }
    )
    for key in EVIDENCE_COUNT_KEYS:
        row[key] = 0
    return row


def _build_parse_error_row(r4_dir: Path, exc: Exception) -> dict:
    row = {col: "" for col in SUMMARY_COLUMNS}
    row.update(
        {
            "artifact_type": "r4_comparability_report",
            "artifact_path": str(r4_dir),
            "status": "parse_error",
            "exit_code": 2,
            "comparability_status": "contract_error",
            "status_basis": "parse_error",
            "limitations_count": 0,
            "primary_limitation": "not_applicable",
            "message": f"Could not parse comparability_report_manifest.json: {exc}",
        }
    )
    for key in EVIDENCE_COUNT_KEYS:
        row[key] = 0
    return row


def _summary_row_for_comparison(
    r4_dir: Path,
    manifest: dict,
    comparison: dict,
    limitations_for_comparison: int,
    primary_limitation: str,
) -> dict:
    row = {col: "" for col in SUMMARY_COLUMNS}
    row.update(
        {
            "artifact_type": "r4_comparability_report",
            "artifact_path": str(r4_dir),
            "validator_name": _safe_str(manifest.get("validator_name")),
            "validator_version": _safe_str(manifest.get("validator_version")),
            "validation_mode": _safe_str(manifest.get("validation_mode")),
            "status": _safe_str(manifest.get("status")),
            "exit_code": _safe_int(manifest.get("exit_code")),
            "created_at": _safe_str(manifest.get("created_at")),
            "model_id": _safe_str(comparison.get("model_id") or manifest.get("model_id")),
            "context_id": _safe_str(
                comparison.get("context_id") or manifest.get("context_id")
            ),
            "comparison_count": _safe_int(manifest.get("comparison_count")),
            "comparison_id": _safe_str(comparison.get("comparison_id")),
            "left_system_id": _safe_str(comparison.get("left_system_id")),
            "right_system_id": _safe_str(comparison.get("right_system_id")),
            "entity_scope": _safe_str(comparison.get("entity_scope")),
            "comparability_status": _safe_str(comparison.get("comparability_status")),
            "status_basis": _safe_str(comparison.get("status_basis")),
            "limitations_count": _safe_int(
                comparison.get("limitations_count") or limitations_for_comparison
            ),
            "primary_limitation": _safe_str(
                comparison.get("primary_limitation") or primary_limitation
            ),
            "message": (
                f"status={_safe_str(manifest.get('status'))}; "
                f"comparability_status={_safe_str(comparison.get('comparability_status'))}"
            ),
        }
    )
    for key in EVIDENCE_COUNT_KEYS:
        row[key] = _safe_int(comparison.get(key))
    return row


def _annotate_evidence_rows(
    upstream_rows: list[dict],
    r4_dir: Path,
) -> list[dict]:
    """Pass-through copy of upstream R4 evidence rows under the unified CAME
    EVIDENCE_OUTPUT_COLUMNS schema, annotated with source_artifact and an
    interpretation_note. Upstream columns not in the schema are dropped on
    purpose so the CAME-side evidence TSV has a stable shape."""
    rows = []
    for row in upstream_rows:
        new_row = {c: _safe_str(row.get(c, "")) for c in EVIDENCE_OUTPUT_COLUMNS}
        if not new_row.get("source_artifact"):
            new_row["source_artifact"] = str(r4_dir / "comparability_evidence.tsv")
        new_row["interpretation_note"] = EVIDENCE_INTERPRETATION_NOTE
        rows.append(new_row)
    return rows


def _primary_limitation_for(comparison_id: str, limitations_rows: list[dict]) -> str:
    severity_order = {"blocking": 0, "high": 1, "medium": 2, "low": 3, "": 4}
    relevant = [r for r in limitations_rows if _safe_str(r.get("comparison_id")) == comparison_id]
    if not relevant:
        return ""
    relevant.sort(
        key=lambda r: (
            severity_order.get(_safe_str(r.get("severity")).lower(), 5),
            _safe_str(r.get("limitation_type")),
        )
    )
    return _safe_str(relevant[0].get("limitation_type"))


def main() -> int:
    args = _parse_args()
    out_dir: Path = args.out_dir
    out_dir.mkdir(parents=True, exist_ok=True)

    generated_at = args.created_at or _now_utc()

    if args.r4_dir is None:
        _emit_header_only_outputs(out_dir, generated_at, None)
        return 0

    r4_dir: Path = args.r4_dir
    manifest_path = r4_dir / "comparability_report_manifest.json"
    summary_in_path = r4_dir / "comparability_summary.tsv"
    evidence_in_path = r4_dir / "comparability_evidence.tsv"
    limitations_in_path = r4_dir / "comparability_limitations.tsv"

    summary_out = out_dir / "ceeg_r4_comparability_summary.tsv"
    limitations_out = out_dir / "ceeg_r4_comparability_limitations.tsv"
    evidence_out = out_dir / "ceeg_r4_comparability_evidence.tsv"
    manifest_out = out_dir / "ceeg_r4_outputs_manifest.tsv"

    # Limitations are read first so the diagnostic-row builder can count them.
    limitations_rows: list[dict] = []
    if limitations_in_path.is_file():
        _, limitations_rows = _read_tsv(limitations_in_path)

    # Evidence pass-through copy (header-only when upstream absent).
    if evidence_in_path.is_file():
        _, evidence_rows = _read_tsv(evidence_in_path)
        annotated_evidence = _annotate_evidence_rows(evidence_rows, r4_dir)
        _write_tsv(evidence_out, EVIDENCE_OUTPUT_COLUMNS, annotated_evidence)
        evidence_row_count = len(annotated_evidence)
    else:
        _write_tsv(evidence_out, EVIDENCE_OUTPUT_COLUMNS, [])
        evidence_row_count = 0

    # CAME-side limitations are a verbatim pass-through (subset of columns).
    limitations_out_rows = []
    for row in limitations_rows:
        limitations_out_rows.append(
            {c: _safe_str(row.get(c, "")) for c in LIMITATIONS_COLUMNS}
        )
    _write_tsv(limitations_out, LIMITATIONS_COLUMNS, limitations_out_rows)

    summary_rows: list[dict] = []
    manifest_exit_code = 0

    if not manifest_path.is_file():
        summary_rows.append(_build_missing_manifest_row(r4_dir))
        manifest_exit_code = 2
    else:
        manifest: object | None
        try:
            manifest = json.loads(manifest_path.read_text())
        except Exception as exc:
            summary_rows.append(_build_parse_error_row(r4_dir, exc))
            manifest_exit_code = 2
            manifest = None
        else:
            if not isinstance(manifest, dict):
                # JSON parsed but the top-level value is not an object (e.g.
                # bare `null`, a list, or a string). Treat as a parse error so
                # CHECK and the renderer see a diagnostic row instead of
                # silently emitting a header-only summary.
                summary_rows.append(
                    _build_parse_error_row(
                        r4_dir,
                        TypeError(
                            f"comparability_report_manifest.json top-level value is "
                            f"{type(manifest).__name__!s}, expected object"
                        ),
                    )
                )
                manifest_exit_code = 2
                manifest = None
        if manifest is not None:
            manifest_exit_code = _safe_int(manifest.get("exit_code"))
            manifest_status = _safe_str(manifest.get("status"))

            upstream_summary_rows: list[dict] = []
            if summary_in_path.is_file():
                _, upstream_summary_rows = _read_tsv(summary_in_path)

            usable_summary_rows = [
                r for r in upstream_summary_rows if _safe_str(r.get("comparison_id"))
            ]

            is_error_manifest = (
                manifest_status == "contract_error" or manifest_exit_code > 0
            )

            if usable_summary_rows:
                for comp in usable_summary_rows:
                    comparison_id = _safe_str(comp.get("comparison_id"))
                    primary = _primary_limitation_for(comparison_id, limitations_rows)
                    summary_rows.append(
                        _summary_row_for_comparison(
                            r4_dir,
                            manifest,
                            comp,
                            sum(
                                1
                                for lim in limitations_rows
                                if _safe_str(lim.get("comparison_id")) == comparison_id
                            ),
                            primary,
                        )
                    )
            elif is_error_manifest:
                # Refinement 2: emit a CAME diagnostic row so CHECK + renderer
                # can see the contract_error even though upstream summary is
                # empty or absent (F0e exit-2 shape).
                limitations_count = len(limitations_rows)
                if summary_in_path.is_file():
                    diagnostic_msg = (
                        "R4 contract_error reported by manifest; upstream "
                        "comparability_summary.tsv has no data rows."
                    )
                else:
                    diagnostic_msg = (
                        "R4 contract_error reported by manifest; upstream "
                        "comparability_summary.tsv absent in fatal-shape artifact."
                    )
                summary_rows.append(
                    _build_diagnostic_row(
                        r4_dir, manifest, limitations_count, diagnostic_msg
                    )
                )
            elif not summary_in_path.is_file():
                # exit 0 manifest but required summary missing → CAME consumption error.
                row = {col: "" for col in SUMMARY_COLUMNS}
                row.update(
                    {
                        "artifact_type": "r4_comparability_report",
                        "artifact_path": str(r4_dir),
                        "validator_name": _safe_str(manifest.get("validator_name")),
                        "validator_version": _safe_str(manifest.get("validator_version")),
                        "validation_mode": _safe_str(manifest.get("validation_mode")),
                        "status": "missing_summary",
                        "exit_code": 2,
                        "created_at": _safe_str(manifest.get("created_at")),
                        "model_id": _safe_str(manifest.get("model_id")),
                        "context_id": _safe_str(manifest.get("context_id")),
                        "comparison_count": _safe_int(manifest.get("comparison_count")),
                        "comparability_status": "contract_error",
                        "status_basis": "missing_summary",
                        "limitations_count": len(limitations_rows),
                        "primary_limitation": "not_applicable",
                        "message": (
                            "R4 manifest reports exit_code=0 but "
                            "comparability_summary.tsv is missing from the R4 output directory."
                        ),
                    }
                )
                for key in EVIDENCE_COUNT_KEYS:
                    row[key] = 0
                summary_rows.append(row)
                manifest_exit_code = 2
            else:
                # exit 0 manifest, summary present but no usable rows.
                row = {col: "" for col in SUMMARY_COLUMNS}
                row.update(
                    {
                        "artifact_type": "r4_comparability_report",
                        "artifact_path": str(r4_dir),
                        "validator_name": _safe_str(manifest.get("validator_name")),
                        "validator_version": _safe_str(manifest.get("validator_version")),
                        "validation_mode": _safe_str(manifest.get("validation_mode")),
                        "status": _safe_str(manifest.get("status")),
                        "exit_code": _safe_int(manifest.get("exit_code")),
                        "created_at": _safe_str(manifest.get("created_at")),
                        "model_id": _safe_str(manifest.get("model_id")),
                        "context_id": _safe_str(manifest.get("context_id")),
                        "comparison_count": _safe_int(manifest.get("comparison_count")),
                        "comparability_status": "no_comparisons",
                        "status_basis": "empty_summary",
                        "limitations_count": len(limitations_rows),
                        "primary_limitation": "not_applicable",
                        "message": (
                            "R4 manifest reports success but "
                            "comparability_summary.tsv contains no comparison rows."
                        ),
                    }
                )
                for key in EVIDENCE_COUNT_KEYS:
                    row[key] = 0
                summary_rows.append(row)

    _write_tsv(summary_out, SUMMARY_COLUMNS, summary_rows)

    # outputs_manifest reflects what CAME actually wrote.
    _write_tsv(
        manifest_out,
        OUTPUTS_MANIFEST_COLUMNS,
        [
            {
                "output_file": "ceeg_r4_comparability_summary.tsv",
                "artifact_type": "r4_comparability_summary",
                "row_count": len(summary_rows),
                "source_artifact": str(r4_dir),
                "generated_at": generated_at,
            },
            {
                "output_file": "ceeg_r4_comparability_limitations.tsv",
                "artifact_type": "r4_comparability_limitations",
                "row_count": len(limitations_out_rows),
                "source_artifact": str(r4_dir),
                "generated_at": generated_at,
            },
            {
                "output_file": "ceeg_r4_comparability_evidence.tsv",
                "artifact_type": "r4_comparability_evidence",
                "row_count": evidence_row_count,
                "source_artifact": str(r4_dir),
                "generated_at": generated_at,
            },
        ],
    )

    if args.fail_on_error and manifest_exit_code > 0:
        return min(int(manifest_exit_code), 2)
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except SystemExit:
        raise
    except Exception as exc:  # pragma: no cover - defensive
        sys.stderr.write(f"summarize_ceeg_r4_comparability_artifacts: {exc}\n")
        sys.exit(3)
