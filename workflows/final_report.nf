include { REPORT_COLLECTION } from '../subworkflows/report_collection'
include { RELEASE_CHECKS } from '../subworkflows/release_checks'
include { REPORT_RENDERING } from '../subworkflows/report_rendering'

process COLLECT_CAME_RUN_PROVENANCE {
    publishDir { "${params.outdir}/final/provenance" }, mode: 'copy'

    input:
    val results_dir

    output:
    path 'came_run_provenance.tsv', emit: provenance
    path 'came_parameters_snapshot.tsv', emit: parameters

    script:
    """
    cat > came_nextflow_params_snapshot.tsv <<EOF
parameter	value
run_stage	${params.run_stage}
study_profile	${params.study_profile ?: ''}
outdir	${params.outdir}
omics_stub	${params.omics_stub}
omics_types	${params.omics_types}
resume_completed_stages	${params.resume_completed_stages}
phylo_model_types	${params.phylo_model_types}
integration_model_types	${params.integration_model_types}
phenotype_response_scope	${params.phenotype_response_scope}
functional_interpretation_top_n	${params.functional_interpretation_top_n}
EOF
    python3 ${projectDir}/bin/collect_run_provenance.py \\
      --project_dir "${projectDir}" \\
      --results_dir "${results_dir}" \\
      --output_dir . \\
      --params_snapshot came_nextflow_params_snapshot.tsv
    """
}

process MAKE_CAME_REPORT_ASSETS {
    publishDir { "${params.outdir}/final/assets" }, mode: 'copy'

    input:
    val results_dir
    path manifest
    path stage_summary
    path missing_outputs
    path release_checks
    path release_summary

    output:
    path 'stage_completion_summary.tsv', emit: stage_completion
    path 'top_candidates.tsv', emit: top_candidates
    path 'top_enriched_gene_sets.tsv', emit: top_enriched_gene_sets
    path 'warning_summary.tsv', emit: warning_summary
    path 'report_asset_manifest.tsv', emit: asset_manifest

    script:
    """
    python3 ${projectDir}/bin/make_report_assets.py \\
      --results_dir "${results_dir}" \\
      --manifest "${manifest}" \\
      --stage_summary "${stage_summary}" \\
      --missing_outputs "${missing_outputs}" \\
      --release_checks "${release_checks}" \\
      --release_summary "${release_summary}" \\
      --output_dir .
    """
}

process ASSERT_CAME_RELEASE_CHECKS {
    publishDir { "${params.outdir}/final/release_checks" }, mode: 'copy'

    input:
    path release_checks

    output:
    path 'came_release_status.txt', emit: status

    script:
    """
    errors=\$(awk 'BEGIN{FS="\\t"} NR>1 && \$2=="ERROR"{count++} END{print count+0}' "${release_checks}")
    printf 'release_check_errors\\t%s\\n' "\$errors" > came_release_status.txt
    if [ "\$errors" -gt 0 ]; then
      echo "CAME release checks reported \$errors ERROR record(s)." >&2
      exit 1
    fi
    """
}

workflow FINAL_REPORT {
    take:
    study_profile
    results_dir

    main:
    REPORT_COLLECTION(results_dir)
    COLLECT_CAME_RUN_PROVENANCE(results_dir)
    RELEASE_CHECKS(REPORT_COLLECTION.out.manifest, results_dir)
    MAKE_CAME_REPORT_ASSETS(
        results_dir,
        REPORT_COLLECTION.out.manifest,
        REPORT_COLLECTION.out.stage_summary,
        REPORT_COLLECTION.out.missing_outputs,
        RELEASE_CHECKS.out.checks,
        RELEASE_CHECKS.out.summary
    )
    REPORT_RENDERING(
        study_profile,
        results_dir,
        REPORT_COLLECTION.out.manifest,
        REPORT_COLLECTION.out.stage_summary,
        REPORT_COLLECTION.out.missing_outputs,
        RELEASE_CHECKS.out.checks,
        RELEASE_CHECKS.out.summary,
        COLLECT_CAME_RUN_PROVENANCE.out.provenance,
        COLLECT_CAME_RUN_PROVENANCE.out.parameters,
        MAKE_CAME_REPORT_ASSETS.out.asset_manifest,
        MAKE_CAME_REPORT_ASSETS.out.stage_completion,
        MAKE_CAME_REPORT_ASSETS.out.top_candidates,
        MAKE_CAME_REPORT_ASSETS.out.top_enriched_gene_sets,
        MAKE_CAME_REPORT_ASSETS.out.warning_summary
    )
    ASSERT_CAME_RELEASE_CHECKS(RELEASE_CHECKS.out.checks)

    emit:
    manifest = REPORT_COLLECTION.out.manifest
    stage_summary = REPORT_COLLECTION.out.stage_summary
    missing_outputs = REPORT_COLLECTION.out.missing_outputs
    provenance = COLLECT_CAME_RUN_PROVENANCE.out.provenance
    parameters = COLLECT_CAME_RUN_PROVENANCE.out.parameters
    asset_manifest = MAKE_CAME_REPORT_ASSETS.out.asset_manifest
    asset_stage_completion = MAKE_CAME_REPORT_ASSETS.out.stage_completion
    asset_top_candidates = MAKE_CAME_REPORT_ASSETS.out.top_candidates
    asset_top_enriched_gene_sets = MAKE_CAME_REPORT_ASSETS.out.top_enriched_gene_sets
    asset_warning_summary = MAKE_CAME_REPORT_ASSETS.out.warning_summary
    release_checks = RELEASE_CHECKS.out.checks
    release_summary = RELEASE_CHECKS.out.summary
    report_html = REPORT_RENDERING.out.html
    report_markdown = REPORT_RENDERING.out.markdown
    report_css = REPORT_RENDERING.out.css
    release_status = ASSERT_CAME_RELEASE_CHECKS.out.status
}
