process RUN_DIFFERENTIAL_ANALYSIS {
    publishDir { "${params.outdir}/differential_omics" }, mode: 'copy'

    input:
    val omics_type
    val counts_path
    path sample_annotation
    path contrasts
    val min_count
    val min_total_count
    val min_samples_per_group
    val alpha
    val differential_force_fallback

    output:
    path "${omics_type}/differential_results.tsv", emit: results
    path "${omics_type}/normalized_counts.tsv", emit: normalized
    path "${omics_type}/differential_warnings.tsv", emit: warnings
    path "${omics_type}/differential_summary.tsv", emit: summary

    script:
    """
    mkdir -p "${omics_type}"
    Rscript ${projectDir}/bin/run_differential_analysis.R \\
      --counts "${counts_path}" \\
      --samples "${sample_annotation}" \\
      --contrasts "${contrasts}" \\
      --omics_type "${omics_type}" \\
      --output_dir "${omics_type}" \\
      --min_count "${min_count}" \\
      --min_total_count "${min_total_count}" \\
      --min_samples_per_group "${min_samples_per_group}" \\
      --alpha "${alpha}" \\
      --force_fallback "${differential_force_fallback}"
    """
}
