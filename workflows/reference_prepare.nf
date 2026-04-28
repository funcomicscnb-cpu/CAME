include { WGS_MAPPING } from '../subworkflows/wgs_mapping'
include { VARIANT_ANNOTATION } from '../subworkflows/variant_annotation'
include { REFERENCE_MASKING } from '../subworkflows/reference_masking'

process PREPARE_REFERENCE_INPUTS {
    publishDir { "${params.outdir}/reference" }, mode: 'copy'

    input:
    path wgs_samplesheet
    path reference_manifest
    path reference_prepare_config
    val reference_stub

    output:
    path 'input/reference_prepare_manifest.tsv', emit: prepared_manifest
    path 'input/reference_prepare_warnings.tsv', emit: warnings

    script:
    """
    mkdir -p input
    python3 ${projectDir}/bin/prepare_reference_inputs.py \\
      --wgs_samplesheet "${wgs_samplesheet}" \\
      --reference_manifest "${reference_manifest}" \\
      --reference_prepare_config "${reference_prepare_config}" \\
      --reference_stub "${reference_stub}" \\
      --output_dir input
    """
}

process MAKE_SYNTHETIC_REFERENCE_OUTPUTS {
    publishDir { "${params.outdir}/reference" }, mode: 'copy'

    input:
    path prepared_manifest
    val reference_stub

    output:
    path 'genomes', emit: genomes
    path 'variants', emit: variants
    path 'masks', emit: masks
    path 'cnv', emit: cnv
    path 'summary/reference_prepare_outputs.tsv', emit: outputs_table

    script:
    """
    case "${reference_stub}" in
      true|TRUE|1|yes|YES) ;;
      *)
        echo "ERROR: reference_prepare real mode must not emit synthetic outputs. Use --reference_stub true for scaffold outputs or provide a production implementation." >&2
        exit 1
        ;;
    esac
    python3 ${projectDir}/bin/make_synthetic_reference_outputs.py \\
      --prepared_manifest "${prepared_manifest}" \\
      --output_dir .
    """
}

process SUMMARIZE_REFERENCE_PREPARE {
    publishDir { "${params.outdir}/reference" }, mode: 'copy'

    input:
    path prepared_manifest
    path warnings
    path outputs_table
    path genomes_dir
    path variants_dir
    path masks_dir
    path cnv_dir
    val reference_stub

    output:
    path 'summary/reference_prepare_summary.tsv', emit: summary
    path 'summary/reference_outputs_manifest.tsv', emit: outputs_manifest

    script:
    """
    mkdir -p summary
    python3 ${projectDir}/bin/summarize_reference_prepare.py \\
      --prepared_manifest "${prepared_manifest}" \\
      --warnings "${warnings}" \\
      --outputs_table "${outputs_table}" \\
      --outputs_root . \\
      --reference_stub "${reference_stub}" \\
      --output_dir summary
    """
}

workflow REFERENCE_PREPARE {
    take:
    wgs_samplesheet
    reference_manifest
    reference_prepare_config
    reference_stub

    main:
    PREPARE_REFERENCE_INPUTS(wgs_samplesheet, reference_manifest, reference_prepare_config, reference_stub)

    if (params.reference_stub.toString().toBoolean()) {
        MAKE_SYNTHETIC_REFERENCE_OUTPUTS(PREPARE_REFERENCE_INPUTS.out.prepared_manifest, reference_stub)
        referenceGenomes = MAKE_SYNTHETIC_REFERENCE_OUTPUTS.out.genomes
        referenceVariants = MAKE_SYNTHETIC_REFERENCE_OUTPUTS.out.variants
        referenceMasks = MAKE_SYNTHETIC_REFERENCE_OUTPUTS.out.masks
        referenceCnv = MAKE_SYNTHETIC_REFERENCE_OUTPUTS.out.cnv
        referenceOutputsTable = MAKE_SYNTHETIC_REFERENCE_OUTPUTS.out.outputs_table
    } else {
        WGS_MAPPING(PREPARE_REFERENCE_INPUTS.out.prepared_manifest, reference_stub)
        VARIANT_ANNOTATION(PREPARE_REFERENCE_INPUTS.out.prepared_manifest, WGS_MAPPING.out.bam, reference_stub)
        REFERENCE_MASKING(PREPARE_REFERENCE_INPUTS.out.prepared_manifest, VARIANT_ANNOTATION.out.variants, reference_stub)
        referenceGenomes = REFERENCE_MASKING.out.genomes
        referenceVariants = VARIANT_ANNOTATION.out.variants
        referenceMasks = REFERENCE_MASKING.out.masks
        referenceCnv = REFERENCE_MASKING.out.cnv
        referenceOutputsTable = REFERENCE_MASKING.out.outputs_table
    }

    SUMMARIZE_REFERENCE_PREPARE(
        PREPARE_REFERENCE_INPUTS.out.prepared_manifest,
        PREPARE_REFERENCE_INPUTS.out.warnings,
        referenceOutputsTable,
        referenceGenomes,
        referenceVariants,
        referenceMasks,
        referenceCnv,
        reference_stub
    )

    emit:
    prepared_manifest = PREPARE_REFERENCE_INPUTS.out.prepared_manifest
    warnings = PREPARE_REFERENCE_INPUTS.out.warnings
    summary = SUMMARIZE_REFERENCE_PREPARE.out.summary
    outputs_manifest = SUMMARIZE_REFERENCE_PREPARE.out.outputs_manifest
}
