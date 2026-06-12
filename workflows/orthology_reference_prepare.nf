process RUN_ORTHOLOGY_REFERENCE_PREPARE {
    label 'process_low'
    publishDir { "${params.outdir}/orthology_reference_prepare" }, mode: 'copy'

    input:
    val orthology_reference_prepare_stub
    val orthology_reference_prepare_cmd
    val orthology_reference_prepare_run_dir
    val orthology_reference_prepare_created_at
    val orthology_reference_prepare_check_paths

    output:
    path 'bundle', emit: bundle_dir
    path 'orthology_reference_bundle_validation.tsv', emit: validation
    path 'orthology_reference_bundle_warnings.tsv', emit: warnings
    path 'orthology_reference_prepare_summary.tsv', emit: summary
    path 'orthology_reference_prepare_outputs_manifest.tsv', emit: outputs_manifest
    path 'orthology_reference_prepare_command.log', emit: command_log, optional: true
    path 'orthology_reference_prepare_exit_code.txt', emit: exit_code

    script:
    """
    python3 ${projectDir}/bin/run_orthology_reference_prepare.py \\
      --output-dir . \\
      --stub "${orthology_reference_prepare_stub}" \\
      --command "${orthology_reference_prepare_cmd}" \\
      --run-dir "${orthology_reference_prepare_run_dir}" \\
      --created-at "${orthology_reference_prepare_created_at}" \\
      --check-paths "${orthology_reference_prepare_check_paths}" \\
      --fail-on-error false
    """
}

process CHECK_ORTHOLOGY_REFERENCE_PREPARE_STATUS {
    label 'process_low'

    input:
    path exit_code
    path summary

    output:
    path 'orthology_reference_prepare_status.ok', emit: ok

    script:
    """
    code="\$(cat "${exit_code}" | tr -d '[:space:]')"
    case "\$code" in
      0)
        printf 'ok\\n' > orthology_reference_prepare_status.ok
        ;;
      *)
        echo "ERROR: orthology_reference_prepare failed with exit code \$code" >&2
        cat "${summary}" >&2
        exit "\$code"
        ;;
    esac
    """
}

workflow ORTHOLOGY_REFERENCE_PREPARE {
    take:
    orthology_reference_prepare_stub
    orthology_reference_prepare_cmd
    orthology_reference_prepare_run_dir
    orthology_reference_prepare_created_at
    orthology_reference_prepare_check_paths

    main:
    RUN_ORTHOLOGY_REFERENCE_PREPARE(
        orthology_reference_prepare_stub,
        orthology_reference_prepare_cmd,
        orthology_reference_prepare_run_dir,
        orthology_reference_prepare_created_at,
        orthology_reference_prepare_check_paths
    )
    CHECK_ORTHOLOGY_REFERENCE_PREPARE_STATUS(
        RUN_ORTHOLOGY_REFERENCE_PREPARE.out.exit_code,
        RUN_ORTHOLOGY_REFERENCE_PREPARE.out.summary
    )

    emit:
    bundle_dir = RUN_ORTHOLOGY_REFERENCE_PREPARE.out.bundle_dir
    validation = RUN_ORTHOLOGY_REFERENCE_PREPARE.out.validation
    warnings = RUN_ORTHOLOGY_REFERENCE_PREPARE.out.warnings
    summary = RUN_ORTHOLOGY_REFERENCE_PREPARE.out.summary
    outputs_manifest = RUN_ORTHOLOGY_REFERENCE_PREPARE.out.outputs_manifest
    command_log = RUN_ORTHOLOGY_REFERENCE_PREPARE.out.command_log
    status = CHECK_ORTHOLOGY_REFERENCE_PREPARE_STATUS.out.ok
}
