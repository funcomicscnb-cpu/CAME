process PHYLO_MODELS {
    publishDir { "${params.outdir}/phylo" }, mode: 'copy'

    input:
    path hypothesis_model_table
    path study_profile
    val model_types

    output:
    path 'models/model_results.tsv', emit: results
    path 'models/model_diagnostics.tsv', emit: diagnostics
    path 'models/model_residuals.tsv', emit: residuals
    path 'models/model_warnings.tsv', emit: warnings

    script:
    """
    mkdir -p models
    Rscript ${projectDir}/bin/run_phylo_model.R \\
      --input ${hypothesis_model_table} \\
      --study_profile ${study_profile} \\
      --model_types ${model_types} \\
      --pgls_min_species "${params.pgls_min_species ?: 6}" \\
      --output_dir models
    """
}
