process RENDER_CAME_FINAL_REPORT {
    publishDir { "${params.outdir}/final/report" }, mode: 'copy'

    input:
    path study_profile
    val results_dir
    path manifest
    path stage_summary
    path missing_outputs
    path release_checks
    path release_summary
    path provenance
    path parameters
    path asset_manifest
    path asset_stage_completion
    path asset_top_candidates
    path asset_top_enriched_gene_sets
    path asset_warning_summary

    output:
    path 'came_final_report.html', emit: html
    path 'came_final_report.md', emit: markdown
    path 'came_report.css', emit: css

    script:
    """
    python3 ${projectDir}/bin/render_final_report.py \\
      --study_profile "${study_profile}" \\
      --results_dir "${results_dir}" \\
      --manifest "${manifest}" \\
      --stage_summary "${stage_summary}" \\
      --missing_outputs "${missing_outputs}" \\
      --release_checks "${release_checks}" \\
      --release_summary "${release_summary}" \\
      --output_dir . \\
      --template_dir "${projectDir}/templates" \\
      --provenance "${provenance}" \\
      --parameters "${parameters}" \\
      --asset_manifest "${asset_manifest}" \\
      --asset_stage_completion "${asset_stage_completion}" \\
      --asset_top_candidates "${asset_top_candidates}" \\
      --asset_top_enriched_gene_sets "${asset_top_enriched_gene_sets}" \\
      --asset_warning_summary "${asset_warning_summary}" \\
      --comparability_mode "${params.comparability_mode ?: 'design_assumed'}"
    """
}

workflow REPORT_RENDERING {
    take:
    study_profile
    results_dir
    manifest
    stage_summary
    missing_outputs
    release_checks
    release_summary
    provenance
    parameters
    asset_manifest
    asset_stage_completion
    asset_top_candidates
    asset_top_enriched_gene_sets
    asset_warning_summary

    main:
    RENDER_CAME_FINAL_REPORT(
        study_profile,
        results_dir,
        manifest,
        stage_summary,
        missing_outputs,
        release_checks,
        release_summary,
        provenance,
        parameters,
        asset_manifest,
        asset_stage_completion,
        asset_top_candidates,
        asset_top_enriched_gene_sets,
        asset_warning_summary
    )

    emit:
    html = RENDER_CAME_FINAL_REPORT.out.html
    markdown = RENDER_CAME_FINAL_REPORT.out.markdown
    css = RENDER_CAME_FINAL_REPORT.out.css
}
