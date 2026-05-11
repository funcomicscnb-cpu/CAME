process CONSUME_CEEG_CONTRACT_ARTIFACTS {
    label 'process_low'
    publishDir "${params.outdir}/ceeg_compatibility", mode: 'copy'

    input:
    val r2_overlay_dir
    val r3_mapping_dir
    val validation_mode
    val fail_on_contract_error
    val ceeg_stub

    output:
    path 'ceeg_contract_summary.tsv',       emit: contract_summary
    path 'ceeg_mapping_summary.tsv',        emit: mapping_summary
    path 'ceeg_unmapped_features.tsv',      emit: unmapped_features
    path 'ceeg_ambiguous_mappings.tsv',     emit: ambiguous_mappings
    path 'ceeg_compatibility_warnings.tsv', emit: warnings
    path 'ceeg_outputs_manifest.tsv',       emit: manifest

    script:
    def is_stub = ceeg_stub.toString().trim().toLowerCase() in ['true', '1', 'yes']
    if (is_stub) {
        """
        printf 'artifact_type\tartifact_path\tstatus\texit_code\tvalidator_name\tvalidator_version\trun_id\tmessage\n' \
            > ceeg_contract_summary.tsv
        printf 'run_id\ttotal_features\tmapped_count\tambiguous_count\tfailed_count\tsource_artifact\n' \
            > ceeg_mapping_summary.tsv
        printf 'unmapped_id\tfeature_id\tfailure_reason\tnotes\tsource_artifact\tinterpretation_note\n' \
            > ceeg_unmapped_features.tsv
        printf 'ambiguous_id\tfeature_id\tcandidate_count\tcandidate_ids\tnotes\tsource_artifact\tinterpretation_note\n' \
            > ceeg_ambiguous_mappings.tsv
        printf 'severity\tsource\tmessage\n' \
            > ceeg_compatibility_warnings.tsv
        printf 'output_file\tartifact_type\trow_count\tsource_artifact\tgenerated_at\n' \
            > ceeg_outputs_manifest.tsv
        """
    } else {
        def r2_arg = r2_overlay_dir ? "--r2-dir '${r2_overlay_dir}'" : ''
        def r3_arg = r3_mapping_dir ? "--r3-dir '${r3_mapping_dir}'" : ''
        def fail_arg = fail_on_contract_error.toString() in ['true', '1', 'yes'] ? '--fail-on-error' : ''
        """
        python3 ${projectDir}/bin/summarize_ceeg_contract_artifacts.py \\
            --out-dir . \\
            ${r2_arg} \\
            ${r3_arg} \\
            --validation-mode ${validation_mode} \\
            ${fail_arg}

        [ -f ceeg_contract_summary.tsv ] || \\
            printf 'artifact_type\tartifact_path\tstatus\texit_code\tvalidator_name\tvalidator_version\trun_id\tmessage\n' \
            > ceeg_contract_summary.tsv
        [ -f ceeg_mapping_summary.tsv ] || \\
            printf 'run_id\ttotal_features\tmapped_count\tambiguous_count\tfailed_count\tsource_artifact\n' \
            > ceeg_mapping_summary.tsv
        [ -f ceeg_unmapped_features.tsv ] || \\
            printf 'unmapped_id\tfeature_id\tfailure_reason\tnotes\tsource_artifact\tinterpretation_note\n' \
            > ceeg_unmapped_features.tsv
        [ -f ceeg_ambiguous_mappings.tsv ] || \\
            printf 'ambiguous_id\tfeature_id\tcandidate_count\tcandidate_ids\tnotes\tsource_artifact\tinterpretation_note\n' \
            > ceeg_ambiguous_mappings.tsv
        [ -f ceeg_compatibility_warnings.tsv ] || \\
            printf 'severity\tsource\tmessage\n' \
            > ceeg_compatibility_warnings.tsv
        [ -f ceeg_outputs_manifest.tsv ] || \\
            printf 'output_file\tartifact_type\trow_count\tsource_artifact\tgenerated_at\n' \
            > ceeg_outputs_manifest.tsv
        """
    }
}
