process VALIDATE_METADATA {
    publishDir { "${params.outdir}/validation" }, mode: 'copy'

    input:
    path phenotype_samplesheet
    path omics_samplesheet
    path species_traits
    path reference_manifest
    path phylogeny_manifest
    path study_design

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
      --report metadata_validation_report.tsv
    """
}

process VALIDATE_STUDY_PROFILE {
    publishDir { "${params.outdir}/validation" }, mode: 'copy'

    input:
    path study_profile
    path phenotype_samplesheet
    path species_traits

    output:
    path 'study_profile_validation_report.tsv', emit: report

    script:
    """
    python3 ${projectDir}/bin/validate_study_profile.py \\
      --study_profile ${study_profile} \\
      --phenotype_samplesheet ${phenotype_samplesheet} \\
      --species_traits ${species_traits} \\
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
    python3 - <<'PY'
import csv
import os
import sys
from collections import defaultdict

def norm(value):
    return str(value or "").strip()

def infer_delimiter(path):
    with open(path, newline="") as handle:
        sample = handle.read(4096)
    return "\\t" if sample.count("\\t") > sample.count(",") else ","

def read_table(path, source, records):
    if not os.path.exists(path):
        records.append(("ERROR", source, "", "", f"File does not exist: {path}"))
        return [], []
    try:
        with open(path, newline="") as handle:
            reader = csv.DictReader(handle, delimiter=infer_delimiter(path))
            return reader.fieldnames or [], list(reader)
    except Exception as exc:
        records.append(("ERROR", source, "", "", f"Could not read table: {exc}"))
        return [], []

def require_columns(source, fields, required, records):
    for field in required:
        if field not in fields:
            records.append(("ERROR", source, field, "", "Missing required column"))

records = []
pheno_fields, pheno_rows = read_table("${phenotype_samplesheet}", "phenotype_samplesheet", records)
trait_fields, trait_rows = read_table("${species_traits}", "species_traits", records)
phylo_fields, phylo_rows = read_table("${phylogeny_manifest}", "phylogeny_manifest", records)
require_columns("phenotype_samplesheet", pheno_fields, ["sample_id", "species", "condition", "timepoint", "measurement", "value"], records)
require_columns("species_traits", trait_fields, ["species", "phylogeny_label", "trait_value"], records)
require_columns("phylogeny_manifest", phylo_fields, ["phylogeny_id", "phylogeny_file"], records)

trait_species = {norm(row.get("species")) for row in trait_rows if norm(row.get("species"))}
for idx, row in enumerate(pheno_rows, start=2):
    species = norm(row.get("species"))
    if species and species not in trait_species:
        records.append(("ERROR", "phenotype_samplesheet", "species", str(idx), f"Species not found in species_traits: {species}"))

labels_by_species = defaultdict(set)
for row in trait_rows:
    species = norm(row.get("species"))
    label = norm(row.get("phylogeny_label"))
    if species and label:
        labels_by_species[species].add(label)
for species, labels in sorted(labels_by_species.items()):
    if len(labels) > 1:
        records.append(("ERROR", "species_traits", "phylogeny_label", "", f"Multiple phylogeny labels for species {species}: {', '.join(sorted(labels))}"))
trait_label = {species: next(iter(labels)) for species, labels in labels_by_species.items() if len(labels) == 1}
for idx, row in enumerate(phylo_rows, start=2):
    species = norm(row.get("species"))
    label = norm(row.get("phylogeny_label"))
    if species and species not in trait_species:
        records.append(("ERROR", "phylogeny_manifest", "species", str(idx), f"Species not found in species_traits: {species}"))
    if species and label and trait_label.get(species) and label != trait_label[species]:
        records.append(("ERROR", "phylogeny_manifest", "phylogeny_label", str(idx), f"Phylogeny label for {species} differs from species_traits"))
records.append(("INFO", "validation", "", "", "Validated Stage 4 metadata inputs"))

with open("metadata_validation_report.tsv", "w", newline="") as handle:
    writer = csv.writer(handle, delimiter="\\t")
    writer.writerow(["severity", "source", "field", "row", "message"])
    writer.writerows(records)
errors = sum(1 for row in records if row[0] == "ERROR")
warnings = sum(1 for row in records if row[0] == "WARNING")
print(f"CAME Stage 4 metadata validation summary ERROR={errors} WARNING={warnings}")
sys.exit(1 if errors else 0)
PY
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

    main:
    VALIDATE_METADATA(
        phenotype_samplesheet,
        omics_samplesheet,
        species_traits,
        reference_manifest,
        phylogeny_manifest,
        study_design
    )

    emit:
    report = VALIDATE_METADATA.out.report
}

workflow STUDY_PROFILE_VALIDATION {
    take:
    study_profile
    phenotype_samplesheet
    species_traits

    main:
    VALIDATE_STUDY_PROFILE(study_profile, phenotype_samplesheet, species_traits)

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
