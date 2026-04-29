#!/usr/bin/env python3
"""Summarize Stage 26 reference-quality validation outputs."""

from __future__ import annotations

import argparse
import csv
import os
from collections import defaultdict
from pathlib import Path


MISSING_VALUES = {"", "na", "n/a", "nan", "null", "none", "."}
SUMMARY_FIELDS = [
    "reference_id",
    "species",
    "assay_scope",
    "fasta_status",
    "annotation_status",
    "assembly_report_status",
    "seqname_concordance_status",
    "busco_status",
    "masking_status",
    "mappability_status",
    "overall_status",
    "n_errors",
    "n_warnings",
]
MANIFEST_FIELDS = ["artifact", "path", "status", "description"]
STATUS_ORDER = {"OK": 0, "NOT_DECLARED": 1, "SKIPPED": 1, "WARNING": 2, "ERROR": 3}


def norm(value: object) -> str:
    text = str(value if value is not None else "").strip()
    return "" if text.lower() in MISSING_VALUES else text


def infer_delimiter(path: str) -> str:
    ext = os.path.splitext(path)[1].lower()
    if ext == ".tsv":
        return "\t"
    if ext == ".csv":
        return ","
    with open(path, newline="") as handle:
        sample = handle.read(min(65536, os.path.getsize(path)))
    return "\t" if sample.count("\t") > sample.count(",") else ","


def read_table(path: str) -> tuple[list[str], list[dict[str, str]]]:
    if not path or not os.path.exists(path):
        return [], []
    delimiter = infer_delimiter(path)
    with open(path, newline="") as handle:
        reader = csv.DictReader(handle, delimiter=delimiter)
        fields = reader.fieldnames or []
        return fields, [dict(row) for row in reader]


def write_tsv(path: Path, fields: list[str], rows: list[dict[str, str]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fields, delimiter="\t", extrasaction="ignore", lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)


def worst(*statuses: str) -> str:
    result = "OK"
    for status in statuses:
        cleaned = norm(status) or "OK"
        if STATUS_ORDER.get(cleaned, 0) > STATUS_ORDER.get(result, 0):
            result = cleaned
    return result


def severity_to_status(severity: str) -> str:
    return "ERROR" if severity == "ERROR" else ("WARNING" if severity == "WARNING" else "OK")


def statuses_for_asset(rows: list[dict[str, str]], reference_id: str, assets: set[str]) -> str:
    statuses = [norm(row.get("status")) or severity_to_status(norm(row.get("severity"))) for row in rows if norm(row.get("reference_id")) == reference_id and norm(row.get("asset")) in assets]
    return worst(*statuses) if statuses else "NOT_DECLARED"


def statuses_for_field(warnings: list[dict[str, str]], reference_id: str, fields: set[str]) -> str:
    statuses = [severity_to_status(norm(row.get("severity"))) for row in warnings if norm(row.get("reference_id")) == reference_id and norm(row.get("field")) in fields]
    return worst(*statuses) if statuses else "OK"


def summarize(args: argparse.Namespace) -> list[dict[str, str]]:
    _, refs = read_table(args.reference_manifest)
    _, asset_rows = read_table(args.asset_validation)
    _, asset_warnings = read_table(args.asset_warnings)
    _, assembly_warnings = read_table(args.assembly_warnings)
    _, concordance_rows = read_table(args.seqname_concordance)
    _, concordance_warnings = read_table(args.seqname_warnings)
    all_problem_rows = asset_rows + asset_warnings + assembly_warnings + concordance_rows + concordance_warnings
    assay_scope_by_ref: dict[str, set[str]] = defaultdict(set)
    for row in asset_rows:
        ref = norm(row.get("reference_id"))
        assay = norm(row.get("assay"))
        if ref and assay and assay != "all":
            assay_scope_by_ref[ref].add(assay)
    summary: list[dict[str, str]] = []
    for ref in refs:
        reference_id = norm(ref.get("reference_id"))
        species = norm(ref.get("species"))
        fasta_status = statuses_for_asset(asset_rows, reference_id, {"fasta", "fai"})
        annotation_status = statuses_for_asset(asset_rows, reference_id, {"annotation"})
        assembly_status = worst(*(severity_to_status(norm(row.get("severity"))) for row in assembly_warnings if norm(row.get("reference_id")) == reference_id))
        concordance_status = worst(*(norm(row.get("status")) or severity_to_status(norm(row.get("severity"))) for row in concordance_rows if norm(row.get("reference_id")) == reference_id))
        busco_status = statuses_for_asset(asset_rows, reference_id, {"busco_score"})
        masking_status = statuses_for_field(asset_warnings, reference_id, {"repeatmask_bed", "blacklist_bed"})
        mappability_status = statuses_for_field(asset_warnings, reference_id, {"mappability_bed"})
        n_errors = sum(1 for row in all_problem_rows if norm(row.get("reference_id")) == reference_id and norm(row.get("severity")) == "ERROR")
        n_warnings = sum(1 for row in all_problem_rows if norm(row.get("reference_id")) == reference_id and norm(row.get("severity")) == "WARNING")
        overall_status = worst(fasta_status, annotation_status, assembly_status, concordance_status, busco_status, masking_status, mappability_status)
        if n_errors:
            overall_status = "ERROR"
        elif n_warnings and overall_status == "OK":
            overall_status = "WARNING"
        summary.append(
            {
                "reference_id": reference_id,
                "species": species,
                "assay_scope": ",".join(sorted(assay_scope_by_ref.get(reference_id, []))),
                "fasta_status": fasta_status,
                "annotation_status": annotation_status,
                "assembly_report_status": assembly_status,
                "seqname_concordance_status": concordance_status,
                "busco_status": busco_status,
                "masking_status": masking_status,
                "mappability_status": mappability_status,
                "overall_status": overall_status,
                "n_errors": str(n_errors),
                "n_warnings": str(n_warnings),
            }
        )
    return summary


def manifest_rows(outdir: Path) -> list[dict[str, str]]:
    artifacts = {
        "reference_asset_validation": "reference_asset_validation.tsv",
        "reference_asset_warnings": "reference_asset_warnings.tsv",
        "reference_asset_summary": "reference_asset_summary.tsv",
        "seqname_alias_map": "seqname_alias_map.tsv",
        "assembly_report_warnings": "assembly_report_warnings.tsv",
        "seqname_concordance": "seqname_concordance.tsv",
        "seqname_concordance_warnings": "seqname_concordance_warnings.tsv",
        "reference_quality_summary": "reference_quality_summary.tsv",
    }
    rows = []
    for artifact, filename in artifacts.items():
        path = outdir / filename
        rows.append({"artifact": artifact, "path": str(path), "status": "OK" if path.exists() else "MISSING", "description": f"Stage 26 {artifact.replace('_', ' ')}"})
    return rows


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--reference_manifest", required=True)
    parser.add_argument("--outdir", required=True)
    parser.add_argument("--asset_validation", required=True)
    parser.add_argument("--asset_warnings", required=True)
    parser.add_argument("--assembly_warnings", required=True)
    parser.add_argument("--seqname_concordance", required=True)
    parser.add_argument("--seqname_warnings", required=True)
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    outdir = Path(args.outdir)
    summary = summarize(args)
    write_tsv(outdir / "reference_quality_summary.tsv", SUMMARY_FIELDS, summary)
    write_tsv(outdir / "reference_quality_manifest.tsv", MANIFEST_FIELDS, manifest_rows(outdir))
    errors = sum(1 for row in summary if row["overall_status"] == "ERROR")
    warnings = sum(1 for row in summary if row["overall_status"] == "WARNING")
    print(f"CAME reference quality summary: ERROR={errors} WARNING={warnings}")
    return 1 if errors else 0


if __name__ == "__main__":
    raise SystemExit(main())
