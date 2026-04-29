process WGS_FASTQC_SAMPLE {
    label 'process_low'
    publishDir { "${params.outdir}/wgs/qc" }, mode: 'copy'

    input:
    tuple val(sample_key), path(sample_manifest)

    output:
    path "fastqc/${sample_key}", emit: fastqc

    script:
    """
    set -euo pipefail
    command -v fastqc >/dev/null 2>&1 || { echo "ERROR: FastQC executable not found for WGS real mode. Install it or run --wgs_mode stub." >&2; exit 1; }
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

process WGS_SAMTOOLS_SORT_QC_SAMPLE {
    label 'process_medium'

    input:
    tuple val(sample_key), path(sample_manifest), path(raw_bam)

    output:
    tuple val(sample_key), path(sample_manifest), path("bam/${sample_key}.bam"), path("bam/${sample_key}.bam.bai"), emit: bam_for_variants
    path "bam/${sample_key}.bam", emit: bam_files
    path "bam/${sample_key}.bam.bai", emit: bai_files
    path "logs/samtools/${sample_key}.*", emit: logs

    script:
    """
    set -euo pipefail
    command -v samtools >/dev/null 2>&1 || { echo "ERROR: samtools executable not found for WGS real mode. Install it or run --wgs_mode stub." >&2; exit 1; }
    mkdir -p bam logs/samtools tmp
    samtools sort -n -@ ${task.cpus} -o "tmp/${sample_key}.name.bam" "${raw_bam}"
    samtools fixmate -m "tmp/${sample_key}.name.bam" "tmp/${sample_key}.fixmate.bam"
    samtools sort -@ ${task.cpus} -o "tmp/${sample_key}.coord.bam" "tmp/${sample_key}.fixmate.bam"
    if samtools markdup -@ ${task.cpus} "tmp/${sample_key}.coord.bam" "bam/${sample_key}.bam" > "logs/samtools/${sample_key}.markdup.stdout.log" 2> "logs/samtools/${sample_key}.markdup.stderr.log"; then
      :
    else
      printf 'WARNING: samtools markdup failed; using coordinate-sorted BAM without duplicate marking.\\n' > "logs/samtools/${sample_key}.markdup.stderr.log"
      cp "tmp/${sample_key}.coord.bam" "bam/${sample_key}.bam"
    fi
    samtools quickcheck "bam/${sample_key}.bam"
    samtools index "bam/${sample_key}.bam"
    samtools flagstat "bam/${sample_key}.bam" > "logs/samtools/${sample_key}.flagstat.txt"
    samtools stats "bam/${sample_key}.bam" > "logs/samtools/${sample_key}.stats.txt"
    samtools coverage "bam/${sample_key}.bam" > "logs/samtools/${sample_key}.coverage.tsv" || printf '#rname\\tstartpos\\tendpos\\tnumreads\\tcovbases\\tcoverage\\tmeandepth\\tmeanbaseq\\tmeanmapq\\n' > "logs/samtools/${sample_key}.coverage.tsv"
    """
}

workflow WGS_QC {
    take:
    sample_ch
    raw_bam_ch

    main:
    WGS_FASTQC_SAMPLE(sample_ch)
    WGS_SAMTOOLS_SORT_QC_SAMPLE(raw_bam_ch)

    emit:
    fastqc = WGS_FASTQC_SAMPLE.out.fastqc
    bam_for_variants = WGS_SAMTOOLS_SORT_QC_SAMPLE.out.bam_for_variants
    bam_files = WGS_SAMTOOLS_SORT_QC_SAMPLE.out.bam_files
    bai_files = WGS_SAMTOOLS_SORT_QC_SAMPLE.out.bai_files
    logs = WGS_SAMTOOLS_SORT_QC_SAMPLE.out.logs
}
