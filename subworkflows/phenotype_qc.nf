process PHENOTYPE_QC {
    publishDir { "${params.outdir}/phenotype" }, mode: 'copy'

    input:
    path phenotype_table
    path study_profile

    output:
    path 'qc/phenotype_qc_metrics.tsv', emit: metrics
    path 'qc/outliers.tsv', emit: outliers
    path 'qc/group_counts.tsv', emit: group_counts

    script:
    """
    mkdir -p qc
    python3 ${projectDir}/bin/phenotype_qc.py \\
      --input ${phenotype_table} \\
      --study_profile ${study_profile} \\
      --metrics qc/phenotype_qc_metrics.tsv \\
      --outliers qc/outliers.tsv \\
      --group_counts qc/group_counts.tsv
    """
}
