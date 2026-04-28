process GATK_VARIANT_CALLING {
    publishDir { "${params.outdir}/reference" }, mode: 'copy'

    input:
    path prepared_manifest
    path bam_dir
    val reference_stub

    output:
    path 'variants', emit: variants
    path 'logs/gatk', emit: logs

    script:
    """
    case "${reference_stub}" in
      true|TRUE|1|yes|YES)
        mkdir -p variants logs/gatk
        printf 'status\\tmessage\\nSTUB\\tGATK placeholder was not used by the reference_prepare stub route.\\n' > logs/gatk/gatk_placeholder.tsv
        printf '##fileformat=VCFv4.2\\n#CHROM\\tPOS\\tID\\tREF\\tALT\\tQUAL\\tFILTER\\tINFO\\n' > variants/gatk_placeholder.vcf
        ;;
      *)
        command -v gatk >/dev/null 2>&1 || { echo "ERROR: gatk executable not found for reference_prepare real mode." >&2; exit 1; }
        echo "ERROR: reference_prepare real-mode GATK variant calling is scaffold-only in Stage 18; no production VCFs are emitted." >&2
        exit 1
        ;;
    esac
    """
}
