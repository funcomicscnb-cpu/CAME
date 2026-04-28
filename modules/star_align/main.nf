process STAR_ALIGN {
    publishDir { "${params.outdir}/rnaseq" }, mode: 'copy'

    input:
    path manifest
    val omics_stub

    output:
    path 'bam', emit: bam
    path 'logs', emit: logs

    script:
    """
    if [ "${omics_stub}" = "true" ] || [ "${omics_stub}" = "1" ] || [ "${omics_stub}" = "yes" ]; then
      mkdir -p bam logs
      python3 - "${manifest}" <<'PY'
import csv
import os
import sys

rows = list(csv.DictReader(open(sys.argv[1]), delimiter="\\t"))
if not rows:
    open("logs/star_align.NO_SAMPLES.log", "w").write("No rnaseq samples in manifest\\n")
for row in rows:
    sample_id = row["sample_id"]
    open(os.path.join("bam", f"{sample_id}.stub.bam.txt"), "w").write(f"STAR stub BAM marker for {sample_id}\\n")
    open(os.path.join("logs", f"{sample_id}.STAR.log"), "w").write("status\\tstub\\n")
PY
    else
      sample_count=\$(python3 - "${manifest}" <<'PY'
import csv
import sys
print(sum(1 for _ in csv.DictReader(open(sys.argv[1]), delimiter="\\t")))
PY
)
      if [ "\$sample_count" = "0" ]; then
        mkdir -p bam logs
        printf 'No rnaseq samples\\n' > logs/star_align.NO_SAMPLES.log
        exit 0
      fi
      command -v STAR >/dev/null 2>&1 || { echo "ERROR: STAR executable not found for RNA-seq real mode." >&2; exit 1; }
      mkdir -p bam logs
      python3 - "${manifest}" "${task.cpus}" <<'PY' > star_commands.sh
import csv
import shlex
import sys

manifest, cpus = sys.argv[1], sys.argv[2]
for row in csv.DictReader(open(manifest), delimiter="\\t"):
    sample_id = row["sample_id"]
    reads = [row["fastq_1"]]
    if row.get("read_layout") == "paired_end":
        reads.append(row["fastq_2"])
    read_cmd = "--readFilesCommand zcat" if any(path.endswith(".gz") for path in reads) else ""
    cmd = [
        "STAR",
        "--runThreadN", cpus,
        "--genomeDir", row["star_index"],
        "--readFilesIn",
        *reads,
    ]
    if read_cmd:
        cmd.extend(read_cmd.split())
    cmd.extend(["--outSAMtype", "BAM", "SortedByCoordinate", "--outFileNamePrefix", f"logs/{sample_id}."])
    print(" ".join(shlex.quote(part) for part in cmd))
    print(f"test -s {shlex.quote('logs/' + sample_id + '.Aligned.sortedByCoord.out.bam')}")
    print(f"mv {shlex.quote('logs/' + sample_id + '.Aligned.sortedByCoord.out.bam')} {shlex.quote('bam/' + sample_id + '.bam')}")
PY
      if [ -s star_commands.sh ]; then
        sh star_commands.sh
      else
        printf 'No rnaseq samples\\n' > logs/star_align.NO_SAMPLES.log
      fi
    fi
    """
}
