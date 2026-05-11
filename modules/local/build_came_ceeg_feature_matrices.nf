process BUILD_CAME_CEEG_FEATURE_MATRICES {
    publishDir { "${params.outdir}/ceeg/features" }, mode: 'copy'

    input:
    path imported_nodes
    path imported_edges
    path imported_evidence
    path imported_metrics
    val  ceeg_stub

    output:
    path 'ceeg_regulatory_projection_features.tsv', emit: re_features
    path 'ceeg_system_features.tsv',                emit: system_features
    path 'ceeg_evidence_features.tsv',              emit: evidence_features

    script:
    """
    if [ "${ceeg_stub}" = "true" ] || [ "${ceeg_stub}" = "1" ] || [ "${ceeg_stub}" = "yes" ]; then
      printf 'node_id\tevidence_id\tbiological_system\tsystem_id\tspecies_id\tdata_mode\tevidence_status\tprojection_type\tmapping_state\tprojection_edge_id\tprojection_source_node_id\tprojection_mode\tprojection_weight\tceeg_score\tceeg_rank\tn_supporting_species\n' \
        > ceeg_regulatory_projection_features.tsv
      printf 'system_id\tre_count\tobserved_count\tprojected_direct_count\tprojected_indirect_count\tunknown_unmappable_count\tdata_modes\tevidence_count\tunknown_evidence_count\tabsent_evidence_count\tmean_ceeg_score\tmax_ceeg_score\tmin_ceeg_score\tn_supporting_species_max\tcomponent_node_ids\tevidence_ids\tcomponent_ceeg_scores\n' \
        > ceeg_system_features.tsv
      printf 'evidence_id\tnode_id\tedge_id\tevidence_type\tdata_mode\tunknown_absent\tprovenance\tbiological_system\tsystem_id\tspecies_id\tevidence_status\tmapping_state\tceeg_score\tn_supporting_species\n' \
        > ceeg_evidence_features.tsv
    else
      mkdir -p imported
      cp "${imported_nodes}"    imported/ceeg_imported_nodes.tsv
      cp "${imported_edges}"    imported/ceeg_imported_edges.tsv
      cp "${imported_evidence}" imported/ceeg_imported_evidence.tsv
      cp "${imported_metrics}"  imported/ceeg_imported_metrics.tsv
      python3 ${projectDir}/bin/build_came_ceeg_feature_matrices.py \\
        --import-dir imported \\
        --outdir .
    fi
    """
}
