process FEATURECOUNTS {
    publishDir { "${params.outdir}/rnaseq" }, mode: 'copy'

    input:
    path manifest
    path bam_dir
    val omics_stub

    output:
    path 'counts/gene_counts.tsv', emit: counts

    script:
    """
    if [ "${omics_stub}" = "true" ] || [ "${omics_stub}" = "1" ] || [ "${omics_stub}" = "yes" ]; then
      mkdir -p counts
      python3 ${projectDir}/bin/make_synthetic_counts.py \\
        --manifest "${manifest}" \\
        --omics_type rnaseq \\
        --output counts/gene_counts.tsv
    else
      sample_count=\$(python3 - "${manifest}" <<'PY'
import csv
import sys
print(sum(1 for _ in csv.DictReader(open(sys.argv[1]), delimiter="\\t")))
PY
)
      if [ "\$sample_count" = "0" ]; then
        mkdir -p counts
        printf 'feature_id\\tfeature_type\\tannotation_id\\n' > counts/gene_counts.tsv
        exit 0
      fi
      command -v featureCounts >/dev/null 2>&1 || { echo "ERROR: featureCounts executable not found for RNA-seq real mode." >&2; exit 1; }
      mkdir -p counts
      python3 - "${manifest}" <<'PY' > featurecounts_commands.sh
import csv
import os
import shlex
import sys

for row in csv.DictReader(open(sys.argv[1]), delimiter="\\t"):
    sample_id = row["sample_id"]
    bam = os.path.join("bam", f"{sample_id}.bam")
    out = os.path.join("counts", f"{sample_id}.featureCounts.txt")
    stranded = {"unstranded": "0", "no": "0", "forward": "1", "yes": "1", "reverse": "2"}.get(row.get("strandedness", "").lower(), "0")
    cmd = ["featureCounts", "-s", stranded, "-a", row["gtf"], "-o", out, bam]
    print(" ".join(shlex.quote(part) for part in cmd))
PY
      if [ -s featurecounts_commands.sh ]; then
        sh featurecounts_commands.sh
      fi
      python3 - "${manifest}" <<'PY'
import csv
import os
import sys
from collections import OrderedDict

manifest = sys.argv[1]
samples = [row["sample_id"] for row in csv.DictReader(open(manifest), delimiter="\\t")]
features = OrderedDict()
for sample_id in samples:
    path = os.path.join("counts", f"{sample_id}.featureCounts.txt")
    if not os.path.exists(path):
        raise SystemExit(f"Missing featureCounts output: {path}")
    with open(path) as handle:
        reader = csv.reader((line for line in handle if not line.startswith("#")), delimiter="\\t")
        header = next(reader)
        count_col = len(header) - 1
        for row in reader:
            feature_id = row[0]
            features.setdefault(feature_id, {"feature_id": feature_id, "feature_type": "gene", "annotation_id": "featureCounts"})
            features[feature_id][sample_id] = row[count_col]
os.makedirs("counts", exist_ok=True)
with open("counts/gene_counts.tsv", "w", newline="") as handle:
    fields = ["feature_id", "feature_type", "annotation_id"] + samples
    writer = csv.DictWriter(handle, fieldnames=fields, delimiter="\\t", extrasaction="ignore", lineterminator="\\n")
    writer.writeheader()
    writer.writerows(features.values())
PY
    fi
    """
}
