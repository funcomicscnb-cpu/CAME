process REGULATORY_ORTHOLOGY_INFERENCE_FROM_SUMMARY {
    publishDir { "${params.outdir}/coordinate_projection" }, mode: 'copy'

    input:
    path region_summary
    path projected_regions
    path projection_warnings_in, stageAs: 'in_projection_warnings.tsv'
    val coordinate_projection_stub

    output:
    path 'inferred_orthologous_res.tsv', emit: inferred_orthologous_res
    path 'projection_warnings.tsv', emit: projection_warnings

    script:
    def primaryOnly = params.orthology_primary_only.toString().toBoolean() ? '--primary-only' : ''
    """
    case "${coordinate_projection_stub}" in
      true|TRUE|1|yes|YES)
        printf 'species\\tfeature_id\\torthogroup_id\\tchrom\\tstart\\tend\\thuman_anchor_region\\tre_type\\torthology_type\\torthology_confidence\\tsource\\tnotes\\n' > inferred_orthologous_res.tsv
        cp "${projection_warnings_in}" projection_warnings.tsv
        exit 0
        ;;
    esac

    python3 ${projectDir}/bin/classify_orthologous_regions.py \\
      --region-summary "${region_summary}" \\
      --projected-regions "${projected_regions}" \\
      --output-dir . ${primaryOnly}
    cp "${projection_warnings_in}" projection_warnings.tsv
    """
}

workflow REGULATORY_ORTHOLOGY_INFERENCE {
    take:
    region_summary
    projected_regions
    projection_warnings
    coordinate_projection_stub

    main:
    REGULATORY_ORTHOLOGY_INFERENCE_FROM_SUMMARY(
        region_summary,
        projected_regions,
        projection_warnings,
        coordinate_projection_stub
    )

    emit:
    inferred_orthologous_res = REGULATORY_ORTHOLOGY_INFERENCE_FROM_SUMMARY.out.inferred_orthologous_res
    projection_warnings = REGULATORY_ORTHOLOGY_INFERENCE_FROM_SUMMARY.out.projection_warnings
}
