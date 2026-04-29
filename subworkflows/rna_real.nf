process RNA_SPLIT_MANIFEST {
    label 'process_low'

    input:
    path manifest

    output:
    path 'split/manifest/rnaseq_manifest.tsv', emit: manifest
    path 'split/samples/*.tsv', optional: true, emit: samples
    path 'split/references/*.tsv', optional: true, emit: references

    script:
    """
    set -euo pipefail
    backend="${params.rna_backend ?: 'star'}"
    if [ "\$backend" = "salmon" ]; then
      echo "ERROR: Salmon backend is declared but not implemented in this release." >&2
      exit 1
    fi
    if [ "\$backend" != "star" ]; then
      echo "ERROR: Unsupported --rna_backend '\$backend'. Supported value: star." >&2
      exit 1
    fi
    python3 ${projectDir}/bin/split_real_mode_manifest.py \\
      --manifest "${manifest}" \\
      --assay rnaseq \\
      --output_dir split
    """
}

process RNA_STAR_INDEX {
    label 'process_star_index'

    input:
    tuple val(reference_key), path(reference_manifest)

    output:
    path 'logs/star/*', emit: logs
    path "index/${reference_key}.done", emit: done

    script:
    """
    set -euo pipefail
    command -v STAR >/dev/null 2>&1 || { echo "ERROR: STAR executable not found for RNA-seq real mode. Install it or run --omics_mode stub." >&2; exit 1; }
    mkdir -p logs/star index
    python3 - "${reference_manifest}" "${task.cpus}" <<'PY' > build_star_index.sh
import csv
import os
import shlex
import sys

manifest, cpus = sys.argv[1], sys.argv[2]
row = next(csv.DictReader(open(manifest), delimiter="\\t"))
genome_dir = row["star_index"]

def fasta_len(path):
    total = 0
    with open(path) as handle:
        for line in handle:
            if not line.startswith(">"):
                total += len(line.strip())
    return total

def star_index_exists(path):
    return os.path.isdir(path) and os.path.exists(os.path.join(path, "SA"))

if not star_index_exists(genome_dir):
    os.makedirs(genome_dir, exist_ok=True)
    extra = []
    try:
        size = fasta_len(row["fasta"])
    except Exception:
        size = 0
    if size and size < 1_000_000:
        extra = ["--genomeSAindexNbases", "3", "--genomeChrBinNbits", "5"]
    cmd = [
        "STAR", "--runThreadN", cpus, "--runMode", "genomeGenerate",
        "--genomeDir", genome_dir,
        "--genomeFastaFiles", row["fasta"],
        "--sjdbGTFfile", row["annotation_file"],
        *extra,
    ]
    print(" ".join(shlex.quote(part) for part in cmd) + " > " + shlex.quote("logs/star/" + row["reference_key"] + ".genomeGenerate.log") + " 2>&1")
print("test -s " + shlex.quote(os.path.join(genome_dir, "SA")))
PY
    bash build_star_index.sh
    [ -e "logs/star/${reference_key}.genomeGenerate.log" ] || printf 'STAR index reused for %s\\n' "${reference_key}" > "logs/star/${reference_key}.genomeGenerate.log"
    printf 'reference_key\\tstatus\\n%s\\tready\\n' "${reference_key}" > "index/${reference_key}.done"
    """
}

process RNA_FASTQC_SAMPLE {
    label 'process_low'
    publishDir { "${params.outdir}/rnaseq/qc" }, mode: 'copy'

    input:
    tuple val(sample_key), path(sample_manifest)

    output:
    path "fastqc/${sample_key}", emit: fastqc

    script:
    """
    set -euo pipefail
    command -v fastqc >/dev/null 2>&1 || { echo "ERROR: FastQC executable not found for RNA-seq real mode. Install it or run --omics_mode stub." >&2; exit 1; }
    mkdir -p "fastqc/${sample_key}"
    python3 - "${sample_manifest}" <<'PY' > fastqc_inputs.txt
import csv
row = next(csv.DictReader(open(__import__("sys").argv[1]), delimiter="\\t"))
print(row["fastq_1"])
if row.get("read_layout") == "paired_end" and row.get("fastq_2"):
    print(row["fastq_2"])
PY
    fastqc --outdir "fastqc/${sample_key}" \$(cat fastqc_inputs.txt)
    """
}

process RNA_STAR_ALIGN_SAMPLE {
    label 'process_star_align'

    input:
    tuple val(sample_key), path(sample_manifest), path(index_markers)

    output:
    tuple val(sample_key), path(sample_manifest), path("raw_bam/${sample_key}.bam"), emit: raw_bam
    path "logs/star/${sample_key}.*", emit: logs

    script:
    """
    set -euo pipefail
    command -v STAR >/dev/null 2>&1 || { echo "ERROR: STAR executable not found for RNA-seq real mode. Install it or run --omics_mode stub." >&2; exit 1; }
    mkdir -p raw_bam star logs/star
    python3 - "${sample_manifest}" "${task.cpus}" <<'PY' > star_align.sh
import csv
import shlex
import sys

manifest, cpus = sys.argv[1], sys.argv[2]
row = next(csv.DictReader(open(manifest), delimiter="\\t"))
sample_key = row["sample_key"]
reads = [row["fastq_1"]]
if row.get("read_layout") == "paired_end" and row.get("fastq_2"):
    reads.append(row["fastq_2"])
read_cmd = ["--readFilesCommand", "zcat"] if any(read.endswith(".gz") for read in reads) else []
prefix = f"star/{sample_key}."
cmd = [
    "STAR", "--runThreadN", cpus,
    "--genomeDir", row["star_index"],
    "--readFilesIn", *reads,
    *read_cmd,
    "--outSAMtype", "BAM", "Unsorted",
    "--outFileNamePrefix", prefix,
]
print(" ".join(shlex.quote(part) for part in cmd) + " > " + shlex.quote(f"logs/star/{sample_key}.align.stdout.log") + " 2> " + shlex.quote(f"logs/star/{sample_key}.align.stderr.log"))
print("test -s " + shlex.quote(f"{prefix}Aligned.out.bam"))
print("mv " + shlex.quote(f"{prefix}Aligned.out.bam") + " " + shlex.quote(f"raw_bam/{sample_key}.bam"))
for suffix in ["Log.final.out", "Log.out", "Log.progress.out", "SJ.out.tab"]:
    print("[ ! -e " + shlex.quote(f"{prefix}{suffix}") + " ] || mv " + shlex.quote(f"{prefix}{suffix}") + " " + shlex.quote(f"logs/star/{sample_key}.{suffix}") )
PY
    bash star_align.sh
    """
}

process RNA_SAMTOOLS_QC_SAMPLE {
    label 'process_medium'

    input:
    tuple val(sample_key), path(sample_manifest), path(raw_bam)

    output:
    tuple val(sample_key), path(sample_manifest), path("bam/${sample_key}.bam"), path("bam/${sample_key}.bam.bai"), emit: bam_for_counting
    path "bam/${sample_key}.bam", emit: bam_files
    path "bam/${sample_key}.bam.bai", emit: bai_files
    path "logs/samtools/${sample_key}.*", emit: logs

    script:
    """
    set -euo pipefail
    command -v samtools >/dev/null 2>&1 || { echo "ERROR: samtools executable not found for RNA-seq real mode. Install it or run --omics_mode stub." >&2; exit 1; }
    mkdir -p bam logs/samtools
    samtools sort -@ ${task.cpus} -o "bam/${sample_key}.bam" "${raw_bam}"
    samtools quickcheck "bam/${sample_key}.bam"
    samtools index "bam/${sample_key}.bam"
    samtools flagstat "bam/${sample_key}.bam" > "logs/samtools/${sample_key}.flagstat.txt"
    samtools idxstats "bam/${sample_key}.bam" > "logs/samtools/${sample_key}.idxstats.tsv"
    samtools stats "bam/${sample_key}.bam" > "logs/samtools/${sample_key}.stats.txt"
    """
}

process RNA_FEATURECOUNTS_SAMPLE {
    label 'process_counting'

    input:
    tuple val(sample_key), path(sample_manifest), path(bam), path(bai)

    output:
    path "counts/${sample_key}.featureCounts.txt", emit: counts
    path "logs/featurecounts/${sample_key}.*", emit: logs

    script:
    """
    set -euo pipefail
    command -v featureCounts >/dev/null 2>&1 || { echo "ERROR: featureCounts executable not found for RNA-seq real mode. Install it or run --omics_mode stub." >&2; exit 1; }
    mkdir -p counts logs/featurecounts
    python3 - "${sample_manifest}" "${bam}" "${task.cpus}" <<'PY' > featurecounts.sh
import csv
import shlex
import sys

manifest, bam, cpus = sys.argv[1], sys.argv[2], sys.argv[3]
row = next(csv.DictReader(open(manifest), delimiter="\\t"))
sample_key = row["sample_key"]
stranded = {"unstranded": "0", "unknown": "0", "forward": "1", "reverse": "2"}.get(row.get("strandedness", "").lower(), "0")
cmd = ["featureCounts", "-T", cpus, "-s", stranded]
if row.get("read_layout") == "paired_end":
    cmd.extend(["-p", "--countReadPairs"])
cmd.extend(["-a", row["annotation_file"], "-o", f"counts/{sample_key}.featureCounts.txt", bam])
print(" ".join(shlex.quote(part) for part in cmd) + " > " + shlex.quote(f"logs/featurecounts/{sample_key}.stdout.log") + " 2> " + shlex.quote(f"logs/featurecounts/{sample_key}.stderr.log"))
print("test -s " + shlex.quote(f"counts/{sample_key}.featureCounts.txt"))
print("[ ! -e " + shlex.quote(f"counts/{sample_key}.featureCounts.txt.summary") + " ] || cp " + shlex.quote(f"counts/{sample_key}.featureCounts.txt.summary") + " " + shlex.quote(f"logs/featurecounts/{sample_key}.featureCounts.summary.tsv"))
PY
    bash featurecounts.sh
    """
}

process RNA_REAL_AGGREGATE {
    label 'process_medium'
    publishDir { "${params.outdir}/rnaseq" }, mode: 'copy'

    input:
    path manifest
    path feature_count_files
    path featurecount_logs
    path bam_files
    path bai_files
    path samtools_logs
    path star_logs

    output:
    path 'bam', emit: bam
    path 'logs', emit: logs
    path 'counts/gene_counts.tsv', emit: gene_counts
    path 'qc/alignment_qc.tsv', emit: qc
    path 'qc/featurecounts_summary.tsv', emit: featurecounts_summary
    path 'qc/rna_qc_warnings.tsv', emit: warnings
    path 'summary/rnaseq_summary.tsv', emit: summary
    path 'validation/rna_real_validation.tsv', emit: validation

    script:
    """
    set -euo pipefail
    mkdir -p bam counts featurecounts logs/star logs/samtools logs/featurecounts qc summary validation
    sample_count=\$(python3 - "${manifest}" <<'PY'
import csv
import sys
print(sum(1 for row in csv.DictReader(open(sys.argv[1]), delimiter="\\t") if row.get("omics_type") == "rnaseq"))
PY
)
    if [ "\$sample_count" = "0" ]; then
      printf 'feature_id\\tfeature_type\\tannotation_id\\n' > counts/gene_counts.tsv
      printf 'sample_id\\tspecies\\tomics_type\\tcondition\\ttimepoint\\treference_id\\tstatus\\tn_features\\ttotal_counts\\toutput_files\\twarnings\\n' > summary/rnaseq_summary.tsv
      printf 'sample_id\\tspecies\\tomics_type\\tcondition\\ttimepoint\\treference_id\\tstrandedness\\tbam\\tbai\\tbam_exists\\tbam_nonempty\\ttotal_reads\\tuniquely_mapped_reads\\tunique_mapping_rate\\tmulti_mapped_reads\\tmulti_mapping_rate\\tassigned_reads\\tassigned_fraction\\tmapping_rate\\tn_features\\ttotal_counts\\tstatus\\twarnings\\n' > qc/alignment_qc.tsv
      printf 'sample_id\\tstatus\\treads\\n' > qc/featurecounts_summary.tsv
      printf 'severity\\tsource\\tmetric\\tsample_id\\tmessage\\n' > qc/rna_qc_warnings.tsv
      printf 'severity\\tsource\\tfield\\tsample_id\\tmessage\\nINFO\\trna_real\\t\\t\\tNo RNA-seq samples requested\\n' > validation/rna_real_validation.tsv
      printf 'No rnaseq samples\\n' > logs/star/NO_SAMPLES.log
      exit 0
    fi
    for file in ${feature_count_files}; do [ ! -e "\$file" ] || cp "\$file" featurecounts/; done
    for file in ${featurecount_logs}; do [ ! -e "\$file" ] || cp "\$file" logs/featurecounts/; done
    for file in ${bam_files}; do [ ! -e "\$file" ] || cp "\$file" bam/; done
    for file in ${bai_files}; do [ ! -e "\$file" ] || cp "\$file" bam/; done
    for file in ${samtools_logs}; do [ ! -e "\$file" ] || cp "\$file" logs/samtools/; done
    for file in ${star_logs}; do [ ! -e "\$file" ] || cp "\$file" logs/star/; done
    python3 ${projectDir}/bin/merge_real_counts.py \\
      --assay rnaseq \\
      --manifest "${manifest}" \\
      --input_dir featurecounts \\
      --output counts/gene_counts.tsv
    python3 ${projectDir}/bin/collect_real_qc_metrics.py \\
      --assay rnaseq \\
      --manifest "${manifest}" \\
      --counts counts/gene_counts.tsv \\
      --bam_dir bam \\
      --logs_dir logs \\
      --output qc/alignment_qc.tsv \\
      --featurecounts_summary_output qc/featurecounts_summary.tsv \\
      --warnings_output qc/rna_qc_warnings.tsv
    python3 - qc/alignment_qc.tsv summary/rnaseq_summary.tsv counts/gene_counts.tsv <<'PY'
import csv
import sys

qc_path, out_path, counts_path = sys.argv[1:4]
rows = list(csv.DictReader(open(qc_path), delimiter="\\t"))
fields = ["sample_id", "species", "omics_type", "condition", "timepoint", "reference_id", "status", "n_features", "total_counts", "output_files", "warnings"]
with open(out_path, "w", newline="") as handle:
    writer = csv.DictWriter(handle, fieldnames=fields, delimiter="\\t", lineterminator="\\n")
    writer.writeheader()
    for row in rows:
        writer.writerow({
            "sample_id": row["sample_id"],
            "species": row.get("species", ""),
            "omics_type": "rnaseq",
            "condition": row.get("condition", ""),
            "timepoint": row.get("timepoint", ""),
            "reference_id": row.get("reference_id", ""),
            "status": row.get("status", "OK"),
            "n_features": row.get("n_features", "0"),
            "total_counts": row.get("total_counts", "0"),
            "output_files": counts_path,
            "warnings": row.get("warnings", ""),
        })
PY
    python3 ${projectDir}/bin/validate_real_outputs.py \\
      --assay rnaseq \\
      --manifest "${manifest}" \\
      --counts counts/gene_counts.tsv \\
      --bam_dir bam \\
      --qc qc/alignment_qc.tsv \\
      --featurecounts_summary qc/featurecounts_summary.tsv \\
      --report validation/rna_real_validation.tsv
    """
}

workflow RNA_REAL {
    take:
    manifest

    main:
    RNA_SPLIT_MANIFEST(manifest)
    sample_ch = RNA_SPLIT_MANIFEST.out.samples.flatten().map { sample_file -> tuple(sample_file.baseName.toString(), sample_file) }
    reference_ch = RNA_SPLIT_MANIFEST.out.references.flatten().map { reference_file -> tuple(reference_file.baseName.toString(), reference_file) }
    RNA_STAR_INDEX(reference_ch)
    index_done_ch = RNA_STAR_INDEX.out.done.collect()
    RNA_FASTQC_SAMPLE(sample_ch)
    RNA_STAR_ALIGN_SAMPLE(sample_ch.combine(index_done_ch))
    RNA_SAMTOOLS_QC_SAMPLE(RNA_STAR_ALIGN_SAMPLE.out.raw_bam)
    RNA_FEATURECOUNTS_SAMPLE(RNA_SAMTOOLS_QC_SAMPLE.out.bam_for_counting)
    RNA_REAL_AGGREGATE(
        RNA_SPLIT_MANIFEST.out.manifest,
        RNA_FEATURECOUNTS_SAMPLE.out.counts.collect(),
        RNA_FEATURECOUNTS_SAMPLE.out.logs.collect(),
        RNA_SAMTOOLS_QC_SAMPLE.out.bam_files.collect(),
        RNA_SAMTOOLS_QC_SAMPLE.out.bai_files.collect(),
        RNA_SAMTOOLS_QC_SAMPLE.out.logs.collect(),
        RNA_STAR_ALIGN_SAMPLE.out.logs.collect()
    )

    emit:
    fastqc = RNA_FASTQC_SAMPLE.out.fastqc
    bam = RNA_REAL_AGGREGATE.out.bam
    logs = RNA_REAL_AGGREGATE.out.logs
    gene_counts = RNA_REAL_AGGREGATE.out.gene_counts
    qc = RNA_REAL_AGGREGATE.out.qc
    featurecounts_summary = RNA_REAL_AGGREGATE.out.featurecounts_summary
    warnings = RNA_REAL_AGGREGATE.out.warnings
    summary = RNA_REAL_AGGREGATE.out.summary
    validation = RNA_REAL_AGGREGATE.out.validation
}
