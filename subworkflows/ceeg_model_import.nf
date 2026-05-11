include { VALIDATE_CEEG_MODEL_BUNDLE      } from '../modules/local/validate_ceeg_model_bundle'
include { IMPORT_CEEG_MODEL_BUNDLE        } from '../modules/local/import_ceeg_model_bundle'
include { SUMMARIZE_CEEG_COMPATIBILITY    } from '../modules/local/summarize_ceeg_compatibility'
include { BUILD_CAME_CEEG_FEATURE_MATRICES } from '../modules/local/build_came_ceeg_feature_matrices'

workflow CEEG_MODEL_IMPORT {
    take:
    bundle_dir
    ceeg_stub

    main:
    VALIDATE_CEEG_MODEL_BUNDLE(bundle_dir, ceeg_stub)
    IMPORT_CEEG_MODEL_BUNDLE(bundle_dir, ceeg_stub, VALIDATE_CEEG_MODEL_BUNDLE.out.report)
    SUMMARIZE_CEEG_COMPATIBILITY(
        IMPORT_CEEG_MODEL_BUNDLE.out.nodes,
        IMPORT_CEEG_MODEL_BUNDLE.out.edges,
        IMPORT_CEEG_MODEL_BUNDLE.out.evidence,
        IMPORT_CEEG_MODEL_BUNDLE.out.metrics,
        ceeg_stub,
        VALIDATE_CEEG_MODEL_BUNDLE.out.report
    )
    BUILD_CAME_CEEG_FEATURE_MATRICES(
        IMPORT_CEEG_MODEL_BUNDLE.out.nodes,
        IMPORT_CEEG_MODEL_BUNDLE.out.edges,
        IMPORT_CEEG_MODEL_BUNDLE.out.evidence,
        IMPORT_CEEG_MODEL_BUNDLE.out.metrics,
        ceeg_stub
    )

    emit:
    nodes             = IMPORT_CEEG_MODEL_BUNDLE.out.nodes
    edges             = IMPORT_CEEG_MODEL_BUNDLE.out.edges
    evidence          = IMPORT_CEEG_MODEL_BUNDLE.out.evidence
    metrics           = IMPORT_CEEG_MODEL_BUNDLE.out.metrics
    validation_report = VALIDATE_CEEG_MODEL_BUNDLE.out.report
    summary           = SUMMARIZE_CEEG_COMPATIBILITY.out.summary
    report            = SUMMARIZE_CEEG_COMPATIBILITY.out.report
    re_features       = BUILD_CAME_CEEG_FEATURE_MATRICES.out.re_features
    system_features   = BUILD_CAME_CEEG_FEATURE_MATRICES.out.system_features
    evidence_features = BUILD_CAME_CEEG_FEATURE_MATRICES.out.evidence_features
}
