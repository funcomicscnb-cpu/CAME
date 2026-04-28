include { MODEL_COMPARISON } from '../subworkflows/model_comparison'
include { ROBUSTNESS_CHECKS } from '../subworkflows/robustness_checks'
include { MULTIVARIATE_MODELS } from '../subworkflows/multivariate_models'

process PREPARE_ADVANCED_MODEL_INPUTS {
    publishDir { "${params.outdir}/advanced_statistics" }, mode: 'copy'

    input:
    path advanced_model_config
    val results_dir
    val species_traits
    val phylogeny_manifest
    val phenotype_index_contrasts
    val component_trait_contrasts
    val hypothesis_model_table
    val hypothesis_model_results
    val phenotype_omics_model_table

    output:
    path 'input/advanced_model_manifest.tsv', emit: manifest
    path 'input/advanced_model_warnings.tsv', emit: warnings

    script:
    """
    mkdir -p input
    python3 ${projectDir}/bin/prepare_advanced_model_inputs.py \\
      --config "${advanced_model_config}" \\
      --outdir "${results_dir}" \\
      --species_traits "${species_traits}" \\
      --phylogeny_manifest "${phylogeny_manifest}" \\
      --phenotype_index_contrasts "${phenotype_index_contrasts}" \\
      --component_trait_contrasts "${component_trait_contrasts}" \\
      --hypothesis_model_table "${hypothesis_model_table}" \\
      --hypothesis_model_results "${hypothesis_model_results}" \\
      --phenotype_omics_model_table "${phenotype_omics_model_table}" \\
      --output_dir input
    """
}

process SUMMARIZE_ADVANCED_STATISTICS {
    publishDir { "${params.outdir}/advanced_statistics" }, mode: 'copy'

    input:
    path advanced_model_manifest
    path advanced_model_warnings
    path model_comparison_results
    path model_comparison_warnings
    path robustness_check_results
    path robustness_warnings

    output:
    path 'summary/advanced_statistics_summary.tsv', emit: summary
    path 'summary/advanced_statistics_outputs_manifest.tsv', emit: manifest

    script:
    """
    mkdir -p summary
    python3 ${projectDir}/bin/summarize_advanced_statistics.py \\
      --advanced_model_manifest "${advanced_model_manifest}" \\
      --advanced_model_warnings "${advanced_model_warnings}" \\
      --model_comparison_results "${model_comparison_results}" \\
      --model_comparison_warnings "${model_comparison_warnings}" \\
      --robustness_check_results "${robustness_check_results}" \\
      --robustness_warnings "${robustness_warnings}" \\
      --output_dir summary
    """
}

workflow ADVANCED_STATISTICS {
    take:
    advanced_model_config
    results_dir
    species_traits
    phylogeny_manifest
    phenotype_index_contrasts
    component_trait_contrasts
    hypothesis_model_table
    hypothesis_model_results
    phenotype_omics_model_table
    advanced_statistics_stub

    main:
    PREPARE_ADVANCED_MODEL_INPUTS(
        advanced_model_config,
        results_dir,
        species_traits,
        phylogeny_manifest,
        phenotype_index_contrasts,
        component_trait_contrasts,
        hypothesis_model_table,
        hypothesis_model_results,
        phenotype_omics_model_table
    )
    MULTIVARIATE_MODELS(PREPARE_ADVANCED_MODEL_INPUTS.out.manifest)
    MODEL_COMPARISON(PREPARE_ADVANCED_MODEL_INPUTS.out.manifest, advanced_statistics_stub)
    ROBUSTNESS_CHECKS(PREPARE_ADVANCED_MODEL_INPUTS.out.manifest, advanced_statistics_stub)
    SUMMARIZE_ADVANCED_STATISTICS(
        PREPARE_ADVANCED_MODEL_INPUTS.out.manifest,
        PREPARE_ADVANCED_MODEL_INPUTS.out.warnings,
        MODEL_COMPARISON.out.results,
        MODEL_COMPARISON.out.warnings,
        ROBUSTNESS_CHECKS.out.results,
        ROBUSTNESS_CHECKS.out.warnings
    )

    emit:
    input_manifest = PREPARE_ADVANCED_MODEL_INPUTS.out.manifest
    input_warnings = PREPARE_ADVANCED_MODEL_INPUTS.out.warnings
    model_results = MODEL_COMPARISON.out.results
    model_warnings = MODEL_COMPARISON.out.warnings
    robustness_results = ROBUSTNESS_CHECKS.out.results
    robustness_warnings = ROBUSTNESS_CHECKS.out.warnings
    summary = SUMMARIZE_ADVANCED_STATISTICS.out.summary
    manifest = SUMMARIZE_ADVANCED_STATISTICS.out.manifest
}
