process VALIDATE_ORTHOLOGY_TABLES {
    publishDir { "${params.outdir}/orthology" }, mode: 'copy'

    input:
    path omics_samplesheet
    path orthologous_genes
    path orthologous_res
    val rnaseq_counts
    val atacseq_counts
    val differential_expression
    val differential_accessibility

    output:
    path 'validation/orthology_validation_report.tsv', emit: report

    script:
    """
    mkdir -p validation
    python3 ${projectDir}/bin/validate_orthology_tables.py \\
      --omics_samplesheet "${omics_samplesheet}" \\
      --orthologous_genes "${orthologous_genes}" \\
      --orthologous_res "${orthologous_res}" \\
      --rnaseq_counts "${rnaseq_counts}" \\
      --atacseq_counts "${atacseq_counts}" \\
      --differential_expression "${differential_expression}" \\
      --differential_accessibility "${differential_accessibility}" \\
      --output validation/orthology_validation_report.tsv
    """
}

process PROJECT_FEATURES_TO_ORTHOGROUPS {
    publishDir { "${params.outdir}/orthology" }, mode: 'copy'

    input:
    path omics_samplesheet
    path orthologous_genes
    path orthologous_res
    val omics_types
    val rnaseq_counts
    val atacseq_counts
    val differential_expression
    val differential_accessibility
    path validation_report

    output:
    path 'gene_orthogroup_counts.tsv', emit: gene_counts
    path 're_orthogroup_counts.tsv', emit: re_counts
    path 'differential_expression_orthogroups.tsv', emit: differential_expression
    path 'differential_accessibility_orthogroups.tsv', emit: differential_accessibility
    path 'feature_to_orthogroup_map.tsv', emit: feature_map
    path 'orthology_projection_warnings.tsv', emit: warnings

    script:
    """
    python3 ${projectDir}/bin/project_features_to_orthogroups.py \\
      --omics_samplesheet "${omics_samplesheet}" \\
      --orthologous_genes "${orthologous_genes}" \\
      --orthologous_res "${orthologous_res}" \\
      --omics_types "${omics_types}" \\
      --rnaseq_counts "${rnaseq_counts}" \\
      --atacseq_counts "${atacseq_counts}" \\
      --differential_expression "${differential_expression}" \\
      --differential_accessibility "${differential_accessibility}" \\
      --output_dir .
    """
}

process SUMMARIZE_ORTHOLOGY_PROJECTION {
    publishDir { "${params.outdir}/orthology" }, mode: 'copy'

    input:
    path omics_samplesheet
    val rnaseq_counts
    val atacseq_counts
    val differential_expression
    val differential_accessibility
    path feature_map
    path gene_counts
    path re_counts
    path differential_expression_orthogroups
    path differential_accessibility_orthogroups
    path warnings

    output:
    path 'summary/orthology_projection_summary.tsv', emit: summary
    path 'summary/orthology_outputs_manifest.tsv', emit: manifest

    script:
    """
    mkdir -p summary
    python3 ${projectDir}/bin/summarize_orthology_projection.py \\
      --omics_samplesheet "${omics_samplesheet}" \\
      --rnaseq_counts "${rnaseq_counts}" \\
      --atacseq_counts "${atacseq_counts}" \\
      --differential_expression "${differential_expression}" \\
      --differential_accessibility "${differential_accessibility}" \\
      --feature_map "${feature_map}" \\
      --gene_orthogroup_counts "${gene_counts}" \\
      --re_orthogroup_counts "${re_counts}" \\
      --differential_expression_orthogroups "${differential_expression_orthogroups}" \\
      --differential_accessibility_orthogroups "${differential_accessibility_orthogroups}" \\
      --warnings "${warnings}" \\
      --output_dir summary
    """
}

workflow ORTHOLOGY_PROJECTION {
    take:
    omics_samplesheet
    orthologous_genes
    orthologous_res
    omics_types
    rnaseq_counts
    atacseq_counts
    differential_expression
    differential_accessibility

    main:
    VALIDATE_ORTHOLOGY_TABLES(
        omics_samplesheet,
        orthologous_genes,
        orthologous_res,
        rnaseq_counts,
        atacseq_counts,
        differential_expression,
        differential_accessibility
    )
    PROJECT_FEATURES_TO_ORTHOGROUPS(
        omics_samplesheet,
        orthologous_genes,
        orthologous_res,
        omics_types,
        rnaseq_counts,
        atacseq_counts,
        differential_expression,
        differential_accessibility,
        VALIDATE_ORTHOLOGY_TABLES.out.report
    )
    SUMMARIZE_ORTHOLOGY_PROJECTION(
        omics_samplesheet,
        rnaseq_counts,
        atacseq_counts,
        differential_expression,
        differential_accessibility,
        PROJECT_FEATURES_TO_ORTHOGROUPS.out.feature_map,
        PROJECT_FEATURES_TO_ORTHOGROUPS.out.gene_counts,
        PROJECT_FEATURES_TO_ORTHOGROUPS.out.re_counts,
        PROJECT_FEATURES_TO_ORTHOGROUPS.out.differential_expression,
        PROJECT_FEATURES_TO_ORTHOGROUPS.out.differential_accessibility,
        PROJECT_FEATURES_TO_ORTHOGROUPS.out.warnings
    )

    emit:
    validation_report = VALIDATE_ORTHOLOGY_TABLES.out.report
    gene_counts = PROJECT_FEATURES_TO_ORTHOGROUPS.out.gene_counts
    re_counts = PROJECT_FEATURES_TO_ORTHOGROUPS.out.re_counts
    differential_expression = PROJECT_FEATURES_TO_ORTHOGROUPS.out.differential_expression
    differential_accessibility = PROJECT_FEATURES_TO_ORTHOGROUPS.out.differential_accessibility
    feature_map = PROJECT_FEATURES_TO_ORTHOGROUPS.out.feature_map
    warnings = PROJECT_FEATURES_TO_ORTHOGROUPS.out.warnings
    summary = SUMMARIZE_ORTHOLOGY_PROJECTION.out.summary
    manifest = SUMMARIZE_ORTHOLOGY_PROJECTION.out.manifest
}
