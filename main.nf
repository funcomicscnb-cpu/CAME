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
include { WGS_VARIANTS } from './workflows/wgs_variants'
include { COORDINATE_PROJECTION } from './workflows/coordinate_projection'
include { ORTHOLOGY_REFERENCE_PREPARE } from './workflows/orthology_reference_prepare'
include { RE_TO_GENE_INFERENCE } from './workflows/re_to_gene_inference'
include { ADVANCED_STATISTICS } from './workflows/advanced_statistics'
include { CEEG_COMPATIBILITY } from './workflows/ceeg_compatibility'
include { ALL } from './workflows/all'
include { METADATA_VALIDATION; STUDY_PROFILE_VALIDATION; PHYLO_METADATA_VALIDATION; REAL_MODE_REQUIREMENTS_VALIDATION } from './subworkflows/validation'
include { REFERENCE_QUALITY } from './subworkflows/reference_quality'

params.phenotype_samplesheet = null
params.omics_samplesheet = null
params.wgs_samplesheet = 'assets/example_samplesheets/wgs_samplesheet.csv'
params.wgs_mode = 'stub'
params.wgs_variant_mode = 'haplotypecaller'
params.wgs_calling_mode = 'per_sample'
params.wgs_filtering_mode = 'hard_filter'
params.require_known_sites = false
params.allow_no_bqsr = true
params.regulatory_regions = 'assets/example_samplesheets/regulatory_regions.tsv'
params.genome_alignment_manifest = 'assets/example_samplesheets/genome_alignment_manifest.tsv'
params.coordinate_projection_config = 'assets/example_samplesheets/coordinate_projection_config.tsv'
params.orthology_reference_bundle_manifest = null
params.orthology_reference_prepare_stub = true
params.orthology_reference_prepare_cmd = null
params.orthology_reference_prepare_run_dir = null
params.orthology_reference_prepare_created_at = null
params.orthology_reference_prepare_check_paths = true
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
params.enable_real_mode_validation = false
params.real_mode_metadata = null
params.validate_only = false
params.run_stage = 'validation'
params.normalization = 'none'
params.phylo_model_types = 'lm,pgls_brownian'
params.hypothesis_model_types = ''
params.omics_types = 'rnaseq,atacseq'
params.omics_mode = null
params.rna_backend = 'star'
params.atac_backend = 'bowtie2'
params.peak_caller = 'macs3'
params.atac_replicate_concordance = 'none'
params.container_image = null
params.came_version = params.came_version ?: (new File('VERSION').exists() ? new File('VERSION').text.trim() : '0.1.0')
params.default_container_image = params.default_container_image ?: "ghcr.io/funcomicscnb-cpu/came:${params.came_version}"
params.list_stages = false
params.real_fail_on_missing_tools = true
params.real_require_paired_atac = false
params.threads = 8
params.max_memory = '16 GB'
params.reference_cache_dir = null
params.check_paths = false
params.reference_quality_strict = false
params.allow_low_quality_reference = false
params.reference_quality_assay = 'rna,atac'
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
params.pgls_min_species = 6
params.integration_min_species = null
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
params.slurm_queue = ''
params.slurm_queue_high = ''
params.slurm_account = ''
params.outdir = 'results'
params.ceeg_model_bundle             = null
params.enable_ceeg_compatibility     = false
params.ceeg_stub                     = false
params.ceeg_r2_overlay_dir           = null
params.ceeg_r3_mapping_dir           = null
params.ceeg_validation_mode          = 'development'
params.ceeg_fail_on_contract_error   = true
params.ceeg_run_came_overlay_cmd     = null
params.ceeg_run_mapping_contract_cmd = null
params.ceeg_r2_run_dir               = null
params.ceeg_r3_run_dir               = null
params.ceeg_orchestrate_contracts    = false
params.ceeg_validator_created_at     = null
params.ceeg_r4_comparability_dir     = null
params.comparability_mode            = 'design_assumed'

workflow {
    def stageCatalog = [
        [run_stage: 'validation', maturity: 'validation', included_in_all: false, real_mode_scope: 'metadata and real-mode preflight', notes: 'Validates metadata, profiles, and optional real-mode requirements'],
        [run_stage: 'phenotype_response', maturity: 'production', included_in_all: true, real_mode_scope: 'not assay-specific', notes: 'Phenotype processing'],
        [run_stage: 'phylo_hypothesis', maturity: 'production', included_in_all: true, real_mode_scope: 'not assay-specific', notes: 'LM/PGLS hypothesis testing'],
        [run_stage: 'bulk_omics', maturity: 'production', included_in_all: true, real_mode_scope: 'RNA-seq and ATAC-seq', notes: 'Stub or real RNA/ATAC bulk omics'],
        [run_stage: 'differential_omics', maturity: 'production', included_in_all: true, real_mode_scope: 'RNA-seq and ATAC-seq counts', notes: 'Differential expression/accessibility'],
        [run_stage: 'orthology_projection', maturity: 'production', included_in_all: true, real_mode_scope: 'precomputed orthology', notes: 'Projects features to orthogroups'],
        [run_stage: 'gra_analysis', maturity: 'production', included_in_all: true, real_mode_scope: 'promoter-proximity links', notes: 'Gene regulatory architecture analysis'],
        [run_stage: 'phenotype_omics_integration', maturity: 'production', included_in_all: true, real_mode_scope: 'summary tables', notes: 'Phenotype-omics association models'],
        [run_stage: 'candidate_prioritization', maturity: 'production', included_in_all: true, real_mode_scope: 'summary tables', notes: 'Candidate ranking'],
        [run_stage: 'functional_interpretation', maturity: 'production', included_in_all: true, real_mode_scope: 'summary tables', notes: 'Gene-set interpretation'],
        [run_stage: 'final_report', maturity: 'production', included_in_all: true, real_mode_scope: 'reporting', notes: 'Final HTML/Markdown report'],
        [run_stage: 'reference_prepare', maturity: 'scaffold', included_in_all: false, real_mode_scope: 'reference assets', notes: 'Optional scaffold; not production reference preparation'],
        [run_stage: 'wgs_variants', maturity: 'production', included_in_all: false, real_mode_scope: 'WGS per-sample SNP/indel calling', notes: 'Optional; per-sample only, no joint genotyping'],
        [run_stage: 'reference_quality', maturity: 'production', included_in_all: false, real_mode_scope: 'reference assets', notes: 'Optional reference-quality validation'],
        [run_stage: 'coordinate_projection', maturity: 'basic', included_in_all: false, real_mode_scope: 'reciprocal-best orthologous regions', notes: 'Optional; basic reciprocal-best lift-over orthology, requires external lift-over tools in real mode'],
        [run_stage: 'orthology_reference_prepare', maturity: 'basic', included_in_all: false, real_mode_scope: 'orthology reference bundle', notes: 'Optional; orchestrates external reciprocal-best bundle generation and validates the emitted manifest'],
        [run_stage: 're_to_gene_inference', maturity: 'scaffold', included_in_all: false, real_mode_scope: 'regulatory links', notes: 'Optional scaffold; not production RE-to-gene inference'],
        [run_stage: 'advanced_statistics', maturity: 'scaffold', included_in_all: false, real_mode_scope: 'advanced models', notes: 'Optional scaffold; not production advanced statistics'],
        [run_stage: 'ceeg_compatibility', maturity: 'scaffold', included_in_all: false, real_mode_scope: 'CEEG model bundle', notes: 'Optional CEEG contract artifact consumption interface; requires --ceeg_model_bundle'],
        [run_stage: 'all', maturity: 'orchestration', included_in_all: false, real_mode_scope: 'stub/real as configured', notes: 'Runs the core production chain; excludes optional/scaffold stages']
    ]
    if (params.list_stages.toString().toBoolean()) {
        log.info "run_stage\tmaturity\tincluded_in_all\treal_mode_scope\tnotes"
        stageCatalog.each { row ->
            log.info "${row.run_stage}\t${row.maturity}\t${row.included_in_all}\t${row.real_mode_scope}\t${row.notes}"
        }
        System.exit(0)
    }
    def validateOnly = params.validate_only.toString().toBoolean()
    def realModeValidationEnabled = params.enable_real_mode_validation.toString().toBoolean()
    def explicitOmicsMode = params.omics_mode ? params.omics_mode.toString().trim().toLowerCase() : ''
    def effectiveOmicsMode = explicitOmicsMode ?: (params.omics_stub.toString().toBoolean() ? 'stub' : 'real')
    if (!(effectiveOmicsMode in ['stub', 'real'])) {
        error "Unsupported --omics_mode '${params.omics_mode}'. Supported values: stub, real."
    }
    def effectiveWgsMode = params.wgs_mode ? params.wgs_mode.toString().trim().toLowerCase() : 'stub'
    if (!(effectiveWgsMode in ['stub', 'real'])) {
        error "Unsupported --wgs_mode '${params.wgs_mode}'. Supported values: stub, real."
    }
    def effectivePglsMinSpecies = params.pgls_min_species != null ? params.pgls_min_species.toString() as Integer : 6
    if (effectivePglsMinSpecies < 1) {
        error "--pgls_min_species must be at least 1."
    }
    def effectiveIntegrationMinSpecies = params.integration_min_species != null ? params.integration_min_species.toString() as Integer : effectivePglsMinSpecies
    if (effectiveIntegrationMinSpecies < 1) {
        error "--integration_min_species must be at least 1."
    }
    def effectiveAtacReplicateConcordance = params.atac_replicate_concordance.toString().trim().toLowerCase()
    if (!(effectiveAtacReplicateConcordance in ['none', 'idr'])) {
        error "Unsupported --atac_replicate_concordance '${params.atac_replicate_concordance}'. Supported values: none, idr."
    }
    def allowedStages = stageCatalog.collect { it.run_stage }
    if (!allowedStages.contains(params.run_stage)) {
        error "Unsupported --run_stage '${params.run_stage}'. Supported values: ${allowedStages.join(', ')}."
    }
    if (!params.outdir.toString().startsWith('/')) {
        log.warn "CAME: --outdir '${params.outdir}' is a relative path. Outputs will be written relative to the Nextflow launch directory. Use an absolute path to ensure consistent output locations across stages."
    }
    def ceegEnabled = params.enable_ceeg_compatibility.toString().toBoolean()
    def activeProfileText = workflow.profile ? workflow.profile.toString() : ''
    if (['docker', 'apptainer', 'singularity'].any { activeProfileText.contains(it) }) {
        if (params.container_image) {
            log.info "CAME: using user-supplied container image '${params.container_image}'."
        } else {
            log.info "CAME: using default CAME container image '${params.default_container_image}'. Override with --container_image <uri>."
        }
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
    def isWgsVariantsStage = params.run_stage == 'wgs_variants'
    def isReferenceQualityStage = params.run_stage == 'reference_quality'
    def isCoordinateProjectionStage = params.run_stage == 'coordinate_projection'
    def isOrthologyReferencePrepareStage = params.run_stage == 'orthology_reference_prepare'
    def isReToGeneInferenceStage = params.run_stage == 're_to_gene_inference'
    def isAdvancedStatisticsStage = params.run_stage == 'advanced_statistics'
    def isCeegCompatibilityStage = params.run_stage == 'ceeg_compatibility' || (ceegEnabled && params.run_stage == 'validation')
    def ceegStub = params.ceeg_stub.toString().trim().toLowerCase()
    def ceegBundlePath = params.ceeg_model_bundle ? file(params.ceeg_model_bundle.toString()).toAbsolutePath().toString() : null
    def ceegR2OverlayDir = params.ceeg_r2_overlay_dir ? file(params.ceeg_r2_overlay_dir.toString()).toAbsolutePath().toString() : null
    def ceegR3MappingDir = params.ceeg_r3_mapping_dir ? file(params.ceeg_r3_mapping_dir.toString()).toAbsolutePath().toString() : null
    def ceegR4ComparabilityDir = params.ceeg_r4_comparability_dir ? file(params.ceeg_r4_comparability_dir.toString()).toAbsolutePath().toString() : null
    def defaultGenomeAlignmentManifest = 'assets/example_samplesheets/genome_alignment_manifest.tsv'
    def defaultCoordinateProjectionConfig = 'assets/example_samplesheets/coordinate_projection_config.tsv'
    def isDefaultPath = { value, defaultPath ->
        if (!value) {
            return false
        }
        def valueText = value.toString()
        if (valueText == defaultPath) {
            return true
        }
        return file(valueText).toAbsolutePath().toString() == file(defaultPath).toAbsolutePath().toString()
    }
    def ceegOrchestrateContracts = params.ceeg_orchestrate_contracts.toString().toBoolean()
    def ceegR2RunDir             = params.ceeg_r2_run_dir ? file(params.ceeg_r2_run_dir.toString()).toAbsolutePath().toString() : ''
    def ceegR3RunDir             = params.ceeg_r3_run_dir ? file(params.ceeg_r3_run_dir.toString()).toAbsolutePath().toString() : ''
    def ceegR2Cmd                = params.ceeg_run_came_overlay_cmd ? params.ceeg_run_came_overlay_cmd.toString() : ''
    def ceegR3Cmd                = params.ceeg_run_mapping_contract_cmd ? params.ceeg_run_mapping_contract_cmd.toString() : ''
    def ceegValidatorCreatedAt   = params.ceeg_validator_created_at ? params.ceeg_validator_created_at.toString() : ''
    def orthologyReferencePrepareStub = params.orthology_reference_prepare_stub.toString().trim().toLowerCase()
    def orthologyReferencePrepareCmd = params.orthology_reference_prepare_cmd ? params.orthology_reference_prepare_cmd.toString() : ''
    def orthologyReferencePrepareRunDir = params.orthology_reference_prepare_run_dir ? file(params.orthology_reference_prepare_run_dir.toString()).toAbsolutePath().toString() : ''
    def orthologyReferencePrepareCreatedAt = params.orthology_reference_prepare_created_at ? params.orthology_reference_prepare_created_at.toString() : ''
    def comparabilityMode = params.comparability_mode ? params.comparability_mode.toString().trim() : 'design_assumed'
    def allowedComparabilityModes = ['design_assumed', 'ceeg_contract_checked', 'ceeg_comparability_evidence_consumed']
    if (!(comparabilityMode in allowedComparabilityModes)) {
        error "Unsupported --comparability_mode '${params.comparability_mode}'. Supported values: ${allowedComparabilityModes.join(', ')}."
    }
    def r2r3Engaged = (ceegR2OverlayDir as boolean) || (ceegR3MappingDir as boolean) || (ceegOrchestrateContracts && ((ceegR2Cmd as boolean) || (ceegR3Cmd as boolean)))
    def r4Engaged = (ceegR4ComparabilityDir as boolean)
    if (comparabilityMode == 'design_assumed' && (r2r3Engaged || r4Engaged)) {
        error "Comparability mode 'design_assumed' is incompatible with supplied CEEG artifacts or orchestration. Set --comparability_mode ceeg_contract_checked (R2/R3 only) or --comparability_mode ceeg_comparability_evidence_consumed (R4), or remove --ceeg_r2_overlay_dir / --ceeg_r3_mapping_dir / --ceeg_orchestrate_contracts / --ceeg_r4_comparability_dir."
    }
    // R4-vs-mode incompatibility checks fire before "missing R2/R3" so that a user
    // who supplied --ceeg_r4_comparability_dir is told to switch to
    // ceeg_comparability_evidence_consumed instead of being asked for R2/R3 inputs.
    if (comparabilityMode == 'ceeg_contract_checked' && r4Engaged) {
        error "Comparability mode 'ceeg_contract_checked' is incompatible with --ceeg_r4_comparability_dir. R4 comparability evidence artifacts must be consumed under 'ceeg_comparability_evidence_consumed'. Set --comparability_mode ceeg_comparability_evidence_consumed, or remove --ceeg_r4_comparability_dir."
    }
    if (comparabilityMode == 'ceeg_contract_checked' && !r2r3Engaged) {
        error "Comparability mode 'ceeg_contract_checked' requires CEEG R2/R3 contract artifacts. Supply --ceeg_r2_overlay_dir or --ceeg_r3_mapping_dir, or enable --ceeg_orchestrate_contracts with at least one of --ceeg_run_came_overlay_cmd / --ceeg_run_mapping_contract_cmd. Otherwise set --comparability_mode design_assumed."
    }
    if (comparabilityMode == 'ceeg_comparability_evidence_consumed' && !r4Engaged) {
        error "Comparability mode 'ceeg_comparability_evidence_consumed' requires --ceeg_r4_comparability_dir pointing to a directory of externally generated CEEG R4 comparability evidence artifacts. Otherwise set --comparability_mode design_assumed or --comparability_mode ceeg_contract_checked."
    }
    def phylogenyManifestPath = params.phylogeny_manifest ? file(params.phylogeny_manifest) : null
    def phylogenyBaseDir = phylogenyManifestPath ? (phylogenyManifestPath.parent ?: '.') : '.'
    def existingIndexByGroup = file("${params.outdir}/phenotype/index/phenotype_index_by_group.tsv")
    def existingIndexContrasts = file("${params.outdir}/phenotype/contrasts/phenotype_index_contrasts.tsv")
    def existingComponentContrasts = file("${params.outdir}/phenotype/contrasts/component_trait_contrasts.tsv")
    def useExistingPhenotypeOutputs = false
    def realModeMetadataForValidation = isWgsVariantsStage ? params.wgs_samplesheet : params.real_mode_metadata
    def realModeAssaysForValidation = isWgsVariantsStage ? 'wgs' : (params.omics_types ?: '')
    def realModeRequirementsRequested = realModeValidationEnabled && (params.run_stage == 'validation' || (isBulkOmicsStage && effectiveOmicsMode == 'real') || (isWgsVariantsStage && effectiveWgsMode == 'real'))
    def referenceQualityPreflightRequested = realModeValidationEnabled && ((isBulkOmicsStage && effectiveOmicsMode == 'real') || (isWgsVariantsStage && effectiveWgsMode == 'real'))
    if (realModeRequirementsRequested && (!params.reference_manifest || !realModeMetadataForValidation)) {
        error "Real-mode validation requires --reference_manifest and --real_mode_metadata, or --wgs_samplesheet for --run_stage wgs_variants."
    }
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
        if (!params.reference_manifest) {
            error "Stage bulk_omics requires --reference_manifest."
        }
        if (effectiveOmicsMode == 'real') {
            if (!params.real_mode_metadata && !params.omics_samplesheet) {
                error "Stage bulk_omics real mode requires --real_mode_metadata or legacy --omics_samplesheet."
            }
        } else if (!params.omics_samplesheet) {
            error "Stage bulk_omics stub mode requires --omics_samplesheet."
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
    } else if (isWgsVariantsStage) {
        if (!params.wgs_samplesheet || !params.reference_manifest) {
            error "Stage wgs_variants requires --wgs_samplesheet and --reference_manifest."
        }
        if (params.wgs_variant_mode.toString() != 'haplotypecaller') {
            error "Unsupported --wgs_variant_mode '${params.wgs_variant_mode}'. Supported value: haplotypecaller."
        }
        if (params.wgs_calling_mode.toString() != 'per_sample') {
            error "Unsupported --wgs_calling_mode '${params.wgs_calling_mode}'. CAME v0.1 supports per_sample only; cohort/joint genotyping is not implemented."
        }
        if (!(params.wgs_filtering_mode.toString() in ['hard_filter', 'none'])) {
            error "Unsupported --wgs_filtering_mode '${params.wgs_filtering_mode}'. Supported values: hard_filter, none."
        }
    } else if (isReferenceQualityStage) {
        if (!params.reference_manifest) {
            error "Stage reference_quality requires --reference_manifest."
        }
    } else if (isCoordinateProjectionStage) {
        if (!params.regulatory_regions) {
            error "Stage coordinate_projection requires --regulatory_regions."
        }
        if (params.orthology_reference_bundle_manifest) {
            if (!file(params.orthology_reference_bundle_manifest).exists()) {
                error "Stage coordinate_projection could not find orthology_reference_bundle_manifest at '${params.orthology_reference_bundle_manifest}'."
            }
            def explicitAlignment = params.genome_alignment_manifest && !isDefaultPath(params.genome_alignment_manifest, defaultGenomeAlignmentManifest)
            def explicitConfig = params.coordinate_projection_config && !isDefaultPath(params.coordinate_projection_config, defaultCoordinateProjectionConfig)
            if (explicitAlignment || explicitConfig || params.orthology_hal_file || params.orthology_species_callable_mask || params.orthology_source_callable_mask || params.orthology_source_element_union) {
                error "Cannot combine --orthology_reference_bundle_manifest with loose coordinate-projection alignment/config or orthology asset parameters. Supply the bundle manifest alone, or omit it and use --genome_alignment_manifest/--coordinate_projection_config plus optional orthology assets."
            }
        } else if (!params.genome_alignment_manifest || !params.coordinate_projection_config) {
            error "Stage coordinate_projection requires --regulatory_regions plus either --orthology_reference_bundle_manifest or both --genome_alignment_manifest and --coordinate_projection_config."
        }
    } else if (isOrthologyReferencePrepareStage) {
        if (!(orthologyReferencePrepareStub in ["true", "1", "yes"])) {
            if (!orthologyReferencePrepareCmd) {
                error "Stage orthology_reference_prepare real mode requires --orthology_reference_prepare_cmd."
            }
            if (!orthologyReferencePrepareRunDir) {
                error "Stage orthology_reference_prepare real mode requires --orthology_reference_prepare_run_dir."
            }
            if (orthologyReferencePrepareRunDir && !file(orthologyReferencePrepareRunDir).exists()) {
                error "Stage orthology_reference_prepare could not find orthology_reference_prepare_run_dir at '${params.orthology_reference_prepare_run_dir}'."
            }
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
    } else if (isCeegCompatibilityStage) {
        if (!params.ceeg_model_bundle) {
            error "Stage ceeg_compatibility requires --ceeg_model_bundle."
        }
        if (!(ceegStub in ["true", "1", "yes"]) && !file(ceegBundlePath).exists()) {
            error "Stage ceeg_compatibility could not find ceeg_model_bundle at '${params.ceeg_model_bundle}'."
        }
        // Conflict detection: cannot supply both a user-provided dir and an orchestration command for the same artifact
        if (ceegOrchestrateContracts && ceegR2Cmd && ceegR2OverlayDir) {
            error "Cannot use both --ceeg_r2_overlay_dir and --ceeg_run_came_overlay_cmd. Supply one or the other."
        }
        if (ceegOrchestrateContracts && ceegR3Cmd && ceegR3MappingDir) {
            error "Cannot use both --ceeg_r3_mapping_dir and --ceeg_run_mapping_contract_cmd. Supply one or the other."
        }
        // Orchestration requirements — only when orchestrating and not in stub mode
        if (ceegOrchestrateContracts && !(ceegStub in ["true", "1", "yes"])) {
            if (!ceegR2Cmd && !ceegR3Cmd) {
                error "Stage ceeg_compatibility: --ceeg_orchestrate_contracts true requires at least one of --ceeg_run_came_overlay_cmd or --ceeg_run_mapping_contract_cmd."
            }
            if (ceegR2Cmd && !ceegR2RunDir) {
                error "Stage ceeg_compatibility: --ceeg_run_came_overlay_cmd requires --ceeg_r2_run_dir."
            }
            if (ceegR3Cmd && !ceegR3RunDir) {
                error "Stage ceeg_compatibility: --ceeg_run_mapping_contract_cmd requires --ceeg_r3_run_dir."
            }
            if (ceegR2RunDir && !file(ceegR2RunDir).exists()) {
                error "Stage ceeg_compatibility could not find ceeg_r2_run_dir at '${params.ceeg_r2_run_dir}'."
            }
            if (ceegR3RunDir && !file(ceegR3RunDir).exists()) {
                error "Stage ceeg_compatibility could not find ceeg_r3_run_dir at '${params.ceeg_r3_run_dir}'."
            }
        }
        // Existence check for user-supplied artifact dirs — skip when orchestrating those artifacts
        if (!(ceegStub in ["true", "1", "yes"])) {
            if (!ceegOrchestrateContracts && ceegR2OverlayDir && !file(ceegR2OverlayDir).exists()) {
                error "Stage ceeg_compatibility could not find ceeg_r2_overlay_dir at '${params.ceeg_r2_overlay_dir}'."
            }
            if (!ceegOrchestrateContracts && ceegR3MappingDir && !file(ceegR3MappingDir).exists()) {
                error "Stage ceeg_compatibility could not find ceeg_r3_mapping_dir at '${params.ceeg_r3_mapping_dir}'."
            }
            if (ceegR4ComparabilityDir && !file(ceegR4ComparabilityDir).exists()) {
                error "Stage ceeg_compatibility could not find ceeg_r4_comparability_dir at '${params.ceeg_r4_comparability_dir}'."
            }
        }
    } else if (!realModeValidationEnabled && (!params.phenotype_samplesheet || !params.omics_samplesheet || !params.species_traits ||
        !params.reference_manifest || !params.phylogeny_manifest || !params.study_design)) {
        error "Missing metadata input. Provide --phenotype_samplesheet, --omics_samplesheet, --species_traits, --reference_manifest, --phylogeny_manifest, and --study_design."
    }

    def hasFullMetadata = params.phenotype_samplesheet && params.omics_samplesheet && params.species_traits &&
        params.reference_manifest && params.phylogeny_manifest && params.study_design
    def metadataReport
    def activeReferenceManifest = params.reference_manifest ? file(params.reference_manifest) : null
    def realModeDone = null
    if (realModeRequirementsRequested) {
        REAL_MODE_REQUIREMENTS_VALIDATION(
            file(params.reference_manifest),
            file(realModeMetadataForValidation),
            realModeAssaysForValidation
        )
        activeReferenceManifest = REAL_MODE_REQUIREMENTS_VALIDATION.out.reference_manifest
        realModeDone = REAL_MODE_REQUIREMENTS_VALIDATION.out.done
    }
    if (referenceQualityPreflightRequested) {
        REFERENCE_QUALITY(
            activeReferenceManifest,
            isWgsVariantsStage ? 'wgs' : (params.reference_quality_assay ?: 'rna,atac'),
            params.check_paths ?: false,
            params.reference_quality_strict ?: false,
            params.allow_low_quality_reference ?: false
        )
        activeReferenceManifest = REFERENCE_QUALITY.out.reference_manifest
        realModeDone = REFERENCE_QUALITY.out.done
    }
    def gateFile = { value -> realModeValidationEnabled ? realModeDone.map { file(value) } : file(value) }
    def gateValue = { value -> realModeValidationEnabled ? realModeDone.map { value } : value }
    def activePhenotypeSamplesheet = params.phenotype_samplesheet ? gateFile(params.phenotype_samplesheet) : null
    def activeOmicsSamplesheet = params.omics_samplesheet ? gateFile(params.omics_samplesheet) : null
    def activeBulkOmicsInput = activeOmicsSamplesheet ?: (params.real_mode_metadata ? gateFile(params.real_mode_metadata) : null)
    def activeSpeciesTraits = params.species_traits ? gateFile(params.species_traits) : null
    def activePhylogenyManifest = params.phylogeny_manifest ? gateFile(params.phylogeny_manifest) : null
    def activeStudyDesign = params.study_design ? gateFile(params.study_design) : null
    def activeStudyProfile = params.study_profile ? gateFile(params.study_profile) : null
    def activeWgsSamplesheet = params.wgs_samplesheet ? gateFile(params.wgs_samplesheet) : null
    def activeReferencePrepareConfig = params.reference_prepare_config ? gateFile(params.reference_prepare_config) : null
    def activeRegulatoryRegions = params.regulatory_regions ? gateFile(params.regulatory_regions) : null
    def activeGenomeAlignmentManifest = params.genome_alignment_manifest ? gateFile(params.genome_alignment_manifest) : null
    def activeCoordinateProjectionConfig = params.coordinate_projection_config ? gateFile(params.coordinate_projection_config) : null
    def activeOrthologyReferenceBundleManifest = params.orthology_reference_bundle_manifest ? gateFile(params.orthology_reference_bundle_manifest) : null
    def activeOrthologyReferenceBundleManifestSource = params.orthology_reference_bundle_manifest ? gateValue(file(params.orthology_reference_bundle_manifest).toAbsolutePath().toString()) : null
    def activeGeneCoordinates = params.gene_coordinates ? gateFile(params.gene_coordinates) : null
    def activeReToGeneInferenceConfig = params.re_to_gene_inference_config ? gateFile(params.re_to_gene_inference_config) : null
    def activeAdvancedModelConfig = params.advanced_model_config ? gateFile(params.advanced_model_config) : null
    def activeOrthologousGenes = params.orthologous_genes ? gateFile(params.orthologous_genes) : null
    def activeOrthologousRes = params.orthologous_res ? gateFile(params.orthologous_res) : null
    def activeReToGeneLinks = params.re_to_gene_links ? gateFile(params.re_to_gene_links) : null
    def activeGeneAnnotations = params.gene_annotations ? gateFile(params.gene_annotations) : null
    def activeGeneSets = params.gene_sets ? gateFile(params.gene_sets) : null
    def activeCandidateScoringConfigValue = params.candidate_scoring_config ? gateValue(file(params.candidate_scoring_config).toString()) : null
    if (!isAllStage && !isReferencePrepareStage && !isWgsVariantsStage && !isReferenceQualityStage && !isCoordinateProjectionStage && !isOrthologyReferencePrepareStage && !isReToGeneInferenceStage && !isAdvancedStatisticsStage && !isCeegCompatibilityStage && hasFullMetadata) {
        METADATA_VALIDATION(
            activePhenotypeSamplesheet,
            activeOmicsSamplesheet,
            activeSpeciesTraits,
            activeReferenceManifest,
            activePhylogenyManifest,
            activeStudyDesign,
            params.validation_strict ?: false
        )
        metadataReport = METADATA_VALIDATION.out.report
    } else if (!realModeValidationEnabled && !isAllStage && !isBulkOmicsStage && !isDifferentialOmicsStage && !isOrthologyStage && !isGraStage && !isIntegrationStage && !isCandidateStage && !isFunctionalStage && !isFinalReportStage && !isReferencePrepareStage && !isWgsVariantsStage && !isReferenceQualityStage && !isCoordinateProjectionStage && !isOrthologyReferencePrepareStage && !isReToGeneInferenceStage && !isAdvancedStatisticsStage && !isCeegCompatibilityStage) {
        PHYLO_METADATA_VALIDATION(
            activePhenotypeSamplesheet,
            activeSpeciesTraits,
            activePhylogenyManifest
        )
        metadataReport = PHYLO_METADATA_VALIDATION.out.report
    } else if (isAllStage) {
        log.info "Stage all performs metadata and study profile validation inside the end-to-end workflow."
    } else if (realModeValidationEnabled && params.run_stage == 'validation' && !hasFullMetadata) {
        // Intentional path: --enable_real_mode_validation=true with --run_stage=validation but without
        // a full samplesheet set. Stage 23 real-mode checks run below; Stage 1 phenotype/omics
        // metadata validation is intentionally skipped because only downstream inputs were supplied.
        // This is expected when callers validate reference assets independently of a full pipeline run.
        log.info "Running Stage 23 real-mode validation without requiring the full Stage 1 metadata set."
    } else {
        log.info "Skipping full Stage 1 metadata validation for ${params.run_stage} because only downstream inputs were provided."
    }

    if (!isAllStage && params.study_profile && !isBulkOmicsStage && !isDifferentialOmicsStage && !isOrthologyStage && !isGraStage && !isIntegrationStage && !isCandidateStage && !isFunctionalStage && !isFinalReportStage && !isReferencePrepareStage && !isWgsVariantsStage && !isReferenceQualityStage && !isCoordinateProjectionStage && !isOrthologyReferencePrepareStage && !isReToGeneInferenceStage && !isAdvancedStatisticsStage && !isCeegCompatibilityStage) {
        STUDY_PROFILE_VALIDATION(
            activeStudyProfile,
            activePhenotypeSamplesheet,
            activeSpeciesTraits,
            params.validation_strict ?: false
        )
    }

    if (params.run_stage in ['phenotype_response', 'phylo_hypothesis'] && !params.study_profile) {
        error "Stage ${params.run_stage} requires --study_profile."
    }

    if (params.run_stage == 'all' && !validateOnly) {
        log.warn "[CAME WARNING] --run_stage all excludes optional/scaffold stages: reference_prepare, reference_quality, wgs_variants, coordinate_projection, orthology_reference_prepare, re_to_gene_inference, advanced_statistics, ceeg_compatibility. Run each explicitly with --run_stage <name>. Use --list_stages true for the full catalog."
        def functionalMinScore = params.functional_interpretation_min_score != null ? params.functional_interpretation_min_score.toString() : ''
        ALL(
            activePhenotypeSamplesheet,
            activeOmicsSamplesheet,
            activeSpeciesTraits,
            activeReferenceManifest,
            activePhylogenyManifest,
            activeStudyDesign,
            activeStudyProfile,
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
            activeOrthologousGenes,
            activeOrthologousRes,
            activeReToGeneLinks,
            activeGeneAnnotations,
            activeGeneSets,
            activeCandidateScoringConfigValue,
            params.candidate_linked_evidence_weight,
            params.candidate_score_cap,
            params.gra_activity_aggregation,     // workflow param: aggregation
            params.phenotype_response_metric,
            params.molecular_response_metric,
            params.phenotype_response_scope,
            params.integration_model_types,       // workflow param: model_types
            effectiveIntegrationMinSpecies,       // workflow param: min_species
            params.integration_cluster_method,
            params.species_pairs ?: '',
            params.functional_interpretation_top_n,
            functionalMinScore,
            params.resume_completed_stages,
            params.validation_strict ?: false
        )
    } else if (params.run_stage == 'bulk_omics' && !validateOnly) {
        BULK_OMICS(
            activeBulkOmicsInput,
            activeReferenceManifest,
            params.omics_types,
            params.omics_stub
        )
    } else if (params.run_stage == 'reference_prepare' && !validateOnly) {
        REFERENCE_PREPARE(
            activeWgsSamplesheet,
            activeReferenceManifest,
            activeReferencePrepareConfig,
            params.reference_stub
        )
    } else if (params.run_stage == 'wgs_variants' && !validateOnly) {
        WGS_VARIANTS(
            activeWgsSamplesheet,
            activeReferenceManifest,
            effectiveWgsMode,
            params.wgs_variant_mode,
            params.wgs_filtering_mode,
            params.require_known_sites,
            params.allow_no_bqsr
        )
    } else if (params.run_stage == 'reference_quality' && !validateOnly) {
        REFERENCE_QUALITY(
            activeReferenceManifest,
            params.reference_quality_assay ?: 'rna,atac',
            params.check_paths ?: false,
            params.reference_quality_strict ?: false,
            params.allow_low_quality_reference ?: false
        )
    } else if (params.run_stage == 'coordinate_projection' && !validateOnly) {
        COORDINATE_PROJECTION(
            activeRegulatoryRegions,
            activeGenomeAlignmentManifest,
            activeCoordinateProjectionConfig,
            activeOrthologyReferenceBundleManifest,
            activeOrthologyReferenceBundleManifestSource,
            params.coordinate_projection_stub
        )
    } else if (params.run_stage == 'orthology_reference_prepare' && !validateOnly) {
        ORTHOLOGY_REFERENCE_PREPARE(
            params.orthology_reference_prepare_stub,
            orthologyReferencePrepareCmd,
            orthologyReferencePrepareRunDir,
            orthologyReferencePrepareCreatedAt,
            params.orthology_reference_prepare_check_paths
        )
    } else if (params.run_stage == 're_to_gene_inference' && !validateOnly) {
        RE_TO_GENE_INFERENCE(
            activeRegulatoryRegions,
            activeGeneCoordinates,
            params.chromatin_contacts ? file(params.chromatin_contacts).toString() : '',
            activeReToGeneInferenceConfig,
            params.re_to_gene_inference_stub
        )
    } else if (params.run_stage == 'advanced_statistics' && !validateOnly) {
        def advancedPhenotypeIndexContrasts = params.phenotype_index_contrasts ? file(params.phenotype_index_contrasts).toString() : ''
        def advancedComponentTraitContrasts = params.component_trait_contrasts ? file(params.component_trait_contrasts).toString() : ''
        def advancedHypothesisModelTable = file("${params.outdir}/phylo/input/hypothesis_model_table.tsv")
        def advancedHypothesisModelResults = params.hypothesis_model_results ? file(params.hypothesis_model_results).toString() : ''
        def advancedPhenotypeOmicsModelTable = file("${params.outdir}/integration/input/phenotype_omics_model_table.tsv")
        ADVANCED_STATISTICS(
            activeAdvancedModelConfig,
            file(params.outdir).toString(),
            params.species_traits ? gateValue(file(params.species_traits).toString()) : '',
            params.phylogeny_manifest ? gateValue(file(params.phylogeny_manifest).toString()) : '',
            advancedPhenotypeIndexContrasts,
            advancedComponentTraitContrasts,
            advancedHypothesisModelTable.toString(),
            advancedHypothesisModelResults,
            advancedPhenotypeOmicsModelTable.toString(),
            params.advanced_statistics_stub
        )
    } else if (isCeegCompatibilityStage && !validateOnly) {
        CEEG_COMPATIBILITY(
            ceegBundlePath,
            ceegR2OverlayDir ?: '',
            ceegR3MappingDir ?: '',
            ceegR4ComparabilityDir ?: '',
            params.ceeg_validation_mode.toString(),
            params.ceeg_fail_on_contract_error.toString().toBoolean(),
            ceegStub,
            ceegOrchestrateContracts,
            ceegR2RunDir,
            ceegR3RunDir,
            ceegR2Cmd,
            ceegR3Cmd,
            ceegValidatorCreatedAt
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
            activeOmicsSamplesheet,
            params.study_profile ? gateValue(file(params.study_profile).toString()) : '',
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
            activeOmicsSamplesheet,
            activeOrthologousGenes,
            activeOrthologousRes,
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
            activeOmicsSamplesheet,
            activeReToGeneLinks,
            geneOrthogroupCountsFile,
            reOrthogroupCountsFile,
            featureMapFile,
            differentialExpressionOrthogroupsFile,
            differentialAccessibilityOrthogroupsFile,
            params.study_profile ? gateValue(file(params.study_profile).toString()) : '',
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
            activeSpeciesTraits,
            activePhylogenyManifest,
            activeStudyProfile,
            phylogenyBaseDir.toString(),
            params.phenotype_response_metric,
            params.molecular_response_metric,
            params.phenotype_response_scope,
            params.integration_model_types,       // workflow param: model_types
            effectiveIntegrationMinSpecies,       // workflow param: min_species
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
            gateValue(phenotypeIndexContrastsFile.toString()),
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
            gateValue(candidateScoringConfigPath),
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
            gateFile(candidateGenesFile.toString()),
            candidateResFile,
            candidateGrasFile,
            candidateAllFile,
            featureMapFile,
            geneRegulatoryArchitecturesFile,
            graReMembershipFile,
            activeGeneAnnotations,
            activeGeneSets,
            params.functional_interpretation_top_n,
            functionalMinScore
        )
    } else if (params.run_stage == 'final_report' && !validateOnly) {
        FINAL_REPORT(
            activeStudyProfile,
            file(params.outdir).toString()
        )
    } else if (params.run_stage == 'phenotype_response' && !validateOnly) {
        PHENOTYPE_RESPONSE(
            activePhenotypeSamplesheet,
            activeStudyProfile,
            params.normalization,
            metadataReport,
            STUDY_PROFILE_VALIDATION.out.report
        )
    } else if (params.run_stage == 'phylo_hypothesis' && !validateOnly) {
        if (useExistingPhenotypeOutputs) {
            PHYLO_HYPOTHESIS(
                activeSpeciesTraits,
                activePhylogenyManifest,
                activeStudyProfile,
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
                activePhenotypeSamplesheet,
                activeStudyProfile,
                params.normalization,
                metadataReport,
                STUDY_PROFILE_VALIDATION.out.report
            )
            PHYLO_HYPOTHESIS(
                activeSpeciesTraits,
                activePhylogenyManifest,
                activeStudyProfile,
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
