include { EVIDENCE_COLLECTION } from '../subworkflows/evidence_collection'
include { CANDIDATE_SCORING } from '../subworkflows/candidate_scoring'
include { CANDIDATE_TABLES } from '../subworkflows/candidate_tables'

workflow CANDIDATE_PRIORITIZATION {
    take:
    phenotype_index_contrasts
    hypothesis_model_results
    differential_expression
    differential_accessibility
    differential_gra_activity
    gene_regulatory_architectures
    gra_re_membership
    feature_to_orthogroup_map
    phenotype_expression_associations
    phenotype_accessibility_associations
    phenotype_gra_associations
    response_clusters_expression
    response_clusters_accessibility
    response_clusters_gra_activity
    pairwise_species_molecular_contrasts
    candidate_scoring_config
    candidate_linked_evidence_weight
    candidate_score_cap

    main:
    EVIDENCE_COLLECTION(
        phenotype_index_contrasts,
        hypothesis_model_results,
        differential_expression,
        differential_accessibility,
        differential_gra_activity,
        gene_regulatory_architectures,
        gra_re_membership,
        feature_to_orthogroup_map,
        phenotype_expression_associations,
        phenotype_accessibility_associations,
        phenotype_gra_associations,
        response_clusters_expression,
        response_clusters_accessibility,
        response_clusters_gra_activity,
        pairwise_species_molecular_contrasts
    )
    CANDIDATE_SCORING(
        EVIDENCE_COLLECTION.out.evidence,
        candidate_scoring_config,
        candidate_linked_evidence_weight,
        candidate_score_cap
    )
    CANDIDATE_TABLES(
        EVIDENCE_COLLECTION.out.evidence,
        EVIDENCE_COLLECTION.out.warnings,
        CANDIDATE_SCORING.out.scored_evidence,
        CANDIDATE_SCORING.out.genes,
        CANDIDATE_SCORING.out.res,
        CANDIDATE_SCORING.out.gras,
        CANDIDATE_SCORING.out.all,
        CANDIDATE_SCORING.out.warnings
    )

    emit:
    evidence = EVIDENCE_COLLECTION.out.evidence
    evidence_warnings = EVIDENCE_COLLECTION.out.warnings
    scored_evidence = CANDIDATE_SCORING.out.scored_evidence
    ranked_genes = CANDIDATE_SCORING.out.genes
    ranked_res = CANDIDATE_SCORING.out.res
    ranked_gras = CANDIDATE_SCORING.out.gras
    ranked_all = CANDIDATE_SCORING.out.all
    scoring_warnings = CANDIDATE_SCORING.out.warnings
    summary = CANDIDATE_TABLES.out.summary
    manifest = CANDIDATE_TABLES.out.manifest
}
