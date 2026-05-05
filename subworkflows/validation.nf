process VALIDATE_METADATA {
    publishDir { "${params.outdir}/validation" }, mode: 'copy'

    input:
    path phenotype_samplesheet
    path omics_samplesheet
    path species_traits
    path reference_manifest
    path phylogeny_manifest
    path study_design
    val validation_strict

    output:
    path 'metadata_validation_report.tsv', emit: report

    script:
    """
    python3 ${projectDir}/bin/validate_metadata.py \\
      --phenotype_samplesheet ${phenotype_samplesheet} \\
      --omics_samplesheet ${omics_samplesheet} \\
      --species_traits ${species_traits} \\
      --reference_manifest ${reference_manifest} \\
      --phylogeny_manifest ${phylogeny_manifest} \\
      --study_design ${study_design} \\
      ${validation_strict ? '--validation_strict' : ''} \\
      --schema_dir "${projectDir}/assets/schema" \\
      --report metadata_validation_report.tsv
    """
}

process VALIDATE_STUDY_PROFILE {
    publishDir { "${params.outdir}/validation" }, mode: 'copy'

    input:
    path study_profile
    path phenotype_samplesheet
    path species_traits
    val validation_strict

    output:
    path 'study_profile_validation_report.tsv', emit: report

    script:
    """
    python3 ${projectDir}/bin/validate_study_profile.py \\
      --study_profile ${study_profile} \\
      --phenotype_samplesheet ${phenotype_samplesheet} \\
      --species_traits ${species_traits} \\
      ${validation_strict ? '--validation_strict' : ''} \\
      --schema_dir "${projectDir}/assets/schema" \\
      --output study_profile_validation_report.tsv
    """
}

process VALIDATE_PHYLO_METADATA {
    publishDir { "${params.outdir}/validation" }, mode: 'copy'

    input:
    path phenotype_samplesheet
    path species_traits
    path phylogeny_manifest

    output:
    path 'metadata_validation_report.tsv', emit: report

    script:
    """
    python3 ${projectDir}/bin/validate_metadata.py \\
      --mode phylo \\
      --phenotype_samplesheet ${phenotype_samplesheet} \\
      --species_traits ${species_traits} \\
      --phylogeny_manifest ${phylogeny_manifest} \\
      --schema_dir "${projectDir}/assets/schema" \\
      --report metadata_validation_report.tsv
    """
}

process VALIDATE_REAL_MODE_REQUIREMENTS {
    publishDir { "${params.outdir}/validation" }, mode: 'copy', pattern: '*validation_report.tsv'

    input:
    path reference_manifest
    path real_mode_metadata
    val assays

    output:
    path 'reference_manifest_real_mode_validation_report.tsv', emit: reference_report
    path 'real_mode_metadata_validation_report.tsv', emit: metadata_report
    path 'real_mode_validation_status.tsv', emit: status
    path 'validated_reference_manifest.tsv', emit: reference_manifest
    path 'validated_real_mode_metadata.tsv', emit: metadata

    script:
    """
    ref_status=0
    python3 ${projectDir}/bin/validate_reference_manifest.py \\
      --manifest "${reference_manifest}" \\
      --assays "${assays}" \\
      --report reference_manifest_real_mode_validation_report.tsv || ref_status=\$?

    metadata_status=0
    python3 ${projectDir}/bin/validate_real_mode_metadata.py \\
      --metadata "${real_mode_metadata}" \\
      --reference_manifest "${reference_manifest}" \\
      --report real_mode_metadata_validation_report.tsv || metadata_status=\$?

    printf 'validator\\texit_status\\nreference_manifest\\t%s\\nreal_mode_metadata\\t%s\\n' "\$ref_status" "\$metadata_status" > real_mode_validation_status.tsv
    if [ "\$(basename "${reference_manifest}")" != "validated_reference_manifest.tsv" ]; then
      cp "${reference_manifest}" validated_reference_manifest.tsv
    fi
    if [ "\$(basename "${real_mode_metadata}")" != "validated_real_mode_metadata.tsv" ]; then
      cp "${real_mode_metadata}" validated_real_mode_metadata.tsv
    fi
    """
}

process CHECK_REAL_MODE_REQUIREMENTS {
    input:
    path status
    path reference_report
    path metadata_report
    path reference_manifest
    path real_mode_metadata

    output:
    path 'validated_reference_manifest.tsv', emit: reference_manifest
    path 'validated_real_mode_metadata.tsv', emit: metadata
    path 'real_mode_validation_done.txt', emit: done

    script:
    """
    awk -F '\\t' 'NR > 1 && \$2 != 0 { bad = 1 } END { exit bad ? 1 : 0 }' ${status}
    printf 'real_mode_validation\\tPASS\\n' > real_mode_validation_done.txt
    """
}

workflow METADATA_VALIDATION {
    take:
    phenotype_samplesheet
    omics_samplesheet
    species_traits
    reference_manifest
    phylogeny_manifest
    study_design
    validation_strict

    main:
    VALIDATE_METADATA(
        phenotype_samplesheet,
        omics_samplesheet,
        species_traits,
        reference_manifest,
        phylogeny_manifest,
        study_design,
        validation_strict
    )

    emit:
    report = VALIDATE_METADATA.out.report
}

workflow STUDY_PROFILE_VALIDATION {
    take:
    study_profile
    phenotype_samplesheet
    species_traits
    validation_strict

    main:
    VALIDATE_STUDY_PROFILE(study_profile, phenotype_samplesheet, species_traits, validation_strict)

    emit:
    report = VALIDATE_STUDY_PROFILE.out.report
}

workflow PHYLO_METADATA_VALIDATION {
    take:
    phenotype_samplesheet
    species_traits
    phylogeny_manifest

    main:
    VALIDATE_PHYLO_METADATA(phenotype_samplesheet, species_traits, phylogeny_manifest)

    emit:
    report = VALIDATE_PHYLO_METADATA.out.report
}

workflow REAL_MODE_REQUIREMENTS_VALIDATION {
    take:
    reference_manifest
    real_mode_metadata
    assays

    main:
    VALIDATE_REAL_MODE_REQUIREMENTS(reference_manifest, real_mode_metadata, assays)
    CHECK_REAL_MODE_REQUIREMENTS(
        VALIDATE_REAL_MODE_REQUIREMENTS.out.status,
        VALIDATE_REAL_MODE_REQUIREMENTS.out.reference_report,
        VALIDATE_REAL_MODE_REQUIREMENTS.out.metadata_report,
        VALIDATE_REAL_MODE_REQUIREMENTS.out.reference_manifest,
        VALIDATE_REAL_MODE_REQUIREMENTS.out.metadata
    )

    emit:
    reference_report = VALIDATE_REAL_MODE_REQUIREMENTS.out.reference_report
    metadata_report = VALIDATE_REAL_MODE_REQUIREMENTS.out.metadata_report
    status = VALIDATE_REAL_MODE_REQUIREMENTS.out.status
    reference_manifest = CHECK_REAL_MODE_REQUIREMENTS.out.reference_manifest
    metadata = CHECK_REAL_MODE_REQUIREMENTS.out.metadata
    done = CHECK_REAL_MODE_REQUIREMENTS.out.done
}
