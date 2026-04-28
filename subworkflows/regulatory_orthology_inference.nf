process REGULATORY_ORTHOLOGY_INFERENCE_PLACEHOLDER {
    publishDir { "${params.outdir}/coordinate_projection" }, mode: 'copy'

    input:
    path prepared_manifest
    path projected_regions
    path projection_warnings_in
    val coordinate_projection_stub

    output:
    path 'inferred_orthologous_res.tsv', emit: inferred_orthologous_res
    path 'projection_warnings.tsv', emit: projection_warnings

    script:
    """
    case "${coordinate_projection_stub}" in
      true|TRUE|1|yes|YES)
        printf 'species\\tfeature_id\\torthogroup_id\\tchrom\\tstart\\tend\\thuman_anchor_region\\tre_type\\torthology_type\\torthology_confidence\\tsource\\tnotes\\n' > inferred_orthologous_res.tsv
        cp "${projection_warnings_in}" projection_warnings.tsv
        ;;
      *)
        echo "ERROR: coordinate_projection real-mode regulatory orthology inference is scaffold-only in Stage 19; no inferred orthology table is emitted." >&2
        exit 1
        ;;
    esac
    """
}

workflow REGULATORY_ORTHOLOGY_INFERENCE {
    take:
    prepared_manifest
    projected_regions
    projection_warnings
    coordinate_projection_stub

    main:
    REGULATORY_ORTHOLOGY_INFERENCE_PLACEHOLDER(
        prepared_manifest,
        projected_regions,
        projection_warnings,
        coordinate_projection_stub
    )

    emit:
    inferred_orthologous_res = REGULATORY_ORTHOLOGY_INFERENCE_PLACEHOLDER.out.inferred_orthologous_res
    projection_warnings = REGULATORY_ORTHOLOGY_INFERENCE_PLACEHOLDER.out.projection_warnings
}
