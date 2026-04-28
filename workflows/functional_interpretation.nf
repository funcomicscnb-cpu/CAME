include { GENE_SET_ENRICHMENT } from '../subworkflows/gene_set_enrichment'
include { REGULATORY_REGION_EXPORT } from '../subworkflows/regulatory_region_export'
include { CANDIDATE_INTERPRETATION } from '../subworkflows/candidate_interpretation'

workflow FUNCTIONAL_INTERPRETATION {
    take:
    candidate_genes
    candidate_res
    candidate_gras
    candidate_all
    feature_to_orthogroup_map
    gene_regulatory_architectures
    gra_re_membership
    gene_annotations
    gene_sets
    top_n
    min_score

    main:
    GENE_SET_ENRICHMENT(
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
    REGULATORY_REGION_EXPORT(
        candidate_res,
        candidate_gras,
        feature_to_orthogroup_map,
        gra_re_membership,
        top_n,
        min_score
    )
    CANDIDATE_INTERPRETATION(
        candidate_genes,
        candidate_res,
        candidate_gras,
        gene_annotations,
        GENE_SET_ENRICHMENT.out.candidate_gene_sets,
        GENE_SET_ENRICHMENT.out.background,
        GENE_SET_ENRICHMENT.out.input_warnings,
        GENE_SET_ENRICHMENT.out.enrichment,
        GENE_SET_ENRICHMENT.out.enrichment_warnings,
        REGULATORY_REGION_EXPORT.out.candidate_res_bed,
        REGULATORY_REGION_EXPORT.out.gra_linked_candidate_res_bed,
        REGULATORY_REGION_EXPORT.out.warnings
    )

    emit:
    candidate_gene_sets = GENE_SET_ENRICHMENT.out.candidate_gene_sets
    enrichment_background = GENE_SET_ENRICHMENT.out.background
    enrichment_input_warnings = GENE_SET_ENRICHMENT.out.input_warnings
    gene_set_enrichment = GENE_SET_ENRICHMENT.out.enrichment
    enrichment_warnings = GENE_SET_ENRICHMENT.out.enrichment_warnings
    candidate_res_bed = REGULATORY_REGION_EXPORT.out.candidate_res_bed
    gra_linked_candidate_res_bed = REGULATORY_REGION_EXPORT.out.gra_linked_candidate_res_bed
    regulatory_region_export_warnings = REGULATORY_REGION_EXPORT.out.warnings
    gene_summary = CANDIDATE_INTERPRETATION.out.gene_summary
    re_summary = CANDIDATE_INTERPRETATION.out.re_summary
    gra_summary = CANDIDATE_INTERPRETATION.out.gra_summary
    summary = CANDIDATE_INTERPRETATION.out.summary
    manifest = CANDIDATE_INTERPRETATION.out.manifest
}
