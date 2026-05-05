#!/usr/bin/env python3
"""Check required CAME outputs for one stage."""

import argparse
import csv
import sys
from pathlib import Path


FIELDS = [
    "stage",
    "overall_status",
    "expected_count",
    "present_count",
    "missing_count",
    "relative_path",
    "required",
    "present",
    "size_bytes",
    "file_status",
]

EXPECTED_OUTPUTS = {
    "validation": [
        "validation/metadata_validation_report.tsv",
        "validation/study_profile_validation_report.tsv",
    ],
    "phenotype_response": [
        "phenotype/tables/phenotype_long_normalized.tsv",
        "phenotype/qc/normalization_summary.tsv",
        "phenotype/qc/phenotype_design_summary.tsv",
        "phenotype/qc/phenotype_qc_metrics.tsv",
        "phenotype/index/phenotype_index_by_sample.tsv",
        "phenotype/index/phenotype_index_by_group.tsv",
        "phenotype/index/phenotype_indexes_by_sample.tsv",
        "phenotype/index/phenotype_indexes_by_group.tsv",
        "phenotype/contrasts/phenotype_index_contrasts.tsv",
        "phenotype/contrasts/component_trait_contrasts.tsv",
        "phenotype/contrasts/phenotype_index_contrasts_long.tsv",
        "phenotype/summary/phenotype_processing_manifest.tsv",
    ],
    "phylo_hypothesis": [
        "phylo/input/species_traits_wide.tsv",
        "phylo/input/phenotype_model_table.tsv",
        "phylo/input/hypothesis_model_table.tsv",
        "phylo/models/model_results.tsv",
        "hypotheses/hypothesis_test_summary.tsv",
        "hypotheses/hypothesis_model_results.tsv",
    ],
    "bulk_omics": [
        "omics/input/omics_manifest_prepared.tsv",
        "omics/input/rnaseq_manifest.tsv",
        "omics/input/atacseq_manifest.tsv",
        "rnaseq/counts/gene_counts.tsv",
        "rnaseq/summary/rnaseq_summary.tsv",
        "atacseq/counts/re_counts.tsv",
        "atacseq/summary/atacseq_summary.tsv",
        "omics/summary/omics_run_summary.tsv",
        "omics/summary/omics_outputs_manifest.tsv",
    ],
    "differential_omics": [
        "differential_omics/input/differential_input_manifest.tsv",
        "differential_omics/rnaseq/differential_results.tsv",
        "differential_omics/rnaseq/normalized_counts.tsv",
        "differential_omics/atacseq/differential_results.tsv",
        "differential_omics/atacseq/normalized_counts.tsv",
        "differential_omics/summary/differential_omics_summary.tsv",
        "differential_omics/summary/differential_outputs_manifest.tsv",
    ],
    "orthology_projection": [
        "orthology/validation/orthology_validation_report.tsv",
        "orthology/gene_orthogroup_counts.tsv",
        "orthology/re_orthogroup_counts.tsv",
        "orthology/differential_expression_orthogroups.tsv",
        "orthology/differential_accessibility_orthogroups.tsv",
        "orthology/feature_to_orthogroup_map.tsv",
        "orthology/summary/orthology_projection_summary.tsv",
        "orthology/summary/orthology_outputs_manifest.tsv",
    ],
    "gra_analysis": [
        "gra/validation/re_to_gene_link_validation_report.tsv",
        "gra/tables/gene_regulatory_architectures.tsv",
        "gra/tables/gra_re_membership.tsv",
        "gra/activity/gra_activity_matrix.tsv",
        "gra/differential/differential_gra_activity.tsv",
        "gra/differential/normalized_gra_activity.tsv",
        "gra/summary/gra_analysis_summary.tsv",
        "gra/summary/gra_outputs_manifest.tsv",
    ],
    "phenotype_omics_integration": [
        "integration/input/phenotype_response_table.tsv",
        "integration/input/molecular_response_long.tsv",
        "integration/input/phenotype_omics_model_table.tsv",
        "integration/associations/phenotype_expression_associations.tsv",
        "integration/associations/phenotype_accessibility_associations.tsv",
        "integration/associations/phenotype_gra_associations.tsv",
        "integration/clustering/response_cluster_summary.tsv",
        "integration/pairwise/pairwise_species_molecular_contrasts.tsv",
        "integration/summary/phenotype_omics_integration_summary.tsv",
        "integration/summary/phenotype_omics_outputs_manifest.tsv",
    ],
    "candidate_prioritization": [
        "candidates/evidence/candidate_evidence_long.tsv",
        "candidates/evidence/candidate_evidence_scored.tsv",
        "candidates/ranked/candidate_genes_ranked.tsv",
        "candidates/ranked/candidate_res_ranked.tsv",
        "candidates/ranked/candidate_gras_ranked.tsv",
        "candidates/ranked/candidate_all_ranked.tsv",
        "candidates/summary/candidate_prioritization_summary.tsv",
        "candidates/summary/candidate_outputs_manifest.tsv",
    ],
    "functional_interpretation": [
        "interpretation/input/candidate_gene_sets.tsv",
        "interpretation/input/enrichment_background.tsv",
        "interpretation/enrichment/gene_set_enrichment.tsv",
        "interpretation/regulatory_regions/candidate_res.bed",
        "interpretation/regulatory_regions/gra_linked_candidate_res.bed",
        "interpretation/summary/candidate_gene_interpretation.tsv",
        "interpretation/summary/functional_interpretation_summary.tsv",
        "interpretation/summary/functional_interpretation_outputs_manifest.tsv",
    ],
    "final_report": [
        "final/manifest/came_outputs_manifest.tsv",
        "final/manifest/came_stage_completion_summary.tsv",
        "final/manifest/came_missing_outputs.tsv",
        "final/provenance/came_run_provenance.tsv",
        "final/provenance/came_parameters_snapshot.tsv",
        "final/assets/stage_completion_summary.tsv",
        "final/assets/top_candidates.tsv",
        "final/assets/top_enriched_gene_sets.tsv",
        "final/assets/warning_summary.tsv",
        "final/assets/report_asset_manifest.tsv",
        "final/release_checks/came_release_checks.tsv",
        "final/release_checks/came_release_summary.tsv",
        "final/release_checks/came_release_status.txt",
        "final/report/came_final_report.html",
        "final/report/came_final_report.md",
        "final/report/came_report.css",
    ],
}


def parse_bool(value):
    return str(value).strip().lower() in {"1", "true", "yes", "y"}


def stage_status(present_count, expected_count):
    if expected_count and present_count == expected_count:
        return "COMPLETE"
    if present_count:
        return "PARTIAL"
    return "MISSING"


def write_tsv(path, rows):
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=FIELDS, delimiter="\t", quoting=csv.QUOTE_NONE, escapechar="\\", lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)


def check_stage(stage, outdir):
    expected = EXPECTED_OUTPUTS[stage]
    states = []
    present_count = 0
    for rel_path in expected:
        path = outdir / rel_path
        present = path.is_file() and path.stat().st_size > 0
        if present:
            present_count += 1
        states.append((rel_path, path.stat().st_size if path.is_file() else 0, present))
    status = stage_status(present_count, len(expected))
    rows = []
    for rel_path, size, present in states:
        rows.append(
            {
                "stage": stage,
                "overall_status": status,
                "expected_count": str(len(expected)),
                "present_count": str(present_count),
                "missing_count": str(len(expected) - present_count),
                "relative_path": rel_path,
                "required": "true",
                "present": "true" if present else "false",
                "size_bytes": str(size),
                "file_status": "present" if present else "missing",
            }
        )
    return status, rows


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--stage", required=True, choices=sorted(EXPECTED_OUTPUTS))
    parser.add_argument("--outdir", required=True)
    parser.add_argument("--output", default="")
    parser.add_argument("--fail_on_missing", default="false")
    args = parser.parse_args(argv)

    outdir = Path(args.outdir).resolve()
    output = Path(args.output) if args.output else outdir / "all" / "stage_status" / f"{args.stage}_status.tsv"
    status, rows = check_stage(args.stage, outdir)
    write_tsv(output, rows)
    print(f"CAME stage output check: stage={args.stage} status={status} present={rows[0]['present_count']}/{rows[0]['expected_count']}")
    if parse_bool(args.fail_on_missing) and status != "COMPLETE":
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
