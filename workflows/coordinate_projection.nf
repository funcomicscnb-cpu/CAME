include { LIFTOVER_PROJECTION } from '../subworkflows/liftover_projection'
include { REGULATORY_ORTHOLOGY_INFERENCE } from '../subworkflows/regulatory_orthology_inference'

process PREPARE_ORTHOLOGY_REFERENCE_BUNDLE {
    publishDir { "${params.outdir}/coordinate_projection" }, mode: 'copy', pattern: 'input/orthology_reference_bundle_*.tsv'
    publishDir { "${params.outdir}/coordinate_projection" }, mode: 'copy', pattern: 'input/*from_bundle.tsv'

    input:
    path orthology_reference_bundle_manifest
    val orthology_reference_bundle_manifest_source

    output:
    path 'input/orthology_reference_bundle_validation.tsv', emit: validation
    path 'input/orthology_reference_bundle_warnings.tsv', emit: warnings
    path 'input/genome_alignment_manifest.from_bundle.tsv', emit: genome_alignment_manifest
    path 'input/coordinate_projection_config.from_bundle.tsv', emit: coordinate_projection_config
    path 'input/effective_orthology_lift_tool.txt', emit: effective_lift_tool
    path 'input/orthology_reference_bundle_asset_selectors.tsv', emit: asset_selectors
    path 'input/pair_assets', emit: pair_assets

    script:
    """
    mkdir -p input
    python3 ${projectDir}/bin/validate_orthology_reference_bundle.py \\
      --manifest "${orthology_reference_bundle_manifest_source}" \\
      --outdir input \\
      --check-paths true
    python3 ${projectDir}/bin/prepare_coordinate_projection_bundle_inputs.py \\
      --bundle-manifest "${orthology_reference_bundle_manifest_source}" \\
      --output-dir input
    """
}

process PREPARE_COORDINATE_PROJECTION_INPUTS {
    publishDir { "${params.outdir}/coordinate_projection" }, mode: 'copy'

    input:
    path regulatory_regions
    path genome_alignment_manifest
    path coordinate_projection_config
    val coordinate_projection_stub
    path hal_file, stageAs: 'opt_hal/*'
    val has_hal
    val orthology_lift_tool
    val allow_pair_hal_assets

    output:
    path 'input/coordinate_projection_manifest.tsv', emit: prepared_manifest
    path 'input/coordinate_projection_warnings.tsv', emit: warnings

    script:
    // The HAL is staged as an input (NO_FILE.hal placeholder when unset) so the
    // existence check holds in the task work directory and remote executors and
    // the task cache see the actual file. Presence is from the explicit has_hal
    // flag, not the basename. Left unquoted: Nextflow backslash-escapes staged
    // paths, so our own quotes would make the escape a literal backslash.
    def halArg = has_hal ? "--orthology_hal_file ${hal_file}" : ''
    """
	    mkdir -p input
	    python3 ${projectDir}/bin/prepare_coordinate_projection_inputs.py \\
	      --regulatory_regions "${regulatory_regions}" \\
	      --genome_alignment_manifest "${genome_alignment_manifest}" \\
	      --coordinate_projection_config "${coordinate_projection_config}" \\
	      --coordinate_projection_stub "${coordinate_projection_stub}" \\
	      --orthology_lift_tool "${orthology_lift_tool}" ${halArg} \\
	      --allow_pair_hal_assets "${allow_pair_hal_assets}" \\
	      --output_dir input
    """
}

process MAKE_SYNTHETIC_COORDINATE_PROJECTION_OUTPUTS {
    publishDir { "${params.outdir}/coordinate_projection" }, mode: 'copy'

    input:
    path prepared_manifest
    val coordinate_projection_stub

    output:
    path 'projected_regions.tsv', emit: projected_regions
    path 'inferred_orthologous_res.tsv', emit: inferred_orthologous_res
    path 'projection_warnings.tsv', emit: projection_warnings
    path 'region_orthology_summary.tsv', emit: region_summary
    path 'orthologous_region_blocks.tsv', emit: blocks

    script:
    """
    case "${coordinate_projection_stub}" in
      true|TRUE|1|yes|YES) ;;
      *)
        echo "ERROR: coordinate_projection real mode must not emit synthetic outputs. Use --coordinate_projection_stub true for scaffold outputs or provide a production implementation." >&2
        exit 1
        ;;
    esac
    python3 ${projectDir}/bin/make_synthetic_coordinate_projection_outputs.py \\
      --prepared_manifest "${prepared_manifest}" \\
      --output_dir .
    """
}

process SUMMARIZE_COORDINATE_PROJECTION {
    publishDir { "${params.outdir}/coordinate_projection" }, mode: 'copy'

    input:
    path prepared_manifest
    path projected_regions
    path inferred_orthologous_res
    path projection_warnings
    path region_summary
    path region_blocks
    val coordinate_projection_stub

    output:
    path 'summary/coordinate_projection_summary.tsv', emit: summary
    path 'summary/coordinate_projection_outputs_manifest.tsv', emit: outputs_manifest

    script:
    """
    mkdir -p summary
    python3 ${projectDir}/bin/summarize_coordinate_projection.py \\
      --prepared_manifest "${prepared_manifest}" \\
      --projected_regions "${projected_regions}" \\
      --inferred_orthologous_res "${inferred_orthologous_res}" \\
      --projection_warnings "${projection_warnings}" \\
      --region_summary "${region_summary}" \\
      --region_blocks "${region_blocks}" \\
      --coordinate_projection_stub "${coordinate_projection_stub}" \\
      --output_dir summary
    """
}

workflow COORDINATE_PROJECTION {
    take:
    regulatory_regions
    genome_alignment_manifest
    coordinate_projection_config
    orthology_reference_bundle_manifest
    orthology_reference_bundle_manifest_source
    coordinate_projection_stub

    main:
    // Optional projection assets are staged via distinct NO_FILE.* placeholders
    // (distinct names avoid an input-name collision) so content changes
    // invalidate caches and remote executors/containers can see them. The HAL is
    // staged into prep too, so its existence check is portable and cache-aware.
    def hasBundle = orthology_reference_bundle_manifest ? true : false
    if (hasBundle) {
        PREPARE_ORTHOLOGY_REFERENCE_BUNDLE(
            orthology_reference_bundle_manifest,
            orthology_reference_bundle_manifest_source
        )
        effectiveGenomeAlignmentManifest = PREPARE_ORTHOLOGY_REFERENCE_BUNDLE.out.genome_alignment_manifest
        effectiveCoordinateProjectionConfig = PREPARE_ORTHOLOGY_REFERENCE_BUNDLE.out.coordinate_projection_config
        effectiveLiftTool = PREPARE_ORTHOLOGY_REFERENCE_BUNDLE.out.effective_lift_tool.map { it.text.trim() }
        pairAssetSelectors = PREPARE_ORTHOLOGY_REFERENCE_BUNDLE.out.asset_selectors
        pairAssetsDir = PREPARE_ORTHOLOGY_REFERENCE_BUNDLE.out.pair_assets
        hasSpeciesMask = false
        hasSourceMask = false
        hasElementUnion = false
        hasHal = false
        speciesMask = file("${projectDir}/assets/NO_FILE.species_mask")
        sourceMask = file("${projectDir}/assets/NO_FILE.source_mask")
        elementUnion = file("${projectDir}/assets/NO_FILE.element_union")
        halFile = file("${projectDir}/assets/NO_FILE.hal")
        allowPairHalAssets = true
    } else {
        effectiveGenomeAlignmentManifest = genome_alignment_manifest
        effectiveCoordinateProjectionConfig = coordinate_projection_config
        effectiveLiftTool = params.orthology_lift_tool ?: 'liftover'
        pairAssetSelectors = file("${projectDir}/assets/NO_FILE.pair_asset_selectors.tsv")
        pairAssetsDir = file("${projectDir}/assets/NO_FILE.pair_assets_dir")
        hasSpeciesMask = params.orthology_species_callable_mask ? true : false
        hasSourceMask = params.orthology_source_callable_mask ? true : false
        hasElementUnion = params.orthology_source_element_union ? true : false
        hasHal = params.orthology_hal_file ? true : false
        speciesMask = hasSpeciesMask ? file(params.orthology_species_callable_mask) : file("${projectDir}/assets/NO_FILE.species_mask")
        sourceMask = hasSourceMask ? file(params.orthology_source_callable_mask) : file("${projectDir}/assets/NO_FILE.source_mask")
        elementUnion = hasElementUnion ? file(params.orthology_source_element_union) : file("${projectDir}/assets/NO_FILE.element_union")
        halFile = hasHal ? file(params.orthology_hal_file) : file("${projectDir}/assets/NO_FILE.hal")
        allowPairHalAssets = false
    }

    PREPARE_COORDINATE_PROJECTION_INPUTS(
        regulatory_regions,
        effectiveGenomeAlignmentManifest,
        effectiveCoordinateProjectionConfig,
        coordinate_projection_stub,
        halFile,
        hasHal,
        effectiveLiftTool,
        allowPairHalAssets
    )

    if (params.coordinate_projection_stub.toString().toBoolean()) {
        MAKE_SYNTHETIC_COORDINATE_PROJECTION_OUTPUTS(
            PREPARE_COORDINATE_PROJECTION_INPUTS.out.prepared_manifest,
            coordinate_projection_stub
        )
        projectedRegions = MAKE_SYNTHETIC_COORDINATE_PROJECTION_OUTPUTS.out.projected_regions
        inferredOrthologousRes = MAKE_SYNTHETIC_COORDINATE_PROJECTION_OUTPUTS.out.inferred_orthologous_res
        projectionWarnings = MAKE_SYNTHETIC_COORDINATE_PROJECTION_OUTPUTS.out.projection_warnings
        regionSummary = MAKE_SYNTHETIC_COORDINATE_PROJECTION_OUTPUTS.out.region_summary
        regionBlocks = MAKE_SYNTHETIC_COORDINATE_PROJECTION_OUTPUTS.out.blocks
    } else {
        LIFTOVER_PROJECTION(
            PREPARE_COORDINATE_PROJECTION_INPUTS.out.prepared_manifest,
            coordinate_projection_stub,
            pairAssetSelectors,
            pairAssetsDir,
            speciesMask,
            sourceMask,
            elementUnion,
            halFile,
            effectiveLiftTool,
            hasSpeciesMask,
            hasSourceMask,
            hasElementUnion,
            hasHal
        )
        REGULATORY_ORTHOLOGY_INFERENCE(
            LIFTOVER_PROJECTION.out.region_summary,
            LIFTOVER_PROJECTION.out.projected_regions,
            LIFTOVER_PROJECTION.out.projection_warnings,
            coordinate_projection_stub
        )
        projectedRegions = LIFTOVER_PROJECTION.out.projected_regions
        inferredOrthologousRes = REGULATORY_ORTHOLOGY_INFERENCE.out.inferred_orthologous_res
        projectionWarnings = REGULATORY_ORTHOLOGY_INFERENCE.out.projection_warnings
        regionSummary = LIFTOVER_PROJECTION.out.region_summary
        regionBlocks = LIFTOVER_PROJECTION.out.blocks
    }

    SUMMARIZE_COORDINATE_PROJECTION(
        PREPARE_COORDINATE_PROJECTION_INPUTS.out.prepared_manifest,
        projectedRegions,
        inferredOrthologousRes,
        projectionWarnings,
        regionSummary,
        regionBlocks,
        coordinate_projection_stub
    )

    emit:
    prepared_manifest = PREPARE_COORDINATE_PROJECTION_INPUTS.out.prepared_manifest
    warnings = PREPARE_COORDINATE_PROJECTION_INPUTS.out.warnings
    projected_regions = projectedRegions
    inferred_orthologous_res = inferredOrthologousRes
    projection_warnings = projectionWarnings
    summary = SUMMARIZE_COORDINATE_PROJECTION.out.summary
    outputs_manifest = SUMMARIZE_COORDINATE_PROJECTION.out.outputs_manifest
}
