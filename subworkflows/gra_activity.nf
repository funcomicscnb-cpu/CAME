process AGGREGATE_GRA_ACTIVITY {
    publishDir { "${params.outdir}/gra" }, mode: 'copy'

    input:
    path re_orthogroup_counts
    path gene_regulatory_architectures
    path gra_re_membership
    path omics_samplesheet
    val aggregation

    output:
    path 'activity/gra_activity_matrix.tsv', emit: matrix
    path 'activity/gra_activity_long.tsv', emit: activity_long
    path 'activity/gra_activity_contributing_res.tsv', emit: contributing_res
    path 'activity/gra_activity_warnings.tsv', emit: warnings

    script:
    """
    mkdir -p activity
    python3 ${projectDir}/bin/aggregate_gra_activity.py \\
      --re_orthogroup_counts "${re_orthogroup_counts}" \\
      --gene_regulatory_architectures "${gene_regulatory_architectures}" \\
      --gra_re_membership "${gra_re_membership}" \\
      --omics_samplesheet "${omics_samplesheet}" \\
      --aggregation "${aggregation}" \\
      --output_dir activity
    """
}

workflow GRA_ACTIVITY {
    take:
    re_orthogroup_counts
    gene_regulatory_architectures
    gra_re_membership
    omics_samplesheet
    aggregation

    main:
    AGGREGATE_GRA_ACTIVITY(
        re_orthogroup_counts,
        gene_regulatory_architectures,
        gra_re_membership,
        omics_samplesheet,
        aggregation
    )

    emit:
    matrix = AGGREGATE_GRA_ACTIVITY.out.matrix
    activity_long = AGGREGATE_GRA_ACTIVITY.out.activity_long
    contributing_res = AGGREGATE_GRA_ACTIVITY.out.contributing_res
    warnings = AGGREGATE_GRA_ACTIVITY.out.warnings
}
