process CONSUME_CEEG_R4_COMPARABILITY_ARTIFACTS {
    label 'process_low'
    publishDir "${params.outdir}/ceeg_compatibility", mode: 'copy'

    input:
    val r4_comparability_dir
    val validation_mode
    val ceeg_stub

    output:
    path 'ceeg_r4_comparability_summary.tsv',     emit: r4_summary
    path 'ceeg_r4_comparability_limitations.tsv', emit: r4_limitations
    path 'ceeg_r4_comparability_evidence.tsv',    emit: r4_evidence
    path 'ceeg_r4_outputs_manifest.tsv',          emit: r4_manifest

    script:
    def is_stub = ceeg_stub.toString().trim().toLowerCase() in ['true', '1', 'yes']
    def has_dir = r4_comparability_dir ? true : false
    def r4_arg = has_dir ? "--r4-dir '${r4_comparability_dir}'" : ''
    def summary_header = 'artifact_type\\tartifact_path\\tvalidator_name\\tvalidator_version\\tvalidation_mode\\tstatus\\texit_code\\tcreated_at\\tmodel_id\\tcontext_id\\tcomparison_count\\tcomparison_id\\tleft_system_id\\tright_system_id\\tentity_scope\\tcomparability_status\\tstatus_basis\\tsupporting_evidence_count\\tweakening_evidence_count\\tmixed_evidence_count\\tunresolved_evidence_count\\tambiguity_count\\tunknown_count\\tunknown_unmappable_count\\tabsent_count\\tlimitations_count\\tprimary_limitation\\tmessage\\n'
    def limitations_header = 'comparison_id\\tcontext_id\\tlimitation_id\\tlimitation_type\\tseverity\\taffected_scope\\tdescription\\trecommended_interpretation\\n'
    def evidence_header = 'evidence_id\\tcomparison_id\\tcontext_id\\tevidence_type\\tevidence_class\\tconfidence\\tnotes\\tsource_artifact\\tinterpretation_note\\n'
    def outputs_header = 'output_file\\tartifact_type\\trow_count\\tsource_artifact\\tgenerated_at\\n'
    if (is_stub && !has_dir) {
        // Stub mode + no R4 dir: write header-only TSVs, do not fabricate.
        """
        printf '${summary_header}' > ceeg_r4_comparability_summary.tsv
        printf '${limitations_header}' > ceeg_r4_comparability_limitations.tsv
        printf '${evidence_header}' > ceeg_r4_comparability_evidence.tsv
        printf '${outputs_header}' > ceeg_r4_outputs_manifest.tsv
        """
    } else {
        // Always invoke the CAME-side summarizer. The summarizer is a pure
        // parser; it does not call CEEG validators. Stub mode with a supplied
        // R4 directory consumes the directory exactly as in non-stub mode.
        """
        python3 ${projectDir}/bin/summarize_ceeg_r4_comparability_artifacts.py \\
            --out-dir . \\
            ${r4_arg} \\
            --validation-mode ${validation_mode}

        [ -f ceeg_r4_comparability_summary.tsv ] || \\
            printf '${summary_header}' > ceeg_r4_comparability_summary.tsv
        [ -f ceeg_r4_comparability_limitations.tsv ] || \\
            printf '${limitations_header}' > ceeg_r4_comparability_limitations.tsv
        [ -f ceeg_r4_comparability_evidence.tsv ] || \\
            printf '${evidence_header}' > ceeg_r4_comparability_evidence.tsv
        [ -f ceeg_r4_outputs_manifest.tsv ] || \\
            printf '${outputs_header}' > ceeg_r4_outputs_manifest.tsv
        """
    }
}
