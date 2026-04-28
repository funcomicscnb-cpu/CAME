process SUMMARIZE_CANDIDATE_PRIORITIZATION {
    publishDir { "${params.outdir}/candidates" }, mode: 'copy'

    input:
    path candidate_evidence_long
    path candidate_evidence_warnings
    path candidate_evidence_scored
    path candidate_genes_ranked
    path candidate_res_ranked
    path candidate_gras_ranked
    path candidate_all_ranked
    path candidate_scoring_warnings

    output:
    path 'summary/candidate_prioritization_summary.tsv', emit: summary
    path 'summary/candidate_outputs_manifest.tsv', emit: manifest

    script:
    """
    mkdir -p summary
    python3 ${projectDir}/bin/summarize_candidate_prioritization.py \\
      --candidate_evidence_long "${candidate_evidence_long}" \\
      --candidate_evidence_warnings "${candidate_evidence_warnings}" \\
      --candidate_evidence_scored "${candidate_evidence_scored}" \\
      --candidate_genes_ranked "${candidate_genes_ranked}" \\
      --candidate_res_ranked "${candidate_res_ranked}" \\
      --candidate_gras_ranked "${candidate_gras_ranked}" \\
      --candidate_all_ranked "${candidate_all_ranked}" \\
      --candidate_scoring_warnings "${candidate_scoring_warnings}" \\
      --output_dir summary
    """
}

workflow CANDIDATE_TABLES {
    take:
    candidate_evidence_long
    candidate_evidence_warnings
    candidate_evidence_scored
    candidate_genes_ranked
    candidate_res_ranked
    candidate_gras_ranked
    candidate_all_ranked
    candidate_scoring_warnings

    main:
    SUMMARIZE_CANDIDATE_PRIORITIZATION(
        candidate_evidence_long,
        candidate_evidence_warnings,
        candidate_evidence_scored,
        candidate_genes_ranked,
        candidate_res_ranked,
        candidate_gras_ranked,
        candidate_all_ranked,
        candidate_scoring_warnings
    )

    emit:
    summary = SUMMARIZE_CANDIDATE_PRIORITIZATION.out.summary
    manifest = SUMMARIZE_CANDIDATE_PRIORITIZATION.out.manifest
}
