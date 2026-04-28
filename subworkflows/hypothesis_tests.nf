process HYPOTHESIS_TESTS {
    publishDir { "${params.outdir}/hypotheses" }, mode: 'copy'

    input:
    path hypothesis_model_table
    path study_profile
    val model_types

    output:
    path 'hypothesis_test_summary.tsv', emit: summary
    path 'hypothesis_model_results.tsv', emit: results
    path 'hypothesis_residuals.tsv', emit: residuals
    path 'hypothesis_warnings.tsv', emit: warnings

    script:
    def modelTypesArg = model_types ? "--model_types ${model_types}" : ""
    """
    Rscript ${projectDir}/bin/run_hypothesis_tests.R \\
      --input ${hypothesis_model_table} \\
      --study_profile ${study_profile} \\
      --output_dir . \\
      ${modelTypesArg}
    """
}
