process PHENOTYPE_CONTRASTS {
    publishDir { "${params.outdir}/phenotype" }, mode: 'copy'

    input:
    path phenotype_table
    path study_profile
    path index_by_sample
    path index_by_group
    path indexes_by_group

    output:
    path 'contrasts/phenotype_index_contrasts.tsv', emit: index
    path 'contrasts/component_trait_contrasts.tsv', emit: components
    path 'contrasts/phenotype_index_contrasts_long.tsv', emit: index_long

    script:
    """
    test -s ${index_by_sample}
    mkdir -p contrasts
    python3 ${projectDir}/bin/phenotype_contrasts.py \\
      --phenotype_table ${phenotype_table} \\
      --study_profile ${study_profile} \\
      --index_by_group ${index_by_group} \\
      --indexes_by_group ${indexes_by_group} \\
      --index_output contrasts/phenotype_index_contrasts.tsv \\
      --component_output contrasts/component_trait_contrasts.tsv \\
      --index_long_output contrasts/phenotype_index_contrasts_long.tsv
    """
}
