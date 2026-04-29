process REFERENCE_ASSET_VALIDATION {
    publishDir { "${params.outdir}/reference_quality" }, mode: 'copy'
    label 'process_low'

    input:
    path reference_manifest
    val assay
    val check_paths
    val strict
    val allow_low_quality_reference

    output:
    path 'reference_asset_validation.tsv', emit: validation
    path 'reference_asset_warnings.tsv', emit: warnings
    path 'reference_asset_summary.tsv', emit: summary

    script:
    """
    python3 ${projectDir}/bin/validate_reference_assets.py \\
      --reference_manifest "${reference_manifest}" \\
      --outdir . \\
      --check-paths "${check_paths}" \\
      --strict "${strict}" \\
      --assay "${assay}" \\
      --allow_low_quality_reference "${allow_low_quality_reference}"
    """
}

process PARSE_REFERENCE_ASSEMBLY_REPORTS {
    publishDir { "${params.outdir}/reference_quality" }, mode: 'copy'
    label 'process_low'

    input:
    path reference_manifest
    val check_paths
    val strict

    output:
    path 'seqname_alias_map.tsv', emit: alias_map
    path 'assembly_report_warnings.tsv', emit: warnings

    script:
    """
    python3 ${projectDir}/bin/parse_assembly_report.py \\
      --reference_manifest "${reference_manifest}" \\
      --outdir . \\
      --check-paths "${check_paths}" \\
      --strict "${strict}"
    """
}

process CHECK_REFERENCE_SEQNAME_CONCORDANCE {
    publishDir { "${params.outdir}/reference_quality" }, mode: 'copy'
    label 'process_low'

    input:
    path reference_manifest
    path alias_map
    val check_paths
    val strict

    output:
    path 'seqname_concordance.tsv', emit: concordance
    path 'seqname_concordance_warnings.tsv', emit: warnings

    script:
    """
    python3 ${projectDir}/bin/check_seqname_concordance.py \\
      --reference_manifest "${reference_manifest}" \\
      --alias_map "${alias_map}" \\
      --outdir . \\
      --check-paths "${check_paths}" \\
      --strict "${strict}"
    """
}

process SUMMARIZE_REFERENCE_QUALITY {
    publishDir { "${params.outdir}/reference_quality" }, mode: 'copy'
    label 'process_low'

    input:
    path reference_manifest
    path asset_validation
    path asset_warnings
    path assembly_warnings
    path seqname_concordance
    path seqname_warnings

    output:
    path 'reference_quality_summary.tsv', emit: summary
    path 'reference_quality_manifest.tsv', emit: manifest
    path 'validated_reference_manifest.tsv', emit: reference_manifest
    path 'reference_quality_done.txt', emit: done

    script:
    """
    python3 ${projectDir}/bin/summarize_reference_quality.py \\
      --reference_manifest "${reference_manifest}" \\
      --outdir . \\
      --asset_validation "${asset_validation}" \\
      --asset_warnings "${asset_warnings}" \\
      --assembly_warnings "${assembly_warnings}" \\
      --seqname_concordance "${seqname_concordance}" \\
      --seqname_warnings "${seqname_warnings}"
    [ -e validated_reference_manifest.tsv ] || cp "${reference_manifest}" validated_reference_manifest.tsv
    printf 'reference_quality\\tPASS\\n' > reference_quality_done.txt
    """
}

workflow REFERENCE_QUALITY {
    take:
    reference_manifest
    assay
    check_paths
    strict
    allow_low_quality_reference

    main:
    REFERENCE_ASSET_VALIDATION(reference_manifest, assay, check_paths, strict, allow_low_quality_reference)
    PARSE_REFERENCE_ASSEMBLY_REPORTS(reference_manifest, check_paths, strict)
    CHECK_REFERENCE_SEQNAME_CONCORDANCE(
        reference_manifest,
        PARSE_REFERENCE_ASSEMBLY_REPORTS.out.alias_map,
        check_paths,
        strict
    )
    SUMMARIZE_REFERENCE_QUALITY(
        reference_manifest,
        REFERENCE_ASSET_VALIDATION.out.validation,
        REFERENCE_ASSET_VALIDATION.out.warnings,
        PARSE_REFERENCE_ASSEMBLY_REPORTS.out.warnings,
        CHECK_REFERENCE_SEQNAME_CONCORDANCE.out.concordance,
        CHECK_REFERENCE_SEQNAME_CONCORDANCE.out.warnings
    )

    emit:
    asset_validation = REFERENCE_ASSET_VALIDATION.out.validation
    asset_warnings = REFERENCE_ASSET_VALIDATION.out.warnings
    asset_summary = REFERENCE_ASSET_VALIDATION.out.summary
    alias_map = PARSE_REFERENCE_ASSEMBLY_REPORTS.out.alias_map
    assembly_warnings = PARSE_REFERENCE_ASSEMBLY_REPORTS.out.warnings
    seqname_concordance = CHECK_REFERENCE_SEQNAME_CONCORDANCE.out.concordance
    seqname_warnings = CHECK_REFERENCE_SEQNAME_CONCORDANCE.out.warnings
    summary = SUMMARIZE_REFERENCE_QUALITY.out.summary
    manifest = SUMMARIZE_REFERENCE_QUALITY.out.manifest
    reference_manifest = SUMMARIZE_REFERENCE_QUALITY.out.reference_manifest
    done = SUMMARIZE_REFERENCE_QUALITY.out.done
}
