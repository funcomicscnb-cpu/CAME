process CHECK_CEEG_CONTRACT_STATUS {
    label 'process_low'

    input:
    path contract_summary
    path r4_summary
    val  fail_on_contract_error
    val  ceeg_stub

    script:
    def is_stub = ceeg_stub.toString().trim().toLowerCase() in ['true', '1', 'yes']
    def do_fail = !is_stub && fail_on_contract_error.toString() in ['true', '1', 'yes']
    """
    if ${do_fail ? 'true' : 'false'}; then
        # Resolve exit_code column by header name so the check is robust to
        # schema width differences between the R2/R3 summary (8 columns) and
        # the R4 comparability summary (28 columns).
        max_exit_for() {
            local file="\$1"
            [ -s "\$file" ] || { echo 0; return; }
            awk -F'\\t' '
                NR == 1 {
                    for (i = 1; i <= NF; i++) {
                        if (\$i == "exit_code") {
                            col = i
                        }
                    }
                    max = 0
                    next
                }
                col > 0 && \$col ~ /^[0-9]+\$/ {
                    if (\$col + 0 > max) { max = \$col + 0 }
                }
                END { print max + 0 }
            ' "\$file"
        }

        R2R3_MAX=\$(max_exit_for '${contract_summary}')
        R4_MAX=\$(max_exit_for '${r4_summary}')
        FAIL=0
        if [ "\$R2R3_MAX" -gt 0 ]; then
            printf 'CAME ceeg_compatibility: contract error recorded (exit_code=%d). See results/ceeg_compatibility/ceeg_contract_summary.tsv for details.\\n' "\$R2R3_MAX" >&2
            if [ "\$R2R3_MAX" -gt "\$FAIL" ]; then FAIL="\$R2R3_MAX"; fi
        fi
        if [ "\$R4_MAX" -gt 0 ]; then
            printf 'CAME ceeg_compatibility: CEEG R4 comparability contract error detected in results/ceeg_compatibility/ceeg_r4_comparability_summary.tsv (max exit_code=%d). Outputs were published before this failure.\\n' "\$R4_MAX" >&2
            if [ "\$R4_MAX" -gt "\$FAIL" ]; then FAIL="\$R4_MAX"; fi
        fi
        if [ "\$FAIL" -gt 0 ]; then
            exit "\$FAIL"
        fi
    fi
    """
}
