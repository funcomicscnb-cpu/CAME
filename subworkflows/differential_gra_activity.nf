process RUN_DIFFERENTIAL_GRA_ACTIVITY {
    publishDir { "${params.outdir}/gra" }, mode: 'copy'

    input:
    path gra_activity_matrix
    path omics_samplesheet
    val study_profile
    val baseline_condition
    val response_condition
    val baseline_timepoint
    val response_timepoint
    val aggregation
    val min_count
    val min_total_count
    val min_samples_per_group
    val alpha
    val differential_force_fallback

    output:
    path 'differential/differential_gra_activity.tsv', emit: results
    path 'differential/normalized_gra_activity.tsv', emit: normalized
    path 'differential/differential_gra_activity_warnings.tsv', emit: warnings

    script:
    """
    mkdir -p differential
    Rscript ${projectDir}/bin/run_differential_gra_activity.R \\
      --gra_activity_matrix "${gra_activity_matrix}" \\
      --omics_samplesheet "${omics_samplesheet}" \\
      --study_profile "${study_profile}" \\
      --baseline_condition "${baseline_condition}" \\
      --response_condition "${response_condition}" \\
      --baseline_timepoint "${baseline_timepoint}" \\
      --response_timepoint "${response_timepoint}" \\
      --aggregation "${aggregation}" \\
      --output_dir differential \\
      --min_count "${min_count}" \\
      --min_total_count "${min_total_count}" \\
      --min_samples_per_group "${min_samples_per_group}" \\
      --alpha "${alpha}" \\
      --force_fallback "${differential_force_fallback}"
    """
}

workflow DIFFERENTIAL_GRA_ACTIVITY {
    take:
    gra_activity_matrix
    omics_samplesheet
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
    RUN_DIFFERENTIAL_GRA_ACTIVITY(
        gra_activity_matrix,
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

    emit:
    results = RUN_DIFFERENTIAL_GRA_ACTIVITY.out.results
    normalized = RUN_DIFFERENTIAL_GRA_ACTIVITY.out.normalized
    warnings = RUN_DIFFERENTIAL_GRA_ACTIVITY.out.warnings
}
