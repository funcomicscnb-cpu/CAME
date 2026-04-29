process REAL_OMICS_QC {
    publishDir { "${params.outdir}/omics/qc" }, mode: 'copy'

    input:
    path prepared_manifest
    path rna_qc
    path rna_logs, stageAs: 'rna_logs'
    path atac_qc
    path atac_logs, stageAs: 'atac_logs'

    output:
    path 'multiqc', emit: multiqc

    script:
    """
    set -euo pipefail
    command -v multiqc >/dev/null 2>&1 || { echo "ERROR: MultiQC executable not found for real mode. Install MultiQC or run --omics_mode stub." >&2; exit 1; }
    mkdir -p multiqc inputs
    cp "${prepared_manifest}" inputs/omics_manifest_prepared.tsv
    multiqc --outdir multiqc .
    test -s multiqc/multiqc_report.html
    """
}

workflow QC_REAL {
    take:
    prepared_manifest
    rna_qc
    rna_logs
    atac_qc
    atac_logs

    main:
    REAL_OMICS_QC(prepared_manifest, rna_qc, rna_logs, atac_qc, atac_logs)

    emit:
    multiqc = REAL_OMICS_QC.out.multiqc
}
