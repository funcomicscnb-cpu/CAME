process ORCHESTRATE_CEEG_VALIDATORS {
    label 'process_low'
    publishDir "${params.outdir}/ceeg_compatibility/generated", mode: 'copy'

    input:
    val r2_overlay_dir
    val r3_mapping_dir
    val orchestrate
    val r2_run_dir
    val r3_run_dir
    val r2_cmd
    val r3_cmd
    val validation_mode
    val ceeg_stub
    val created_at

    output:
    path 'effective_r2_overlay_dir.txt', emit: effective_r2_overlay_dir
    path 'effective_r3_mapping_dir.txt', emit: effective_r3_mapping_dir
    path 'r2_overlay',                   emit: r2_generated_dir,  optional: true
    path 'r3_mapping',                   emit: r3_generated_dir,  optional: true

    script:
    def is_stub   = ceeg_stub.toString().trim().toLowerCase() in ['true', '1', 'yes']
    def do_orch   = !is_stub && orchestrate.toString().toBoolean()
    def has_r2    = r2_cmd && r2_cmd.toString().trim()
    def has_r3    = r3_cmd && r3_cmd.toString().trim()

    if (is_stub || !do_orch) {
        // Branch A (stub) / Branch B (orchestration disabled):
        // Write selector files with the user-supplied paths (or empty).
        // Never invoke external commands.
        def r2_val = r2_overlay_dir ?: ''
        def r3_val = r3_mapping_dir ?: ''
        """
        printf '%s' '${r2_val}' > effective_r2_overlay_dir.txt
        printf '%s' '${r3_val}' > effective_r3_mapping_dir.txt
        """
    } else {
        // Branch C: orchestrate_contracts=true, stub=false.
        // Run requested validators, validate manifests, write selector files.
        def r2_block
        if (has_r2) {
            r2_block = """
mkdir -p r2_overlay
printf 'command_label: r2_came_overlay_validator\\nrun_dir: ${r2_run_dir}\\nout_dir: r2_overlay\\nvalidation_mode: ${validation_mode}\\ncreated_at_passed: ${created_at ? 'yes' : 'no'}\\n' > r2_overlay/ceeg_command.log
set +e
if [ -n '${created_at}' ]; then
  ${r2_cmd} \\
    --run-dir '${r2_run_dir}' \\
    --out-dir r2_overlay \\
    --validation-mode '${validation_mode}' \\
    --created-at '${created_at}' \\
    >> r2_overlay/ceeg_command.log 2>&1
else
  ${r2_cmd} \\
    --run-dir '${r2_run_dir}' \\
    --out-dir r2_overlay \\
    --validation-mode '${validation_mode}' \\
    >> r2_overlay/ceeg_command.log 2>&1
fi
R2_EXIT=\$?
set -e
printf 'exit_code: %d\\n' \$R2_EXIT >> r2_overlay/ceeg_command.log
python3 ${projectDir}/bin/check_ceeg_orchestration.py \\
    --out-dir r2_overlay \\
    --manifest-name came_report_manifest.json \\
    --exit-code "\$R2_EXIT" \\
    --validator-label r2_overlay
printf '%s' "\$(pwd)/r2_overlay" > effective_r2_overlay_dir.txt
"""
        } else {
            r2_block = """
printf '' > effective_r2_overlay_dir.txt
"""
        }

        def r3_block
        if (has_r3) {
            r3_block = """
mkdir -p r3_mapping
printf 'command_label: r3_mapping_contract_validator\\nrun_dir: ${r3_run_dir}\\nout_dir: r3_mapping\\nvalidation_mode: ${validation_mode}\\ncreated_at_passed: ${created_at ? 'yes' : 'no'}\\n' > r3_mapping/ceeg_command.log
set +e
if [ -n '${created_at}' ]; then
  ${r3_cmd} \\
    --run-dir '${r3_run_dir}' \\
    --out-dir r3_mapping \\
    --validation-mode '${validation_mode}' \\
    --created-at '${created_at}' \\
    >> r3_mapping/ceeg_command.log 2>&1
else
  ${r3_cmd} \\
    --run-dir '${r3_run_dir}' \\
    --out-dir r3_mapping \\
    --validation-mode '${validation_mode}' \\
    >> r3_mapping/ceeg_command.log 2>&1
fi
R3_EXIT=\$?
set -e
printf 'exit_code: %d\\n' \$R3_EXIT >> r3_mapping/ceeg_command.log
python3 ${projectDir}/bin/check_ceeg_orchestration.py \\
    --out-dir r3_mapping \\
    --manifest-name mapping_report_manifest.json \\
    --exit-code "\$R3_EXIT" \\
    --validator-label r3_mapping
printf '%s' "\$(pwd)/r3_mapping" > effective_r3_mapping_dir.txt
"""
        } else {
            r3_block = """
printf '' > effective_r3_mapping_dir.txt
"""
        }

        r2_block + r3_block
    }
}
