process SAMTOOLS_FILTER {
    publishDir { "${params.outdir}/atacseq" }, mode: 'copy'

    input:
    path manifest
    path raw_bam
    val omics_stub

    output:
    path 'bam/filtered', emit: filtered_bam
    path 'logs/samtools_filter', emit: logs

    script:
    """
    if [ "${omics_stub}" = "true" ] || [ "${omics_stub}" = "1" ] || [ "${omics_stub}" = "yes" ]; then
      mkdir -p bam/filtered logs/samtools_filter
      python3 - "${manifest}" <<'PY'
import csv
import os
import sys

rows = list(csv.DictReader(open(sys.argv[1]), delimiter="\\t"))
if not rows:
    open("logs/samtools_filter/NO_SAMPLES.log", "w").write("No atacseq samples in manifest\\n")
for row in rows:
    sample_id = row["sample_id"]
    open(os.path.join("bam/filtered", f"{sample_id}.filtered.bam.txt"), "w").write(f"samtools filter stub marker for {sample_id}\\n")
    open(os.path.join("logs/samtools_filter", f"{sample_id}.samtools_filter.log"), "w").write("status\\tstub\\n")
PY
    else
      sample_count=\$(python3 - "${manifest}" <<'PY'
import csv
import sys
print(sum(1 for _ in csv.DictReader(open(sys.argv[1]), delimiter="\\t")))
PY
)
      if [ "\$sample_count" = "0" ]; then
        mkdir -p bam/filtered logs/samtools_filter
        printf 'No atacseq samples\\n' > logs/samtools_filter/NO_SAMPLES.log
        exit 0
      fi
      command -v samtools >/dev/null 2>&1 || { echo "ERROR: samtools executable not found for ATAC-seq real mode." >&2; exit 1; }
      mkdir -p bam/filtered logs/samtools_filter
      python3 - "${manifest}" <<'PY' > samtools_filter_commands.sh
import csv
import shlex
import sys

for row in csv.DictReader(open(sys.argv[1]), delimiter="\\t"):
    sample_id = row["sample_id"]
    raw_sam = f"bam/raw/{sample_id}.sam"
    out_bam = f"bam/filtered/{sample_id}.filtered.bam"
    print(f"samtools view -bS -q 30 {shlex.quote(raw_sam)} | samtools sort -o {shlex.quote(out_bam)} -")
    print(f"samtools index {shlex.quote(out_bam)}")
PY
      if [ -s samtools_filter_commands.sh ]; then
        sh samtools_filter_commands.sh
      else
        printf 'No atacseq samples\\n' > logs/samtools_filter/NO_SAMPLES.log
      fi
    fi
    """
}
