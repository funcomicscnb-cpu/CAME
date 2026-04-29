include { RNASEQ_STANDARD } from '../subworkflows/rnaseq_standard'
include { ATACSEQ_STANDARD } from '../subworkflows/atacseq_standard'
include { OMICS_QC } from '../subworkflows/omics_qc'
include { RNA_REAL } from '../subworkflows/rna_real'
include { ATAC_REAL } from '../subworkflows/atac_real'
include { QC_REAL } from '../subworkflows/qc_real'

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

process PREPARE_REAL_OMICS_INPUTS {
    publishDir { "${params.outdir}/omics" }, mode: 'copy'

    input:
    path metadata, stageAs: 'real_mode_metadata_input.tsv'
    val metadata_kind
    path reference_manifest, stageAs: 'reference_manifest_input.tsv'
    val omics_types
    val reference_cache_dir
    val metadata_base_dir
    val reference_base_dir
    val real_require_paired_atac

    output:
    path 'input/omics_manifest_prepared.tsv', emit: prepared_manifest
    path 'input/rnaseq_manifest.tsv', emit: rnaseq_manifest
    path 'input/atacseq_manifest.tsv', emit: atacseq_manifest
    path 'input/reference_assets.tsv', emit: reference_assets
    path 'input/omics_input_warnings.tsv', emit: warnings

    script:
    def metadataFlag = metadata_kind == 'real_mode_metadata' ? '--real_mode_metadata' : '--omics_samplesheet'
    """
    mkdir -p input
    python3 ${projectDir}/bin/prepare_real_omics_inputs.py \\
      ${metadataFlag} "${metadata}" \\
      --reference_manifest "${reference_manifest}" \\
      --omics_types "${omics_types}" \\
      --reference_cache_dir "${reference_cache_dir}" \\
      --launch_dir "${launchDir}" \\
      --metadata_base_dir "${metadata_base_dir}" \\
      --reference_base_dir "${reference_base_dir}" \\
      --real_require_paired_atac "${real_require_paired_atac}" \\
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

process EMPTY_RNA_REAL_OUTPUTS {
    publishDir { "${params.outdir}/rnaseq" }, mode: 'copy'
    label 'process_low'

    output:
    path 'qc/fastqc', emit: fastqc
    path 'bam', emit: bam
    path 'logs', emit: logs
    path 'counts/gene_counts.tsv', emit: gene_counts
    path 'qc/alignment_qc.tsv', emit: qc
    path 'summary/rnaseq_summary.tsv', emit: summary
    path 'validation/rna_real_validation.tsv', emit: validation

    script:
    """
    mkdir -p qc/fastqc bam logs/star counts summary validation
    printf 'feature_id\\tfeature_type\\tannotation_id\\n' > counts/gene_counts.tsv
    printf 'sample_id\\tspecies\\tomics_type\\tcondition\\ttimepoint\\treference_id\\tstatus\\tn_features\\ttotal_counts\\toutput_files\\twarnings\\n' > summary/rnaseq_summary.tsv
    printf 'sample_id\\tspecies\\tomics_type\\tcondition\\ttimepoint\\treference_id\\tstrandedness\\tbam\\tbai\\tbam_exists\\tbam_nonempty\\ttotal_reads\\tuniquely_mapped_reads\\tunique_mapping_rate\\tmulti_mapped_reads\\tmulti_mapping_rate\\tassigned_reads\\tassigned_fraction\\tmapping_rate\\tn_features\\ttotal_counts\\tstatus\\twarnings\\n' > qc/alignment_qc.tsv
    printf 'severity\\tsource\\tfield\\tsample_id\\tmessage\\nINFO\\trna_real\\t\\t\\tNo RNA-seq samples requested\\n' > validation/rna_real_validation.tsv
    printf 'No rnaseq samples\\n' > logs/star/NO_SAMPLES.log
    """
}

process EMPTY_ATAC_REAL_OUTPUTS {
    publishDir { "${params.outdir}/atacseq" }, mode: 'copy'
    label 'process_low'

    output:
    path 'qc/fastqc', emit: fastqc
    path 'bam', emit: bam
    path 'peaks', emit: peaks
    path 'logs', emit: logs
    path 'counts/peak_counts.tsv', emit: peak_counts
    path 'counts/re_counts.tsv', emit: re_counts
    path 'counts/peak_consensus.bed', emit: consensus
    path 'qc/atac_qc.tsv', emit: qc
    path 'summary/atacseq_summary.tsv', emit: summary
    path 'validation/atac_real_validation.tsv', emit: validation

    script:
    """
    mkdir -p qc/fastqc bam peaks logs/bowtie2 counts summary validation
    printf 'feature_id\\tfeature_type\\tchrom\\tstart\\tend\\n' > counts/peak_counts.tsv
    cp counts/peak_counts.tsv counts/re_counts.tsv
    : > counts/peak_consensus.bed
    printf 'sample_id\\tspecies\\tomics_type\\tcondition\\ttimepoint\\treference_id\\tstatus\\tn_features\\ttotal_counts\\toutput_files\\twarnings\\n' > summary/atacseq_summary.tsv
    printf 'sample_id\\tspecies\\tomics_type\\tcondition\\ttimepoint\\treference_id\\tread_layout\\tbam\\tbai\\tbam_exists\\tbam_nonempty\\ttotal_reads\\tmapped_reads\\ttotal_aligned_reads\\tmitochondrial_reads\\tmitochondrial_fraction\\tduplicate_reads\\tduplicate_fraction\\tusable_reads\\tn_peaks\\tn_consensus_peaks\\treads_in_peaks\\tfrip\\tfragment_mean\\tfragment_sd\\tstatus\\twarnings\\n' > qc/atac_qc.tsv
    printf 'severity\\tsource\\tfield\\tsample_id\\tmessage\\nINFO\\tatac_real\\t\\t\\tNo ATAC-seq samples requested\\n' > validation/atac_real_validation.tsv
    printf 'No atacseq samples\\n' > logs/bowtie2/NO_SAMPLES.log
    """
}

workflow BULK_OMICS {
    take:
    omics_samplesheet
    reference_manifest
    omics_types
    omics_stub

    main:
    explicitMode = params.omics_mode ? params.omics_mode.toString().trim().toLowerCase() : ''
    inferredMode = omics_stub.toString().toBoolean() ? 'stub' : 'real'
    omicsMode = explicitMode ?: inferredMode
    if (!(omicsMode in ['stub', 'real'])) {
        error "Unsupported --omics_mode '${params.omics_mode}'. Supported values: stub, real."
    }
    referenceCacheDir = params.reference_cache_dir ?: "${params.outdir}/reference_cache"
    metadataKind = params.real_mode_metadata ? 'real_mode_metadata' : 'omics_samplesheet'
    realMetadata = params.real_mode_metadata ? file(params.real_mode_metadata) : omics_samplesheet
    metadataBaseDir = params.real_mode_metadata ? file(params.real_mode_metadata).parent.toString() : (params.omics_samplesheet ? file(params.omics_samplesheet).parent.toString() : launchDir.toString())
    referenceBaseDir = params.reference_manifest ? file(params.reference_manifest).parent.toString() : launchDir.toString()

    if (omicsMode == 'real') {
        requestedRealOmics = omics_types.toString().split(',').collect {
            def item = it.trim().toLowerCase()
            if (item in ['rna', 'rna-seq', 'rna_seq', 'rna seq']) {
                return 'rnaseq'
            }
            if (item in ['atac', 'atac-seq', 'atac_seq', 'atac seq']) {
                return 'atacseq'
            }
            return item
        }.findAll { it }
        PREPARE_REAL_OMICS_INPUTS(
            realMetadata,
            metadataKind,
            reference_manifest,
            omics_types,
            referenceCacheDir,
            metadataBaseDir,
            referenceBaseDir,
            params.real_require_paired_atac ?: false
        )
        if (requestedRealOmics.contains('rnaseq')) {
            RNA_REAL(PREPARE_REAL_OMICS_INPUTS.out.rnaseq_manifest)
            rnaQc = RNA_REAL.out.qc
            rnaLogs = RNA_REAL.out.logs
            rnaseqCounts = RNA_REAL.out.gene_counts
            rnaseqSummary = RNA_REAL.out.summary
        } else {
            EMPTY_RNA_REAL_OUTPUTS()
            rnaQc = EMPTY_RNA_REAL_OUTPUTS.out.qc
            rnaLogs = EMPTY_RNA_REAL_OUTPUTS.out.logs
            rnaseqCounts = EMPTY_RNA_REAL_OUTPUTS.out.gene_counts
            rnaseqSummary = EMPTY_RNA_REAL_OUTPUTS.out.summary
        }
        if (requestedRealOmics.contains('atacseq')) {
            ATAC_REAL(PREPARE_REAL_OMICS_INPUTS.out.atacseq_manifest)
            atacQc = ATAC_REAL.out.qc
            atacLogs = ATAC_REAL.out.logs
            atacseqCounts = ATAC_REAL.out.re_counts
            atacseqSummary = ATAC_REAL.out.summary
        } else {
            EMPTY_ATAC_REAL_OUTPUTS()
            atacQc = EMPTY_ATAC_REAL_OUTPUTS.out.qc
            atacLogs = EMPTY_ATAC_REAL_OUTPUTS.out.logs
            atacseqCounts = EMPTY_ATAC_REAL_OUTPUTS.out.re_counts
            atacseqSummary = EMPTY_ATAC_REAL_OUTPUTS.out.summary
        }
        QC_REAL(
            PREPARE_REAL_OMICS_INPUTS.out.prepared_manifest,
            rnaQc,
            rnaLogs,
            atacQc,
            atacLogs
        )
        preparedManifest = PREPARE_REAL_OMICS_INPUTS.out.prepared_manifest
        warnings = PREPARE_REAL_OMICS_INPUTS.out.warnings
        multiqcReport = QC_REAL.out.multiqc
    } else {
        PREPARE_OMICS_INPUTS(omics_samplesheet, reference_manifest, omics_types, omics_stub)
        RNASEQ_STANDARD(PREPARE_OMICS_INPUTS.out.rnaseq_manifest, omics_stub)
        ATACSEQ_STANDARD(PREPARE_OMICS_INPUTS.out.atacseq_manifest, omics_stub)
        OMICS_QC(
            PREPARE_OMICS_INPUTS.out.prepared_manifest,
            RNASEQ_STANDARD.out.summary,
            ATACSEQ_STANDARD.out.summary,
            omics_stub
        )
        preparedManifest = PREPARE_OMICS_INPUTS.out.prepared_manifest
        rnaseqCounts = RNASEQ_STANDARD.out.gene_counts
        rnaseqSummary = RNASEQ_STANDARD.out.summary
        atacseqCounts = ATACSEQ_STANDARD.out.re_counts
        atacseqSummary = ATACSEQ_STANDARD.out.summary
        warnings = PREPARE_OMICS_INPUTS.out.warnings
        multiqcReport = OMICS_QC.out.multiqc
    }
    SUMMARIZE_OMICS_OUTPUTS(
        preparedManifest,
        rnaseqCounts,
        rnaseqSummary,
        atacseqCounts,
        atacseqSummary,
        warnings
    )

    emit:
    prepared_manifest = preparedManifest
    rnaseq_counts = rnaseqCounts
    atacseq_counts = atacseqCounts
    run_summary = SUMMARIZE_OMICS_OUTPUTS.out.run_summary
    outputs_manifest = SUMMARIZE_OMICS_OUTPUTS.out.outputs_manifest
    multiqc = multiqcReport
}
