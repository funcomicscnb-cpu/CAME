include { PHENOTYPE_QC } from '../subworkflows/phenotype_qc'
include { CALC_PHENOTYPE_INDEX } from '../subworkflows/phenotype_index'
include { PHENOTYPE_CONTRASTS } from '../subworkflows/phenotype_contrasts'

process PHENOTYPE_NORMALIZE {
    publishDir { "${params.outdir}/phenotype" }, mode: 'copy'

    input:
    path phenotype_samplesheet
    val normalization
    path metadata_report
    path study_profile_report
    path study_profile

    output:
    path 'tables/phenotype_long_normalized.tsv', emit: table
    path 'qc/normalization_summary.tsv', emit: summary
    path 'qc/phenotype_design_summary.tsv', emit: design_summary

    script:
    """
    test -s ${metadata_report}
    test -s ${study_profile_report}
    mkdir -p tables qc
    python3 ${projectDir}/bin/phenotype_normalize.py \\
      --input ${phenotype_samplesheet} \\
      --normalization ${normalization} \\
      --output tables/phenotype_long_normalized.tsv \\
      --summary qc/normalization_summary.tsv \\
      --study_profile ${study_profile} \\
      --design_summary qc/phenotype_design_summary.tsv
    """
}

workflow PHENOTYPE_RESPONSE {
    take:
    phenotype_samplesheet
    study_profile
    normalization
    metadata_report
    study_profile_report

    main:
    PHENOTYPE_NORMALIZE(phenotype_samplesheet, normalization, metadata_report, study_profile_report, study_profile)
    PHENOTYPE_QC(PHENOTYPE_NORMALIZE.out.table, study_profile)
    CALC_PHENOTYPE_INDEX(PHENOTYPE_NORMALIZE.out.table, study_profile, PHENOTYPE_QC.out.metrics)
    PHENOTYPE_CONTRASTS(
        PHENOTYPE_NORMALIZE.out.table,
        study_profile,
        CALC_PHENOTYPE_INDEX.out.sample,
        CALC_PHENOTYPE_INDEX.out.group,
        CALC_PHENOTYPE_INDEX.out.indexes_group
    )

    emit:
    phenotype_table = PHENOTYPE_NORMALIZE.out.table
    design_summary = PHENOTYPE_NORMALIZE.out.design_summary
    index_by_sample = CALC_PHENOTYPE_INDEX.out.sample
    index_by_group = CALC_PHENOTYPE_INDEX.out.group
    index_contrasts = PHENOTYPE_CONTRASTS.out.index
    component_contrasts = PHENOTYPE_CONTRASTS.out.components
}
