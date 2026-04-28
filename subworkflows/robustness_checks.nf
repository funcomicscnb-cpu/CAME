process RUN_ROBUSTNESS_CHECKS {
    publishDir { "${params.outdir}/advanced_statistics" }, mode: 'copy'

    input:
    path advanced_model_manifest
    val advanced_statistics_stub

    output:
    path 'robustness/robustness_check_results.tsv', emit: results
    path 'robustness/robustness_warnings.tsv', emit: warnings

    script:
    """
    mkdir -p robustness
    Rscript ${projectDir}/bin/run_robustness_checks.R \\
      --manifest "${advanced_model_manifest}" \\
      --advanced_statistics_stub "${advanced_statistics_stub}" \\
      --output_dir robustness
    """
}

workflow ROBUSTNESS_CHECKS {
    take:
    advanced_model_manifest
    advanced_statistics_stub

    main:
    RUN_ROBUSTNESS_CHECKS(advanced_model_manifest, advanced_statistics_stub)

    emit:
    results = RUN_ROBUSTNESS_CHECKS.out.results
    warnings = RUN_ROBUSTNESS_CHECKS.out.warnings
}
