include { CEEG_MODEL_IMPORT } from '../subworkflows/ceeg_model_import'

workflow CEEG_COMPATIBILITY {
    take:
    bundle_dir
    ceeg_stub

    main:
    CEEG_MODEL_IMPORT(bundle_dir, ceeg_stub)

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
