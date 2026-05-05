process CALC_PHENOTYPE_INDEX {
    publishDir { "${params.outdir}/phenotype" }, mode: 'copy'

    input:
    path phenotype_table
    path study_profile
    path qc_metrics

    output:
    path 'index/phenotype_index_by_sample.tsv', emit: sample
    path 'index/phenotype_index_by_group.tsv', emit: group
    path 'index/phenotype_indexes_by_sample.tsv', emit: indexes_sample
    path 'index/phenotype_indexes_by_group.tsv', emit: indexes_group
    path 'summary/phenotype_processing_manifest.tsv', emit: manifest

    script:
    """
    test -s ${qc_metrics}
    mkdir -p index summary
    python3 ${projectDir}/bin/calc_phenotype_index.py \\
      --input ${phenotype_table} \\
      --study_profile ${study_profile} \\
      --sample_output index/phenotype_index_by_sample.tsv \\
      --group_output index/phenotype_index_by_group.tsv \\
      --indexes_sample_output index/phenotype_indexes_by_sample.tsv \\
      --indexes_group_output index/phenotype_indexes_by_group.tsv \\
      --manifest_output summary/phenotype_processing_manifest.tsv \\
      --normalization "${params.normalization ?: ''}"
    """
}
