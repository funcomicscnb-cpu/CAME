process FASTQC {
    publishDir { "${params.outdir}/${omics_type}/qc" }, mode: 'copy'

    input:
    path manifest
    val omics_type
    val omics_stub

    output:
    path 'fastqc', emit: fastqc

    script:
    """
    if [ "${omics_stub}" = "true" ] || [ "${omics_stub}" = "1" ] || [ "${omics_stub}" = "yes" ]; then
      mkdir -p fastqc
      python3 - "${manifest}" "${omics_type}" <<'PY'
import csv
import os
import sys

manifest, omics_type = sys.argv[1], sys.argv[2]
rows = list(csv.DictReader(open(manifest), delimiter="\t"))
if not rows:
    open("fastqc/NO_SAMPLES.txt", "w").write(f"No {omics_type} samples in manifest\\n")
for row in rows:
    sample_id = row["sample_id"]
    html = os.path.join("fastqc", f"{sample_id}_fastqc.html")
    data = os.path.join("fastqc", f"{sample_id}_fastqc_data.txt")
    open(html, "w").write(f"<html><body><h1>{sample_id} FastQC stub</h1></body></html>\\n")
    open(data, "w").write("module\\tstatus\\nBasic Statistics\\tPASS\\nPer base sequence quality\\tPASS\\n")
PY
    else
      sample_count=\$(python3 - "${manifest}" <<'PY'
import csv
import sys
print(sum(1 for _ in csv.DictReader(open(sys.argv[1]), delimiter="\\t")))
PY
)
      if [ "\$sample_count" = "0" ]; then
        mkdir -p fastqc
        printf 'No %s samples\\n' "${omics_type}" > fastqc/NO_SAMPLES.txt
        exit 0
      fi
      command -v fastqc >/dev/null 2>&1 || { echo "ERROR: FastQC executable not found for ${omics_type} real mode." >&2; exit 1; }
      mkdir -p fastqc
      python3 - "${manifest}" <<'PY' > fastqc_inputs.txt
import csv
import sys

for row in csv.DictReader(open(sys.argv[1]), delimiter="\\t"):
    for field in ["fastq_1", "fastq_2"]:
        value = row.get(field, "").strip()
        if value:
            print(value)
PY
      if [ -s fastqc_inputs.txt ]; then
        fastqc --outdir fastqc \$(cat fastqc_inputs.txt)
      else
        printf 'No %s samples\\n' "${omics_type}" > fastqc/NO_SAMPLES.txt
      fi
    fi
    """
}
