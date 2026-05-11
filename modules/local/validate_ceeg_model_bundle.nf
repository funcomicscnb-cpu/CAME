process VALIDATE_CEEG_MODEL_BUNDLE {
    publishDir { "${params.outdir}/ceeg/validation" }, mode: 'copy'

    input:
    val bundle_dir
    val ceeg_stub

    output:
    path 'ceeg_bundle_validation_report.tsv', emit: report

    script:
    """
    if [ "${ceeg_stub}" = "true" ] || [ "${ceeg_stub}" = "1" ] || [ "${ceeg_stub}" = "yes" ]; then
      printf 'severity\trule_id\tsource\tfield\trow\tmessage\tsuggestion\n' \
        > ceeg_bundle_validation_report.tsv
      printf 'INFO\t\tceeg_validation\t\t\tStub mode: bundle validation skipped\t\n' \
        >> ceeg_bundle_validation_report.tsv
    else
      python3 ${projectDir}/bin/validate_ceeg_model_bundle.py \\
        --bundle_dir "${bundle_dir}" \\
        --report ceeg_bundle_validation_report.tsv
    fi
    """
}
