process RUN_PHENOTYPE_MOLECULAR_ASSOCIATIONS {
    publishDir { "${params.outdir}/integration" }, mode: 'copy'

    input:
    path model_table
    path species_traits
    path phylogeny_manifest
    val phylogeny_base_dir
    val model_types
    val min_species

    output:
    path 'associations/phenotype_expression_associations.tsv', emit: expression
    path 'associations/phenotype_accessibility_associations.tsv', emit: accessibility
    path 'associations/phenotype_gra_associations.tsv', emit: gra
    path 'associations/phenotype_omics_association_warnings.tsv', emit: warnings

    script:
    """
    mkdir -p associations
    Rscript ${projectDir}/bin/run_phenotype_omics_associations.R \\
      --model_table "${model_table}" \\
      --species_traits "${species_traits}" \\
      --phylogeny_manifest "${phylogeny_manifest}" \\
      --phylogeny_base_dir "${phylogeny_base_dir}" \\
      --model_types "${model_types}" \\
      --min_species "${min_species}" \\
      --output_dir associations
    """
}

workflow PHENOTYPE_MOLECULAR_ASSOCIATION {
    take:
    model_table
    species_traits
    phylogeny_manifest
    phylogeny_base_dir
    model_types
    min_species

    main:
    RUN_PHENOTYPE_MOLECULAR_ASSOCIATIONS(
        model_table,
        species_traits,
        phylogeny_manifest,
        phylogeny_base_dir,
        model_types,
        min_species
    )

    emit:
    expression = RUN_PHENOTYPE_MOLECULAR_ASSOCIATIONS.out.expression
    accessibility = RUN_PHENOTYPE_MOLECULAR_ASSOCIATIONS.out.accessibility
    gra = RUN_PHENOTYPE_MOLECULAR_ASSOCIATIONS.out.gra
    warnings = RUN_PHENOTYPE_MOLECULAR_ASSOCIATIONS.out.warnings
}
