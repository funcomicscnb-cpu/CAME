process LIFTOVER_PROJECTION_PLACEHOLDER {
    publishDir { "${params.outdir}/coordinate_projection" }, mode: 'copy'

    input:
    path prepared_manifest
    val coordinate_projection_stub

    output:
    path 'projected_regions.tsv', emit: projected_regions
    path 'projection_warnings.tsv', emit: projection_warnings

    script:
    """
    case "${coordinate_projection_stub}" in
      true|TRUE|1|yes|YES)
        printf 'projection_id\\tsource_species\\ttarget_species\\tsource_feature_id\\tprojected_feature_id\\tsource_chrom\\tsource_start\\tsource_end\\ttarget_chrom\\ttarget_start\\ttarget_end\\tstrand\\tregion_type\\talignment_id\\tmethod\\tprojection_status\\toverlap_fraction\\tmapping_class\\tnotes\\n' > projected_regions.tsv
        printf 'severity\\tprojection_id\\tsource_feature_id\\ttarget_species\\tmessage\\n' > projection_warnings.tsv
        ;;
      *)
        if command -v liftOver >/dev/null 2>&1; then
          :
        elif command -v CrossMap.py >/dev/null 2>&1; then
          :
        elif command -v halLiftover >/dev/null 2>&1; then
          :
        else
          echo "ERROR: coordinate_projection real mode requires a lift-over tool such as UCSC liftOver, CrossMap, HAL tools, or a custom MAF projector." >&2
          exit 1
        fi
        echo "ERROR: coordinate_projection real-mode lift-over execution is scaffold-only in Stage 19; no production projected regions are emitted." >&2
        exit 1
        ;;
    esac
    """
}

workflow LIFTOVER_PROJECTION {
    take:
    prepared_manifest
    coordinate_projection_stub

    main:
    LIFTOVER_PROJECTION_PLACEHOLDER(prepared_manifest, coordinate_projection_stub)

    emit:
    projected_regions = LIFTOVER_PROJECTION_PLACEHOLDER.out.projected_regions
    projection_warnings = LIFTOVER_PROJECTION_PLACEHOLDER.out.projection_warnings
}
