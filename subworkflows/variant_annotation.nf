include { GATK_VARIANT_CALLING } from '../modules/gatk/main'

workflow VARIANT_ANNOTATION {
    take:
    prepared_manifest
    bam_dir
    reference_stub

    main:
    GATK_VARIANT_CALLING(prepared_manifest, bam_dir, reference_stub)

    emit:
    variants = GATK_VARIANT_CALLING.out.variants
    logs = GATK_VARIANT_CALLING.out.logs
}
