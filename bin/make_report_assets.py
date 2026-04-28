#!/usr/bin/env python3
"""Create compact final-report assets from existing CAME output tables."""

from __future__ import annotations

import argparse
import csv
import os
from pathlib import Path


STAGE_TITLES = {
    "stage_01_metadata_validation": "Metadata Validation",
    "stage_02_study_profile_validation": "Study Profile Validation",
    "stage_03_phenotype_response": "Phenotype Response",
    "stage_04_phylogenetic_hypothesis": "Phylogenetic/Hypothesis Model",
    "stage_05_bulk_omics": "Bulk Omics",
    "stage_06_differential_omics": "Differential Omics",
    "stage_07_orthology_projection": "Orthology Projection",
    "stage_08_gra_analysis": "GRA Analysis",
    "stage_09_phenotype_omics_integration": "Phenotype-Omics Integration",
    "stage_10_candidate_prioritization": "Candidate Prioritization",
    "stage_11_functional_interpretation": "Functional Interpretation",
    "final_report": "Final Report",
}

PREFIX_CLASSIFIERS = [
    ("validation/study_profile", "stage_02_study_profile_validation"),
    ("validation/", "stage_01_metadata_validation"),
    ("phenotype/", "stage_03_phenotype_response"),
    ("phylo/", "stage_04_phylogenetic_hypothesis"),
    ("hypotheses/", "stage_04_phylogenetic_hypothesis"),
    ("omics/", "stage_05_bulk_omics"),
    ("rnaseq/", "stage_05_bulk_omics"),
    ("atacseq/", "stage_05_bulk_omics"),
    ("differential_omics/", "stage_06_differential_omics"),
    ("orthology/", "stage_07_orthology_projection"),
    ("gra/", "stage_08_gra_analysis"),
    ("integration/", "stage_09_phenotype_omics_integration"),
    ("candidates/", "stage_10_candidate_prioritization"),
    ("interpretation/", "stage_11_functional_interpretation"),
    ("final/", "final_report"),
]

STAGE_ASSET_FIELDS = [
    "stage",
    "stage_title",
    "status",
    "source_status",
    "expected_count",
    "present_count",
    "missing_count",
    "warning_count",
    "error_count",
    "message",
]
TOP_CANDIDATE_FIELDS = [
    "rank",
    "candidate_id",
    "candidate_type",
    "total_score",
    "n_evidence_types",
    "top_evidence_type",
    "top_contrast",
    "combined_direction",
    "status",
    "message",
]
TOP_ENRICHMENT_FIELDS = [
    "candidate_set",
    "gene_set_id",
    "gene_set_name",
    "n_overlap",
    "p_value",
    "padj",
    "status",
    "message",
]
WARNING_FIELDS = ["stage", "stage_title", "severity", "source", "count", "message"]
MANIFEST_FIELDS = ["asset_name", "relative_path", "status", "n_rows", "source", "message"]


def norm(value: object) -> str:
    return str(value if value is not None else "").strip()


def infer_delimiter(path: Path) -> str:
    if path.suffix.lower() in {".tsv", ".bed"}:
        return "\t"
    if path.suffix.lower() == ".csv":
        return ","
    with path.open(newline="") as handle:
        sample = handle.read(min(65536, os.path.getsize(path)))
    return "\t" if sample.count("\t") >= sample.count(",") else ","


def read_table(path: Path, limit: int | None = None) -> tuple[list[str], list[dict[str, str]]]:
    if not path.is_file():
        return [], []
    with path.open(newline="") as handle:
        reader = csv.DictReader(handle, delimiter=infer_delimiter(path))
        fields = reader.fieldnames or []
        rows = []
        for row in reader:
            rows.append({field: norm(row.get(field)) for field in fields})
            if limit and len(rows) >= limit:
                break
    return fields, rows


def write_tsv(path: Path, fields: list[str], rows: list[dict[str, str]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fields, delimiter="\t", extrasaction="ignore", quoting=csv.QUOTE_NONE, escapechar="\\", lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)


def classify(relative_path: str) -> str:
    text = relative_path.strip().lstrip("./")
    for prefix, stage in PREFIX_CLASSIFIERS:
        if text.startswith(prefix):
            return stage
    return "unclassified"


def numeric(value: str, default: float) -> float:
    text = norm(value)
    if not text or text.upper() == "NA":
        return default
    try:
        return float(text)
    except ValueError:
        return default


def rel_to_results(path: Path, results_dir: Path) -> str:
    try:
        return path.resolve().relative_to(results_dir.resolve()).as_posix()
    except ValueError:
        return path.name


def warning_counts(results_dir: Path, missing_outputs: Path, release_checks: Path) -> list[dict[str, str]]:
    counts: dict[tuple[str, str, str, str], int] = {}

    def add(stage: str, severity: str, source: str, message: str, count: int = 1) -> None:
        key = (stage or "unclassified", severity or "WARNING", source, message)
        counts[key] = counts.get(key, 0) + count

    _, missing_rows = read_table(missing_outputs)
    for row in missing_rows:
        add(row.get("stage", ""), row.get("severity", "WARNING"), "missing_outputs", row.get("message", "Expected output missing."))

    _, release_rows = read_table(release_checks)
    for row in release_rows:
        status = row.get("status", "")
        if status in {"WARNING", "ERROR"}:
            add("final_report", status, row.get("check_id", "release_check"), row.get("message", "Release check record."))

    for root, dirs, files in os.walk(results_dir):
        root_path = Path(root)
        dirs[:] = [dirname for dirname in dirs if not dirname.startswith(".") and dirname not in {"work", "__pycache__"}]
        for filename in files:
            path = root_path / filename
            rel = rel_to_results(path, results_dir)
            if rel.startswith("final/"):
                continue
            is_warning_table = filename.endswith("_warnings.tsv") or filename.endswith("warnings.tsv")
            is_validation_report = filename.endswith("_validation_report.tsv")
            if not is_warning_table and not is_validation_report:
                continue
            fields, rows = read_table(path)
            if not rows:
                continue
            stage = classify(rel)
            if "severity" in fields:
                for row in rows:
                    severity = row.get("severity", "")
                    if severity in {"WARNING", "ERROR"}:
                        add(stage, severity, rel, row.get("message", "Warning or error row."))
            elif is_warning_table:
                add(stage, "WARNING", rel, "Warning table row(s) present.", len(rows))

    output = []
    for (stage, severity, source, message), count in sorted(counts.items()):
        output.append(
            {
                "stage": stage,
                "stage_title": STAGE_TITLES.get(stage, stage),
                "severity": severity,
                "source": source,
                "count": str(count),
                "message": message,
            }
        )
    return output


def stage_assets(stage_summary: Path, warnings: list[dict[str, str]]) -> list[dict[str, str]]:
    _, rows = read_table(stage_summary)
    warn_by_stage: dict[str, int] = {}
    error_by_stage: dict[str, int] = {}
    for row in warnings:
        stage = row.get("stage", "")
        count = int(row.get("count") or "0")
        if row.get("severity") == "ERROR":
            error_by_stage[stage] = error_by_stage.get(stage, 0) + count
        elif row.get("severity") == "WARNING":
            warn_by_stage[stage] = warn_by_stage.get(stage, 0) + count

    output = []
    for row in rows:
        stage = row.get("stage", "")
        source_status = row.get("status", "")
        warning_count = warn_by_stage.get(stage, 0)
        error_count = error_by_stage.get(stage, 0)
        if error_count:
            status = "failed/error"
            message = "One or more error records were found for this stage."
        elif source_status == "COMPLETE" and warning_count == 0:
            status = "completed"
            message = "Expected compact outputs were present."
        elif source_status == "MISSING":
            status = "missing_optional"
            message = "No expected compact outputs were found; the stage may not have been run for this report."
        else:
            status = "warning"
            message = "Some expected outputs or warning records require review."
        output.append(
            {
                "stage": stage,
                "stage_title": STAGE_TITLES.get(stage, stage),
                "status": status,
                "source_status": source_status,
                "expected_count": row.get("expected_count", "0"),
                "present_count": row.get("present_count", "0"),
                "missing_count": row.get("missing_count", "0"),
                "warning_count": str(warning_count),
                "error_count": str(error_count),
                "message": message,
            }
        )
    return output


def top_candidates(results_dir: Path, limit: int) -> tuple[list[dict[str, str]], str, str]:
    source = results_dir / "candidates" / "ranked" / "candidate_all_ranked.tsv"
    fields, rows = read_table(source)
    if not rows:
        return (
            [
                {
                    "rank": "",
                    "candidate_id": "",
                    "candidate_type": "",
                    "total_score": "",
                    "n_evidence_types": "",
                    "top_evidence_type": "",
                    "top_contrast": "",
                    "combined_direction": "",
                    "status": "missing_optional",
                    "message": "Candidate ranking table was not available; report generation continued.",
                }
            ],
            "missing_optional",
            rel_to_results(source, results_dir),
        )
    if "rank" in fields:
        rows = sorted(rows, key=lambda row: numeric(row.get("rank", ""), 10**12))
    else:
        rows = sorted(rows, key=lambda row: numeric(row.get("total_score", ""), -10**12), reverse=True)
    output = []
    for row in rows[:limit]:
        output.append({field: row.get(field, "") for field in TOP_CANDIDATE_FIELDS})
        output[-1]["status"] = "present"
        output[-1]["message"] = ""
    return output, "present", rel_to_results(source, results_dir)


def top_enriched_gene_sets(results_dir: Path, limit: int) -> tuple[list[dict[str, str]], str, str]:
    source = results_dir / "interpretation" / "enrichment" / "gene_set_enrichment.tsv"
    fields, rows = read_table(source)
    rows = [
        row
        for row in rows
        if (not row.get("status") or row.get("status") == "OK") and norm(row.get("n_overlap")) not in {"", "0"}
    ]
    if not rows:
        return (
            [
                {
                    "candidate_set": "",
                    "gene_set_id": "",
                    "gene_set_name": "",
                    "n_overlap": "",
                    "p_value": "",
                    "padj": "",
                    "status": "missing_optional",
                    "message": "Enrichment table was not available or had no enriched rows; report generation continued.",
                }
            ],
            "missing_optional",
            rel_to_results(source, results_dir),
        )
    rows = sorted(
        rows,
        key=lambda row: (
            numeric(row.get("padj", ""), 1.0),
            numeric(row.get("p_value", ""), 1.0),
            row.get("candidate_set", ""),
            row.get("gene_set_id", ""),
        ),
    )
    output = []
    for row in rows[:limit]:
        output.append({field: row.get(field, "") for field in TOP_ENRICHMENT_FIELDS})
        output[-1]["status"] = "present"
        output[-1]["message"] = ""
    return output, "present", rel_to_results(source, results_dir)


def manifest_row(asset_name: str, relative_path: str, status: str, n_rows: int, source: str, message: str = "") -> dict[str, str]:
    return {
        "asset_name": asset_name,
        "relative_path": relative_path,
        "status": status,
        "n_rows": str(n_rows),
        "source": source,
        "message": message,
    }


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--results_dir", required=True)
    parser.add_argument("--manifest", required=True)
    parser.add_argument("--stage_summary", required=True)
    parser.add_argument("--missing_outputs", required=True)
    parser.add_argument("--release_checks", required=True)
    parser.add_argument("--release_summary", required=True)
    parser.add_argument("--output_dir", required=True)
    parser.add_argument("--top_n", type=int, default=10)
    args = parser.parse_args(argv)

    results_dir = Path(args.results_dir).resolve()
    output_dir = Path(args.output_dir).resolve()
    warning_rows = warning_counts(results_dir, Path(args.missing_outputs), Path(args.release_checks))
    stage_rows = stage_assets(Path(args.stage_summary), warning_rows)
    candidate_rows, candidate_status, candidate_source = top_candidates(results_dir, args.top_n)
    enrichment_rows, enrichment_status, enrichment_source = top_enriched_gene_sets(results_dir, args.top_n)

    stage_path = output_dir / "stage_completion_summary.tsv"
    candidates_path = output_dir / "top_candidates.tsv"
    enrichment_path = output_dir / "top_enriched_gene_sets.tsv"
    warnings_path = output_dir / "warning_summary.tsv"
    manifest_path = output_dir / "report_asset_manifest.tsv"

    write_tsv(stage_path, STAGE_ASSET_FIELDS, stage_rows)
    write_tsv(candidates_path, TOP_CANDIDATE_FIELDS, candidate_rows)
    write_tsv(enrichment_path, TOP_ENRICHMENT_FIELDS, enrichment_rows)
    write_tsv(warnings_path, WARNING_FIELDS, warning_rows)

    manifest_rows = [
        manifest_row("stage_completion", "final/assets/stage_completion_summary.tsv", "present", len(stage_rows), Path(args.stage_summary).name),
        manifest_row("top_candidates", "final/assets/top_candidates.tsv", candidate_status, len(candidate_rows), candidate_source),
        manifest_row("top_enriched_gene_sets", "final/assets/top_enriched_gene_sets.tsv", enrichment_status, len(enrichment_rows), enrichment_source),
        manifest_row("warning_summary", "final/assets/warning_summary.tsv", "present", len(warning_rows), "missing outputs, release checks, warning tables"),
        manifest_row("release_checks", "final/release_checks/came_release_checks.tsv", "present" if Path(args.release_checks).is_file() else "missing_optional", 0, Path(args.release_checks).name),
        manifest_row("output_manifest", "final/manifest/came_outputs_manifest.tsv", "present" if Path(args.manifest).is_file() else "missing_optional", 0, Path(args.manifest).name),
    ]
    write_tsv(manifest_path, MANIFEST_FIELDS, manifest_rows)

    missing_optional = sum(1 for row in manifest_rows if row["status"] == "missing_optional")
    print(f"CAME report assets: assets={len(manifest_rows)} warning_groups={len(warning_rows)} missing_optional={missing_optional}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
