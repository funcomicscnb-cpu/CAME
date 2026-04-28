process RUN_MODEL_COMPARISON {
    publishDir { "${params.outdir}/advanced_statistics" }, mode: 'copy'

    input:
    path advanced_model_manifest
    val advanced_statistics_stub

    output:
    path 'models/model_comparison_results.tsv', emit: results
    path 'models/model_comparison_warnings.tsv', emit: warnings

    script:
    """
    mkdir -p models
    Rscript ${projectDir}/bin/run_model_comparison.R \\
      --manifest "${advanced_model_manifest}" \\
      --advanced_statistics_stub "${advanced_statistics_stub}" \\
      --output_dir models
    """
}

workflow MODEL_COMPARISON {
    take:
    advanced_model_manifest
    advanced_statistics_stub

    main:
    RUN_MODEL_COMPARISON(advanced_model_manifest, advanced_statistics_stub)

    emit:
    results = RUN_MODEL_COMPARISON.out.results
    warnings = RUN_MODEL_COMPARISON.out.warnings
}
