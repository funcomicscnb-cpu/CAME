include { RNASEQ_STANDARD } from '../subworkflows/rnaseq_standard'
include { ATACSEQ_STANDARD } from '../subworkflows/atacseq_standard'
include { OMICS_QC } from '../subworkflows/omics_qc'

process PREPARE_OMICS_INPUTS {
    publishDir { "${params.outdir}/omics" }, mode: 'copy'

    input:
    path omics_samplesheet
    path reference_manifest
    val omics_types
    val omics_stub

    output:
    path 'input/omics_manifest_prepared.tsv', emit: prepared_manifest
    path 'input/rnaseq_manifest.tsv', emit: rnaseq_manifest
    path 'input/atacseq_manifest.tsv', emit: atacseq_manifest
    path 'input/omics_input_warnings.tsv', emit: warnings

    script:
    """
    mkdir -p input
    python3 ${projectDir}/bin/prepare_omics_inputs.py \\
      --omics_samplesheet "${omics_samplesheet}" \\
      --reference_manifest "${reference_manifest}" \\
      --omics_types "${omics_types}" \\
      --omics_stub "${omics_stub}" \\
      --output_dir input
    """
}

process SUMMARIZE_OMICS_OUTPUTS {
    publishDir { "${params.outdir}/omics" }, mode: 'copy'

    input:
    path prepared_manifest
    path rnaseq_counts
    path rnaseq_summary
    path atacseq_counts
    path atacseq_summary
    path warnings

    output:
    path 'summary/omics_run_summary.tsv', emit: run_summary
    path 'summary/omics_outputs_manifest.tsv', emit: outputs_manifest

    script:
    """
    mkdir -p summary
    python3 ${projectDir}/bin/summarize_omics_outputs.py \\
      --prepared_manifest "${prepared_manifest}" \\
      --rnaseq_counts "${rnaseq_counts}" \\
      --rnaseq_summary "${rnaseq_summary}" \\
      --atacseq_counts "${atacseq_counts}" \\
      --atacseq_summary "${atacseq_summary}" \\
      --warnings "${warnings}" \\
      --output_dir summary
    """
}

workflow BULK_OMICS {
    take:
    omics_samplesheet
    reference_manifest
    omics_types
    omics_stub

    main:
    PREPARE_OMICS_INPUTS(omics_samplesheet, reference_manifest, omics_types, omics_stub)
    RNASEQ_STANDARD(PREPARE_OMICS_INPUTS.out.rnaseq_manifest, omics_stub)
    ATACSEQ_STANDARD(PREPARE_OMICS_INPUTS.out.atacseq_manifest, omics_stub)
    OMICS_QC(
        PREPARE_OMICS_INPUTS.out.prepared_manifest,
        RNASEQ_STANDARD.out.summary,
        ATACSEQ_STANDARD.out.summary,
        omics_stub
    )
    SUMMARIZE_OMICS_OUTPUTS(
        PREPARE_OMICS_INPUTS.out.prepared_manifest,
        RNASEQ_STANDARD.out.gene_counts,
        RNASEQ_STANDARD.out.summary,
        ATACSEQ_STANDARD.out.re_counts,
        ATACSEQ_STANDARD.out.summary,
        PREPARE_OMICS_INPUTS.out.warnings
    )

    emit:
    prepared_manifest = PREPARE_OMICS_INPUTS.out.prepared_manifest
    rnaseq_counts = RNASEQ_STANDARD.out.gene_counts
    atacseq_counts = ATACSEQ_STANDARD.out.re_counts
    run_summary = SUMMARIZE_OMICS_OUTPUTS.out.run_summary
    outputs_manifest = SUMMARIZE_OMICS_OUTPUTS.out.outputs_manifest
    multiqc = OMICS_QC.out.multiqc
}
