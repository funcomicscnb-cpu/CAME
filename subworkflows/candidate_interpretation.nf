process SUMMARIZE_FUNCTIONAL_INTERPRETATION {
    publishDir { "${params.outdir}/interpretation" }, mode: 'copy'

    input:
    path candidate_genes
    path candidate_res
    path candidate_gras
    path gene_annotations
    path candidate_gene_sets
    path enrichment_background
    path enrichment_input_warnings
    path gene_set_enrichment
    path enrichment_warnings
    path candidate_res_bed
    path gra_linked_candidate_res_bed
    path regulatory_region_export_warnings

    output:
    path 'summary/candidate_gene_interpretation.tsv', emit: gene_summary
    path 'summary/candidate_re_interpretation.tsv', emit: re_summary
    path 'summary/candidate_gra_interpretation.tsv', emit: gra_summary
    path 'summary/functional_interpretation_summary.tsv', emit: summary
    path 'summary/functional_interpretation_outputs_manifest.tsv', emit: manifest

    script:
    """
    mkdir -p summary
    python3 ${projectDir}/bin/summarize_candidate_interpretation.py \\
      --candidate_genes_ranked "${candidate_genes}" \\
      --candidate_res_ranked "${candidate_res}" \\
      --candidate_gras_ranked "${candidate_gras}" \\
      --gene_annotations "${gene_annotations}" \\
      --candidate_gene_sets "${candidate_gene_sets}" \\
      --enrichment_background "${enrichment_background}" \\
      --enrichment_input_warnings "${enrichment_input_warnings}" \\
      --gene_set_enrichment "${gene_set_enrichment}" \\
      --enrichment_warnings "${enrichment_warnings}" \\
      --candidate_res_bed "${candidate_res_bed}" \\
      --gra_linked_candidate_res_bed "${gra_linked_candidate_res_bed}" \\
      --regulatory_region_export_warnings "${regulatory_region_export_warnings}" \\
      --output_dir summary
    """
}

workflow CANDIDATE_INTERPRETATION {
    take:
    candidate_genes
    candidate_res
    candidate_gras
    gene_annotations
    candidate_gene_sets
    enrichment_background
    enrichment_input_warnings
    gene_set_enrichment
    enrichment_warnings
    candidate_res_bed
    gra_linked_candidate_res_bed
    regulatory_region_export_warnings

    main:
    SUMMARIZE_FUNCTIONAL_INTERPRETATION(
        candidate_genes,
        candidate_res,
        candidate_gras,
        gene_annotations,
        candidate_gene_sets,
        enrichment_background,
        enrichment_input_warnings,
        gene_set_enrichment,
        enrichment_warnings,
        candidate_res_bed,
        gra_linked_candidate_res_bed,
        regulatory_region_export_warnings
    )

    emit:
    gene_summary = SUMMARIZE_FUNCTIONAL_INTERPRETATION.out.gene_summary
    re_summary = SUMMARIZE_FUNCTIONAL_INTERPRETATION.out.re_summary
    gra_summary = SUMMARIZE_FUNCTIONAL_INTERPRETATION.out.gra_summary
    summary = SUMMARIZE_FUNCTIONAL_INTERPRETATION.out.summary
    manifest = SUMMARIZE_FUNCTIONAL_INTERPRETATION.out.manifest
}
