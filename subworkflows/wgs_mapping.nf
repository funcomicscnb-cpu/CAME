process WGS_MAPPING_PLACEHOLDER {
    publishDir { "${params.outdir}/reference" }, mode: 'copy'

    input:
    path prepared_manifest
    val reference_stub

    output:
    path 'bam/wgs', emit: bam
    path 'logs/wgs_mapping', emit: logs

    script:
    """
    case "${reference_stub}" in
      true|TRUE|1|yes|YES)
        mkdir -p bam/wgs logs/wgs_mapping
        printf 'status\\tmessage\\nSTUB\\tWGS mapping placeholder was not used by the reference_prepare stub route.\\n' > logs/wgs_mapping/wgs_mapping_placeholder.tsv
        printf 'sample_id\\tpath\\tmode\\n' > bam/wgs/wgs_bam_manifest.tsv
        ;;
      *)
        command -v bwa >/dev/null 2>&1 || { echo "ERROR: bwa executable not found for reference_prepare real mode." >&2; exit 1; }
        echo "ERROR: reference_prepare real-mode BWA mapping is scaffold-only in Stage 18; no production BAMs are emitted." >&2
        exit 1
        ;;
    esac
    """
}

workflow WGS_MAPPING {
    take:
    prepared_manifest
    reference_stub

    main:
    WGS_MAPPING_PLACEHOLDER(prepared_manifest, reference_stub)

    emit:
    bam = WGS_MAPPING_PLACEHOLDER.out.bam
    logs = WGS_MAPPING_PLACEHOLDER.out.logs
}
