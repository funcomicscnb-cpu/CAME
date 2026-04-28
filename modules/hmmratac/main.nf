process HMMRATAC {
    publishDir { "${params.outdir}/atacseq" }, mode: 'copy'

    input:
    path manifest
    path filtered_bam
    val omics_stub

    output:
    path 'peaks', emit: peaks
    path 'logs/hmmratac', emit: logs

    script:
    """
    if [ "${omics_stub}" = "true" ] || [ "${omics_stub}" = "1" ] || [ "${omics_stub}" = "yes" ]; then
      mkdir -p peaks logs/hmmratac
      python3 - "${manifest}" <<'PY'
import csv
import os
import sys

rows = list(csv.DictReader(open(sys.argv[1]), delimiter="\\t"))
if not rows:
    open("logs/hmmratac/NO_SAMPLES.log", "w").write("No atacseq samples in manifest\\n")
for row in rows:
    sample_id = row["sample_id"]
    with open(os.path.join("peaks", f"{sample_id}.peaks.bed"), "w") as handle:
        handle.write("chr1\\t1000\\t1250\\t" + sample_id + "_peak_1\\n")
        handle.write("chr2\\t2000\\t2250\\t" + sample_id + "_peak_2\\n")
    open(os.path.join("logs/hmmratac", f"{sample_id}.hmmratac.log"), "w").write("status\\tstub\\n")
PY
    else
      sample_count=\$(python3 - "${manifest}" <<'PY'
import csv
import sys
print(sum(1 for _ in csv.DictReader(open(sys.argv[1]), delimiter="\\t")))
PY
)
      if [ "\$sample_count" = "0" ]; then
        mkdir -p peaks logs/hmmratac
        printf 'No atacseq samples\\n' > logs/hmmratac/NO_SAMPLES.log
        exit 0
      fi
      command -v samtools >/dev/null 2>&1 || { echo "ERROR: samtools executable not found for HMMRATAC real mode." >&2; exit 1; }
      mkdir -p peaks logs/hmmratac
      configured_hmmratac_jar="${params.hmmratac_jar ?: ''}"
      export configured_hmmratac_jar
      cat > run_hmmratac.sh <<'SH'
#!/usr/bin/env sh
set -eu
if command -v HMMRATAC >/dev/null 2>&1; then
  exec HMMRATAC "\$@"
fi
if command -v hmmratac >/dev/null 2>&1; then
  exec hmmratac "\$@"
fi
jar="\${CAME_HMMRATAC_JAR:-}"
if [ -n "\$jar" ] && [ -f "\$jar" ]; then
  command -v java >/dev/null 2>&1 || { echo "ERROR: java executable not found for HMMRATAC jar mode." >&2; exit 1; }
  exec java -jar "\$jar" "\$@"
fi
if [ -n "\${configured_hmmratac_jar:-}" ] && [ -f "\$configured_hmmratac_jar" ]; then
  command -v java >/dev/null 2>&1 || { echo "ERROR: java executable not found for HMMRATAC jar mode." >&2; exit 1; }
  exec java -jar "\$configured_hmmratac_jar" "\$@"
fi
for candidate in HMMRATAC.jar hmmratac.jar tools/HMMRATAC.jar environment/tools/HMMRATAC.jar environment/HMMRATAC.jar; do
  if [ -f "\$candidate" ]; then
    command -v java >/dev/null 2>&1 || { echo "ERROR: java executable not found for HMMRATAC jar mode." >&2; exit 1; }
    exec java -jar "\$candidate" "\$@"
  fi
done
echo "ERROR: HMMRATAC executable not found. Install HMMRATAC as HMMRATAC/hmmratac, set CAME_HMMRATAC_JAR, or pass --hmmratac_jar." >&2
exit 1
SH
      chmod +x run_hmmratac.sh
      python3 - "${manifest}" <<'PY' > hmmratac_commands.sh
import csv
import shlex
import sys

for row in csv.DictReader(open(sys.argv[1]), delimiter="\\t"):
    sample_id = row["sample_id"]
    bam = f"bam/filtered/{sample_id}.filtered.bam"
    print(f"samtools index {shlex.quote(bam)}")
    cmd = ["./run_hmmratac.sh", "-b", bam, "-i", bam + ".bai", "-g", row["chrom_sizes"], "-o", f"peaks/{sample_id}"]
    print(" ".join(shlex.quote(part) for part in cmd) + f" > {shlex.quote('logs/hmmratac/' + sample_id + '.hmmratac.log')} 2>&1")
PY
      if [ -s hmmratac_commands.sh ]; then
        sh hmmratac_commands.sh
      else
        printf 'No atacseq samples\\n' > logs/hmmratac/NO_SAMPLES.log
      fi
    fi
    """
}
