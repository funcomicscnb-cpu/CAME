include { GRA_BUILDING } from '../subworkflows/gra_building'
include { GRA_ACTIVITY } from '../subworkflows/gra_activity'
include { DIFFERENTIAL_GRA_ACTIVITY } from '../subworkflows/differential_gra_activity'

process SUMMARIZE_GRA_ANALYSIS {
    publishDir { "${params.outdir}/gra" }, mode: 'copy'

    input:
    path validation_report
    path gene_orthogroup_counts
    path gene_regulatory_architectures
    path gra_re_membership
    path gra_link_warnings
    path gra_activity_matrix
    path gra_activity_long
    path gra_activity_contributing_res
    path gra_activity_warnings
    path differential_gra_activity
    path normalized_gra_activity
    path differential_gra_activity_warnings

    output:
    path 'summary/gra_analysis_summary.tsv', emit: summary
    path 'summary/gra_outputs_manifest.tsv', emit: manifest

    script:
    """
    mkdir -p summary
    python3 ${projectDir}/bin/summarize_gra_analysis.py \\
      --validation_report "${validation_report}" \\
      --gene_orthogroup_counts "${gene_orthogroup_counts}" \\
      --gene_regulatory_architectures "${gene_regulatory_architectures}" \\
      --gra_re_membership "${gra_re_membership}" \\
      --gra_link_warnings "${gra_link_warnings}" \\
      --gra_activity_matrix "${gra_activity_matrix}" \\
      --gra_activity_long "${gra_activity_long}" \\
      --gra_activity_contributing_res "${gra_activity_contributing_res}" \\
      --gra_activity_warnings "${gra_activity_warnings}" \\
      --differential_gra_activity "${differential_gra_activity}" \\
      --normalized_gra_activity "${normalized_gra_activity}" \\
      --differential_gra_activity_warnings "${differential_gra_activity_warnings}" \\
      --output_dir summary
    """
}

workflow GRA_ANALYSIS {
    take:
    omics_samplesheet
    re_to_gene_links
    gene_orthogroup_counts
    re_orthogroup_counts
    feature_to_orthogroup_map
    differential_expression_orthogroups
    differential_accessibility_orthogroups
    study_profile
    baseline_condition
    response_condition
    baseline_timepoint
    response_timepoint
    aggregation
    min_count
    min_total_count
    min_samples_per_group
    alpha
    differential_force_fallback

    main:
    GRA_BUILDING(
        re_to_gene_links,
        gene_orthogroup_counts,
        re_orthogroup_counts,
        feature_to_orthogroup_map
    )
    GRA_ACTIVITY(
        re_orthogroup_counts,
        GRA_BUILDING.out.architectures,
        GRA_BUILDING.out.membership,
        omics_samplesheet,
        aggregation
    )
    DIFFERENTIAL_GRA_ACTIVITY(
        GRA_ACTIVITY.out.matrix,
        omics_samplesheet,
        study_profile,
        baseline_condition,
        response_condition,
        baseline_timepoint,
        response_timepoint,
        aggregation,
        min_count,
        min_total_count,
        min_samples_per_group,
        alpha,
        differential_force_fallback
    )
    SUMMARIZE_GRA_ANALYSIS(
        GRA_BUILDING.out.validation_report,
        gene_orthogroup_counts,
        GRA_BUILDING.out.architectures,
        GRA_BUILDING.out.membership,
        GRA_BUILDING.out.warnings,
        GRA_ACTIVITY.out.matrix,
        GRA_ACTIVITY.out.activity_long,
        GRA_ACTIVITY.out.contributing_res,
        GRA_ACTIVITY.out.warnings,
        DIFFERENTIAL_GRA_ACTIVITY.out.results,
        DIFFERENTIAL_GRA_ACTIVITY.out.normalized,
        DIFFERENTIAL_GRA_ACTIVITY.out.warnings
    )

    emit:
    validation_report = GRA_BUILDING.out.validation_report
    architectures = GRA_BUILDING.out.architectures
    membership = GRA_BUILDING.out.membership
    activity_matrix = GRA_ACTIVITY.out.matrix
    activity_long = GRA_ACTIVITY.out.activity_long
    activity_contributing_res = GRA_ACTIVITY.out.contributing_res
    differential = DIFFERENTIAL_GRA_ACTIVITY.out.results
    normalized = DIFFERENTIAL_GRA_ACTIVITY.out.normalized
    summary = SUMMARIZE_GRA_ANALYSIS.out.summary
    manifest = SUMMARIZE_GRA_ANALYSIS.out.manifest
}
