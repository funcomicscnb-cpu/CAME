include { WGS_REAL } from '../subworkflows/wgs_real'

workflow WGS_VARIANTS {
    take:
    wgs_samplesheet
    reference_manifest
    wgs_mode
    wgs_variant_mode
    wgs_filtering_mode
    require_known_sites
    allow_no_bqsr

    main:
    WGS_REAL(
        wgs_samplesheet,
        reference_manifest,
        wgs_mode,
        wgs_variant_mode,
        wgs_filtering_mode,
        require_known_sites,
        allow_no_bqsr
    )

    emit:
    bam = WGS_REAL.out.bam
    variants = WGS_REAL.out.variants
    alignment_qc = WGS_REAL.out.alignment_qc
    variant_qc = WGS_REAL.out.variant_qc
    summary = WGS_REAL.out.summary
    outputs_manifest = WGS_REAL.out.outputs_manifest
    validation = WGS_REAL.out.validation
}
