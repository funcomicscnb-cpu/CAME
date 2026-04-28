process CONTACT_LINKING_PLACEHOLDER {
    publishDir { "${params.outdir}/re_to_gene_inference" }, mode: 'copy'

    input:
    path prepared_manifest
    val re_to_gene_inference_stub

    output:
    path 're_to_gene_links.tsv', emit: links
    path 're_to_gene_inference_warnings.tsv', emit: warnings

    script:
    """
    case "${re_to_gene_inference_stub}" in
      true|TRUE|1|yes|YES)
        printf 'species\\tre_feature_id\\tgene_feature_id\\tlink_type\\tre_orthogroup_id\\tgene_orthogroup_id\\tdistance_to_tss\\tcontact_score\\tlink_confidence\\tsource\\tnotes\\n' > re_to_gene_links.tsv
        printf 'severity\\tinference_id\\tre_feature_id\\tgene_feature_id\\tmessage\\n' > re_to_gene_inference_warnings.tsv
        ;;
      *)
        echo "ERROR: re_to_gene_inference real-mode chromatin-contact linking is scaffold-only in Stage 20; no production links are emitted." >&2
        exit 1
        ;;
    esac
    """
}

workflow CONTACT_LINKING {
    take:
    prepared_manifest
    re_to_gene_inference_stub

    main:
    CONTACT_LINKING_PLACEHOLDER(prepared_manifest, re_to_gene_inference_stub)

    emit:
    links = CONTACT_LINKING_PLACEHOLDER.out.links
    warnings = CONTACT_LINKING_PLACEHOLDER.out.warnings
}
