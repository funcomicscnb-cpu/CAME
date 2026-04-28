#!/usr/bin/env nextflow

nextflow.enable.dsl = 2

include { PHENOTYPE_RESPONSE } from './workflows/phenotype_response'
include { PHYLO_HYPOTHESIS } from './workflows/phylo_hypothesis'
include { BULK_OMICS } from './workflows/bulk_omics'
include { DIFFERENTIAL_OMICS } from './workflows/differential_omics'
include { ORTHOLOGY_PROJECTION } from './workflows/orthology_projection'
include { GRA_ANALYSIS } from './workflows/gra_analysis'
include { PHENOTYPE_OMICS_INTEGRATION } from './workflows/phenotype_omics_integration'
include { CANDIDATE_PRIORITIZATION } from './workflows/candidate_prioritization'
include { FUNCTIONAL_INTERPRETATION } from './workflows/functional_interpretation'
include { FINAL_REPORT } from './workflows/final_report'
include { REFERENCE_PREPARE } from './workflows/reference_prepare'
include { COORDINATE_PROJECTION } from './workflows/coordinate_projection'
include { RE_TO_GENE_INFERENCE } from './workflows/re_to_gene_inference'
include { ADVANCED_STATISTICS } from './workflows/advanced_statistics'
include { ALL } from './workflows/all'
include { METADATA_VALIDATION; STUDY_PROFILE_VALIDATION; PHYLO_METADATA_VALIDATION } from './subworkflows/validation'

params.phenotype_samplesheet = null
params.omics_samplesheet = null
params.wgs_samplesheet = 'assets/example_samplesheets/wgs_samplesheet.csv'
params.regulatory_regions = 'assets/example_samplesheets/regulatory_regions.tsv'
params.genome_alignment_manifest = 'assets/example_samplesheets/genome_alignment_manifest.tsv'
params.coordinate_projection_config = 'assets/example_samplesheets/coordinate_projection_config.tsv'
params.gene_coordinates = 'assets/example_samplesheets/gene_coordinates.tsv'
params.chromatin_contacts = 'assets/example_samplesheets/chromatin_contacts.tsv'
params.re_to_gene_inference_config = 'assets/example_samplesheets/re_to_gene_inference_config.tsv'
params.advanced_model_config = 'assets/example_samplesheets/advanced_model_config.tsv'
params.species_traits = null
params.reference_manifest = null
params.reference_prepare_config = 'assets/example_samplesheets/reference_prepare_config.tsv'
params.phylogeny_manifest = null
params.study_design = null
params.study_profile = null
params.validate_only = false
params.run_stage = 'validation'
params.normalization = 'none'
params.phylo_model_types = 'lm,pgls_brownian'
params.hypothesis_model_types = ''
params.omics_types = 'rnaseq,atacseq'
params.omics_stub = true
params.reference_stub = true
params.coordinate_projection_stub = true
params.re_to_gene_inference_stub = true
params.advanced_statistics_stub = true
params.rnaseq_counts = null
params.atacseq_counts = null
params.differential_expression = null
params.differential_accessibility = null
params.orthologous_genes = null
params.orthologous_res = null
params.gene_orthogroup_counts = null
params.re_orthogroup_counts = null
params.feature_to_orthogroup_map = null
params.differential_expression_orthogroups = null
params.differential_accessibility_orthogroups = null
params.phenotype_index_contrasts = null
params.component_trait_contrasts = null
params.differential_gra_activity = null
params.hypothesis_model_results = null
params.gene_regulatory_architectures = null
params.gra_re_membership = null
params.phenotype_expression_associations = null
params.phenotype_accessibility_associations = null
params.phenotype_gra_associations = null
params.response_clusters_expression = null
params.response_clusters_accessibility = null
params.response_clusters_gra_activity = null
params.pairwise_species_molecular_contrasts = null
params.candidate_scoring_config = null
params.candidate_genes = null
params.candidate_res = null
params.candidate_gras = null
params.candidate_all = null
params.gene_annotations = 'assets/example_samplesheets/gene_annotations.tsv'
params.gene_sets = 'assets/example_samplesheets/gene_sets.tsv'
params.functional_interpretation_top_n = 50
params.functional_interpretation_min_score = null
params.candidate_linked_evidence_weight = 0.5
params.candidate_score_cap = 50
params.re_to_gene_links = null
params.gra_activity_aggregation = 'mean'
params.phenotype_response_metric = 'difference'
params.molecular_response_metric = 'log2_fold_change'
params.phenotype_response_scope = 'index'
params.integration_model_types = 'lm,pgls_brownian'
params.integration_min_species = 3
params.integration_cluster_method = 'sign'
params.species_pairs = null
params.baseline_condition = null
params.response_condition = null
params.baseline_timepoint = null
params.response_timepoint = null
params.min_count = 10
params.min_total_count = 10
params.min_samples_per_group = 1
params.alpha = 0.05
params.differential_force_fallback = false
params.hmmratac_jar = null
params.resume_completed_stages = true
params.outdir = 'results'

workflow {
    def validateOnly = params.validate_only.toString().toBoolean()
    def allowedStages = ['validation', 'phenotype_response', 'phylo_hypothesis', 'bulk_omics', 'differential_omics', 'orthology_projection', 'gra_analysis', 'phenotype_omics_integration', 'candidate_prioritization', 'functional_interpretation', 'final_report', 'reference_prepare', 'coordinate_projection', 're_to_gene_inference', 'advanced_statistics', 'all']
    if (!allowedStages.contains(params.run_stage)) {
        error "Unsupported --run_stage '${params.run_stage}'. Supported values: ${allowedStages.join(', ')}."
    }
    if (!params.outdir.toString().startsWith('/')) {
        log.warn "CAME: --outdir '${params.outdir}' is a relative path. Outputs will be written relative to the Nextflow launch directory. Use an absolute path to ensure consistent output locations across stages."
    }

    def isAllStage = params.run_stage == 'all'
    def isPhyloStage = params.run_stage == 'phylo_hypothesis'
    def isBulkOmicsStage = params.run_stage == 'bulk_omics'
    def isDifferentialOmicsStage = params.run_stage == 'differential_omics'
    def isOrthologyStage = params.run_stage == 'orthology_projection'
    def isGraStage = params.run_stage == 'gra_analysis'
    def isIntegrationStage = params.run_stage == 'phenotype_omics_integration'
    def isCandidateStage = params.run_stage == 'candidate_prioritization'
    def isFunctionalStage = params.run_stage == 'functional_interpretation'
    def isFinalReportStage = params.run_stage == 'final_report'
    def isReferencePrepareStage = params.run_stage == 'reference_prepare'
    def isCoordinateProjectionStage = params.run_stage == 'coordinate_projection'
    def isReToGeneInferenceStage = params.run_stage == 're_to_gene_inference'
    def isAdvancedStatisticsStage = params.run_stage == 'advanced_statistics'
    def phylogenyManifestPath = params.phylogeny_manifest ? file(params.phylogeny_manifest) : null
    def phylogenyBaseDir = phylogenyManifestPath ? (phylogenyManifestPath.parent ?: '.') : '.'
    def existingIndexByGroup = file("${params.outdir}/phenotype/index/phenotype_index_by_group.tsv")
    def existingIndexContrasts = file("${params.outdir}/phenotype/contrasts/phenotype_index_contrasts.tsv")
    def existingComponentContrasts = file("${params.outdir}/phenotype/contrasts/component_trait_contrasts.tsv")
    def useExistingPhenotypeOutputs = false
    if (isAllStage) {
        if (!params.phenotype_samplesheet || !params.omics_samplesheet || !params.species_traits ||
            !params.reference_manifest || !params.phylogeny_manifest || !params.study_design ||
            !params.study_profile || !params.orthologous_genes || !params.orthologous_res ||
            !params.re_to_gene_links || !params.gene_annotations || !params.gene_sets ||
            !params.candidate_scoring_config) {
            error "Stage all requires --study_profile, --phenotype_samplesheet, --omics_samplesheet, --species_traits, --reference_manifest, --phylogeny_manifest, --study_design, --orthologous_genes, --orthologous_res, --re_to_gene_links, --gene_annotations, --gene_sets, and --candidate_scoring_config."
        }
    } else if (isPhyloStage) {
        if (!params.phenotype_samplesheet || !params.species_traits || !params.phylogeny_manifest || !params.study_profile) {
            error "Stage phylo_hypothesis requires --phenotype_samplesheet, --species_traits, --phylogeny_manifest, and --study_profile."
        }
        if (existingIndexByGroup.exists() && existingIndexContrasts.exists() && existingComponentContrasts.exists()) {
            def profileMatcher = new File(params.study_profile.toString()).text =~ /(?m)^\s*profile_id:\s*["']?([^"'\s#]+)["']?(?:\s*#[^\n]*)?\s*$/
            def requestedProfileId = profileMatcher.find() ? profileMatcher.group(1) : ''
            def indexLines = existingIndexByGroup.readLines()
            def existingProfileId = indexLines.size() > 1 ? indexLines[1].split('\t')[0] : ''
            useExistingPhenotypeOutputs = requestedProfileId && requestedProfileId == existingProfileId
            if (useExistingPhenotypeOutputs) {
                log.info "Using existing Stage 3 phenotype outputs for profile_id '${requestedProfileId}'."
            } else {
                log.info "Existing Stage 3 phenotype outputs are absent or do not match --study_profile; recomputing phenotype_response."
            }
        }
    } else if (isBulkOmicsStage) {
        if (!params.omics_samplesheet || !params.reference_manifest) {
            error "Stage bulk_omics requires --omics_samplesheet and --reference_manifest."
        }
    } else if (isDifferentialOmicsStage) {
        if (!params.omics_samplesheet) {
            error "Stage differential_omics requires --omics_samplesheet."
        }
        def contrastParams = [
            params.baseline_condition,
            params.response_condition,
            params.baseline_timepoint,
            params.response_timepoint
        ]
        def suppliedContrastParams = contrastParams.count { it != null && it.toString().trim() != '' }
        if (suppliedContrastParams > 0 && suppliedContrastParams < 4) {
            error "Stage differential_omics CLI contrast override requires all four of --baseline_condition, --response_condition, --baseline_timepoint, and --response_timepoint."
        }
        if (suppliedContrastParams == 0 && !params.study_profile) {
            error "Stage differential_omics requires --study_profile unless all four CLI contrast override params are supplied."
        }
    } else if (isOrthologyStage) {
        if (!params.omics_samplesheet || !params.orthologous_genes || !params.orthologous_res) {
            error "Stage orthology_projection requires --omics_samplesheet, --orthologous_genes, and --orthologous_res."
        }
    } else if (isGraStage) {
        if (!params.omics_samplesheet || !params.re_to_gene_links) {
            error "Stage gra_analysis requires --omics_samplesheet and --re_to_gene_links."
        }
    } else if (isIntegrationStage) {
        if (!params.study_profile || !params.omics_samplesheet || !params.species_traits || !params.phylogeny_manifest) {
            error "Stage phenotype_omics_integration requires --study_profile, --omics_samplesheet, --species_traits, and --phylogeny_manifest."
        }
    } else if (isCandidateStage) {
        if (!params.study_profile) {
            error "Stage candidate_prioritization requires --study_profile."
        }
        if (!file(params.study_profile).exists()) {
            error "Stage candidate_prioritization could not find study_profile at '${params.study_profile}'."
        }
    } else if (isFunctionalStage) {
        def candidateGenesFile = params.candidate_genes ? file(params.candidate_genes) : file("${params.outdir}/candidates/ranked/candidate_genes_ranked.tsv")
        def candidateResFile = params.candidate_res ? file(params.candidate_res) : file("${params.outdir}/candidates/ranked/candidate_res_ranked.tsv")
        def candidateGrasFile = params.candidate_gras ? file(params.candidate_gras) : file("${params.outdir}/candidates/ranked/candidate_gras_ranked.tsv")
        def candidateAllFile = params.candidate_all ? file(params.candidate_all) : file("${params.outdir}/candidates/ranked/candidate_all_ranked.tsv")
        def featureMapFile = params.feature_to_orthogroup_map ? file(params.feature_to_orthogroup_map) : file("${params.outdir}/orthology/feature_to_orthogroup_map.tsv")
        def geneRegulatoryArchitecturesFile = params.gene_regulatory_architectures ? file(params.gene_regulatory_architectures) : file("${params.outdir}/gra/tables/gene_regulatory_architectures.tsv")
        def graReMembershipFile = params.gra_re_membership ? file(params.gra_re_membership) : file("${params.outdir}/gra/tables/gra_re_membership.tsv")
        def geneAnnotationsFile = params.gene_annotations ? file(params.gene_annotations) : null
        def geneSetsFile = params.gene_sets ? file(params.gene_sets) : null
        def requiredStage11Inputs = [
            'candidate_genes': candidateGenesFile,
            'candidate_res': candidateResFile,
            'candidate_gras': candidateGrasFile,
            'candidate_all': candidateAllFile,
            'feature_to_orthogroup_map': featureMapFile,
            'gene_regulatory_architectures': geneRegulatoryArchitecturesFile,
            'gra_re_membership': graReMembershipFile,
            'gene_annotations': geneAnnotationsFile,
            'gene_sets': geneSetsFile
        ]
        requiredStage11Inputs.each { label, path ->
            if (!path || !path.exists()) {
                error "Stage functional_interpretation could not find required input ${label} at '${path ?: ''}'. Run upstream stages first with the same --outdir or provide --${label}."
            }
        }
    } else if (isFinalReportStage) {
        if (!params.study_profile) {
            error "Stage final_report requires --study_profile."
        }
        if (!file(params.study_profile).exists()) {
            error "Stage final_report could not find study_profile at '${params.study_profile}'."
        }
    } else if (isReferencePrepareStage) {
        if (!params.wgs_samplesheet || !params.reference_manifest || !params.reference_prepare_config) {
            error "Stage reference_prepare requires --wgs_samplesheet, --reference_manifest, and --reference_prepare_config."
        }
    } else if (isCoordinateProjectionStage) {
        if (!params.regulatory_regions || !params.genome_alignment_manifest || !params.coordinate_projection_config) {
            error "Stage coordinate_projection requires --regulatory_regions, --genome_alignment_manifest, and --coordinate_projection_config."
        }
    } else if (isReToGeneInferenceStage) {
        if (!params.regulatory_regions || !params.gene_coordinates || !params.re_to_gene_inference_config) {
            error "Stage re_to_gene_inference requires --regulatory_regions, --gene_coordinates, and --re_to_gene_inference_config."
        }
    } else if (isAdvancedStatisticsStage) {
        if (!params.advanced_model_config) {
            error "Stage advanced_statistics requires --advanced_model_config."
        }
        if (!file(params.advanced_model_config).exists()) {
            error "Stage advanced_statistics could not find advanced_model_config at '${params.advanced_model_config}'."
        }
    } else if (!params.phenotype_samplesheet || !params.omics_samplesheet || !params.species_traits ||
        !params.reference_manifest || !params.phylogeny_manifest || !params.study_design) {
        error "Missing metadata input. Provide --phenotype_samplesheet, --omics_samplesheet, --species_traits, --reference_manifest, --phylogeny_manifest, and --study_design."
    }

    def hasFullMetadata = params.phenotype_samplesheet && params.omics_samplesheet && params.species_traits &&
        params.reference_manifest && params.phylogeny_manifest && params.study_design
    def metadataReport
    if (!isAllStage && !isReferencePrepareStage && !isCoordinateProjectionStage && !isReToGeneInferenceStage && !isAdvancedStatisticsStage && hasFullMetadata) {
        METADATA_VALIDATION(
            file(params.phenotype_samplesheet),
            file(params.omics_samplesheet),
            file(params.species_traits),
            file(params.reference_manifest),
            file(params.phylogeny_manifest),
            file(params.study_design)
        )
        metadataReport = METADATA_VALIDATION.out.report
    } else if (!isAllStage && !isBulkOmicsStage && !isDifferentialOmicsStage && !isOrthologyStage && !isGraStage && !isIntegrationStage && !isCandidateStage && !isFunctionalStage && !isFinalReportStage && !isReferencePrepareStage && !isCoordinateProjectionStage && !isReToGeneInferenceStage && !isAdvancedStatisticsStage) {
        PHYLO_METADATA_VALIDATION(
            file(params.phenotype_samplesheet),
            file(params.species_traits),
            file(params.phylogeny_manifest)
        )
        metadataReport = PHYLO_METADATA_VALIDATION.out.report
    } else if (isAllStage) {
        log.info "Stage all performs metadata and study profile validation inside the end-to-end workflow."
    } else {
        log.info "Skipping full Stage 1 metadata validation for ${params.run_stage} because only downstream inputs were provided."
    }

    if (!isAllStage && params.study_profile && !isBulkOmicsStage && !isDifferentialOmicsStage && !isOrthologyStage && !isGraStage && !isIntegrationStage && !isCandidateStage && !isFunctionalStage && !isFinalReportStage && !isReferencePrepareStage && !isCoordinateProjectionStage && !isReToGeneInferenceStage && !isAdvancedStatisticsStage) {
        STUDY_PROFILE_VALIDATION(
            file(params.study_profile),
            file(params.phenotype_samplesheet),
            file(params.species_traits)
        )
    }

    if (params.run_stage in ['phenotype_response', 'phylo_hypothesis'] && !params.study_profile) {
        error "Stage ${params.run_stage} requires --study_profile."
    }

    if (params.run_stage == 'all' && !validateOnly) {
        def functionalMinScore = params.functional_interpretation_min_score != null ? params.functional_interpretation_min_score.toString() : ''
        ALL(
            file(params.phenotype_samplesheet),
            file(params.omics_samplesheet),
            file(params.species_traits),
            file(params.reference_manifest),
            file(params.phylogeny_manifest),
            file(params.study_design),
            file(params.study_profile),
            file(params.outdir).toString(),
            phylogenyBaseDir.toString(),
            params.normalization,
            params.phylo_model_types,
            params.hypothesis_model_types,
            params.omics_types,
            params.omics_stub,
            params.baseline_condition ?: '',
            params.response_condition ?: '',
            params.baseline_timepoint ?: '',
            params.response_timepoint ?: '',
            params.min_count,
            params.min_total_count,
            params.min_samples_per_group,
            params.alpha,
            params.differential_force_fallback,
            file(params.orthologous_genes),
            file(params.orthologous_res),
            file(params.re_to_gene_links),
            file(params.gene_annotations),
            file(params.gene_sets),
            file(params.candidate_scoring_config).toString(),
            params.candidate_linked_evidence_weight,
            params.candidate_score_cap,
            params.gra_activity_aggregation,     // workflow param: aggregation
            params.phenotype_response_metric,
            params.molecular_response_metric,
            params.phenotype_response_scope,
            params.integration_model_types,       // workflow param: model_types
            params.integration_min_species,       // workflow param: min_species
            params.integration_cluster_method,
            params.species_pairs ?: '',
            params.functional_interpretation_top_n,
            functionalMinScore,
            params.resume_completed_stages
        )
    } else if (params.run_stage == 'bulk_omics' && !validateOnly) {
        BULK_OMICS(
            file(params.omics_samplesheet),
            file(params.reference_manifest),
            params.omics_types,
            params.omics_stub
        )
    } else if (params.run_stage == 'reference_prepare' && !validateOnly) {
        REFERENCE_PREPARE(
            file(params.wgs_samplesheet),
            file(params.reference_manifest),
            file(params.reference_prepare_config),
            params.reference_stub
        )
    } else if (params.run_stage == 'coordinate_projection' && !validateOnly) {
        COORDINATE_PROJECTION(
            file(params.regulatory_regions),
            file(params.genome_alignment_manifest),
            file(params.coordinate_projection_config),
            params.coordinate_projection_stub
        )
    } else if (params.run_stage == 're_to_gene_inference' && !validateOnly) {
        RE_TO_GENE_INFERENCE(
            file(params.regulatory_regions),
            file(params.gene_coordinates),
            params.chromatin_contacts ? file(params.chromatin_contacts).toString() : '',
            file(params.re_to_gene_inference_config),
            params.re_to_gene_inference_stub
        )
    } else if (params.run_stage == 'advanced_statistics' && !validateOnly) {
        def advancedPhenotypeIndexContrasts = params.phenotype_index_contrasts ? file(params.phenotype_index_contrasts).toString() : ''
        def advancedComponentTraitContrasts = params.component_trait_contrasts ? file(params.component_trait_contrasts).toString() : ''
        def advancedHypothesisModelTable = file("${params.outdir}/phylo/input/hypothesis_model_table.tsv")
        def advancedHypothesisModelResults = params.hypothesis_model_results ? file(params.hypothesis_model_results).toString() : ''
        def advancedPhenotypeOmicsModelTable = file("${params.outdir}/integration/input/phenotype_omics_model_table.tsv")
        ADVANCED_STATISTICS(
            file(params.advanced_model_config),
            file(params.outdir).toString(),
            params.species_traits ? file(params.species_traits).toString() : '',
            params.phylogeny_manifest ? file(params.phylogeny_manifest).toString() : '',
            advancedPhenotypeIndexContrasts,
            advancedComponentTraitContrasts,
            advancedHypothesisModelTable.toString(),
            advancedHypothesisModelResults,
            advancedPhenotypeOmicsModelTable.toString(),
            params.advanced_statistics_stub
        )
    } else if (params.run_stage == 'differential_omics' && !validateOnly) {
        def requestedOmicsTypes = params.omics_types.toString().split(',').collect { it.trim().toLowerCase() }.findAll { it }
        def rnaseqCountsFile = params.rnaseq_counts ? file(params.rnaseq_counts) : file("${params.outdir}/rnaseq/counts/gene_counts.tsv")
        def atacseqCountsFile = params.atacseq_counts ? file(params.atacseq_counts) : file("${params.outdir}/atacseq/counts/re_counts.tsv")
        if (requestedOmicsTypes.contains('rnaseq') && !rnaseqCountsFile.exists()) {
            error "Stage differential_omics could not find RNA-seq counts at '${rnaseqCountsFile}'. Run --run_stage bulk_omics first with the same --outdir or provide --rnaseq_counts."
        }
        if (requestedOmicsTypes.contains('atacseq') && !atacseqCountsFile.exists()) {
            error "Stage differential_omics could not find ATAC-seq counts at '${atacseqCountsFile}'. Run --run_stage bulk_omics first with the same --outdir or provide --atacseq_counts."
        }
        DIFFERENTIAL_OMICS(
            file(params.omics_samplesheet),
            params.study_profile ? file(params.study_profile).toString() : '',
            params.omics_types,
            requestedOmicsTypes.contains('rnaseq') ? rnaseqCountsFile.toString() : '',
            requestedOmicsTypes.contains('atacseq') ? atacseqCountsFile.toString() : '',
            params.baseline_condition ?: '',
            params.response_condition ?: '',
            params.baseline_timepoint ?: '',
            params.response_timepoint ?: '',
            params.min_count,
            params.min_total_count,
            params.min_samples_per_group,
            params.alpha,
            params.differential_force_fallback
        )
    } else if (params.run_stage == 'orthology_projection' && !validateOnly) {
        def requestedOmicsTypes = params.omics_types.toString().split(',').collect { it.trim().toLowerCase() }.findAll { it }
        def rnaseqCountsFile = params.rnaseq_counts ? file(params.rnaseq_counts) : file("${params.outdir}/rnaseq/counts/gene_counts.tsv")
        def atacseqCountsFile = params.atacseq_counts ? file(params.atacseq_counts) : file("${params.outdir}/atacseq/counts/re_counts.tsv")
        def differentialExpressionFile = params.differential_expression ? file(params.differential_expression) : file("${params.outdir}/differential_omics/rnaseq/differential_results.tsv")
        def differentialAccessibilityFile = params.differential_accessibility ? file(params.differential_accessibility) : file("${params.outdir}/differential_omics/atacseq/differential_results.tsv")
        if (requestedOmicsTypes.contains('rnaseq') && !rnaseqCountsFile.exists()) {
            error "Stage orthology_projection could not find RNA-seq counts at '${rnaseqCountsFile}'. Run --run_stage bulk_omics first with the same --outdir or provide --rnaseq_counts."
        }
        if (requestedOmicsTypes.contains('atacseq') && !atacseqCountsFile.exists()) {
            error "Stage orthology_projection could not find ATAC-seq counts at '${atacseqCountsFile}'. Run --run_stage bulk_omics first with the same --outdir or provide --atacseq_counts."
        }
        if (params.differential_expression && !differentialExpressionFile.exists()) {
            error "Stage orthology_projection could not find explicitly supplied differential expression table at '${differentialExpressionFile}'."
        }
        if (params.differential_accessibility && !differentialAccessibilityFile.exists()) {
            error "Stage orthology_projection could not find explicitly supplied differential accessibility table at '${differentialAccessibilityFile}'."
        }
        ORTHOLOGY_PROJECTION(
            file(params.omics_samplesheet),
            file(params.orthologous_genes),
            file(params.orthologous_res),
            params.omics_types,
            requestedOmicsTypes.contains('rnaseq') ? rnaseqCountsFile.toString() : '',
            requestedOmicsTypes.contains('atacseq') ? atacseqCountsFile.toString() : '',
            differentialExpressionFile.exists() ? differentialExpressionFile.toString() : '',
            differentialAccessibilityFile.exists() ? differentialAccessibilityFile.toString() : ''
        )
    } else if (params.run_stage == 'gra_analysis' && !validateOnly) {
        def geneOrthogroupCountsFile = params.gene_orthogroup_counts ? file(params.gene_orthogroup_counts) : file("${params.outdir}/orthology/gene_orthogroup_counts.tsv")
        def reOrthogroupCountsFile = params.re_orthogroup_counts ? file(params.re_orthogroup_counts) : file("${params.outdir}/orthology/re_orthogroup_counts.tsv")
        def featureMapFile = params.feature_to_orthogroup_map ? file(params.feature_to_orthogroup_map) : file("${params.outdir}/orthology/feature_to_orthogroup_map.tsv")
        def differentialExpressionOrthogroupsFile = params.differential_expression_orthogroups ? file(params.differential_expression_orthogroups) : file("${params.outdir}/orthology/differential_expression_orthogroups.tsv")
        def differentialAccessibilityOrthogroupsFile = params.differential_accessibility_orthogroups ? file(params.differential_accessibility_orthogroups) : file("${params.outdir}/orthology/differential_accessibility_orthogroups.tsv")
        def requiredStage7Outputs = [
            'gene_orthogroup_counts': geneOrthogroupCountsFile,
            're_orthogroup_counts': reOrthogroupCountsFile,
            'feature_to_orthogroup_map': featureMapFile,
            'differential_expression_orthogroups': differentialExpressionOrthogroupsFile,
            'differential_accessibility_orthogroups': differentialAccessibilityOrthogroupsFile
        ]
        requiredStage7Outputs.each { label, path ->
            if (!path.exists()) {
                error "Stage gra_analysis could not find Stage 7 output ${label} at '${path}'. Run --run_stage orthology_projection first with the same --outdir or provide --${label}."
            }
        }
        GRA_ANALYSIS(
            file(params.omics_samplesheet),
            file(params.re_to_gene_links),
            geneOrthogroupCountsFile,
            reOrthogroupCountsFile,
            featureMapFile,
            differentialExpressionOrthogroupsFile,
            differentialAccessibilityOrthogroupsFile,
            params.study_profile ? file(params.study_profile).toString() : '',
            params.baseline_condition ?: '',
            params.response_condition ?: '',
            params.baseline_timepoint ?: '',
            params.response_timepoint ?: '',
            params.gra_activity_aggregation,      // workflow param: aggregation
            params.min_count,
            params.min_total_count,
            params.min_samples_per_group,
            params.alpha,
            params.differential_force_fallback
        )
    } else if (params.run_stage == 'phenotype_omics_integration' && !validateOnly) {
        def phenotypeIndexContrastsFile = params.phenotype_index_contrasts ? file(params.phenotype_index_contrasts) : file("${params.outdir}/phenotype/contrasts/phenotype_index_contrasts.tsv")
        def componentTraitContrastsFile = params.component_trait_contrasts ? file(params.component_trait_contrasts) : file("${params.outdir}/phenotype/contrasts/component_trait_contrasts.tsv")
        def differentialExpressionOrthogroupsFile = params.differential_expression_orthogroups ? file(params.differential_expression_orthogroups) : file("${params.outdir}/orthology/differential_expression_orthogroups.tsv")
        def differentialAccessibilityOrthogroupsFile = params.differential_accessibility_orthogroups ? file(params.differential_accessibility_orthogroups) : file("${params.outdir}/orthology/differential_accessibility_orthogroups.tsv")
        def differentialGraActivityFile = params.differential_gra_activity ? file(params.differential_gra_activity) : file("${params.outdir}/gra/differential/differential_gra_activity.tsv")
        def requiredStage9Inputs = [
            'phenotype_index_contrasts': phenotypeIndexContrastsFile,
            'component_trait_contrasts': componentTraitContrastsFile,
            'differential_expression_orthogroups': differentialExpressionOrthogroupsFile,
            'differential_accessibility_orthogroups': differentialAccessibilityOrthogroupsFile,
            'differential_gra_activity': differentialGraActivityFile
        ]
        requiredStage9Inputs.each { label, path ->
            if (!path.exists()) {
                error "Stage phenotype_omics_integration could not find required upstream output ${label} at '${path}'. Run the required upstream stages first with the same --outdir or provide --${label}."
            }
        }
        if (params.species_pairs && !file(params.species_pairs).exists()) {
            error "Stage phenotype_omics_integration could not find species_pairs at '${params.species_pairs}'."
        }
        PHENOTYPE_OMICS_INTEGRATION(
            phenotypeIndexContrastsFile,
            componentTraitContrastsFile,
            differentialExpressionOrthogroupsFile,
            differentialAccessibilityOrthogroupsFile,
            differentialGraActivityFile,
            file(params.species_traits),
            file(params.phylogeny_manifest),
            file(params.study_profile),
            phylogenyBaseDir.toString(),
            params.phenotype_response_metric,
            params.molecular_response_metric,
            params.phenotype_response_scope,
            params.integration_model_types,       // workflow param: model_types
            params.integration_min_species,       // workflow param: min_species
            params.integration_cluster_method,
            params.species_pairs ?: ''
        )
    } else if (params.run_stage == 'candidate_prioritization' && !validateOnly) {
        def phenotypeIndexContrastsFile = params.phenotype_index_contrasts ? file(params.phenotype_index_contrasts) : file("${params.outdir}/phenotype/contrasts/phenotype_index_contrasts.tsv")
        def hypothesisModelResultsFile = params.hypothesis_model_results ? file(params.hypothesis_model_results) : file("${params.outdir}/hypotheses/hypothesis_model_results.tsv")
        def differentialExpressionCandidatesFile = params.differential_expression_orthogroups ? file(params.differential_expression_orthogroups) : (params.differential_expression ? file(params.differential_expression) : file("${params.outdir}/orthology/differential_expression_orthogroups.tsv"))
        def differentialAccessibilityCandidatesFile = params.differential_accessibility_orthogroups ? file(params.differential_accessibility_orthogroups) : (params.differential_accessibility ? file(params.differential_accessibility) : file("${params.outdir}/orthology/differential_accessibility_orthogroups.tsv"))
        def differentialGraActivityFile = params.differential_gra_activity ? file(params.differential_gra_activity) : file("${params.outdir}/gra/differential/differential_gra_activity.tsv")
        def geneRegulatoryArchitecturesFile = params.gene_regulatory_architectures ? file(params.gene_regulatory_architectures) : file("${params.outdir}/gra/tables/gene_regulatory_architectures.tsv")
        def graReMembershipFile = params.gra_re_membership ? file(params.gra_re_membership) : file("${params.outdir}/gra/tables/gra_re_membership.tsv")
        def featureMapFile = params.feature_to_orthogroup_map ? file(params.feature_to_orthogroup_map) : file("${params.outdir}/orthology/feature_to_orthogroup_map.tsv")
        def phenotypeExpressionAssociationsFile = params.phenotype_expression_associations ? file(params.phenotype_expression_associations) : file("${params.outdir}/integration/associations/phenotype_expression_associations.tsv")
        def phenotypeAccessibilityAssociationsFile = params.phenotype_accessibility_associations ? file(params.phenotype_accessibility_associations) : file("${params.outdir}/integration/associations/phenotype_accessibility_associations.tsv")
        def phenotypeGraAssociationsFile = params.phenotype_gra_associations ? file(params.phenotype_gra_associations) : file("${params.outdir}/integration/associations/phenotype_gra_associations.tsv")
        def responseClustersExpressionFile = params.response_clusters_expression ? file(params.response_clusters_expression) : file("${params.outdir}/integration/clustering/response_clusters_expression.tsv")
        def responseClustersAccessibilityFile = params.response_clusters_accessibility ? file(params.response_clusters_accessibility) : file("${params.outdir}/integration/clustering/response_clusters_accessibility.tsv")
        def responseClustersGraActivityFile = params.response_clusters_gra_activity ? file(params.response_clusters_gra_activity) : file("${params.outdir}/integration/clustering/response_clusters_gra_activity.tsv")
        def pairwiseSpeciesMolecularContrastsFile = params.pairwise_species_molecular_contrasts ? file(params.pairwise_species_molecular_contrasts) : file("${params.outdir}/integration/pairwise/pairwise_species_molecular_contrasts.tsv")
        def defaultCandidateScoringConfig = file("${projectDir}/assets/example_samplesheets/candidate_scoring_config.tsv")
        def candidateScoringConfigFile = params.candidate_scoring_config ? file(params.candidate_scoring_config) : defaultCandidateScoringConfig
        def candidateScoringConfigPath = params.candidate_scoring_config ? candidateScoringConfigFile.toString() : (candidateScoringConfigFile.exists() ? candidateScoringConfigFile.toString() : '')
        CANDIDATE_PRIORITIZATION(
            phenotypeIndexContrastsFile.toString(),
            hypothesisModelResultsFile.toString(),
            differentialExpressionCandidatesFile.toString(),
            differentialAccessibilityCandidatesFile.toString(),
            differentialGraActivityFile.toString(),
            geneRegulatoryArchitecturesFile.toString(),
            graReMembershipFile.toString(),
            featureMapFile.toString(),
            phenotypeExpressionAssociationsFile.toString(),
            phenotypeAccessibilityAssociationsFile.toString(),
            phenotypeGraAssociationsFile.toString(),
            responseClustersExpressionFile.toString(),
            responseClustersAccessibilityFile.toString(),
            responseClustersGraActivityFile.toString(),
            pairwiseSpeciesMolecularContrastsFile.toString(),
            candidateScoringConfigPath,
            params.candidate_linked_evidence_weight,
            params.candidate_score_cap
        )
    } else if (params.run_stage == 'functional_interpretation' && !validateOnly) {
        def candidateGenesFile = params.candidate_genes ? file(params.candidate_genes) : file("${params.outdir}/candidates/ranked/candidate_genes_ranked.tsv")
        def candidateResFile = params.candidate_res ? file(params.candidate_res) : file("${params.outdir}/candidates/ranked/candidate_res_ranked.tsv")
        def candidateGrasFile = params.candidate_gras ? file(params.candidate_gras) : file("${params.outdir}/candidates/ranked/candidate_gras_ranked.tsv")
        def candidateAllFile = params.candidate_all ? file(params.candidate_all) : file("${params.outdir}/candidates/ranked/candidate_all_ranked.tsv")
        def featureMapFile = params.feature_to_orthogroup_map ? file(params.feature_to_orthogroup_map) : file("${params.outdir}/orthology/feature_to_orthogroup_map.tsv")
        def geneRegulatoryArchitecturesFile = params.gene_regulatory_architectures ? file(params.gene_regulatory_architectures) : file("${params.outdir}/gra/tables/gene_regulatory_architectures.tsv")
        def graReMembershipFile = params.gra_re_membership ? file(params.gra_re_membership) : file("${params.outdir}/gra/tables/gra_re_membership.tsv")
        def functionalMinScore = params.functional_interpretation_min_score != null ? params.functional_interpretation_min_score.toString() : ''
        FUNCTIONAL_INTERPRETATION(
            candidateGenesFile,
            candidateResFile,
            candidateGrasFile,
            candidateAllFile,
            featureMapFile,
            geneRegulatoryArchitecturesFile,
            graReMembershipFile,
            file(params.gene_annotations),
            file(params.gene_sets),
            params.functional_interpretation_top_n,
            functionalMinScore
        )
    } else if (params.run_stage == 'final_report' && !validateOnly) {
        FINAL_REPORT(
            file(params.study_profile),
            file(params.outdir).toString()
        )
    } else if (params.run_stage == 'phenotype_response' && !validateOnly) {
        PHENOTYPE_RESPONSE(
            file(params.phenotype_samplesheet),
            file(params.study_profile),
            params.normalization,
            metadataReport,
            STUDY_PROFILE_VALIDATION.out.report
        )
    } else if (params.run_stage == 'phylo_hypothesis' && !validateOnly) {
        if (useExistingPhenotypeOutputs) {
            PHYLO_HYPOTHESIS(
                file(params.species_traits),
                file(params.phylogeny_manifest),
                file(params.study_profile),
                existingIndexByGroup,
                existingIndexContrasts,
                existingComponentContrasts,
                metadataReport,
                STUDY_PROFILE_VALIDATION.out.report,
                phylogenyBaseDir.toString(),
                params.phylo_model_types,
                params.hypothesis_model_types
            )
        } else {
            PHENOTYPE_RESPONSE(
                file(params.phenotype_samplesheet),
                file(params.study_profile),
                params.normalization,
                metadataReport,
                STUDY_PROFILE_VALIDATION.out.report
            )
            PHYLO_HYPOTHESIS(
                file(params.species_traits),
                file(params.phylogeny_manifest),
                file(params.study_profile),
                PHENOTYPE_RESPONSE.out.index_by_group,
                PHENOTYPE_RESPONSE.out.index_contrasts,
                PHENOTYPE_RESPONSE.out.component_contrasts,
                metadataReport,
                STUDY_PROFILE_VALIDATION.out.report,
                phylogenyBaseDir.toString(),
                params.phylo_model_types,
                params.hypothesis_model_types
            )
        }
    } else if (!validateOnly) {
        log.info "CAME currently runs metadata and optional study profile validation only. Set --validate_only true to make this explicit."
    }
}
