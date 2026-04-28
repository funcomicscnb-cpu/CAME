process RUN_PAIRWISE_SPECIES_CONTRASTS {
    publishDir { "${params.outdir}/integration" }, mode: 'copy'

    input:
    path phenotype_response_table
    path molecular_response_long
    val species_pairs
    val phenotype_response_scope

    output:
    path 'pairwise/pairwise_species_molecular_contrasts.tsv', emit: contrasts
    path 'pairwise/pairwise_species_contrast_summary.tsv', emit: summary

    script:
    """
    mkdir -p pairwise
    python3 ${projectDir}/bin/run_pairwise_species_contrasts.py \\
      --phenotype_response_table "${phenotype_response_table}" \\
      --molecular_response_long "${molecular_response_long}" \\
      --species_pairs "${species_pairs}" \\
      --phenotype_response_scope "${phenotype_response_scope}" \\
      --output_dir pairwise
    """
}

workflow PAIRWISE_SPECIES_CONTRAST {
    take:
    phenotype_response_table
    molecular_response_long
    species_pairs
    phenotype_response_scope

    main:
    RUN_PAIRWISE_SPECIES_CONTRASTS(
        phenotype_response_table,
        molecular_response_long,
        species_pairs,
        phenotype_response_scope
    )

    emit:
    contrasts = RUN_PAIRWISE_SPECIES_CONTRASTS.out.contrasts
    summary = RUN_PAIRWISE_SPECIES_CONTRASTS.out.summary
}
