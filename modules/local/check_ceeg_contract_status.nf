process CHECK_CEEG_CONTRACT_STATUS {
    label 'process_low'

    input:
    path contract_summary
    val  fail_on_contract_error
    val  ceeg_stub

    script:
    def is_stub = ceeg_stub.toString().trim().toLowerCase() in ['true', '1', 'yes']
    def do_fail = !is_stub && fail_on_contract_error.toString() in ['true', '1', 'yes']
    """
    if ${do_fail ? 'true' : 'false'}; then
        MAX_EXIT=\$(awk -F'\\t' 'NR > 1 && \$4 ~ /^[0-9]+\$/ { print \$4 }' '${contract_summary}' | sort -n | tail -1)
        if [ -n "\$MAX_EXIT" ] && [ "\$MAX_EXIT" -gt 0 ]; then
            printf 'CAME ceeg_compatibility: contract error recorded (exit_code=%d). See results/ceeg_compatibility/ceeg_contract_summary.tsv for details.\\n' "\$MAX_EXIT" >&2
            exit "\$MAX_EXIT"
        fi
    fi
    """
}
