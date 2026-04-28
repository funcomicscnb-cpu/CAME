include { METADATA_VALIDATION as ALL_METADATA_VALIDATION; STUDY_PROFILE_VALIDATION as ALL_STUDY_PROFILE_VALIDATION } from '../subworkflows/validation'
include { ALL_RUN_STATUS_AND_SUMMARY; ALL_STUB_OMICS_CONTRASTS } from '../subworkflows/stage_orchestration'
include { PHENOTYPE_RESPONSE as ALL_PHENOTYPE_RESPONSE } from './phenotype_response'
include { PHYLO_HYPOTHESIS as ALL_PHYLO_HYPOTHESIS } from './phylo_hypothesis'
include { BULK_OMICS as ALL_BULK_OMICS } from './bulk_omics'
include { DIFFERENTIAL_OMICS as ALL_DIFFERENTIAL_OMICS } from './differential_omics'
include { ORTHOLOGY_PROJECTION as ALL_ORTHOLOGY_PROJECTION } from './orthology_projection'
include { GRA_ANALYSIS as ALL_GRA_ANALYSIS } from './gra_analysis'
include { PHENOTYPE_OMICS_INTEGRATION as ALL_PHENOTYPE_OMICS_INTEGRATION } from './phenotype_omics_integration'
include { CANDIDATE_PRIORITIZATION as ALL_CANDIDATE_PRIORITIZATION } from './candidate_prioritization'
include { FUNCTIONAL_INTERPRETATION as ALL_FUNCTIONAL_INTERPRETATION } from './functional_interpretation'
include { FINAL_REPORT as ALL_FINAL_REPORT } from './final_report'

workflow ALL {
    take:
    phenotype_samplesheet
    omics_samplesheet
    species_traits
    reference_manifest
    phylogeny_manifest
    study_design
    study_profile
    results_dir
    phylogeny_base_dir
    normalization
    phylo_model_types
    hypothesis_model_types
    omics_types
    omics_stub
    baseline_condition
    response_condition
    baseline_timepoint
    response_timepoint
    min_count
    min_total_count
    min_samples_per_group
    alpha
    differential_force_fallback
    orthologous_genes
    orthologous_res
    re_to_gene_links
    gene_annotations
    gene_sets
    candidate_scoring_config
    candidate_linked_evidence_weight
    candidate_score_cap
    gra_activity_aggregation
    phenotype_response_metric
    molecular_response_metric
    phenotype_response_scope
    integration_model_types
    integration_min_species
    integration_cluster_method
    species_pairs
    functional_interpretation_top_n
    functional_interpretation_min_score
    resume_completed_stages

    main:
    ALL_METADATA_VALIDATION(
        phenotype_samplesheet,
        omics_samplesheet,
        species_traits,
        reference_manifest,
        phylogeny_manifest,
        study_design
    )
    ALL_STUDY_PROFILE_VALIDATION(study_profile, phenotype_samplesheet, species_traits)

    ALL_PHENOTYPE_RESPONSE(
        phenotype_samplesheet,
        study_profile,
        normalization,
        ALL_METADATA_VALIDATION.out.report,
        ALL_STUDY_PROFILE_VALIDATION.out.report
    )

    ALL_PHYLO_HYPOTHESIS(
        species_traits,
        phylogeny_manifest,
        study_profile,
        ALL_PHENOTYPE_RESPONSE.out.index_by_group,
        ALL_PHENOTYPE_RESPONSE.out.index_contrasts,
        ALL_PHENOTYPE_RESPONSE.out.component_contrasts,
        ALL_METADATA_VALIDATION.out.report,
        ALL_STUDY_PROFILE_VALIDATION.out.report,
        phylogeny_base_dir,
        phylo_model_types,
        hypothesis_model_types
    )

    bulkOmicsSamplesheet = ALL_PHYLO_HYPOTHESIS.out.hypothesis_results.map { omics_samplesheet }
    bulkReferenceManifest = ALL_PHYLO_HYPOTHESIS.out.hypothesis_results.map { reference_manifest }
    ALL_BULK_OMICS(
        bulkOmicsSamplesheet,
        bulkReferenceManifest,
        omics_types,
        omics_stub
    )

    if (params.omics_stub.toString().toBoolean()) {
        ALL_STUB_OMICS_CONTRASTS(
            bulkOmicsSamplesheet,
            study_profile,
            ALL_BULK_OMICS.out.rnaseq_counts,
            ALL_BULK_OMICS.out.atacseq_counts
        )
        differentialOmicsSamplesheet = ALL_STUB_OMICS_CONTRASTS.out.omics_samplesheet
        differentialRnaseqCounts = ALL_STUB_OMICS_CONTRASTS.out.rnaseq_counts
        differentialAtacseqCounts = ALL_STUB_OMICS_CONTRASTS.out.atacseq_counts
    } else {
        differentialOmicsSamplesheet = bulkOmicsSamplesheet
        differentialRnaseqCounts = ALL_BULK_OMICS.out.rnaseq_counts
        differentialAtacseqCounts = ALL_BULK_OMICS.out.atacseq_counts
    }

    ALL_DIFFERENTIAL_OMICS(
        differentialOmicsSamplesheet,
        study_profile,
        omics_types,
        differentialRnaseqCounts,
        differentialAtacseqCounts,
        baseline_condition,
        response_condition,
        baseline_timepoint,
        response_timepoint,
        min_count,
        min_total_count,
        min_samples_per_group,
        alpha,
        differential_force_fallback
    )

    ALL_ORTHOLOGY_PROJECTION(
        differentialOmicsSamplesheet,
        orthologous_genes,
        orthologous_res,
        omics_types,
        differentialRnaseqCounts,
        differentialAtacseqCounts,
        ALL_DIFFERENTIAL_OMICS.out.rnaseq_results,
        ALL_DIFFERENTIAL_OMICS.out.atacseq_results
    )

    ALL_GRA_ANALYSIS(
        differentialOmicsSamplesheet,
        re_to_gene_links,
        ALL_ORTHOLOGY_PROJECTION.out.gene_counts,
        ALL_ORTHOLOGY_PROJECTION.out.re_counts,
        ALL_ORTHOLOGY_PROJECTION.out.feature_map,
        ALL_ORTHOLOGY_PROJECTION.out.differential_expression,
        ALL_ORTHOLOGY_PROJECTION.out.differential_accessibility,
        study_profile,
        baseline_condition,
        response_condition,
        baseline_timepoint,
        response_timepoint,
        gra_activity_aggregation,
        min_count,
        min_total_count,
        min_samples_per_group,
        alpha,
        differential_force_fallback
    )

    ALL_PHENOTYPE_OMICS_INTEGRATION(
        ALL_PHENOTYPE_RESPONSE.out.index_contrasts,
        ALL_PHENOTYPE_RESPONSE.out.component_contrasts,
        ALL_ORTHOLOGY_PROJECTION.out.differential_expression,
        ALL_ORTHOLOGY_PROJECTION.out.differential_accessibility,
        ALL_GRA_ANALYSIS.out.differential,
        species_traits,
        phylogeny_manifest,
        study_profile,
        phylogeny_base_dir,
        phenotype_response_metric,
        molecular_response_metric,
        phenotype_response_scope,
        integration_model_types,
        integration_min_species,
        integration_cluster_method,
        species_pairs
    )

    ALL_CANDIDATE_PRIORITIZATION(
        ALL_PHENOTYPE_RESPONSE.out.index_contrasts,
        ALL_PHYLO_HYPOTHESIS.out.hypothesis_results,
        ALL_ORTHOLOGY_PROJECTION.out.differential_expression,
        ALL_ORTHOLOGY_PROJECTION.out.differential_accessibility,
        ALL_GRA_ANALYSIS.out.differential,
        ALL_GRA_ANALYSIS.out.architectures,
        ALL_GRA_ANALYSIS.out.membership,
        ALL_ORTHOLOGY_PROJECTION.out.feature_map,
        ALL_PHENOTYPE_OMICS_INTEGRATION.out.association_expression,
        ALL_PHENOTYPE_OMICS_INTEGRATION.out.association_accessibility,
        ALL_PHENOTYPE_OMICS_INTEGRATION.out.association_gra,
        ALL_PHENOTYPE_OMICS_INTEGRATION.out.response_clusters_expression,
        ALL_PHENOTYPE_OMICS_INTEGRATION.out.response_clusters_accessibility,
        ALL_PHENOTYPE_OMICS_INTEGRATION.out.response_clusters_gra_activity,
        ALL_PHENOTYPE_OMICS_INTEGRATION.out.pairwise_contrasts,
        candidate_scoring_config,
        candidate_linked_evidence_weight,
        candidate_score_cap
    )

    ALL_FUNCTIONAL_INTERPRETATION(
        ALL_CANDIDATE_PRIORITIZATION.out.ranked_genes,
        ALL_CANDIDATE_PRIORITIZATION.out.ranked_res,
        ALL_CANDIDATE_PRIORITIZATION.out.ranked_gras,
        ALL_CANDIDATE_PRIORITIZATION.out.ranked_all,
        ALL_ORTHOLOGY_PROJECTION.out.feature_map,
        ALL_GRA_ANALYSIS.out.architectures,
        ALL_GRA_ANALYSIS.out.membership,
        gene_annotations,
        gene_sets,
        functional_interpretation_top_n,
        functional_interpretation_min_score
    )

    finalReportResultsDir = ALL_FUNCTIONAL_INTERPRETATION.out.manifest.map { results_dir }
    ALL_FINAL_REPORT(study_profile, finalReportResultsDir)

    ALL_RUN_STATUS_AND_SUMMARY(
        ALL_FINAL_REPORT.out.release_status,
        ALL_FINAL_REPORT.out.release_checks,
        ALL_FINAL_REPORT.out.release_summary,
        ALL_FINAL_REPORT.out.report_html,
        ALL_FINAL_REPORT.out.report_markdown,
        results_dir,
        resume_completed_stages
    )

    emit:
    final_report_html = ALL_FINAL_REPORT.out.report_html
    final_report_markdown = ALL_FINAL_REPORT.out.report_markdown
    all_run_summary = ALL_RUN_STATUS_AND_SUMMARY.out.summary
    all_outputs_manifest = ALL_RUN_STATUS_AND_SUMMARY.out.manifest
    all_run_status = ALL_RUN_STATUS_AND_SUMMARY.out.status
}
