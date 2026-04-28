process REFERENCE_MASKING_PLACEHOLDER {
    publishDir { "${params.outdir}/reference" }, mode: 'copy'

    input:
    path prepared_manifest
    path variants_dir
    val reference_stub

    output:
    path 'genomes', emit: genomes
    path 'masks', emit: masks
    path 'cnv', emit: cnv
    path 'summary/reference_prepare_outputs.tsv', emit: outputs_table

    script:
    """
    case "${reference_stub}" in
      true|TRUE|1|yes|YES)
        mkdir -p genomes masks cnv summary
        printf 'reference_id\\tspecies\\toutput_type\\tpath\\tmode\\tstatus\\tdescription\\n' > summary/reference_prepare_outputs.tsv
        ;;
      *)
        command -v bedtools >/dev/null 2>&1 || { echo "ERROR: bedtools executable not found for reference_prepare real mode." >&2; exit 1; }
        echo "ERROR: reference_prepare real-mode masking/CNV integration is scaffold-only in Stage 18; no production masks are emitted." >&2
        exit 1
        ;;
    esac
    """
}

workflow REFERENCE_MASKING {
    take:
    prepared_manifest
    variants_dir
    reference_stub

    main:
    REFERENCE_MASKING_PLACEHOLDER(prepared_manifest, variants_dir, reference_stub)

    emit:
    genomes = REFERENCE_MASKING_PLACEHOLDER.out.genomes
    masks = REFERENCE_MASKING_PLACEHOLDER.out.masks
    cnv = REFERENCE_MASKING_PLACEHOLDER.out.cnv
    outputs_table = REFERENCE_MASKING_PLACEHOLDER.out.outputs_table
}
