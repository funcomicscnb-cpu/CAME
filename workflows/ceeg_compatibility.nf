include { CEEG_MODEL_IMPORT       } from '../subworkflows/ceeg_model_import'
include { CEEG_CONTRACT_ARTIFACTS } from '../subworkflows/ceeg_contract_artifacts'

workflow CEEG_COMPATIBILITY {
    take:
    bundle_dir
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
    CEEG_MODEL_IMPORT(bundle_dir, ceeg_stub)
    CEEG_CONTRACT_ARTIFACTS(
        r2_overlay_dir,
        r3_mapping_dir,
        validation_mode,
        fail_on_contract_error,
        ceeg_stub,
        orchestrate,
        r2_run_dir,
        r3_run_dir,
        r2_cmd,
        r3_cmd,
        created_at
    )

    emit:
    nodes             = CEEG_MODEL_IMPORT.out.nodes
    edges             = CEEG_MODEL_IMPORT.out.edges
    evidence          = CEEG_MODEL_IMPORT.out.evidence
    metrics           = CEEG_MODEL_IMPORT.out.metrics
    validation_report = CEEG_MODEL_IMPORT.out.validation_report
    summary           = CEEG_MODEL_IMPORT.out.summary
    report            = CEEG_MODEL_IMPORT.out.report
    re_features       = CEEG_MODEL_IMPORT.out.re_features
    system_features   = CEEG_MODEL_IMPORT.out.system_features
    evidence_features = CEEG_MODEL_IMPORT.out.evidence_features
}
