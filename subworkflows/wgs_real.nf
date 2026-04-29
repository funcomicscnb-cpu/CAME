include { WGS_QC } from './wgs_qc'
include { WGS_VARIANT_CALLING } from './wgs_variant_calling'

process PREPARE_WGS_INPUTS {
    publishDir { "${params.outdir}/wgs" }, mode: 'copy'
    label 'process_low'

    input:
    path wgs_samplesheet, stageAs: 'wgs_samplesheet_input.csv'
    path reference_manifest, stageAs: 'reference_manifest_input.tsv'
    val wgs_mode
    val wgs_variant_mode
    val wgs_filtering_mode
    val require_known_sites
    val allow_no_bqsr
    val reference_cache_dir
    val metadata_base_dir
    val reference_base_dir

    output:
    path 'input/wgs_manifest_prepared.tsv', emit: prepared_manifest
    path 'input/wgs_manifest.tsv', emit: wgs_manifest
    path 'input/wgs_reference_assets.tsv', emit: reference_assets
    path 'input/wgs_input_warnings.tsv', emit: warnings

    script:
    """
    set -euo pipefail
    mkdir -p input
    python3 ${projectDir}/bin/prepare_wgs_inputs.py \\
      --wgs_samplesheet "${wgs_samplesheet}" \\
      --reference_manifest "${reference_manifest}" \\
      --wgs_mode "${wgs_mode}" \\
      --wgs_variant_mode "${wgs_variant_mode}" \\
      --wgs_filtering_mode "${wgs_filtering_mode}" \\
      --require_known_sites "${require_known_sites}" \\
      --allow_no_bqsr "${allow_no_bqsr}" \\
      --reference_cache_dir "${reference_cache_dir}" \\
      --launch_dir "${launchDir}" \\
      --metadata_base_dir "${metadata_base_dir}" \\
      --reference_base_dir "${reference_base_dir}" \\
      --output_dir input
    """
}

process WGS_STUB_OUTPUTS {
    publishDir { "${params.outdir}/wgs" }, mode: 'copy'
    label 'process_low'

    input:
    path manifest
    path warnings

    output:
    path 'input', emit: input
    path 'bam', emit: bam
    path 'variants', emit: variants
    path 'logs', emit: logs
    path 'qc/wgs_alignment_qc.tsv', emit: alignment_qc
    path 'qc/variant_qc.tsv', emit: variant_qc
    path 'qc/wgs_qc_warnings.tsv', emit: qc_warnings
    path 'summary/wgs_variant_summary.tsv', emit: summary
    path 'summary/wgs_outputs_manifest.tsv', emit: outputs_manifest
    path 'validation/wgs_outputs_validation.tsv', emit: validation

    script:
    """
    set -euo pipefail
    mkdir -p input bam variants logs/samtools logs/gatk qc summary validation
    cp "${manifest}" input/wgs_manifest.tsv
    cp "${warnings}" input/wgs_input_warnings.tsv
    python3 - input/wgs_manifest.tsv <<'PY'
import csv
import gzip
from pathlib import Path

rows = [row for row in csv.DictReader(open("input/wgs_manifest.tsv"), delimiter="\\t") if row.get("assay") == "wgs" or row.get("omics_type") == "wgs"]
for row in rows:
    sample_key = row.get("sample_key") or row["sample_id"]
    sample_id = row["sample_id"]
    Path(f"bam/{sample_key}.bam").write_text(f"CAME_WGS_STUB stub contract BAM for {sample_id}; not biological output.\\n")
    Path(f"bam/{sample_key}.bam.bai").write_text(f"CAME_WGS_STUB stub contract BAI for {sample_id}; not biological output.\\n")
    with gzip.open(f"variants/{sample_key}.vcf.gz", "wt") as handle:
        handle.write("##fileformat=VCFv4.2\\n")
        handle.write("##source=CAME_WGS_STUB contract fixture; not biological output\\n")
        handle.write("#CHROM\\tPOS\\tID\\tREF\\tALT\\tQUAL\\tFILTER\\tINFO\\tFORMAT\\t" + sample_id + "\\n")
    Path(f"variants/{sample_key}.vcf.gz.tbi").write_text(f"CAME_WGS_STUB stub contract VCF index for {sample_id}; not biological output.\\n")
    Path(f"logs/samtools/{sample_key}.flagstat.txt").write_text("CAME_WGS_STUB no biological flagstat metrics emitted.\\n")
    Path(f"logs/samtools/{sample_key}.stats.txt").write_text("CAME_WGS_STUB no biological samtools stats emitted.\\n")
    Path(f"logs/samtools/{sample_key}.coverage.tsv").write_text("#rname\\tstartpos\\tendpos\\tnumreads\\tcovbases\\tcoverage\\tmeandepth\\tmeanbaseq\\tmeanmapq\\n")
    Path(f"logs/gatk/{sample_key}.stub.log").write_text("CAME_WGS_STUB no biological variant calling was run.\\n")
PY
    python3 ${projectDir}/bin/collect_wgs_qc_metrics.py \\
      --manifest input/wgs_manifest.tsv \\
      --bam_dir bam \\
      --variants_dir variants \\
      --logs_dir logs \\
      --alignment_output qc/wgs_alignment_qc.tsv \\
      --variant_output qc/variant_qc.tsv \\
      --warnings_output qc/wgs_qc_warnings.tsv \\
      --mode stub
    python3 ${projectDir}/bin/summarize_wgs_variants.py \\
      --manifest input/wgs_manifest.tsv \\
      --bam_dir bam \\
      --variants_dir variants \\
      --alignment_qc qc/wgs_alignment_qc.tsv \\
      --variant_qc qc/variant_qc.tsv \\
      --warnings qc/wgs_qc_warnings.tsv \\
      --output_dir summary \\
      --mode stub
    python3 ${projectDir}/bin/validate_wgs_outputs.py \\
      --manifest input/wgs_manifest.tsv \\
      --bam_dir bam \\
      --variants_dir variants \\
      --variant_qc qc/variant_qc.tsv \\
      --report validation/wgs_outputs_validation.tsv \\
      --mode stub
    """
}

process WGS_SPLIT_MANIFEST {
    label 'process_low'

    input:
    path manifest

    output:
    path 'split/manifest/wgs_manifest.tsv', emit: manifest
    path 'split/samples/*.tsv', optional: true, emit: samples
    path 'split/references/*.tsv', optional: true, emit: references

    script:
    """
    set -euo pipefail
    python3 ${projectDir}/bin/split_real_mode_manifest.py \\
      --manifest "${manifest}" \\
      --assay wgs \\
      --output_dir split
    """
}

process WGS_BWA_MEM2_INDEX {
    label 'process_bwa_mem2_index'

    input:
    tuple val(reference_key), path(reference_manifest)

    output:
    path 'logs/bwa_mem2/*', emit: logs
    path "index/${reference_key}.done", emit: done

    script:
    """
    set -euo pipefail
    resolve_bwa_mem2() {
      for cmd in bwa-mem2 bwa-mem2.avx2 bwa-mem2.sse42 bwa-mem2.sse41; do
        if command -v "\$cmd" >/dev/null 2>&1; then
          printf '%s\\n' "\$cmd"
          return 0
        fi
      done
      return 1
    }
    bwa_cmd=\$(resolve_bwa_mem2) || { echo "ERROR: BWA-MEM2 executable not found for WGS real mode. Install bwa-mem2 or run --wgs_mode stub." >&2; exit 1; }
    mkdir -p logs/bwa_mem2 index
    python3 - "${reference_manifest}" "\$bwa_cmd" <<'PY' > build_bwa_mem2_index.sh
import csv
import os
import shlex
import sys

manifest, bwa_cmd = sys.argv[1:3]
row = next(csv.DictReader(open(manifest), delimiter="\\t"))
prefix = row["bwa_index_prefix"]

def index_exists(prefix):
    modern = [".amb", ".ann", ".pac", ".0123", ".bwt.2bit.64"]
    legacy = [".amb", ".ann", ".bwt", ".pac", ".sa"]
    return any(all(os.path.exists(prefix + suffix) for suffix in suffixes) for suffixes in [modern, legacy])

if not index_exists(prefix):
    os.makedirs(os.path.dirname(prefix) or ".", exist_ok=True)
    cmd = [bwa_cmd, "index", "-p", prefix, row["fasta"]]
    print(" ".join(shlex.quote(part) for part in cmd) + " > " + shlex.quote("logs/bwa_mem2/" + row["reference_key"] + ".index.log") + " 2>&1")
print("test -s " + shlex.quote(prefix + ".amb"))
PY
    bash build_bwa_mem2_index.sh
    [ -e "logs/bwa_mem2/${reference_key}.index.log" ] || printf 'BWA-MEM2 index reused for %s\\n' "${reference_key}" > "logs/bwa_mem2/${reference_key}.index.log"
    printf 'reference_key\\tstatus\\n%s\\tready\\n' "${reference_key}" > "index/${reference_key}.done"
    """
}

process WGS_BWA_MEM2_ALIGN_SAMPLE {
    label 'process_bwa_mem2_align'

    input:
    tuple val(sample_key), path(sample_manifest), path(index_markers)

    output:
    tuple val(sample_key), path(sample_manifest), path("raw_bam/${sample_key}.raw.bam"), emit: raw_bam
    path "logs/bwa_mem2/${sample_key}.*", emit: logs

    script:
    """
    set -euo pipefail
    resolve_bwa_mem2() {
      for cmd in bwa-mem2 bwa-mem2.avx2 bwa-mem2.sse42 bwa-mem2.sse41; do
        if command -v "\$cmd" >/dev/null 2>&1; then
          printf '%s\\n' "\$cmd"
          return 0
        fi
      done
      return 1
    }
    bwa_cmd=\$(resolve_bwa_mem2) || { echo "ERROR: BWA-MEM2 executable not found for WGS real mode. Install bwa-mem2 or run --wgs_mode stub." >&2; exit 1; }
    command -v samtools >/dev/null 2>&1 || { echo "ERROR: samtools executable not found for WGS real mode. Install samtools or run --wgs_mode stub." >&2; exit 1; }
    mkdir -p raw_bam logs/bwa_mem2
    python3 - "${sample_manifest}" "\$bwa_cmd" "${task.cpus}" <<'PY' > bwa_mem2_align.sh
import csv
import shlex
import sys

manifest, bwa_cmd, cpus = sys.argv[1:4]
row = next(csv.DictReader(open(manifest), delimiter="\\t"))
sample_key = row["sample_key"]
sample_id = row["sample_id"]
library_id = row.get("library_id") or sample_key
platform = (row.get("platform") or "ILLUMINA").replace(" ", "_")
rg = f"@RG\\tID:{sample_key}\\tSM:{sample_id}\\tPL:{platform}\\tLB:{library_id}"
reads = [row["fastq_1"]]
if row.get("read_layout") == "paired_end" and row.get("fastq_2"):
    reads.append(row["fastq_2"])
align = [bwa_cmd, "mem", "-t", cpus, "-R", rg, row["bwa_index_prefix"], *reads]
print("set -o pipefail")
print(" ".join(shlex.quote(part) for part in align) + " 2> " + shlex.quote(f"logs/bwa_mem2/{sample_key}.bwa_mem2.log") + " | samtools view -@ " + shlex.quote(cpus) + " -bS - > " + shlex.quote(f"raw_bam/{sample_key}.raw.bam"))
print("test -s " + shlex.quote(f"raw_bam/{sample_key}.raw.bam"))
PY
    bash bwa_mem2_align.sh
    """
}

process WGS_REAL_AGGREGATE {
    label 'process_medium'
    publishDir { "${params.outdir}/wgs" }, mode: 'copy'

    input:
    path manifest
    path input_warnings
    path bam_files
    path bai_files
    path bwa_logs
    path samtools_logs
    path vcf_files
    path vcf_indexes
    path gatk_logs

    output:
    path 'input', emit: input
    path 'bam', emit: bam
    path 'variants', emit: variants
    path 'logs', emit: logs
    path 'qc/wgs_alignment_qc.tsv', emit: alignment_qc
    path 'qc/variant_qc.tsv', emit: variant_qc
    path 'qc/wgs_qc_warnings.tsv', emit: qc_warnings
    path 'summary/wgs_variant_summary.tsv', emit: summary
    path 'summary/wgs_outputs_manifest.tsv', emit: outputs_manifest
    path 'validation/wgs_outputs_validation.tsv', emit: validation

    script:
    """
    set -euo pipefail
    mkdir -p input bam variants logs/bwa_mem2 logs/samtools logs/gatk qc summary validation
    cp "${manifest}" input/wgs_manifest.tsv
    cp "${input_warnings}" input/wgs_input_warnings.tsv
    for file in ${bam_files}; do [ ! -e "\$file" ] || cp "\$file" bam/; done
    for file in ${bai_files}; do [ ! -e "\$file" ] || cp "\$file" bam/; done
    for file in ${bwa_logs}; do [ ! -e "\$file" ] || cp "\$file" logs/bwa_mem2/; done
    for file in ${samtools_logs}; do [ ! -e "\$file" ] || cp "\$file" logs/samtools/; done
    for file in ${vcf_files}; do [ ! -e "\$file" ] || cp "\$file" variants/; done
    for file in ${vcf_indexes}; do [ ! -e "\$file" ] || cp "\$file" variants/; done
    for file in ${gatk_logs}; do [ ! -e "\$file" ] || cp "\$file" logs/gatk/; done
    python3 ${projectDir}/bin/collect_wgs_qc_metrics.py \\
      --manifest input/wgs_manifest.tsv \\
      --bam_dir bam \\
      --variants_dir variants \\
      --logs_dir logs \\
      --alignment_output qc/wgs_alignment_qc.tsv \\
      --variant_output qc/variant_qc.tsv \\
      --warnings_output qc/wgs_qc_warnings.tsv \\
      --mode real
    python3 ${projectDir}/bin/summarize_wgs_variants.py \\
      --manifest input/wgs_manifest.tsv \\
      --bam_dir bam \\
      --variants_dir variants \\
      --alignment_qc qc/wgs_alignment_qc.tsv \\
      --variant_qc qc/variant_qc.tsv \\
      --warnings qc/wgs_qc_warnings.tsv \\
      --output_dir summary \\
      --mode real
    python3 ${projectDir}/bin/validate_wgs_outputs.py \\
      --manifest input/wgs_manifest.tsv \\
      --bam_dir bam \\
      --variants_dir variants \\
      --variant_qc qc/variant_qc.tsv \\
      --report validation/wgs_outputs_validation.tsv \\
      --mode real
    """
}

workflow WGS_REAL {
    take:
    wgs_samplesheet
    reference_manifest
    wgs_mode
    wgs_variant_mode
    wgs_filtering_mode
    require_known_sites
    allow_no_bqsr

    main:
    if (!(wgs_mode.toString() in ['stub', 'real'])) {
        error "Unsupported --wgs_mode '${wgs_mode}'. Supported values: stub, real."
    }
    if (wgs_variant_mode.toString() != 'haplotypecaller') {
        error "Unsupported --wgs_variant_mode '${wgs_variant_mode}'. Supported value: haplotypecaller."
    }
    if (!(wgs_filtering_mode.toString() in ['hard_filter', 'none'])) {
        error "Unsupported --wgs_filtering_mode '${wgs_filtering_mode}'. Supported values: hard_filter, none."
    }
    referenceCacheDir = params.reference_cache_dir ?: "${params.outdir}/reference_cache"
    metadataBaseDir = params.wgs_samplesheet ? file(params.wgs_samplesheet).parent.toString() : launchDir.toString()
    referenceBaseDir = params.reference_manifest ? file(params.reference_manifest).parent.toString() : launchDir.toString()
    PREPARE_WGS_INPUTS(
        wgs_samplesheet,
        reference_manifest,
        wgs_mode,
        wgs_variant_mode,
        wgs_filtering_mode,
        require_known_sites,
        allow_no_bqsr,
        referenceCacheDir,
        metadataBaseDir,
        referenceBaseDir
    )
    if (wgs_mode.toString() == 'stub') {
        WGS_STUB_OUTPUTS(PREPARE_WGS_INPUTS.out.wgs_manifest, PREPARE_WGS_INPUTS.out.warnings)
        finalBam = WGS_STUB_OUTPUTS.out.bam
        finalVariants = WGS_STUB_OUTPUTS.out.variants
        finalAlignmentQc = WGS_STUB_OUTPUTS.out.alignment_qc
        finalVariantQc = WGS_STUB_OUTPUTS.out.variant_qc
        finalSummary = WGS_STUB_OUTPUTS.out.summary
        finalManifest = WGS_STUB_OUTPUTS.out.outputs_manifest
        finalValidation = WGS_STUB_OUTPUTS.out.validation
    } else {
        WGS_SPLIT_MANIFEST(PREPARE_WGS_INPUTS.out.wgs_manifest)
        sample_ch = WGS_SPLIT_MANIFEST.out.samples.flatten().map { sample_file -> tuple(sample_file.baseName.toString(), sample_file) }
        reference_ch = WGS_SPLIT_MANIFEST.out.references.flatten().map { reference_file -> tuple(reference_file.baseName.toString(), reference_file) }
        WGS_BWA_MEM2_INDEX(reference_ch)
        index_done_ch = WGS_BWA_MEM2_INDEX.out.done.collect()
        WGS_BWA_MEM2_ALIGN_SAMPLE(sample_ch.combine(index_done_ch))
        WGS_QC(sample_ch, WGS_BWA_MEM2_ALIGN_SAMPLE.out.raw_bam)
        WGS_VARIANT_CALLING(WGS_QC.out.bam_for_variants, wgs_filtering_mode)
        WGS_REAL_AGGREGATE(
            WGS_SPLIT_MANIFEST.out.manifest,
            PREPARE_WGS_INPUTS.out.warnings,
            WGS_QC.out.bam_files.collect(),
            WGS_QC.out.bai_files.collect(),
            WGS_BWA_MEM2_ALIGN_SAMPLE.out.logs.collect(),
            WGS_QC.out.logs.collect(),
            WGS_VARIANT_CALLING.out.vcf_files.collect(),
            WGS_VARIANT_CALLING.out.index_files.collect(),
            WGS_VARIANT_CALLING.out.logs.collect()
        )
        finalBam = WGS_REAL_AGGREGATE.out.bam
        finalVariants = WGS_REAL_AGGREGATE.out.variants
        finalAlignmentQc = WGS_REAL_AGGREGATE.out.alignment_qc
        finalVariantQc = WGS_REAL_AGGREGATE.out.variant_qc
        finalSummary = WGS_REAL_AGGREGATE.out.summary
        finalManifest = WGS_REAL_AGGREGATE.out.outputs_manifest
        finalValidation = WGS_REAL_AGGREGATE.out.validation
    }

    emit:
    bam = finalBam
    variants = finalVariants
    alignment_qc = finalAlignmentQc
    variant_qc = finalVariantQc
    summary = finalSummary
    outputs_manifest = finalManifest
    validation = finalValidation
}
