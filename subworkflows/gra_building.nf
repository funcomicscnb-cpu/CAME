process VALIDATE_RE_TO_GENE_LINKS {
    publishDir { "${params.outdir}/gra" }, mode: 'copy'

    input:
    path re_to_gene_links
    path gene_orthogroup_counts
    path re_orthogroup_counts
    path feature_to_orthogroup_map

    output:
    path 'validation/re_to_gene_link_validation_report.tsv', emit: report

    script:
    """
    mkdir -p validation
    python3 ${projectDir}/bin/validate_re_to_gene_links.py \\
      --re_to_gene_links "${re_to_gene_links}" \\
      --gene_orthogroup_counts "${gene_orthogroup_counts}" \\
      --re_orthogroup_counts "${re_orthogroup_counts}" \\
      --feature_to_orthogroup_map "${feature_to_orthogroup_map}" \\
      --output validation/re_to_gene_link_validation_report.tsv
    """
}

process BUILD_GRA_TABLE {
    publishDir { "${params.outdir}/gra" }, mode: 'copy'

    input:
    path re_to_gene_links
    path gene_orthogroup_counts
    path re_orthogroup_counts
    path feature_to_orthogroup_map
    path validation_report

    output:
    path 'tables/gene_regulatory_architectures.tsv', emit: architectures
    path 'tables/gra_re_membership.tsv', emit: membership
    path 'tables/gra_link_warnings.tsv', emit: warnings

    script:
    """
    mkdir -p tables
    python3 ${projectDir}/bin/build_gra_table.py \\
      --re_to_gene_links "${re_to_gene_links}" \\
      --gene_orthogroup_counts "${gene_orthogroup_counts}" \\
      --re_orthogroup_counts "${re_orthogroup_counts}" \\
      --feature_to_orthogroup_map "${feature_to_orthogroup_map}" \\
      --validation_report "${validation_report}" \\
      --output_dir tables
    """
}

workflow GRA_BUILDING {
    take:
    re_to_gene_links
    gene_orthogroup_counts
    re_orthogroup_counts
    feature_to_orthogroup_map

    main:
    VALIDATE_RE_TO_GENE_LINKS(
        re_to_gene_links,
        gene_orthogroup_counts,
        re_orthogroup_counts,
        feature_to_orthogroup_map
    )
    BUILD_GRA_TABLE(
        re_to_gene_links,
        gene_orthogroup_counts,
        re_orthogroup_counts,
        feature_to_orthogroup_map,
        VALIDATE_RE_TO_GENE_LINKS.out.report
    )

    emit:
    validation_report = VALIDATE_RE_TO_GENE_LINKS.out.report
    architectures = BUILD_GRA_TABLE.out.architectures
    membership = BUILD_GRA_TABLE.out.membership
    warnings = BUILD_GRA_TABLE.out.warnings
}
