process PREPARE_FUNCTIONAL_ENRICHMENT_INPUTS {
    publishDir { "${params.outdir}/interpretation" }, mode: 'copy'

    input:
    path candidate_genes
    path candidate_res
    path candidate_gras
    path candidate_all
    path gene_annotations
    path gene_sets
    path gra_re_membership
    path gene_regulatory_architectures
    val top_n
    val min_score

    output:
    path 'input/candidate_gene_sets.tsv', emit: candidate_gene_sets
    path 'input/enrichment_background.tsv', emit: background
    path 'input/enrichment_input_warnings.tsv', emit: warnings

    script:
    def minScoreArg = min_score != null && min_score.toString().trim() ? "--min_score \"${min_score}\"" : ""
    """
    mkdir -p input
    python3 ${projectDir}/bin/prepare_enrichment_inputs.py \\
      --candidate_genes "${candidate_genes}" \\
      --candidate_res "${candidate_res}" \\
      --candidate_gras "${candidate_gras}" \\
      --candidate_all "${candidate_all}" \\
      --gene_annotations "${gene_annotations}" \\
      --gene_sets "${gene_sets}" \\
      --gra_re_membership "${gra_re_membership}" \\
      --gene_regulatory_architectures "${gene_regulatory_architectures}" \\
      --top_n "${top_n}" \\
      ${minScoreArg} \\
      --output_dir input
    """
}

process RUN_FUNCTIONAL_GENE_SET_ENRICHMENT {
    publishDir { "${params.outdir}/interpretation" }, mode: 'copy'

    input:
    path candidate_gene_sets
    path enrichment_background
    path gene_sets

    output:
    path 'enrichment/gene_set_enrichment.tsv', emit: enrichment
    path 'enrichment/enrichment_warnings.tsv', emit: warnings

    script:
    """
    mkdir -p enrichment
    python3 ${projectDir}/bin/run_gene_set_enrichment.py \\
      --candidate_gene_sets "${candidate_gene_sets}" \\
      --enrichment_background "${enrichment_background}" \\
      --gene_sets "${gene_sets}" \\
      --output_dir enrichment
    """
}

workflow GENE_SET_ENRICHMENT {
    take:
    candidate_genes
    candidate_res
    candidate_gras
    candidate_all
    gene_annotations
    gene_sets
    gra_re_membership
    gene_regulatory_architectures
    top_n
    min_score

    main:
    PREPARE_FUNCTIONAL_ENRICHMENT_INPUTS(
        candidate_genes,
        candidate_res,
        candidate_gras,
        candidate_all,
        gene_annotations,
        gene_sets,
        gra_re_membership,
        gene_regulatory_architectures,
        top_n,
        min_score
    )
    RUN_FUNCTIONAL_GENE_SET_ENRICHMENT(
        PREPARE_FUNCTIONAL_ENRICHMENT_INPUTS.out.candidate_gene_sets,
        PREPARE_FUNCTIONAL_ENRICHMENT_INPUTS.out.background,
        gene_sets
    )

    emit:
    candidate_gene_sets = PREPARE_FUNCTIONAL_ENRICHMENT_INPUTS.out.candidate_gene_sets
    background = PREPARE_FUNCTIONAL_ENRICHMENT_INPUTS.out.background
    input_warnings = PREPARE_FUNCTIONAL_ENRICHMENT_INPUTS.out.warnings
    enrichment = RUN_FUNCTIONAL_GENE_SET_ENRICHMENT.out.enrichment
    enrichment_warnings = RUN_FUNCTIONAL_GENE_SET_ENRICHMENT.out.warnings
}
