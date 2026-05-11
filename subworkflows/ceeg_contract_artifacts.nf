include { CONSUME_CEEG_CONTRACT_ARTIFACTS } from '../modules/local/consume_ceeg_contract_artifacts'
include { ORCHESTRATE_CEEG_VALIDATORS     } from '../modules/local/orchestrate_ceeg_validators'
include { CHECK_CEEG_CONTRACT_STATUS      } from '../modules/local/check_ceeg_contract_status'

workflow CEEG_CONTRACT_ARTIFACTS {
    take:
    r2_overlay_dir
    r3_mapping_dir
    validation_mode
    fail_on_contract_error
    ceeg_stub
    orchestrate
    r2_run_dir
    r3_run_dir
    r2_cmd
    r3_cmd
    created_at

    main:
    ORCHESTRATE_CEEG_VALIDATORS(
        r2_overlay_dir,
        r3_mapping_dir,
        orchestrate,
        r2_run_dir,
        r3_run_dir,
        r2_cmd,
        r3_cmd,
        validation_mode,
        ceeg_stub,
        created_at
    )

    def effective_r2 = ORCHESTRATE_CEEG_VALIDATORS.out.effective_r2_overlay_dir
        .map { it.text.trim() }

    def effective_r3 = ORCHESTRATE_CEEG_VALIDATORS.out.effective_r3_mapping_dir
        .map { it.text.trim() }

    CONSUME_CEEG_CONTRACT_ARTIFACTS(
        effective_r2,
        effective_r3,
        validation_mode,
        ceeg_stub
    )

    CHECK_CEEG_CONTRACT_STATUS(
        CONSUME_CEEG_CONTRACT_ARTIFACTS.out.contract_summary,
        fail_on_contract_error,
        ceeg_stub
    )

    emit:
    contract_summary   = CONSUME_CEEG_CONTRACT_ARTIFACTS.out.contract_summary
    mapping_summary    = CONSUME_CEEG_CONTRACT_ARTIFACTS.out.mapping_summary
    unmapped_features  = CONSUME_CEEG_CONTRACT_ARTIFACTS.out.unmapped_features
    ambiguous_mappings = CONSUME_CEEG_CONTRACT_ARTIFACTS.out.ambiguous_mappings
    warnings           = CONSUME_CEEG_CONTRACT_ARTIFACTS.out.warnings
    manifest           = CONSUME_CEEG_CONTRACT_ARTIFACTS.out.manifest
}
