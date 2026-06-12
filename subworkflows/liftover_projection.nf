process RECIPROCAL_BEST_REGION_LIFTOVER {
    publishDir { "${params.outdir}/coordinate_projection" }, mode: 'copy'

    input:
    path prepared_manifest
    val coordinate_projection_stub
    // Each optional slot stages into its own subdirectory (keeping the original
    // basename, so gzip extensions survive) to avoid input-name collisions when
    // two slots receive files with the same basename from different directories.
    path species_mask, stageAs: 'opt_species_mask/*'
    path source_mask, stageAs: 'opt_source_mask/*'
    path element_union, stageAs: 'opt_element_union/*'
    path hal_file, stageAs: 'opt_hal/*'
    val has_species_mask
    val has_source_mask
    val has_element_union
    val has_hal

    output:
    path 'projected_regions.tsv', emit: projected_regions
    path 'region_orthology_summary.tsv', emit: region_summary
    path 'orthologous_region_blocks.tsv', emit: blocks
    path 'projection_warnings.tsv', emit: projection_warnings

    script:
    // Optional inputs are staged via NO_FILE.* placeholders so file content
    // changes invalidate the cache and non-local executors/containers see them.
    // Presence is taken from explicit has_* flags (computed from params in the
    // workflow), never inferred from the staged basename, so a real user file
    // named exactly like a placeholder is not mistaken for "unset". Path
    // interpolations are left UNQUOTED: Nextflow backslash-escapes staged paths,
    // so adding our own quotes would turn the escape into a literal backslash.
    def liftTool = (params.orthology_lift_tool ?: 'liftover').toString().toLowerCase()
    def minMatch = params.orthology_liftover_min_match
    // Keep the path objects (not stringified) so Nextflow escaping applies.
    def halFile = has_hal ? hal_file : ''
    def elementUnion = has_element_union ? element_union : ''
    def engineExtra = ''
    if (has_species_mask) {
        engineExtra += " --species-callable-mask ${species_mask}"
    }
    if (has_source_mask) {
        engineExtra += " --source-callable-mask ${source_mask}"
    }
    if (has_element_union) {
        engineExtra += " --source-element-union ${element_union}"
    }
    """
    case "${coordinate_projection_stub}" in
      true|TRUE|1|yes|YES)
        printf 'projection_id\\tsource_species\\ttarget_species\\tsource_feature_id\\tprojected_feature_id\\tsource_chrom\\tsource_start\\tsource_end\\ttarget_chrom\\ttarget_start\\ttarget_end\\tstrand\\tregion_type\\talignment_id\\tmethod\\tprojection_status\\toverlap_fraction\\tmapping_class\\tnotes\\n' > projected_regions.tsv
        printf 'projection_id\\tsource_species\\ttarget_species\\tsource_feature_id\\tregion_type\\tsource_chrom\\tsource_start\\tsource_end\\tsource_window_len\\tsource_element_union_len\\tsource_callable_fraction\\traw_fragment_count\\tretained_fragment_count\\tcompeting_target_contigs\\tselected_target_contig\\tselected_piece_count\\tselected_span_len\\tselected_block_union_len\\tblock_density\\tmean_fragment_len\\tpiece_redundancy\\tspecies_mask_support_fraction\\tmask_components_overlapped\\tbacklift_fragment_count\\twindow_recovered_bp\\twindow_recovered_fraction\\telement_recovered_bp\\telement_recovered_fraction\\tcore_recovered\\tforward_status\\troundtrip_qc\\tstructural_class\\thigh_confidence_primary\\n' > region_orthology_summary.tsv
        printf 'projection_id\\tsource_species\\ttarget_species\\tsource_feature_id\\tblock_index\\ttarget_chrom\\ttarget_start\\ttarget_end\\tlength\\n' > orthologous_region_blocks.tsv
        printf 'severity\\tprojection_id\\tsource_feature_id\\ttarget_species\\tmessage\\n' > projection_warnings.tsv
        exit 0
        ;;
    esac

    LIFT_TOOL='${liftTool}'
    HAL_FILE=${halFile}

    # Validate the requested lift-over tool is available.
    case "\$LIFT_TOOL" in
      liftover)
        command -v liftOver >/dev/null 2>&1 || { echo "ERROR: orthology_lift_tool=liftover requires UCSC liftOver on PATH." >&2; exit 1; }
        command -v chainSwap >/dev/null 2>&1 || { echo "ERROR: reciprocal-best back-projection requires UCSC chainSwap on PATH." >&2; exit 1; }
        ;;
      halliftover)
        command -v halLiftover >/dev/null 2>&1 || { echo "ERROR: orthology_lift_tool=halliftover requires halLiftover on PATH." >&2; exit 1; }
        [ -n "\$HAL_FILE" ] || { echo "ERROR: orthology_lift_tool=halliftover requires --orthology_hal_file." >&2; exit 1; }
        [ -e "\$HAL_FILE" ] || { echo "ERROR: HAL file does not exist: \$HAL_FILE" >&2; exit 1; }
        ;;
      *)
        echo "ERROR: unsupported orthology_lift_tool='\$LIFT_TOOL' (expected 'liftover' or 'halliftover')." >&2
        exit 1
        ;;
    esac

    MIN_MATCH='${minMatch}'
    ELEMENT_UNION=${elementUnion}
    if [ -n "\$ELEMENT_UNION" ] && [ ! -e "\$ELEMENT_UNION" ]; then
      echo "ERROR: orthology_source_element_union does not exist: \$ELEMENT_UNION" >&2; exit 1
    fi

    mkdir -p work
    python3 ${projectDir}/bin/manifest_to_region_bed.py \\
      --prepared-manifest "${prepared_manifest}" \\
      --output-dir work

    : > work/forward_fragments.bed
    : > work/backlift_fragments.bed
    : > work/element_fragments.bed

    # One lift-over invocation per alignment group (skip the header line).
    # Read from a file rather than a pipe so a failed lift can exit the task.
    tail -n +2 work/chains.tsv > work/chains_body.tsv
    while IFS=\$'\\t' read -r idx source_species target_species method chain_file bed; do
      [ -n "\$bed" ] || continue
      group_bed="work/\$bed"
      # Restrict the supplied source element union to this group's features.
      elem_in=""
      if [ -n "\$ELEMENT_UNION" ]; then
        elem_in="work/elem_in_\$idx.bed"
        awk 'NR==FNR{k[\$4];next} (\$4 in k)' "\$group_bed" "\$ELEMENT_UNION" > "\$elem_in"
      fi
      if [ "\$LIFT_TOOL" = "liftover" ]; then
        case "\$method" in
          liftover_chain|precomputed_map|.) ;;
          *) echo "ERROR: orthology_lift_tool=liftover cannot execute method='\$method' for group \$idx; use orthology_lift_tool=halliftover or a chain-based method." >&2; exit 1 ;;
        esac
        { [ "\$chain_file" != "." ] && [ -e "\$chain_file" ]; } || { echo "ERROR: chain_file does not exist for group \$idx: \$chain_file" >&2; exit 1; }
        liftOver -minMatch=\$MIN_MATCH -multiple "\$group_bed" "\$chain_file" "work/fwd_\$idx.bed" "work/fwd_\$idx.unmapped" || { echo "ERROR: forward liftOver failed for group \$idx" >&2; exit 1; }
        chainSwap "\$chain_file" "work/swap_\$idx.chain" || { echo "ERROR: chainSwap failed for group \$idx" >&2; exit 1; }
        # Tag back-lift input names with the origin target contig (@@contig) so
        # round-trip recovery is scored only against the selected contig.
        awk 'BEGIN{OFS="\\t"}{ \$4=\$4"@@"\$1; print }' "work/fwd_\$idx.bed" > "work/backin_\$idx.bed"
        liftOver -minMatch=\$MIN_MATCH -multiple "work/backin_\$idx.bed" "work/swap_\$idx.chain" "work/back_\$idx.bed" "work/back_\$idx.unmapped" || { echo "ERROR: back liftOver failed for group \$idx" >&2; exit 1; }
        cat "work/fwd_\$idx.bed" >> work/forward_fragments.bed
        cut -f1-4 "work/back_\$idx.bed" >> work/backlift_fragments.bed
        if [ -n "\$elem_in" ] && [ -s "\$elem_in" ]; then
          liftOver -minMatch=\$MIN_MATCH -multiple "\$elem_in" "\$chain_file" "work/elem_\$idx.bed" "work/elem_\$idx.unmapped" || { echo "ERROR: element liftOver failed for group \$idx" >&2; exit 1; }
          cut -f1-4 "work/elem_\$idx.bed" >> work/element_fragments.bed
        fi
      else
        halLiftover --noDupes "\$HAL_FILE" "\$source_species" "\$group_bed" "\$target_species" "work/fwd_\$idx.bed" || { echo "ERROR: halLiftover forward failed for group \$idx" >&2; exit 1; }
        awk 'BEGIN{OFS="\\t"}{ \$4=\$4"@@"\$1; print }' "work/fwd_\$idx.bed" > "work/backin_\$idx.bed"
        halLiftover --noDupes "\$HAL_FILE" "\$target_species" "work/backin_\$idx.bed" "\$source_species" "work/back_\$idx.bed" || { echo "ERROR: halLiftover back failed for group \$idx" >&2; exit 1; }
        # Preserve all columns (incl. BED6 strand) so the engine can report the
        # projected strand, matching the liftOver branch.
        cat "work/fwd_\$idx.bed" >> work/forward_fragments.bed
        cut -f1-4 "work/back_\$idx.bed" >> work/backlift_fragments.bed
        if [ -n "\$elem_in" ] && [ -s "\$elem_in" ]; then
          halLiftover --noDupes "\$HAL_FILE" "\$source_species" "\$elem_in" "\$target_species" "work/elem_\$idx.bed" || { echo "ERROR: element halLiftover failed for group \$idx" >&2; exit 1; }
          cut -f1-4 "work/elem_\$idx.bed" >> work/element_fragments.bed
        fi
      fi
    done < work/chains_body.tsv

    ELEMENT_ARG=""
    if [ -s work/element_fragments.bed ]; then
      ELEMENT_ARG="--element-fragments work/element_fragments.bed"
    fi

    python3 ${projectDir}/bin/project_orthologous_regions.py \\
      --prepared-manifest "${prepared_manifest}" \\
      --forward-fragments work/forward_fragments.bed \\
      --backlift-fragments work/backlift_fragments.bed \\
      \$ELEMENT_ARG \\
      --min-element-recovery-bp ${params.orthology_min_element_recovery_bp} \\
      --min-element-recovery-frac ${params.orthology_min_element_recovery_frac} \\
      --min-window-recovery-frac ${params.orthology_min_window_recovery_frac}${engineExtra} \\
      --output-dir .
    """
}

workflow LIFTOVER_PROJECTION {
    take:
    prepared_manifest
    coordinate_projection_stub
    species_mask
    source_mask
    element_union
    hal_file
    has_species_mask
    has_source_mask
    has_element_union
    has_hal

    main:
    RECIPROCAL_BEST_REGION_LIFTOVER(
        prepared_manifest,
        coordinate_projection_stub,
        species_mask,
        source_mask,
        element_union,
        hal_file,
        has_species_mask,
        has_source_mask,
        has_element_union,
        has_hal
    )

    emit:
    projected_regions = RECIPROCAL_BEST_REGION_LIFTOVER.out.projected_regions
    region_summary = RECIPROCAL_BEST_REGION_LIFTOVER.out.region_summary
    blocks = RECIPROCAL_BEST_REGION_LIFTOVER.out.blocks
    projection_warnings = RECIPROCAL_BEST_REGION_LIFTOVER.out.projection_warnings
}
