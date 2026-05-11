include { CONSUME_CEEG_CONTRACT_ARTIFACTS } from '../modules/local/consume_ceeg_contract_artifacts'

workflow CEEG_CONTRACT_ARTIFACTS {
    take:
    r2_overlay_dir
    r3_mapping_dir
    validation_mode
    fail_on_contract_error
    ceeg_stub

    main:
    CONSUME_CEEG_CONTRACT_ARTIFACTS(
        r2_overlay_dir,
        r3_mapping_dir,
        validation_mode,
        fail_on_contract_error,
        ceeg_stub
    )

    emit:
    contract_summary  = CONSUME_CEEG_CONTRACT_ARTIFACTS.out.contract_summary
    mapping_summary   = CONSUME_CEEG_CONTRACT_ARTIFACTS.out.mapping_summary
    unmapped_features = CONSUME_CEEG_CONTRACT_ARTIFACTS.out.unmapped_features
    ambiguous_mappings = CONSUME_CEEG_CONTRACT_ARTIFACTS.out.ambiguous_mappings
    warnings          = CONSUME_CEEG_CONTRACT_ARTIFACTS.out.warnings
    manifest          = CONSUME_CEEG_CONTRACT_ARTIFACTS.out.manifest
}
