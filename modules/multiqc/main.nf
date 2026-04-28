process MULTIQC {
    publishDir { "${params.outdir}/omics/qc" }, mode: 'copy'

    input:
    path prepared_manifest
    path rnaseq_summary
    path atacseq_summary
    val omics_stub

    output:
    path 'multiqc', emit: report

    script:
    """
    if [ "${omics_stub}" = "true" ] || [ "${omics_stub}" = "1" ] || [ "${omics_stub}" = "yes" ]; then
      mkdir -p multiqc/multiqc_data
      python3 - "${prepared_manifest}" <<'PY'
import csv
import os
import sys
from collections import Counter

rows = list(csv.DictReader(open(sys.argv[1]), delimiter="\\t"))
counts = Counter(row["omics_type"] for row in rows)
with open("multiqc/multiqc_report.html", "w") as handle:
    handle.write("<html><body><h1>CAME MultiQC stub</h1>\\n")
    for key in sorted(counts):
        handle.write(f"<p>{key}: {counts[key]} samples</p>\\n")
    handle.write("</body></html>\\n")
with open("multiqc/multiqc_data/multiqc_sources.txt", "w") as handle:
    handle.write("source\\ttype\\n")
    handle.write("rnaseq_summary\\tstub\\n")
    handle.write("atacseq_summary\\tstub\\n")
PY
    else
      command -v multiqc >/dev/null 2>&1 || { echo "ERROR: MultiQC executable not found for real mode." >&2; exit 1; }
      mkdir -p multiqc
      multiqc --outdir multiqc .
    fi
    """
}
