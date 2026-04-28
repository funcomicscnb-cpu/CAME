include { FASTQC as FASTQC_ATACSEQ } from '../modules/fastqc/main'
include { BWA_MEM as BWA_MEM_ATAC } from '../modules/bwa_mem/main'
include { SAMTOOLS_FILTER as SAMTOOLS_FILTER_ATAC } from '../modules/samtools_filter/main'
include { HMMRATAC as HMMRATAC_PEAKS } from '../modules/hmmratac/main'
include { BEDTOOLS_COUNTS as BEDTOOLS_COUNTS_ATAC } from '../modules/bedtools_counts/main'

process ATACSEQ_SUMMARY {
    publishDir { "${params.outdir}/atacseq" }, mode: 'copy'

    input:
    path manifest
    path counts
    path filtered_bam
    path peaks

    output:
    path 'summary/atacseq_summary.tsv', emit: summary

    script:
    """
    mkdir -p summary
    python3 - "${manifest}" "${counts}" "summary/atacseq_summary.tsv" <<'PY'
import csv
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
            "omics_type": "atacseq",
            "condition": row.get("condition", ""),
            "timepoint": row.get("timepoint", ""),
            "reference_id": row.get("reference_id", ""),
            "status": "ERROR" if sample_id in missing else "OK",
            "n_features": str(len(count_rows)),
            "total_counts": str(total),
            "output_files": counts_path,
            "warnings": "sample missing from re_counts.tsv" if sample_id in missing else "",
        })
if missing:
    raise SystemExit("Missing ATAC-seq sample column(s): " + ", ".join(missing))
PY
    """
}

workflow ATACSEQ_STANDARD {
    take:
    manifest
    omics_stub

    main:
    FASTQC_ATACSEQ(manifest, 'atacseq', omics_stub)
    BWA_MEM_ATAC(manifest, omics_stub)
    SAMTOOLS_FILTER_ATAC(manifest, BWA_MEM_ATAC.out.raw_bam, omics_stub)
    HMMRATAC_PEAKS(manifest, SAMTOOLS_FILTER_ATAC.out.filtered_bam, omics_stub)
    BEDTOOLS_COUNTS_ATAC(manifest, HMMRATAC_PEAKS.out.peaks, SAMTOOLS_FILTER_ATAC.out.filtered_bam, omics_stub)
    ATACSEQ_SUMMARY(manifest, BEDTOOLS_COUNTS_ATAC.out.counts, SAMTOOLS_FILTER_ATAC.out.filtered_bam, HMMRATAC_PEAKS.out.peaks)

    emit:
    fastqc = FASTQC_ATACSEQ.out.fastqc
    raw_bam = BWA_MEM_ATAC.out.raw_bam
    filtered_bam = SAMTOOLS_FILTER_ATAC.out.filtered_bam
    peaks = HMMRATAC_PEAKS.out.peaks
    re_counts = BEDTOOLS_COUNTS_ATAC.out.counts
    summary = ATACSEQ_SUMMARY.out.summary
}
