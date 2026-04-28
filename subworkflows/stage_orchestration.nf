process PREPARE_ALL_STUB_OMICS_CONTRASTS {
    publishDir { "${params.outdir}/all" }, mode: 'copy'

    input:
    path omics_samplesheet
    path study_profile
    path rnaseq_counts
    path atacseq_counts

    output:
    path 'input/omics_samplesheet_contrast_stub.csv', emit: omics_samplesheet
    path 'input/rnaseq_counts_contrast_stub.tsv', emit: rnaseq_counts
    path 'input/atacseq_counts_contrast_stub.tsv', emit: atacseq_counts
    path 'input/omics_contrast_stub_summary.tsv', emit: summary

    script:
    """
    mkdir -p input
    python3 ${projectDir}/bin/prepare_all_stub_omics_contrasts.py \\
      --omics_samplesheet "${omics_samplesheet}" \\
      --study_profile "${study_profile}" \\
      --rnaseq_counts "${rnaseq_counts}" \\
      --atacseq_counts "${atacseq_counts}" \\
      --output_dir input
    """
}

process CHECK_ALL_STAGE_OUTPUTS {
    publishDir { "${params.outdir}/all" }, mode: 'copy'

    input:
    path release_status
    path release_checks
    path release_summary
    path report_html
    path report_markdown
    val results_dir

    output:
    path 'stage_status', emit: status_dir

    script:
    """
    mkdir -p stage_status
    for stage in validation phenotype_response phylo_hypothesis bulk_omics differential_omics orthology_projection gra_analysis phenotype_omics_integration candidate_prioritization functional_interpretation final_report; do
      python3 ${projectDir}/bin/check_stage_outputs.py \\
        --stage "\${stage}" \\
        --outdir "${results_dir}" \\
        --output "stage_status/\${stage}_status.tsv" \\
        --fail_on_missing false
    done
    """
}

process SUMMARIZE_CAME_ALL_RUN {
    publishDir { "${params.outdir}/all" }, mode: 'copy'

    input:
    path status_dir
    path release_status
    path release_checks
    path release_summary
    path report_html
    path report_markdown
    val results_dir
    val resume_completed_stages

    output:
    path 'summary/came_all_run_summary.tsv', emit: summary
    path 'summary/came_all_outputs_manifest.tsv', emit: manifest

    script:
    """
    mkdir -p summary
    python3 ${projectDir}/bin/summarize_all_run.py \\
      --outdir "${results_dir}" \\
      --stage_status_dir "${status_dir}" \\
      --output_dir summary \\
      --resume_completed_stages "${resume_completed_stages}"
    """
}

process ASSERT_CAME_ALL_RUN_COMPLETE {
    publishDir { "${params.outdir}/all/summary" }, mode: 'copy'

    input:
    path summary

    output:
    path 'came_all_run_status.txt', emit: status

    script:
    """
    python3 - "${summary}" <<'PY'
import csv
import sys

summary_path = sys.argv[1]
overall = ""
with open(summary_path, newline="") as handle:
    for row in csv.DictReader(handle, delimiter="\\t"):
        if row.get("record_type") == "overall" and row.get("key") == "all_run_status":
            overall = row.get("status", "")
            break
with open("came_all_run_status.txt", "w") as handle:
    handle.write(f"all_run_status\\t{overall}\\n")
if overall != "COMPLETE":
    raise SystemExit(f"CAME all-run summary status is {overall or 'missing'}")
PY
    """
}

workflow ALL_STUB_OMICS_CONTRASTS {
    take:
    omics_samplesheet
    study_profile
    rnaseq_counts
    atacseq_counts

    main:
    PREPARE_ALL_STUB_OMICS_CONTRASTS(
        omics_samplesheet,
        study_profile,
        rnaseq_counts,
        atacseq_counts
    )

    emit:
    omics_samplesheet = PREPARE_ALL_STUB_OMICS_CONTRASTS.out.omics_samplesheet
    rnaseq_counts = PREPARE_ALL_STUB_OMICS_CONTRASTS.out.rnaseq_counts
    atacseq_counts = PREPARE_ALL_STUB_OMICS_CONTRASTS.out.atacseq_counts
    summary = PREPARE_ALL_STUB_OMICS_CONTRASTS.out.summary
}

workflow ALL_RUN_STATUS_AND_SUMMARY {
    take:
    release_status
    release_checks
    release_summary
    report_html
    report_markdown
    results_dir
    resume_completed_stages

    main:
    CHECK_ALL_STAGE_OUTPUTS(
        release_status,
        release_checks,
        release_summary,
        report_html,
        report_markdown,
        results_dir
    )
    SUMMARIZE_CAME_ALL_RUN(
        CHECK_ALL_STAGE_OUTPUTS.out.status_dir,
        release_status,
        release_checks,
        release_summary,
        report_html,
        report_markdown,
        results_dir,
        resume_completed_stages
    )
    ASSERT_CAME_ALL_RUN_COMPLETE(SUMMARIZE_CAME_ALL_RUN.out.summary)

    emit:
    status_dir = CHECK_ALL_STAGE_OUTPUTS.out.status_dir
    summary = SUMMARIZE_CAME_ALL_RUN.out.summary
    manifest = SUMMARIZE_CAME_ALL_RUN.out.manifest
    status = ASSERT_CAME_ALL_RUN_COMPLETE.out.status
}
