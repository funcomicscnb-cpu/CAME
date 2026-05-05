#!/usr/bin/env python3
"""Collect CAME run outputs into a compact final-report manifest."""

import argparse
import csv
import os
import sys
from datetime import datetime, timezone
from pathlib import Path


MANIFEST_FIELDS = ["stage", "output_type", "relative_path", "size_bytes", "modified_time_utc", "status"]
SUMMARY_FIELDS = ["stage", "expected_count", "present_count", "missing_count", "status"]
MISSING_FIELDS = ["severity", "stage", "output_type", "expected_path", "message"]

STAGE_ORDER = [
    "stage_01_metadata_validation",
    "stage_02_study_profile_validation",
    "stage_03_phenotype_response",
    "stage_04_phylogenetic_hypothesis",
    "stage_05_bulk_omics",
    "stage_06_differential_omics",
    "stage_07_orthology_projection",
    "stage_08_gra_analysis",
    "stage_09_phenotype_omics_integration",
    "stage_10_candidate_prioritization",
    "stage_11_functional_interpretation",
]

PREFIX_CLASSIFIERS = [
    ("validation/study_profile", "stage_02_study_profile_validation", "validation"),
    ("validation/", "stage_01_metadata_validation", "validation"),
    ("phenotype/", "stage_03_phenotype_response", "phenotype"),
    ("phylo/", "stage_04_phylogenetic_hypothesis", "phylogenetic_model"),
    ("hypotheses/", "stage_04_phylogenetic_hypothesis", "phylogenetic_model"),
    ("omics/", "stage_05_bulk_omics", "bulk_omics"),
    ("rnaseq/", "stage_05_bulk_omics", "bulk_omics"),
    ("atacseq/", "stage_05_bulk_omics", "bulk_omics"),
    ("differential_omics/", "stage_06_differential_omics", "differential_omics"),
    ("orthology/", "stage_07_orthology_projection", "orthology"),
    ("gra/", "stage_08_gra_analysis", "gra"),
    ("integration/", "stage_09_phenotype_omics_integration", "integration"),
    ("candidates/", "stage_10_candidate_prioritization", "candidates"),
    ("interpretation/", "stage_11_functional_interpretation", "interpretation"),
    ("logs/", "logs", "logs"),
]

EXPECTED_OUTPUTS = [
    ("stage_01_metadata_validation", "validation", "validation/metadata_validation_report.tsv"),
    ("stage_02_study_profile_validation", "validation", "validation/study_profile_validation_report.tsv"),
    ("stage_03_phenotype_response", "phenotype", "phenotype/qc/normalization_summary.tsv"),
    ("stage_03_phenotype_response", "phenotype", "phenotype/qc/phenotype_qc_metrics.tsv"),
    ("stage_03_phenotype_response", "phenotype", "phenotype/index/phenotype_index_by_group.tsv"),
    ("stage_03_phenotype_response", "phenotype", "phenotype/index/phenotype_indexes_by_group.tsv"),
    ("stage_03_phenotype_response", "phenotype", "phenotype/contrasts/phenotype_index_contrasts.tsv"),
    ("stage_03_phenotype_response", "phenotype", "phenotype/contrasts/phenotype_index_contrasts_long.tsv"),
    ("stage_03_phenotype_response", "phenotype", "phenotype/summary/phenotype_processing_manifest.tsv"),
    ("stage_04_phylogenetic_hypothesis", "phylogenetic_model", "phylo/input/phenotype_model_table.tsv"),
    ("stage_04_phylogenetic_hypothesis", "phylogenetic_model", "phylo/models/model_results.tsv"),
    ("stage_04_phylogenetic_hypothesis", "phylogenetic_model", "hypotheses/hypothesis_model_results.tsv"),
    ("stage_05_bulk_omics", "bulk_omics", "omics/summary/omics_run_summary.tsv"),
    ("stage_05_bulk_omics", "bulk_omics", "omics/summary/omics_outputs_manifest.tsv"),
    ("stage_05_bulk_omics", "bulk_omics", "rnaseq/summary/rnaseq_summary.tsv"),
    ("stage_05_bulk_omics", "bulk_omics", "atacseq/summary/atacseq_summary.tsv"),
    ("stage_06_differential_omics", "differential_omics", "differential_omics/summary/differential_omics_summary.tsv"),
    ("stage_06_differential_omics", "differential_omics", "differential_omics/summary/differential_outputs_manifest.tsv"),
    ("stage_07_orthology_projection", "orthology", "orthology/summary/orthology_projection_summary.tsv"),
    ("stage_07_orthology_projection", "orthology", "orthology/summary/orthology_outputs_manifest.tsv"),
    ("stage_07_orthology_projection", "orthology", "orthology/feature_to_orthogroup_map.tsv"),
    ("stage_08_gra_analysis", "gra", "gra/summary/gra_analysis_summary.tsv"),
    ("stage_08_gra_analysis", "gra", "gra/summary/gra_outputs_manifest.tsv"),
    ("stage_08_gra_analysis", "gra", "gra/tables/gene_regulatory_architectures.tsv"),
    ("stage_08_gra_analysis", "gra", "gra/tables/gra_re_membership.tsv"),
    ("stage_09_phenotype_omics_integration", "integration", "integration/summary/phenotype_omics_integration_summary.tsv"),
    ("stage_09_phenotype_omics_integration", "integration", "integration/summary/phenotype_omics_outputs_manifest.tsv"),
    ("stage_10_candidate_prioritization", "candidates", "candidates/summary/candidate_prioritization_summary.tsv"),
    ("stage_10_candidate_prioritization", "candidates", "candidates/summary/candidate_outputs_manifest.tsv"),
    ("stage_10_candidate_prioritization", "candidates", "candidates/ranked/candidate_all_ranked.tsv"),
    ("stage_11_functional_interpretation", "interpretation", "interpretation/summary/functional_interpretation_summary.tsv"),
    ("stage_11_functional_interpretation", "interpretation", "interpretation/summary/functional_interpretation_outputs_manifest.tsv"),
    ("stage_11_functional_interpretation", "interpretation", "interpretation/enrichment/gene_set_enrichment.tsv"),
]

SKIP_DIRS = {
    ".git",
    ".nextflow",
    ".nextflow.log",
    "__pycache__",
    "work",
    "final",
}


def norm_rel(path):
    return path.as_posix().lstrip("./")


def classify(relative_path):
    normalized = norm_rel(Path(relative_path))
    for prefix, stage, output_type in PREFIX_CLASSIFIERS:
        if normalized.startswith(prefix):
            return stage, output_type
    if normalized.endswith(".log") or "/log" in normalized:
        return "logs", "logs"
    return "unclassified", "logs"


def should_skip_dir(path, results_dir):
    rel = path.relative_to(results_dir)
    parts = rel.parts
    return any(part.startswith(".") or part in SKIP_DIRS for part in parts)


def iter_files(results_dir):
    if not results_dir.exists():
        return
    for root, dirs, files in os.walk(results_dir):
        root_path = Path(root)
        dirs[:] = [
            dirname
            for dirname in dirs
            if not dirname.startswith(".") and dirname not in SKIP_DIRS and not should_skip_dir(root_path / dirname, results_dir)
        ]
        for filename in files:
            if filename.startswith("."):
                continue
            path = root_path / filename
            if not path.is_file():
                continue
            if should_skip_dir(path.parent, results_dir):
                continue
            yield path


def write_tsv(path, fields, rows):
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fields, delimiter="\t", extrasaction="ignore", quoting=csv.QUOTE_NONE, escapechar="\\", lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)


def collect(results_dir):
    manifest = []
    present = set()
    for path in sorted(iter_files(results_dir) or []):
        rel_path = norm_rel(path.relative_to(results_dir))
        stage, output_type = classify(rel_path)
        stat = path.stat()
        modified = datetime.fromtimestamp(stat.st_mtime, timezone.utc).replace(microsecond=0).isoformat()
        manifest.append(
            {
                "stage": stage,
                "output_type": output_type,
                "relative_path": rel_path,
                "size_bytes": str(stat.st_size),
                "modified_time_utc": modified,
                "status": "present",
            }
        )
        present.add(rel_path)
    return manifest, present


def summarize_expected(present):
    expected_by_stage = {stage: [] for stage in STAGE_ORDER}
    for stage, output_type, path in EXPECTED_OUTPUTS:
        expected_by_stage.setdefault(stage, []).append((output_type, path))

    summary = []
    missing = []
    for stage in STAGE_ORDER:
        expected = expected_by_stage.get(stage, [])
        present_count = sum(1 for _, path in expected if path in present)
        missing_count = len(expected) - present_count
        if missing_count == 0 and expected:
            status = "COMPLETE"
        elif present_count > 0:
            status = "PARTIAL"
        else:
            status = "MISSING"
        summary.append(
            {
                "stage": stage,
                "expected_count": str(len(expected)),
                "present_count": str(present_count),
                "missing_count": str(missing_count),
                "status": status,
            }
        )
        for output_type, path in expected:
            if path not in present:
                missing.append(
                    {
                        "severity": "WARNING",
                        "stage": stage,
                        "output_type": output_type,
                        "expected_path": path,
                        "message": "Expected upstream output was not found; final reporting will continue.",
                    }
                )
    return summary, missing


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--results_dir", required=True, help="CAME results directory to scan.")
    parser.add_argument("--output_dir", required=True, help="Directory for manifest outputs.")
    args = parser.parse_args(argv)

    results_dir = Path(args.results_dir).resolve()
    output_dir = Path(args.output_dir).resolve()
    manifest, present = collect(results_dir)
    summary, missing = summarize_expected(present)

    write_tsv(output_dir / "came_outputs_manifest.tsv", MANIFEST_FIELDS, manifest)
    write_tsv(output_dir / "came_stage_completion_summary.tsv", SUMMARY_FIELDS, summary)
    write_tsv(output_dir / "came_missing_outputs.tsv", MISSING_FIELDS, missing)

    sys.stderr.write(
        f"CAME final output collection: files={len(manifest)} missing_expected={len(missing)} results_dir={results_dir}\n"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
