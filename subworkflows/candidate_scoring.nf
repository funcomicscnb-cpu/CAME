process SCORE_CANDIDATE_MECHANISMS {
    publishDir { "${params.outdir}/candidates" }, mode: 'copy'

    input:
    path candidate_evidence_long
    val candidate_scoring_config
    val candidate_linked_evidence_weight
    val candidate_score_cap

    output:
    path 'ranked/candidate_genes_ranked.tsv', emit: genes
    path 'ranked/candidate_res_ranked.tsv', emit: res
    path 'ranked/candidate_gras_ranked.tsv', emit: gras
    path 'ranked/candidate_all_ranked.tsv', emit: all
    path 'ranked/candidate_scoring_warnings.tsv', emit: warnings
    path 'evidence/candidate_evidence_scored.tsv', emit: scored_evidence

    script:
    """
    mkdir -p ranked evidence
    python3 ${projectDir}/bin/score_candidate_mechanisms.py \\
      --candidate_evidence_long "${candidate_evidence_long}" \\
      --candidate_scoring_config "${candidate_scoring_config}" \\
      --candidate_linked_evidence_weight "${candidate_linked_evidence_weight}" \\
      --candidate_score_cap "${candidate_score_cap}" \\
      --output_dir ranked \\
      --scored_evidence_output evidence/candidate_evidence_scored.tsv
    """
}

workflow CANDIDATE_SCORING {
    take:
    candidate_evidence_long
    candidate_scoring_config
    candidate_linked_evidence_weight
    candidate_score_cap

    main:
    SCORE_CANDIDATE_MECHANISMS(
        candidate_evidence_long,
        candidate_scoring_config,
        candidate_linked_evidence_weight,
        candidate_score_cap
    )

    emit:
    genes = SCORE_CANDIDATE_MECHANISMS.out.genes
    res = SCORE_CANDIDATE_MECHANISMS.out.res
    gras = SCORE_CANDIDATE_MECHANISMS.out.gras
    all = SCORE_CANDIDATE_MECHANISMS.out.all
    warnings = SCORE_CANDIDATE_MECHANISMS.out.warnings
    scored_evidence = SCORE_CANDIDATE_MECHANISMS.out.scored_evidence
}
