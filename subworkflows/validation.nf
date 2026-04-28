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
