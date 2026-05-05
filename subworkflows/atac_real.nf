process ATAC_SPLIT_MANIFEST {
    label 'process_low'

    input:
    path manifest

    output:
    path 'split/manifest/atacseq_manifest.tsv', emit: manifest
    path 'split/samples/*.tsv', optional: true, emit: samples
    path 'split/references/*.tsv', optional: true, emit: references

    script:
    """
    set -euo pipefail
    backend="${params.atac_backend ?: 'bowtie2'}"
    peak_caller="${params.peak_caller ?: 'macs3'}"
    if [ "\$backend" != "bowtie2" ]; then
      echo "ERROR: Stage 25 ATAC real mode supports --atac_backend bowtie2 only." >&2
      exit 1
    fi
    if [ "\$peak_caller" != "macs3" ]; then
      echo "ERROR: Stage 25 ATAC real mode supports --peak_caller macs3 only." >&2
      exit 1
    fi
    python3 ${projectDir}/bin/split_real_mode_manifest.py \\
      --manifest "${manifest}" \\
      --assay atacseq \\
      --output_dir split
    """
}

process ATAC_BOWTIE2_INDEX {
    label 'process_medium'

    input:
    tuple val(reference_key), path(reference_manifest)

    output:
    path 'logs/bowtie2/*', emit: logs
    path "index/${reference_key}.done", emit: done

    script:
    """
    set -euo pipefail
    command -v bowtie2-build >/dev/null 2>&1 || { echo "ERROR: bowtie2-build executable not found for ATAC-seq real mode. Install it or run --omics_mode stub." >&2; exit 1; }
    mkdir -p logs/bowtie2 index
    python3 - "${reference_manifest}" <<'PY' > build_bowtie2_index.sh
import csv
import os
import shlex
import sys

row = next(csv.DictReader(open(sys.argv[1]), delimiter="\\t"))
prefix = row["bowtie2_index"]

def bowtie2_index_exists(prefix):
    return any(os.path.exists(prefix + suffix) for suffix in [".1.bt2", ".1.bt2l"])

if not bowtie2_index_exists(prefix):
    os.makedirs(os.path.dirname(prefix) or ".", exist_ok=True)
    cmd = ["bowtie2-build", row["fasta"], prefix]
    print(" ".join(shlex.quote(part) for part in cmd) + " > " + shlex.quote("logs/bowtie2/" + row["reference_key"] + ".build.log") + " 2>&1")
print("test -s " + shlex.quote(prefix + ".1.bt2") + " || test -s " + shlex.quote(prefix + ".1.bt2l"))
PY
    bash build_bowtie2_index.sh
    [ -e "logs/bowtie2/${reference_key}.build.log" ] || printf 'Bowtie2 index reused for %s\\n' "${reference_key}" > "logs/bowtie2/${reference_key}.build.log"
    printf 'reference_key\\tstatus\\n%s\\tready\\n' "${reference_key}" > "index/${reference_key}.done"
    """
}

process ATAC_FASTQC_SAMPLE {
    label 'process_low'
    publishDir { "${params.outdir}/atacseq/qc" }, mode: 'copy'

    input:
    tuple val(sample_key), path(sample_manifest)

    output:
    path "fastqc/${sample_key}", emit: fastqc

    script:
    """
    set -euo pipefail
    command -v fastqc >/dev/null 2>&1 || { echo "ERROR: FastQC executable not found for ATAC-seq real mode. Install it or run --omics_mode stub." >&2; exit 1; }
    mkdir -p "fastqc/${sample_key}"
    python3 - "${sample_manifest}" <<'PY' > fastqc_inputs.txt
import csv
import sys
row = next(csv.DictReader(open(sys.argv[1]), delimiter="\\t"))
print(row["fastq_1"])
if row.get("read_layout") == "paired_end" and row.get("fastq_2"):
    print(row["fastq_2"])
PY
    fastqc --outdir "fastqc/${sample_key}" \$(cat fastqc_inputs.txt)
    """
}

process ATAC_BOWTIE2_ALIGN_SAMPLE {
    label 'process_bowtie2_align'

    input:
    tuple val(sample_key), path(sample_manifest), path(index_markers)

    output:
    tuple val(sample_key), path(sample_manifest), path("raw_bam/${sample_key}.raw.bam"), emit: raw_bam
    path "logs/bowtie2/${sample_key}.*", emit: logs

    script:
    """
    set -euo pipefail
    command -v bowtie2 >/dev/null 2>&1 || { echo "ERROR: bowtie2 executable not found for ATAC-seq real mode. Install it or run --omics_mode stub." >&2; exit 1; }
    command -v samtools >/dev/null 2>&1 || { echo "ERROR: samtools executable not found for ATAC-seq real mode. Install it or run --omics_mode stub." >&2; exit 1; }
    mkdir -p raw_bam logs/bowtie2
    python3 - "${sample_manifest}" "${task.cpus}" <<'PY' > bowtie2_align.sh
import csv
import shlex
import sys

manifest, cpus = sys.argv[1], sys.argv[2]
row = next(csv.DictReader(open(manifest), delimiter="\\t"))
sample_key = row["sample_key"]
if row.get("read_layout") == "paired_end":
    align = ["bowtie2", "-p", cpus, "-x", row["bowtie2_index"], "-1", row["fastq_1"], "-2", row["fastq_2"]]
else:
    align = ["bowtie2", "-p", cpus, "-x", row["bowtie2_index"], "-U", row["fastq_1"]]
print("set -o pipefail")
print(" ".join(shlex.quote(part) for part in align) + " 2> " + shlex.quote(f"logs/bowtie2/{sample_key}.bowtie2.log") + " | samtools view -bS - > " + shlex.quote(f"raw_bam/{sample_key}.raw.bam"))
print("test -s " + shlex.quote(f"raw_bam/{sample_key}.raw.bam"))
PY
    bash bowtie2_align.sh
    """
}

process ATAC_SAMTOOLS_FILTER_SAMPLE {
    label 'process_medium'

    input:
    tuple val(sample_key), path(sample_manifest), path(raw_bam)

    output:
    tuple val(sample_key), path(sample_manifest), path("bam/${sample_key}.bam"), path("bam/${sample_key}.bam.bai"), emit: bam_for_peaks
    path "bam/${sample_key}.bam", emit: bam_files
    path "bam/${sample_key}.bam.bai", emit: bai_files
    path "logs/samtools/${sample_key}.*", emit: logs

    script:
    """
    set -euo pipefail
    command -v samtools >/dev/null 2>&1 || { echo "ERROR: samtools executable not found for ATAC-seq real mode. Install it or run --omics_mode stub." >&2; exit 1; }
    mkdir -p bam logs/samtools
    samtools view -@ ${task.cpus} -b -q 30 -F 1804 "${raw_bam}" | samtools sort -@ ${task.cpus} -o "bam/${sample_key}.bam" -
    samtools index "bam/${sample_key}.bam"
    samtools quickcheck "bam/${sample_key}.bam"
    samtools flagstat "bam/${sample_key}.bam" > "logs/samtools/${sample_key}.flagstat.txt"
    samtools idxstats "bam/${sample_key}.bam" > "logs/samtools/${sample_key}.idxstats.tsv"
    samtools stats "bam/${sample_key}.bam" > "logs/samtools/${sample_key}.stats.txt"
    samtools view "bam/${sample_key}.bam" | awk '
      BEGIN { OFS="\\t" }
      {
        strand = (int(\$2 / 16) % 2) ? "-" : "+"
        key = \$3 ":" \$4 ":" strand
        counts[key] += 1
        total += 1
      }
      END {
        for (key in counts) {
          distinct += 1
          if (counts[key] == 1) one += 1
          if (counts[key] == 2) two += 1
        }
        nrf = total ? distinct / total : 0
        pbc1 = distinct ? one / distinct : 0
        pbc2 = two ? sprintf("%.6f", one / two) : ""
        print "total_fragments", "distinct_fragments", "one_read_fragments", "two_read_fragments", "nrf", "pbc1", "pbc2"
        printf "%d\\t%d\\t%d\\t%d\\t%.6f\\t%.6f\\t%s\\n", total, distinct, one, two, nrf, pbc1, pbc2
      }
    ' > "logs/samtools/${sample_key}.complexity.tsv"
    """
}

process ATAC_MACS3_PEAKS_SAMPLE {
    label 'process_peak_calling'

    input:
    tuple val(sample_key), path(sample_manifest), path(bam), path(bai)

    output:
    path "peaks/${sample_key}_peaks.narrowPeak", emit: peaks
    path "logs/macs3/${sample_key}.*", emit: logs

    script:
    """
    set -euo pipefail
    command -v macs3 >/dev/null 2>&1 || { echo "ERROR: macs3 executable not found for ATAC-seq real mode. Install it or run --omics_mode stub." >&2; exit 1; }
    mkdir -p peaks logs/macs3
    python3 - "${sample_manifest}" "${bam}" <<'PY' > macs3_callpeak.sh
import csv
import shlex
import sys

manifest, bam = sys.argv[1], sys.argv[2]
row = next(csv.DictReader(open(manifest), delimiter="\\t"))
sample_key = row["sample_key"]

def genome_size(row):
    chrom_sizes = row.get("chrom_sizes", "")
    if chrom_sizes:
        total = 0
        try:
            with open(chrom_sizes) as handle:
                for line in handle:
                    parts = line.rstrip("\\n").split("\\t")
                    if len(parts) >= 2:
                        total += int(parts[1])
        except Exception:
            total = 0
        if total:
            return str(total)
    total = 0
    with open(row["fasta"]) as handle:
        for line in handle:
            if not line.startswith(">"):
                total += len(line.strip())
    return str(total or 1)

fmt = "BAMPE" if row.get("read_layout") == "paired_end" else "BAM"
cmd = ["macs3", "callpeak", "-t", bam, "-f", fmt, "-g", genome_size(row), "-n", sample_key, "--outdir", "peaks", "--keep-dup", "all"]
if fmt == "BAM":
    cmd.extend(["--nomodel", "--shift", "-100", "--extsize", "200"])
print(" ".join(shlex.quote(part) for part in cmd) + " > " + shlex.quote(f"logs/macs3/{sample_key}.macs3.log") + " 2>&1")
print("test -e " + shlex.quote(f"peaks/{sample_key}_peaks.narrowPeak"))
PY
    bash macs3_callpeak.sh
    """
}

process ATAC_CONSENSUS_PEAKS {
    label 'process_peak_calling'
    publishDir { "${params.outdir}/atacseq" }, mode: 'copy'

    input:
    path manifest
    path peak_files

    output:
    path 'counts/peak_consensus.bed', emit: consensus

    script:
    """
    set -euo pipefail
    mkdir -p counts peak_inputs
    sample_count=\$(python3 - "${manifest}" <<'PY'
import csv
import sys
print(sum(1 for row in csv.DictReader(open(sys.argv[1]), delimiter="\\t") if row.get("omics_type") == "atacseq"))
PY
)
    if [ "\$sample_count" = "0" ]; then
      : > counts/peak_consensus.bed
      exit 0
    fi
    command -v bedtools >/dev/null 2>&1 || { echo "ERROR: bedtools executable not found for ATAC-seq real mode. Install it or run --omics_mode stub." >&2; exit 1; }
    for file in ${peak_files}; do [ ! -e "\$file" ] || cp "\$file" peak_inputs/; done
    find peak_inputs -name '*_peaks.narrowPeak' -type f -print0 | xargs -0 cat | awk 'NF >= 3 {print \$1"\\t"\$2"\\t"\$3}' | sort -k1,1 -k2,2n | bedtools merge > counts/peak_consensus.bed
    """
}

process ATAC_PEAK_COUNTS {
    label 'process_counting'
    publishDir { "${params.outdir}/atacseq" }, mode: 'copy'

    input:
    path manifest
    path consensus
    path bam_files

    output:
    path 'counts/peak_counts.tsv', emit: peak_counts
    path 'counts/re_counts.tsv', emit: re_counts
    path 'counts/bedtools', emit: per_sample_counts

    script:
    """
    set -euo pipefail
    mkdir -p bam counts/bedtools
    sample_count=\$(python3 - "${manifest}" <<'PY'
import csv
import sys
print(sum(1 for row in csv.DictReader(open(sys.argv[1]), delimiter="\\t") if row.get("omics_type") == "atacseq"))
PY
)
    if [ "\$sample_count" = "0" ]; then
      printf 'feature_id\\tfeature_type\\tchrom\\tstart\\tend\\n' > counts/peak_counts.tsv
      cp counts/peak_counts.tsv counts/re_counts.tsv
      exit 0
    fi
    command -v bedtools >/dev/null 2>&1 || { echo "ERROR: bedtools executable not found for ATAC-seq real mode. Install it or run --omics_mode stub." >&2; exit 1; }
    for file in ${bam_files}; do [ ! -e "\$file" ] || cp "\$file" bam/; done
    python3 - "${manifest}" <<'PY' > bedtools_counts.sh
import csv
import shlex
import sys

for row in csv.DictReader(open(sys.argv[1]), delimiter="\\t"):
    if row.get("omics_type") != "atacseq":
        continue
    sample_key = row["sample_key"]
    bam = f"bam/{sample_key}.bam"
    out = f"counts/bedtools/{sample_key}.bedtools_counts.tsv"
    print(f"bedtools coverage -a counts/peak_consensus.bed -b {shlex.quote(bam)} -counts > {shlex.quote(out)}")
PY
    cp "${consensus}" counts/peak_consensus.bed
    bash bedtools_counts.sh
    python3 ${projectDir}/bin/merge_real_counts.py \\
      --assay atacseq \\
      --manifest "${manifest}" \\
      --input_dir counts/bedtools \\
      --consensus_peaks counts/peak_consensus.bed \\
      --output counts/peak_counts.tsv \\
      --re_counts_output counts/re_counts.tsv
    """
}

process ATAC_REAL_AGGREGATE {
    label 'process_medium'
    publishDir { "${params.outdir}/atacseq" }, mode: 'copy'

    input:
    path manifest
    path re_counts
    path peak_counts
    path consensus
    path peaks
    path bam_files
    path bai_files
    path bowtie2_logs
    path samtools_logs
    path macs3_logs

    output:
    path 'bam', emit: bam
    path 'peaks', emit: peaks
    path 'logs', emit: logs
    path 'qc/atac_qc.tsv', emit: qc
    path 'qc/library_complexity.tsv', emit: library_complexity
    path 'qc/atac_qc_warnings.tsv', emit: warnings
    path 'summary/atacseq_summary.tsv', emit: summary
    path 'validation/atac_real_validation.tsv', emit: validation

    script:
    """
    set -euo pipefail
    mkdir -p bam peaks counts logs/bowtie2 logs/samtools logs/macs3 qc summary validation
    sample_count=\$(python3 - "${manifest}" <<'PY'
import csv
import sys
print(sum(1 for row in csv.DictReader(open(sys.argv[1]), delimiter="\\t") if row.get("omics_type") == "atacseq"))
PY
)
    cp "${re_counts}" counts/re_counts.tsv
    cp "${peak_counts}" counts/peak_counts.tsv
    cp "${consensus}" counts/peak_consensus.bed
    if [ "\$sample_count" = "0" ]; then
      printf 'sample_id\\tspecies\\tomics_type\\tcondition\\ttimepoint\\treference_id\\tstatus\\tn_features\\ttotal_counts\\toutput_files\\twarnings\\n' > summary/atacseq_summary.tsv
      printf 'sample_id\\tspecies\\tomics_type\\tcondition\\ttimepoint\\treference_id\\tread_layout\\tbam\\tbai\\tbam_exists\\tbam_nonempty\\ttotal_reads\\tmapped_reads\\ttotal_aligned_reads\\tmitochondrial_reads\\tmitochondrial_fraction\\tduplicate_reads\\tduplicate_fraction\\tusable_reads\\tn_peaks\\tn_consensus_peaks\\treads_in_peaks\\tfrip\\ttss_reads\\ttss_enrichment\\tfragment_mean\\tfragment_sd\\tstatus\\twarnings\\n' > qc/atac_qc.tsv
      printf 'sample_id\\ttotal_reads\\tmapped_reads\\tduplicate_reads\\tduplicate_fraction\\tnrf\\tpbc1\\tpbc2\\tstatus\\twarnings\\n' > qc/library_complexity.tsv
      printf 'severity\\tsource\\tmetric\\tsample_id\\tmessage\\n' > qc/atac_qc_warnings.tsv
      printf 'severity\\tsource\\tfield\\tsample_id\\tmessage\\nINFO\\tatac_real\\t\\t\\tNo ATAC-seq samples requested\\n' > validation/atac_real_validation.tsv
      printf 'No atacseq samples\\n' > logs/bowtie2/NO_SAMPLES.log
      exit 0
    fi
    for file in ${peaks}; do [ ! -e "\$file" ] || cp "\$file" peaks/; done
    for file in ${bam_files}; do [ ! -e "\$file" ] || cp "\$file" bam/; done
    for file in ${bai_files}; do [ ! -e "\$file" ] || cp "\$file" bam/; done
    for file in ${bowtie2_logs}; do [ ! -e "\$file" ] || cp "\$file" logs/bowtie2/; done
    for file in ${samtools_logs}; do [ ! -e "\$file" ] || cp "\$file" logs/samtools/; done
    for file in ${macs3_logs}; do [ ! -e "\$file" ] || cp "\$file" logs/macs3/; done
    python3 ${projectDir}/bin/collect_real_qc_metrics.py \\
      --assay atacseq \\
      --manifest "${manifest}" \\
      --counts counts/re_counts.tsv \\
      --bam_dir bam \\
      --logs_dir logs \\
      --peaks_dir peaks \\
      --output qc/atac_qc.tsv \\
      --library_complexity_output qc/library_complexity.tsv \\
      --warnings_output qc/atac_qc_warnings.tsv \\
      --atac_replicate_concordance "${params.atac_replicate_concordance}"
    python3 - qc/atac_qc.tsv summary/atacseq_summary.tsv counts/re_counts.tsv <<'PY'
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
            "omics_type": "atacseq",
            "condition": row.get("condition", ""),
            "timepoint": row.get("timepoint", ""),
            "reference_id": row.get("reference_id", ""),
            "status": row.get("status", "OK"),
            "n_features": row.get("n_consensus_peaks", "0"),
            "total_counts": row.get("usable_reads", "0"),
            "output_files": counts_path,
            "warnings": row.get("warnings", ""),
        })
PY
    python3 ${projectDir}/bin/validate_real_outputs.py \\
      --assay atacseq \\
      --manifest "${manifest}" \\
      --counts counts/re_counts.tsv \\
      --bam_dir bam \\
      --peaks_dir peaks \\
      --consensus_peaks counts/peak_consensus.bed \\
      --qc qc/atac_qc.tsv \\
      --library_complexity qc/library_complexity.tsv \\
      --report validation/atac_real_validation.tsv
    """
}

workflow ATAC_REAL {
    take:
    manifest

    main:
    ATAC_SPLIT_MANIFEST(manifest)
    sample_ch = ATAC_SPLIT_MANIFEST.out.samples.flatten().map { sample_file -> tuple(sample_file.baseName.toString(), sample_file) }
    reference_ch = ATAC_SPLIT_MANIFEST.out.references.flatten().map { reference_file -> tuple(reference_file.baseName.toString(), reference_file) }
    ATAC_BOWTIE2_INDEX(reference_ch)
    index_done_ch = ATAC_BOWTIE2_INDEX.out.done.collect()
    ATAC_FASTQC_SAMPLE(sample_ch)
    ATAC_BOWTIE2_ALIGN_SAMPLE(sample_ch.combine(index_done_ch))
    ATAC_SAMTOOLS_FILTER_SAMPLE(ATAC_BOWTIE2_ALIGN_SAMPLE.out.raw_bam)
    ATAC_MACS3_PEAKS_SAMPLE(ATAC_SAMTOOLS_FILTER_SAMPLE.out.bam_for_peaks)
    ATAC_CONSENSUS_PEAKS(
        ATAC_SPLIT_MANIFEST.out.manifest,
        ATAC_MACS3_PEAKS_SAMPLE.out.peaks.collect()
    )
    ATAC_PEAK_COUNTS(
        ATAC_SPLIT_MANIFEST.out.manifest,
        ATAC_CONSENSUS_PEAKS.out.consensus,
        ATAC_SAMTOOLS_FILTER_SAMPLE.out.bam_files.collect()
    )
    ATAC_REAL_AGGREGATE(
        ATAC_SPLIT_MANIFEST.out.manifest,
        ATAC_PEAK_COUNTS.out.re_counts,
        ATAC_PEAK_COUNTS.out.peak_counts,
        ATAC_CONSENSUS_PEAKS.out.consensus,
        ATAC_MACS3_PEAKS_SAMPLE.out.peaks.collect(),
        ATAC_SAMTOOLS_FILTER_SAMPLE.out.bam_files.collect(),
        ATAC_SAMTOOLS_FILTER_SAMPLE.out.bai_files.collect(),
        ATAC_BOWTIE2_ALIGN_SAMPLE.out.logs.collect(),
        ATAC_SAMTOOLS_FILTER_SAMPLE.out.logs.collect(),
        ATAC_MACS3_PEAKS_SAMPLE.out.logs.collect()
    )

    emit:
    fastqc = ATAC_FASTQC_SAMPLE.out.fastqc
    bam = ATAC_REAL_AGGREGATE.out.bam
    peaks = ATAC_REAL_AGGREGATE.out.peaks
    logs = ATAC_REAL_AGGREGATE.out.logs
    peak_counts = ATAC_PEAK_COUNTS.out.peak_counts
    re_counts = ATAC_PEAK_COUNTS.out.re_counts
    consensus = ATAC_CONSENSUS_PEAKS.out.consensus
    qc = ATAC_REAL_AGGREGATE.out.qc
    library_complexity = ATAC_REAL_AGGREGATE.out.library_complexity
    warnings = ATAC_REAL_AGGREGATE.out.warnings
    summary = ATAC_REAL_AGGREGATE.out.summary
    validation = ATAC_REAL_AGGREGATE.out.validation
}
