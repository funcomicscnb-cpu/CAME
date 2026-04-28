include { RUN_DIFFERENTIAL_ANALYSIS as RUN_DIFFERENTIAL_ACCESSIBILITY } from './omics_normalization'

workflow DIFFERENTIAL_ACCESSIBILITY {
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
    RUN_DIFFERENTIAL_ACCESSIBILITY(
        'atacseq',
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
    results = RUN_DIFFERENTIAL_ACCESSIBILITY.out.results
    normalized = RUN_DIFFERENTIAL_ACCESSIBILITY.out.normalized
    warnings = RUN_DIFFERENTIAL_ACCESSIBILITY.out.warnings
    summary = RUN_DIFFERENTIAL_ACCESSIBILITY.out.summary
}
