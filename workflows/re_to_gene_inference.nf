include { PROMOTER_LINKING } from '../subworkflows/promoter_linking'
include { PROXIMITY_LINKING } from '../subworkflows/proximity_linking'
include { CONTACT_LINKING } from '../subworkflows/contact_linking'

process PREPARE_RE_TO_GENE_INFERENCE_INPUTS {
    publishDir { "${params.outdir}/re_to_gene_inference" }, mode: 'copy'

    input:
    path regulatory_regions
    path gene_coordinates
    val chromatin_contacts
    path re_to_gene_inference_config
    val re_to_gene_inference_stub

    output:
    path 'input/re_to_gene_inference_manifest.tsv', emit: prepared_manifest
    path 'input/re_to_gene_inference_warnings.tsv', emit: warnings

    script:
    """
    mkdir -p input
    python3 ${projectDir}/bin/prepare_re_to_gene_inference_inputs.py \\
      --regulatory_regions "${regulatory_regions}" \\
      --gene_coordinates "${gene_coordinates}" \\
      --chromatin_contacts "${chromatin_contacts}" \\
      --re_to_gene_inference_config "${re_to_gene_inference_config}" \\
      --re_to_gene_inference_stub "${re_to_gene_inference_stub}" \\
      --output_dir input
    """
}

process MAKE_SYNTHETIC_RE_TO_GENE_LINKS {
    publishDir { "${params.outdir}/re_to_gene_inference" }, mode: 'copy'

    input:
    path prepared_manifest
    val re_to_gene_inference_stub

    output:
    path 're_to_gene_links.tsv', emit: links
    path 're_to_gene_inference_warnings.tsv', emit: warnings

    script:
    """
    python3 ${projectDir}/bin/make_synthetic_re_to_gene_links.py \\
      --prepared_manifest "${prepared_manifest}" \\
      --re_to_gene_inference_stub "${re_to_gene_inference_stub}" \\
      --output_dir .
    """
}

process SUMMARIZE_RE_TO_GENE_INFERENCE {
    publishDir { "${params.outdir}/re_to_gene_inference" }, mode: 'copy'

    input:
    path prepared_manifest
    path re_to_gene_links
    path inference_warnings
    val re_to_gene_inference_stub

    output:
    path 'summary/re_to_gene_inference_summary.tsv', emit: summary
    path 'summary/re_to_gene_inference_outputs_manifest.tsv', emit: outputs_manifest

    script:
    """
    mkdir -p summary
    python3 ${projectDir}/bin/summarize_re_to_gene_inference.py \\
      --prepared_manifest "${prepared_manifest}" \\
      --re_to_gene_links "${re_to_gene_links}" \\
      --inference_warnings "${inference_warnings}" \\
      --re_to_gene_inference_stub "${re_to_gene_inference_stub}" \\
      --output_dir summary
    """
}

workflow RE_TO_GENE_INFERENCE {
    take:
    regulatory_regions
    gene_coordinates
    chromatin_contacts
    re_to_gene_inference_config
    re_to_gene_inference_stub

    main:
    PREPARE_RE_TO_GENE_INFERENCE_INPUTS(
        regulatory_regions,
        gene_coordinates,
        chromatin_contacts,
        re_to_gene_inference_config,
        re_to_gene_inference_stub
    )

    if (params.re_to_gene_inference_stub.toString().toBoolean()) {
        MAKE_SYNTHETIC_RE_TO_GENE_LINKS(
            PREPARE_RE_TO_GENE_INFERENCE_INPUTS.out.prepared_manifest,
            re_to_gene_inference_stub
        )
        reToGeneLinks = MAKE_SYNTHETIC_RE_TO_GENE_LINKS.out.links
        inferenceWarnings = MAKE_SYNTHETIC_RE_TO_GENE_LINKS.out.warnings
    } else {
        PROMOTER_LINKING(
            PREPARE_RE_TO_GENE_INFERENCE_INPUTS.out.prepared_manifest,
            re_to_gene_inference_stub
        )
        PROXIMITY_LINKING(
            PREPARE_RE_TO_GENE_INFERENCE_INPUTS.out.prepared_manifest,
            re_to_gene_inference_stub
        )
        CONTACT_LINKING(
            PREPARE_RE_TO_GENE_INFERENCE_INPUTS.out.prepared_manifest,
            re_to_gene_inference_stub
        )
        reToGeneLinks = PROMOTER_LINKING.out.links
        inferenceWarnings = PROMOTER_LINKING.out.warnings
    }

    SUMMARIZE_RE_TO_GENE_INFERENCE(
        PREPARE_RE_TO_GENE_INFERENCE_INPUTS.out.prepared_manifest,
        reToGeneLinks,
        inferenceWarnings,
        re_to_gene_inference_stub
    )

    emit:
    prepared_manifest = PREPARE_RE_TO_GENE_INFERENCE_INPUTS.out.prepared_manifest
    input_warnings = PREPARE_RE_TO_GENE_INFERENCE_INPUTS.out.warnings
    links = reToGeneLinks
    warnings = inferenceWarnings
    summary = SUMMARIZE_RE_TO_GENE_INFERENCE.out.summary
    outputs_manifest = SUMMARIZE_RE_TO_GENE_INFERENCE.out.outputs_manifest
}
