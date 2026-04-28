include { LIFTOVER_PROJECTION } from '../subworkflows/liftover_projection'
include { REGULATORY_ORTHOLOGY_INFERENCE } from '../subworkflows/regulatory_orthology_inference'

process PREPARE_COORDINATE_PROJECTION_INPUTS {
    publishDir { "${params.outdir}/coordinate_projection" }, mode: 'copy'

    input:
    path regulatory_regions
    path genome_alignment_manifest
    path coordinate_projection_config
    val coordinate_projection_stub

    output:
    path 'input/coordinate_projection_manifest.tsv', emit: prepared_manifest
    path 'input/coordinate_projection_warnings.tsv', emit: warnings

    script:
    """
    mkdir -p input
    python3 ${projectDir}/bin/prepare_coordinate_projection_inputs.py \\
      --regulatory_regions "${regulatory_regions}" \\
      --genome_alignment_manifest "${genome_alignment_manifest}" \\
      --coordinate_projection_config "${coordinate_projection_config}" \\
      --coordinate_projection_stub "${coordinate_projection_stub}" \\
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
      --coordinate_projection_stub "${coordinate_projection_stub}" \\
      --output_dir summary
    """
}

workflow COORDINATE_PROJECTION {
    take:
    regulatory_regions
    genome_alignment_manifest
    coordinate_projection_config
    coordinate_projection_stub

    main:
    PREPARE_COORDINATE_PROJECTION_INPUTS(
        regulatory_regions,
        genome_alignment_manifest,
        coordinate_projection_config,
        coordinate_projection_stub
    )

    if (params.coordinate_projection_stub.toString().toBoolean()) {
        MAKE_SYNTHETIC_COORDINATE_PROJECTION_OUTPUTS(
            PREPARE_COORDINATE_PROJECTION_INPUTS.out.prepared_manifest,
            coordinate_projection_stub
        )
        projectedRegions = MAKE_SYNTHETIC_COORDINATE_PROJECTION_OUTPUTS.out.projected_regions
        inferredOrthologousRes = MAKE_SYNTHETIC_COORDINATE_PROJECTION_OUTPUTS.out.inferred_orthologous_res
        projectionWarnings = MAKE_SYNTHETIC_COORDINATE_PROJECTION_OUTPUTS.out.projection_warnings
    } else {
        LIFTOVER_PROJECTION(PREPARE_COORDINATE_PROJECTION_INPUTS.out.prepared_manifest, coordinate_projection_stub)
        REGULATORY_ORTHOLOGY_INFERENCE(
            PREPARE_COORDINATE_PROJECTION_INPUTS.out.prepared_manifest,
            LIFTOVER_PROJECTION.out.projected_regions,
            LIFTOVER_PROJECTION.out.projection_warnings,
            coordinate_projection_stub
        )
        projectedRegions = LIFTOVER_PROJECTION.out.projected_regions
        inferredOrthologousRes = REGULATORY_ORTHOLOGY_INFERENCE.out.inferred_orthologous_res
        projectionWarnings = REGULATORY_ORTHOLOGY_INFERENCE.out.projection_warnings
    }

    SUMMARIZE_COORDINATE_PROJECTION(
        PREPARE_COORDINATE_PROJECTION_INPUTS.out.prepared_manifest,
        projectedRegions,
        inferredOrthologousRes,
        projectionWarnings,
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
