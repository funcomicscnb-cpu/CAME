process BEDTOOLS_COUNTS {
    publishDir { "${params.outdir}/atacseq" }, mode: 'copy'

    input:
    path manifest
    path peaks
    path filtered_bam
    val omics_stub

    output:
    path 'counts/re_counts.tsv', emit: counts

    script:
    """
    if [ "${omics_stub}" = "true" ] || [ "${omics_stub}" = "1" ] || [ "${omics_stub}" = "yes" ]; then
      mkdir -p counts
      python3 ${projectDir}/bin/make_synthetic_counts.py \\
        --manifest "${manifest}" \\
        --omics_type atacseq \\
        --output counts/re_counts.tsv
    else
      sample_count=\$(python3 - "${manifest}" <<'PY'
import csv
import sys
print(sum(1 for _ in csv.DictReader(open(sys.argv[1]), delimiter="\\t")))
PY
)
      if [ "\$sample_count" = "0" ]; then
        mkdir -p counts
        printf 'feature_id\\tfeature_type\\tchrom\\tstart\\tend\\n' > counts/re_counts.tsv
        exit 0
      fi
      command -v bedtools >/dev/null 2>&1 || { echo "ERROR: bedtools executable not found for ATAC-seq real mode." >&2; exit 1; }
      mkdir -p counts
      find peaks -name '*.bed' -type f -print0 | xargs -0 cat | sort -k1,1 -k2,2n | bedtools merge > counts/merged_peaks.bed
      python3 - "${manifest}" <<'PY' > bedtools_count_commands.sh
import csv
import shlex
import sys

for row in csv.DictReader(open(sys.argv[1]), delimiter="\\t"):
    sample_id = row["sample_id"]
    bam = f"bam/filtered/{sample_id}.filtered.bam"
    out = f"counts/{sample_id}.bedtools_counts.tmp"
    print(f"bedtools coverage -a counts/merged_peaks.bed -b {shlex.quote(bam)} -counts > {shlex.quote(out)}")
PY
      if [ -s bedtools_count_commands.sh ]; then
        sh bedtools_count_commands.sh
      fi
      python3 - "${manifest}" <<'PY'
import csv
import os
import sys
from collections import OrderedDict

samples = [row["sample_id"] for row in csv.DictReader(open(sys.argv[1]), delimiter="\\t")]
features = OrderedDict()
with open("counts/merged_peaks.bed") as handle:
    for idx, line in enumerate(handle, start=1):
        chrom, start, end = line.rstrip("\\n").split("\\t")[:3]
        feature_id = f"re_{idx:06d}"
        features[feature_id] = {"feature_id": feature_id, "feature_type": "regulatory_element", "chrom": chrom, "start": start, "end": end}
for sample_id in samples:
    path = f"counts/{sample_id}.bedtools_counts.tmp"
    if not os.path.exists(path):
        raise SystemExit(f"Missing bedtools count output: {path}")
    for feature_id, line in zip(features, open(path)):
        features[feature_id][sample_id] = line.rstrip("\\n").split("\\t")[-1]
with open("counts/re_counts.tsv", "w", newline="") as handle:
    fields = ["feature_id", "feature_type", "chrom", "start", "end"] + samples
    writer = csv.DictWriter(handle, fieldnames=fields, delimiter="\\t", extrasaction="ignore", lineterminator="\\n")
    writer.writeheader()
    writer.writerows(features.values())
PY
    fi
    """
}
