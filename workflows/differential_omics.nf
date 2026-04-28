include { DIFFERENTIAL_EXPRESSION } from '../subworkflows/differential_expression'
include { DIFFERENTIAL_ACCESSIBILITY } from '../subworkflows/differential_accessibility'

process PREPARE_DIFFERENTIAL_INPUTS {
    publishDir { "${params.outdir}/differential_omics" }, mode: 'copy'

    input:
    path omics_samplesheet
    val study_profile
    val omics_types
    val rnaseq_counts
    val atacseq_counts
    val baseline_condition
    val response_condition
    val baseline_timepoint
    val response_timepoint

    output:
    path 'input/differential_samples.tsv', emit: samples
    path 'input/differential_contrasts.tsv', emit: contrasts
    path 'input/rnaseq_sample_annotation.tsv', emit: rnaseq_samples
    path 'input/rnaseq_contrasts.tsv', emit: rnaseq_contrasts
    path 'input/atacseq_sample_annotation.tsv', emit: atacseq_samples
    path 'input/atacseq_contrasts.tsv', emit: atacseq_contrasts
    path 'input/differential_input_manifest.tsv', emit: manifest
    path 'input/differential_input_warnings.tsv', emit: warnings

    script:
    """
    mkdir -p input
    python3 ${projectDir}/bin/prepare_differential_inputs.py \\
      --omics_samplesheet "${omics_samplesheet}" \\
      --study_profile "${study_profile}" \\
      --omics_types "${omics_types}" \\
      --rnaseq_counts "${rnaseq_counts}" \\
      --atacseq_counts "${atacseq_counts}" \\
      --baseline_condition "${baseline_condition}" \\
      --response_condition "${response_condition}" \\
      --baseline_timepoint "${baseline_timepoint}" \\
      --response_timepoint "${response_timepoint}" \\
      --output_dir input
    """
}

process SUMMARIZE_DIFFERENTIAL_OMICS {
    publishDir { "${params.outdir}/differential_omics" }, mode: 'copy'

    input:
    path input_manifest
    path input_warnings
    path rnaseq_results, stageAs: 'rnaseq/differential_results.tsv'
    path rnaseq_normalized, stageAs: 'rnaseq/normalized_counts.tsv'
    path rnaseq_warnings, stageAs: 'rnaseq/differential_warnings.tsv'
    path rnaseq_summary, stageAs: 'rnaseq/differential_summary.tsv'
    path atacseq_results, stageAs: 'atacseq/differential_results.tsv'
    path atacseq_normalized, stageAs: 'atacseq/normalized_counts.tsv'
    path atacseq_warnings, stageAs: 'atacseq/differential_warnings.tsv'
    path atacseq_summary, stageAs: 'atacseq/differential_summary.tsv'

    output:
    path 'summary/differential_omics_summary.tsv', emit: summary
    path 'summary/differential_outputs_manifest.tsv', emit: manifest

    script:
    """
    mkdir -p summary
    python3 ${projectDir}/bin/summarize_differential_results.py \\
      --input_manifest "${input_manifest}" \\
      --input_warnings "${input_warnings}" \\
      --rnaseq_results "${rnaseq_results}" \\
      --rnaseq_normalized "${rnaseq_normalized}" \\
      --rnaseq_warnings "${rnaseq_warnings}" \\
      --rnaseq_summary "${rnaseq_summary}" \\
      --atacseq_results "${atacseq_results}" \\
      --atacseq_normalized "${atacseq_normalized}" \\
      --atacseq_warnings "${atacseq_warnings}" \\
      --atacseq_summary "${atacseq_summary}" \\
      --output_dir summary
    """
}

workflow DIFFERENTIAL_OMICS {
    take:
    omics_samplesheet
    study_profile
    omics_types
    rnaseq_counts
    atacseq_counts
    baseline_condition
    response_condition
    baseline_timepoint
    response_timepoint
    min_count
    min_total_count
    min_samples_per_group
    alpha
    differential_force_fallback

    main:
    PREPARE_DIFFERENTIAL_INPUTS(
        omics_samplesheet,
        study_profile,
        omics_types,
        rnaseq_counts,
        atacseq_counts,
        baseline_condition,
        response_condition,
        baseline_timepoint,
        response_timepoint
    )
    DIFFERENTIAL_EXPRESSION(
        rnaseq_counts,
        PREPARE_DIFFERENTIAL_INPUTS.out.rnaseq_samples,
        PREPARE_DIFFERENTIAL_INPUTS.out.rnaseq_contrasts,
        min_count,
        min_total_count,
        min_samples_per_group,
        alpha,
        differential_force_fallback
    )
    DIFFERENTIAL_ACCESSIBILITY(
        atacseq_counts,
        PREPARE_DIFFERENTIAL_INPUTS.out.atacseq_samples,
        PREPARE_DIFFERENTIAL_INPUTS.out.atacseq_contrasts,
        min_count,
        min_total_count,
        min_samples_per_group,
        alpha,
        differential_force_fallback
    )
    SUMMARIZE_DIFFERENTIAL_OMICS(
        PREPARE_DIFFERENTIAL_INPUTS.out.manifest,
        PREPARE_DIFFERENTIAL_INPUTS.out.warnings,
        DIFFERENTIAL_EXPRESSION.out.results,
        DIFFERENTIAL_EXPRESSION.out.normalized,
        DIFFERENTIAL_EXPRESSION.out.warnings,
        DIFFERENTIAL_EXPRESSION.out.summary,
        DIFFERENTIAL_ACCESSIBILITY.out.results,
        DIFFERENTIAL_ACCESSIBILITY.out.normalized,
        DIFFERENTIAL_ACCESSIBILITY.out.warnings,
        DIFFERENTIAL_ACCESSIBILITY.out.summary
    )

    emit:
    rnaseq_results = DIFFERENTIAL_EXPRESSION.out.results
    rnaseq_normalized = DIFFERENTIAL_EXPRESSION.out.normalized
    atacseq_results = DIFFERENTIAL_ACCESSIBILITY.out.results
    atacseq_normalized = DIFFERENTIAL_ACCESSIBILITY.out.normalized
    summary = SUMMARIZE_DIFFERENTIAL_OMICS.out.summary
    manifest = SUMMARIZE_DIFFERENTIAL_OMICS.out.manifest
}
