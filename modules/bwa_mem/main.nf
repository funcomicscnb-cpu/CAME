process BWA_MEM {
    publishDir { "${params.outdir}/atacseq" }, mode: 'copy'

    input:
    path manifest
    val omics_stub

    output:
    path 'bam/raw', emit: raw_bam
    path 'logs/bwa_mem', emit: logs

    script:
    """
    if [ "${omics_stub}" = "true" ] || [ "${omics_stub}" = "1" ] || [ "${omics_stub}" = "yes" ]; then
      mkdir -p bam/raw logs/bwa_mem
      python3 - "${manifest}" <<'PY'
import csv
import os
import sys

rows = list(csv.DictReader(open(sys.argv[1]), delimiter="\\t"))
if not rows:
    open("logs/bwa_mem/NO_SAMPLES.log", "w").write("No atacseq samples in manifest\\n")
for row in rows:
    sample_id = row["sample_id"]
    open(os.path.join("bam/raw", f"{sample_id}.raw.bam.txt"), "w").write(f"BWA MEM stub marker for {sample_id}\\n")
    open(os.path.join("logs/bwa_mem", f"{sample_id}.bwa_mem.log"), "w").write("status\\tstub\\n")
PY
    else
      sample_count=\$(python3 - "${manifest}" <<'PY'
import csv
import sys
print(sum(1 for _ in csv.DictReader(open(sys.argv[1]), delimiter="\\t")))
PY
)
      if [ "\$sample_count" = "0" ]; then
        mkdir -p bam/raw logs/bwa_mem
        printf 'No atacseq samples\\n' > logs/bwa_mem/NO_SAMPLES.log
        exit 0
      fi
      command -v bwa >/dev/null 2>&1 || { echo "ERROR: bwa executable not found for ATAC-seq real mode." >&2; exit 1; }
      mkdir -p bam/raw logs/bwa_mem
      python3 - "${manifest}" <<'PY' > bwa_mem_commands.sh
import csv
import shlex
import sys

for row in csv.DictReader(open(sys.argv[1]), delimiter="\\t"):
    sample_id = row["sample_id"]
    reads = [row["fastq_1"]]
    if row.get("read_layout") == "paired_end":
        reads.append(row["fastq_2"])
    cmd = ["bwa", "mem", row["bwa_index"], *reads]
    print(" ".join(shlex.quote(part) for part in cmd) + f" > {shlex.quote('bam/raw/' + sample_id + '.sam')} 2> {shlex.quote('logs/bwa_mem/' + sample_id + '.bwa_mem.log')}")
PY
      if [ -s bwa_mem_commands.sh ]; then
        sh bwa_mem_commands.sh
      else
        printf 'No atacseq samples\\n' > logs/bwa_mem/NO_SAMPLES.log
      fi
    fi
    """
}
