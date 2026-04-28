process CLUSTER_MOLECULAR_RESPONSES {
    publishDir { "${params.outdir}/integration" }, mode: 'copy'

    input:
    path molecular_response_long
    val cluster_method

    output:
    path 'clustering/response_clusters_expression.tsv', emit: expression
    path 'clustering/response_clusters_accessibility.tsv', emit: accessibility
    path 'clustering/response_clusters_gra_activity.tsv', emit: gra_activity
    path 'clustering/response_cluster_summary.tsv', emit: summary

    script:
    """
    mkdir -p clustering
    python3 ${projectDir}/bin/cluster_molecular_responses.py \\
      --molecular_response_long "${molecular_response_long}" \\
      --method "${cluster_method}" \\
      --output_dir clustering
    """
}

workflow MOLECULAR_RESPONSE_CLUSTERING {
    take:
    molecular_response_long
    cluster_method

    main:
    CLUSTER_MOLECULAR_RESPONSES(molecular_response_long, cluster_method)

    emit:
    expression = CLUSTER_MOLECULAR_RESPONSES.out.expression
    accessibility = CLUSTER_MOLECULAR_RESPONSES.out.accessibility
    gra_activity = CLUSTER_MOLECULAR_RESPONSES.out.gra_activity
    summary = CLUSTER_MOLECULAR_RESPONSES.out.summary
}
