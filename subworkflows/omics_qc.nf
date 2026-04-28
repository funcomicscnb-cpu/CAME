include { MULTIQC } from '../modules/multiqc/main'

workflow OMICS_QC {
    take:
    prepared_manifest
    rnaseq_summary
    atacseq_summary
    omics_stub

    main:
    MULTIQC(prepared_manifest, rnaseq_summary, atacseq_summary, omics_stub)

    emit:
    multiqc = MULTIQC.out.report
}
