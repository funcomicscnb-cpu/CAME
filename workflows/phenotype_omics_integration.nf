include { MOLECULAR_RESPONSE_CLUSTERING } from '../subworkflows/molecular_response_clustering'
include { PHENOTYPE_MOLECULAR_ASSOCIATION } from '../subworkflows/phenotype_molecular_association'
include { PAIRWISE_SPECIES_CONTRAST } from '../subworkflows/pairwise_species_contrast'

process PREPARE_PHENOTYPE_OMICS_INPUTS {
    publishDir { "${params.outdir}/integration" }, mode: 'copy'

    input:
    path phenotype_index_contrasts
    path component_trait_contrasts
    path differential_expression_orthogroups
    path differential_accessibility_orthogroups
    path differential_gra_activity
    path study_profile
    val phenotype_response_metric
    val molecular_response_metric
    val phenotype_response_scope

    output:
    path 'input/phenotype_response_table.tsv', emit: phenotype_response_table
    path 'input/molecular_response_long.tsv', emit: molecular_response_long
    path 'input/phenotype_omics_model_table.tsv', emit: model_table
    path 'input/phenotype_omics_input_warnings.tsv', emit: warnings

    script:
    """
    mkdir -p input
    python3 ${projectDir}/bin/prepare_phenotype_omics_inputs.py \\
      --phenotype_index_contrasts "${phenotype_index_contrasts}" \\
      --component_trait_contrasts "${component_trait_contrasts}" \\
      --differential_expression_orthogroups "${differential_expression_orthogroups}" \\
      --differential_accessibility_orthogroups "${differential_accessibility_orthogroups}" \\
      --differential_gra_activity "${differential_gra_activity}" \\
      --study_profile "${study_profile}" \\
      --phenotype_response_metric "${phenotype_response_metric}" \\
      --molecular_response_metric "${molecular_response_metric}" \\
      --phenotype_response_scope "${phenotype_response_scope}" \\
      --output_dir input
    """
}

process SUMMARIZE_PHENOTYPE_OMICS_INTEGRATION {
    publishDir { "${params.outdir}/integration" }, mode: 'copy'

    input:
    path phenotype_response_table
    path molecular_response_long
    path model_table
    path input_warnings
    path clusters_expression
    path clusters_accessibility
    path clusters_gra_activity
    path cluster_summary
    path association_expression
    path association_accessibility
    path association_gra
    path association_warnings
    path pairwise_contrasts
    path pairwise_summary

    output:
    path 'summary/phenotype_omics_integration_summary.tsv', emit: summary
    path 'summary/phenotype_omics_outputs_manifest.tsv', emit: manifest

    script:
    """
    mkdir -p summary
    python3 ${projectDir}/bin/summarize_phenotype_omics_integration.py \\
      --phenotype_response_table "${phenotype_response_table}" \\
      --molecular_response_long "${molecular_response_long}" \\
      --model_table "${model_table}" \\
      --input_warnings "${input_warnings}" \\
      --response_clusters_expression "${clusters_expression}" \\
      --response_clusters_accessibility "${clusters_accessibility}" \\
      --response_clusters_gra_activity "${clusters_gra_activity}" \\
      --response_cluster_summary "${cluster_summary}" \\
      --phenotype_expression_associations "${association_expression}" \\
      --phenotype_accessibility_associations "${association_accessibility}" \\
      --phenotype_gra_associations "${association_gra}" \\
      --association_warnings "${association_warnings}" \\
      --pairwise_species_molecular_contrasts "${pairwise_contrasts}" \\
      --pairwise_species_contrast_summary "${pairwise_summary}" \\
      --output_dir summary
    """
}

workflow PHENOTYPE_OMICS_INTEGRATION {
    take:
    phenotype_index_contrasts
    component_trait_contrasts
    differential_expression_orthogroups
    differential_accessibility_orthogroups
    differential_gra_activity
    species_traits
    phylogeny_manifest
    study_profile
    phylogeny_base_dir
    phenotype_response_metric
    molecular_response_metric
    phenotype_response_scope
    model_types
    min_species
    cluster_method
    species_pairs

    main:
    PREPARE_PHENOTYPE_OMICS_INPUTS(
        phenotype_index_contrasts,
        component_trait_contrasts,
        differential_expression_orthogroups,
        differential_accessibility_orthogroups,
        differential_gra_activity,
        study_profile,
        phenotype_response_metric,
        molecular_response_metric,
        phenotype_response_scope
    )
    MOLECULAR_RESPONSE_CLUSTERING(
        PREPARE_PHENOTYPE_OMICS_INPUTS.out.molecular_response_long,
        cluster_method
    )
    PHENOTYPE_MOLECULAR_ASSOCIATION(
        PREPARE_PHENOTYPE_OMICS_INPUTS.out.model_table,
        species_traits,
        phylogeny_manifest,
        phylogeny_base_dir,
        model_types,
        min_species
    )
    PAIRWISE_SPECIES_CONTRAST(
        PREPARE_PHENOTYPE_OMICS_INPUTS.out.phenotype_response_table,
        PREPARE_PHENOTYPE_OMICS_INPUTS.out.molecular_response_long,
        species_pairs,
        phenotype_response_scope
    )
    SUMMARIZE_PHENOTYPE_OMICS_INTEGRATION(
        PREPARE_PHENOTYPE_OMICS_INPUTS.out.phenotype_response_table,
        PREPARE_PHENOTYPE_OMICS_INPUTS.out.molecular_response_long,
        PREPARE_PHENOTYPE_OMICS_INPUTS.out.model_table,
        PREPARE_PHENOTYPE_OMICS_INPUTS.out.warnings,
        MOLECULAR_RESPONSE_CLUSTERING.out.expression,
        MOLECULAR_RESPONSE_CLUSTERING.out.accessibility,
        MOLECULAR_RESPONSE_CLUSTERING.out.gra_activity,
        MOLECULAR_RESPONSE_CLUSTERING.out.summary,
        PHENOTYPE_MOLECULAR_ASSOCIATION.out.expression,
        PHENOTYPE_MOLECULAR_ASSOCIATION.out.accessibility,
        PHENOTYPE_MOLECULAR_ASSOCIATION.out.gra,
        PHENOTYPE_MOLECULAR_ASSOCIATION.out.warnings,
        PAIRWISE_SPECIES_CONTRAST.out.contrasts,
        PAIRWISE_SPECIES_CONTRAST.out.summary
    )

    emit:
    phenotype_response_table = PREPARE_PHENOTYPE_OMICS_INPUTS.out.phenotype_response_table
    molecular_response_long = PREPARE_PHENOTYPE_OMICS_INPUTS.out.molecular_response_long
    model_table = PREPARE_PHENOTYPE_OMICS_INPUTS.out.model_table
    response_clusters_expression = MOLECULAR_RESPONSE_CLUSTERING.out.expression
    response_clusters_accessibility = MOLECULAR_RESPONSE_CLUSTERING.out.accessibility
    response_clusters_gra_activity = MOLECULAR_RESPONSE_CLUSTERING.out.gra_activity
    cluster_summary = MOLECULAR_RESPONSE_CLUSTERING.out.summary
    association_expression = PHENOTYPE_MOLECULAR_ASSOCIATION.out.expression
    association_accessibility = PHENOTYPE_MOLECULAR_ASSOCIATION.out.accessibility
    association_gra = PHENOTYPE_MOLECULAR_ASSOCIATION.out.gra
    association_warnings = PHENOTYPE_MOLECULAR_ASSOCIATION.out.warnings
    pairwise_contrasts = PAIRWISE_SPECIES_CONTRAST.out.contrasts
    pairwise_summary = PAIRWISE_SPECIES_CONTRAST.out.summary
    summary = SUMMARIZE_PHENOTYPE_OMICS_INTEGRATION.out.summary
    manifest = SUMMARIZE_PHENOTYPE_OMICS_INTEGRATION.out.manifest
}
