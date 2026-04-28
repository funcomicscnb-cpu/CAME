process CALC_PHENOTYPE_INDEX {
    publishDir { "${params.outdir}/phenotype" }, mode: 'copy'

    input:
    path phenotype_table
    path study_profile
    path qc_metrics

    output:
    path 'index/phenotype_index_by_sample.tsv', emit: sample
    path 'index/phenotype_index_by_group.tsv', emit: group

    script:
    """
    test -s ${qc_metrics}
    mkdir -p index
    python3 ${projectDir}/bin/calc_phenotype_index.py \\
      --input ${phenotype_table} \\
      --study_profile ${study_profile} \\
      --sample_output index/phenotype_index_by_sample.tsv \\
      --group_output index/phenotype_index_by_group.tsv
    """
}
