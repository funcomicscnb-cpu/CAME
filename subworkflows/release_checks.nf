process RUN_CAME_RELEASE_CHECKS {
    publishDir { "${params.outdir}/final/release_checks" }, mode: 'copy'

    input:
    path manifest
    val results_dir

    output:
    path 'came_release_checks.tsv', emit: checks
    path 'came_release_summary.tsv', emit: summary

    script:
    """
    python3 ${projectDir}/bin/run_release_checks.py \\
      --project_dir "${projectDir}" \\
      --results_dir "${results_dir}" \\
      --manifest "${manifest}" \\
      --output_dir .
    """
}

workflow RELEASE_CHECKS {
    take:
    manifest
    results_dir

    main:
    RUN_CAME_RELEASE_CHECKS(manifest, results_dir)

    emit:
    checks = RUN_CAME_RELEASE_CHECKS.out.checks
    summary = RUN_CAME_RELEASE_CHECKS.out.summary
}
