process COLLECT_FINAL_REPORT_OUTPUTS {
    publishDir { "${params.outdir}/final/manifest" }, mode: 'copy'

    input:
    val results_dir

    output:
    path 'came_outputs_manifest.tsv', emit: manifest
    path 'came_stage_completion_summary.tsv', emit: stage_summary
    path 'came_missing_outputs.tsv', emit: missing_outputs

    script:
    """
    python3 ${projectDir}/bin/collect_run_outputs.py \\
      --results_dir "${results_dir}" \\
      --output_dir .
    """
}

workflow REPORT_COLLECTION {
    take:
    results_dir

    main:
    COLLECT_FINAL_REPORT_OUTPUTS(results_dir)

    emit:
    manifest = COLLECT_FINAL_REPORT_OUTPUTS.out.manifest
    stage_summary = COLLECT_FINAL_REPORT_OUTPUTS.out.stage_summary
    missing_outputs = COLLECT_FINAL_REPORT_OUTPUTS.out.missing_outputs
}
