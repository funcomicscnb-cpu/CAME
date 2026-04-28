include { RUN_DIFFERENTIAL_ANALYSIS as RUN_DIFFERENTIAL_EXPRESSION } from './omics_normalization'

workflow DIFFERENTIAL_EXPRESSION {
    take:
    counts_path
    sample_annotation
    contrasts
    min_count
    min_total_count
    min_samples_per_group
    alpha
    differential_force_fallback

    main:
    RUN_DIFFERENTIAL_EXPRESSION(
        'rnaseq',
        counts_path,
        sample_annotation,
        contrasts,
        min_count,
        min_total_count,
        min_samples_per_group,
        alpha,
        differential_force_fallback
    )

    emit:
    results = RUN_DIFFERENTIAL_EXPRESSION.out.results
    normalized = RUN_DIFFERENTIAL_EXPRESSION.out.normalized
    warnings = RUN_DIFFERENTIAL_EXPRESSION.out.warnings
    summary = RUN_DIFFERENTIAL_EXPRESSION.out.summary
}
