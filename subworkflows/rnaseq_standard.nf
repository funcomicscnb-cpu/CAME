include { FASTQC as FASTQC_RNASEQ } from '../modules/fastqc/main'
include { STAR_ALIGN } from '../modules/star_align/main'
include { FEATURECOUNTS } from '../modules/featurecounts/main'

process RNASEQ_SUMMARY {
    publishDir { "${params.outdir}/rnaseq" }, mode: 'copy'

    input:
    path manifest
    path counts
    path bam_dir
    path logs_dir

    output:
    path 'summary/rnaseq_summary.tsv', emit: summary

    script:
    """
    mkdir -p summary
    python3 - "${manifest}" "${counts}" "summary/rnaseq_summary.tsv" <<'PY'
import csv
import os
import sys

manifest, counts_path, output = sys.argv[1:4]
samples = list(csv.DictReader(open(manifest), delimiter="\\t"))
with open(counts_path, newline="") as handle:
    reader = csv.DictReader(handle, delimiter="\\t")
    fields = reader.fieldnames or []
    count_rows = list(reader)
sample_ids = [row["sample_id"] for row in samples]
missing = [sample_id for sample_id in sample_ids if sample_id not in fields]
with open(output, "w", newline="") as handle:
    out_fields = ["sample_id", "species", "omics_type", "condition", "timepoint", "reference_id", "status", "n_features", "total_counts", "output_files", "warnings"]
    writer = csv.DictWriter(handle, fieldnames=out_fields, delimiter="\\t", lineterminator="\\n")
    writer.writeheader()
    for row in samples:
        sample_id = row["sample_id"]
        total = 0
        if sample_id in fields:
            total = sum(int(float(item.get(sample_id) or 0)) for item in count_rows)
        writer.writerow({
            "sample_id": sample_id,
            "species": row.get("species", ""),
            "omics_type": "rnaseq",
            "condition": row.get("condition", ""),
            "timepoint": row.get("timepoint", ""),
            "reference_id": row.get("reference_id", ""),
            "status": "ERROR" if sample_id in missing else "OK",
            "n_features": str(len(count_rows)),
            "total_counts": str(total),
            "output_files": counts_path,
            "warnings": "sample missing from gene_counts.tsv" if sample_id in missing else "",
        })
if missing:
    raise SystemExit("Missing RNA-seq sample column(s): " + ", ".join(missing))
PY
    """
}

workflow RNASEQ_STANDARD {
    take:
    manifest
    omics_stub

    main:
    FASTQC_RNASEQ(manifest, 'rnaseq', omics_stub)
    STAR_ALIGN(manifest, omics_stub)
    FEATURECOUNTS(manifest, STAR_ALIGN.out.bam, omics_stub)
    RNASEQ_SUMMARY(manifest, FEATURECOUNTS.out.counts, STAR_ALIGN.out.bam, STAR_ALIGN.out.logs)

    emit:
    fastqc = FASTQC_RNASEQ.out.fastqc
    bam = STAR_ALIGN.out.bam
    logs = STAR_ALIGN.out.logs
    gene_counts = FEATURECOUNTS.out.counts
    summary = RNASEQ_SUMMARY.out.summary
}
