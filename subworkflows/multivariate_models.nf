process RUN_MULTIVARIATE_MODEL_PLACEHOLDER {
    publishDir { "${params.outdir}/advanced_statistics" }, mode: 'copy'

    input:
    path advanced_model_manifest

    output:
    path 'multivariate/multivariate_model_warnings.tsv', emit: warnings

    script:
    """
    mkdir -p multivariate
    printf 'severity\tmodel_id\tanalysis_target\tmodel_family\tmessage\n' > multivariate/multivariate_model_warnings.tsv
    awk -F '\\t' 'BEGIN{OFS="\\t"} NR==1{for (i=1; i<=NF; i++) h[\$i]=i; next} h["model_family"] && \$h["model_family"]=="multivariate_placeholder" && \$h["enabled"]=="true" {print "WARNING", \$h["model_id"], \$h["analysis_target"], \$h["model_family"], "Multivariate models are placeholders in this scaffold; no statistical result was emitted."}' "${advanced_model_manifest}" >> multivariate/multivariate_model_warnings.tsv
    """
}

workflow MULTIVARIATE_MODELS {
    take:
    advanced_model_manifest

    main:
    RUN_MULTIVARIATE_MODEL_PLACEHOLDER(advanced_model_manifest)

    emit:
    warnings = RUN_MULTIVARIATE_MODEL_PLACEHOLDER.out.warnings
}
