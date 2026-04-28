include { PHYLO_MODELS } from '../subworkflows/phylo_models'
include { HYPOTHESIS_TESTS } from '../subworkflows/hypothesis_tests'

process PREPARE_PHYLO_INPUTS {
    publishDir { "${params.outdir}/phylo" }, mode: 'copy'

    input:
    path species_traits
    path phylogeny_manifest
    path study_profile
    path phenotype_index_by_group
    path phenotype_index_contrasts
    path component_trait_contrasts
    path metadata_report
    path study_profile_report
    val phylogeny_base_dir

    output:
    path 'input/species_traits_wide.tsv', emit: species_traits_wide
    path 'input/phenotype_model_table.tsv', emit: phenotype_model_table
    path 'input/hypothesis_model_table.tsv', emit: hypothesis_model_table

    script:
    """
    test -s ${metadata_report}
    test -s ${study_profile_report}
    mkdir -p input
    python3 ${projectDir}/bin/prepare_phylo_inputs.py \\
      --species_traits ${species_traits} \\
      --phylogeny_manifest ${phylogeny_manifest} \\
      --phylogeny_base_dir ${phylogeny_base_dir} \\
      --study_profile ${study_profile} \\
      --phenotype_index_by_group ${phenotype_index_by_group} \\
      --phenotype_index_contrasts ${phenotype_index_contrasts} \\
      --component_trait_contrasts ${component_trait_contrasts} \\
      --species_traits_wide input/species_traits_wide.tsv \\
      --phenotype_model_table input/phenotype_model_table.tsv \\
      --hypothesis_model_table input/hypothesis_model_table.tsv
    """
}

workflow PHYLO_HYPOTHESIS {
    take:
    species_traits
    phylogeny_manifest
    study_profile
    phenotype_index_by_group
    phenotype_index_contrasts
    component_trait_contrasts
    metadata_report
    study_profile_report
    phylogeny_base_dir
    phylo_model_types
    hypothesis_model_types

    main:
    PREPARE_PHYLO_INPUTS(
        species_traits,
        phylogeny_manifest,
        study_profile,
        phenotype_index_by_group,
        phenotype_index_contrasts,
        component_trait_contrasts,
        metadata_report,
        study_profile_report,
        phylogeny_base_dir
    )
    PHYLO_MODELS(PREPARE_PHYLO_INPUTS.out.hypothesis_model_table, study_profile, phylo_model_types)
    HYPOTHESIS_TESTS(PREPARE_PHYLO_INPUTS.out.hypothesis_model_table, study_profile, hypothesis_model_types)

    emit:
    species_traits_wide = PREPARE_PHYLO_INPUTS.out.species_traits_wide
    phenotype_model_table = PREPARE_PHYLO_INPUTS.out.phenotype_model_table
    hypothesis_model_table = PREPARE_PHYLO_INPUTS.out.hypothesis_model_table
    model_results = PHYLO_MODELS.out.results
    model_diagnostics = PHYLO_MODELS.out.diagnostics
    model_residuals = PHYLO_MODELS.out.residuals
    model_warnings = PHYLO_MODELS.out.warnings
    hypothesis_summary = HYPOTHESIS_TESTS.out.summary
    hypothesis_results = HYPOTHESIS_TESTS.out.results
    hypothesis_residuals = HYPOTHESIS_TESTS.out.residuals
    hypothesis_warnings = HYPOTHESIS_TESTS.out.warnings
}
