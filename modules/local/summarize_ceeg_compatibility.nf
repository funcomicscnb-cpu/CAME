process SUMMARIZE_CEEG_COMPATIBILITY {
    publishDir { "${params.outdir}/ceeg/summary" }, mode: 'copy'

    input:
    path imported_nodes
    path imported_edges
    path imported_evidence
    path imported_metrics
    val  ceeg_stub
    path validation_report

    output:
    path 'ceeg_compatibility_summary.tsv', emit: summary
    path 'ceeg_compatibility_report.md',   emit: report

    script:
    """
    if [ "${ceeg_stub}" = "true" ] || [ "${ceeg_stub}" = "1" ] || [ "${ceeg_stub}" = "yes" ]; then
      printf 'metric\tvalue\tsource\n'                              > ceeg_compatibility_summary.tsv
      printf 'ceeg_node_count\t0\tnodes\n'                        >> ceeg_compatibility_summary.tsv
      printf 'ceeg_edge_count\t0\tedges\n'                        >> ceeg_compatibility_summary.tsv
      printf 'ceeg_evidence_count\t0\tevidence\n'                 >> ceeg_compatibility_summary.tsv
      printf 'ceeg_regulatory_element_count\t0\tnodes\n'          >> ceeg_compatibility_summary.tsv
      printf 'ceeg_projection_edge_count\t0\tedges\n'             >> ceeg_compatibility_summary.tsv
      printf 'ceeg_system_count\t0\tnodes\n'                      >> ceeg_compatibility_summary.tsv
      printf 'ceeg_unknown_count\t0\tevidence\n'                  >> ceeg_compatibility_summary.tsv
      printf 'ceeg_absent_count\t0\tevidence\n'                   >> ceeg_compatibility_summary.tsv
      printf 'ceeg_observed_count\t0\tnodes\n'                    >> ceeg_compatibility_summary.tsv
      printf 'ceeg_projected_direct_count\t0\tnodes\n'            >> ceeg_compatibility_summary.tsv
      printf 'ceeg_projected_indirect_count\t0\tnodes\n'          >> ceeg_compatibility_summary.tsv
      printf 'ceeg_unknown_unmappable_count\t0\tnodes\n'          >> ceeg_compatibility_summary.tsv
      printf 'ceeg_data_mode_bulk\t0\tevidence\n'                 >> ceeg_compatibility_summary.tsv
      printf 'ceeg_data_mode_counts\tnone\tevidence\n'            >> ceeg_compatibility_summary.tsv
      printf 'ceeg_mean_score\t\tmetrics\n'                       >> ceeg_compatibility_summary.tsv
      printf 'ceeg_max_score\t\tmetrics\n'                        >> ceeg_compatibility_summary.tsv
      printf 'ceeg_min_score\t\tmetrics\n'                        >> ceeg_compatibility_summary.tsv
      printf 'ceeg_max_n_supporting_species\t\tmetrics\n'         >> ceeg_compatibility_summary.tsv
      printf 'ceeg_validation_error_count\tN/A\tvalidation_report\n' >> ceeg_compatibility_summary.tsv
      printf 'ceeg_status\tSKIPPED\tsummary\n'                    >> ceeg_compatibility_summary.tsv
      printf '# CEEG Compatibility Summary\n\nStub mode: no bundle imported.\n\n' \
        > ceeg_compatibility_report.md
      printf 'projected_direct nodes represent positional projection only. ' \
        >> ceeg_compatibility_report.md
      printf 'Functional conservation is not implied.\n' \
        >> ceeg_compatibility_report.md
    else
      mkdir -p imported
      cp "${imported_nodes}"    imported/ceeg_imported_nodes.tsv
      cp "${imported_edges}"    imported/ceeg_imported_edges.tsv
      cp "${imported_evidence}" imported/ceeg_imported_evidence.tsv
      cp "${imported_metrics}"  imported/ceeg_imported_metrics.tsv
      python3 ${projectDir}/bin/summarize_ceeg_compatibility.py \\
        --import-dir imported \\
        --outdir . \\
        --validation-report "${validation_report}"
    fi
    """
}
