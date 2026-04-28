process COLLECT_CANDIDATE_EVIDENCE {
    publishDir { "${params.outdir}/candidates" }, mode: 'copy'

    input:
    val phenotype_index_contrasts
    val hypothesis_model_results
    val differential_expression
    val differential_accessibility
    val differential_gra_activity
    val gene_regulatory_architectures
    val gra_re_membership
    val feature_to_orthogroup_map
    val phenotype_expression_associations
    val phenotype_accessibility_associations
    val phenotype_gra_associations
    val response_clusters_expression
    val response_clusters_accessibility
    val response_clusters_gra_activity
    val pairwise_species_molecular_contrasts

    output:
    path 'evidence/candidate_evidence_long.tsv', emit: evidence
    path 'evidence/candidate_evidence_warnings.tsv', emit: warnings

    script:
    """
    mkdir -p evidence
    python3 ${projectDir}/bin/collect_candidate_evidence.py \\
      --phenotype_index_contrasts "${phenotype_index_contrasts}" \\
      --hypothesis_model_results "${hypothesis_model_results}" \\
      --differential_expression "${differential_expression}" \\
      --differential_accessibility "${differential_accessibility}" \\
      --differential_gra_activity "${differential_gra_activity}" \\
      --gene_regulatory_architectures "${gene_regulatory_architectures}" \\
      --gra_re_membership "${gra_re_membership}" \\
      --feature_to_orthogroup_map "${feature_to_orthogroup_map}" \\
      --phenotype_expression_associations "${phenotype_expression_associations}" \\
      --phenotype_accessibility_associations "${phenotype_accessibility_associations}" \\
      --phenotype_gra_associations "${phenotype_gra_associations}" \\
      --response_clusters_expression "${response_clusters_expression}" \\
      --response_clusters_accessibility "${response_clusters_accessibility}" \\
      --response_clusters_gra_activity "${response_clusters_gra_activity}" \\
      --pairwise_species_molecular_contrasts "${pairwise_species_molecular_contrasts}" \\
      --output_dir evidence
    """
}

workflow EVIDENCE_COLLECTION {
    take:
    phenotype_index_contrasts
    hypothesis_model_results
    differential_expression
    differential_accessibility
    differential_gra_activity
    gene_regulatory_architectures
    gra_re_membership
    feature_to_orthogroup_map
    phenotype_expression_associations
    phenotype_accessibility_associations
    phenotype_gra_associations
    response_clusters_expression
    response_clusters_accessibility
    response_clusters_gra_activity
    pairwise_species_molecular_contrasts

    main:
    COLLECT_CANDIDATE_EVIDENCE(
        phenotype_index_contrasts,
        hypothesis_model_results,
        differential_expression,
        differential_accessibility,
        differential_gra_activity,
        gene_regulatory_architectures,
        gra_re_membership,
        feature_to_orthogroup_map,
        phenotype_expression_associations,
        phenotype_accessibility_associations,
        phenotype_gra_associations,
        response_clusters_expression,
        response_clusters_accessibility,
        response_clusters_gra_activity,
        pairwise_species_molecular_contrasts
    )

    emit:
    evidence = COLLECT_CANDIDATE_EVIDENCE.out.evidence
    warnings = COLLECT_CANDIDATE_EVIDENCE.out.warnings
}
