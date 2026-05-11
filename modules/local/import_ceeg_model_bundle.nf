process IMPORT_CEEG_MODEL_BUNDLE {
    publishDir { "${params.outdir}/ceeg/imported" }, mode: 'copy'

    input:
    val  bundle_dir
    val  ceeg_stub
    path validation_report

    output:
    path 'ceeg_imported_nodes.tsv',    emit: nodes
    path 'ceeg_imported_edges.tsv',    emit: edges
    path 'ceeg_imported_evidence.tsv', emit: evidence
    path 'ceeg_imported_metrics.tsv',  emit: metrics

    script:
    """
    if [ "${ceeg_stub}" = "true" ] || [ "${ceeg_stub}" = "1" ] || [ "${ceeg_stub}" = "yes" ]; then
      printf 'node_id\tnode_type\tbiological_system\tdata_mode\tevidence_status\tprojection_type\tmapping_state\tlabel\tspecies\tnotes\tceeg_bundle_source\n' \
        > ceeg_imported_nodes.tsv
      printf 'edge_id\tsource_node_id\ttarget_node_id\tedge_type\tprojection_mode\tbiological_system\tweight\tnotes\tceeg_bundle_source\n' \
        > ceeg_imported_edges.tsv
      printf 'evidence_id\tnode_id\tedge_id\tevidence_type\tdata_mode\tunknown_absent\tprovenance\tnotes\tceeg_bundle_source\n' \
        > ceeg_imported_evidence.tsv
      printf 'node_id\tbiological_system\tdata_mode\tceeg_score\tceeg_rank\tn_supporting_species\tnotes\tceeg_bundle_source\n' \
        > ceeg_imported_metrics.tsv
    else
      python3 ${projectDir}/bin/import_ceeg_model_bundle.py \\
        --bundle "${bundle_dir}" \\
        --outdir .
    fi
    """
}
