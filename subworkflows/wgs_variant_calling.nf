process WGS_GATK_HAPLOTYPECALLER_SAMPLE {
    label 'process_variant_calling'

    input:
    tuple val(sample_key), path(sample_manifest), path(bam), path(bai)

    output:
    tuple val(sample_key), path(sample_manifest), path("raw_variants/${sample_key}.raw.vcf.gz"), path("raw_variants/${sample_key}.raw.vcf.gz.tbi"), emit: raw_vcf
    path "logs/gatk/${sample_key}.haplotypecaller.*", emit: logs

    script:
    """
    set -euo pipefail
    command -v gatk >/dev/null 2>&1 || { echo "ERROR: gatk executable not found for WGS real mode. Install GATK or run --wgs_mode stub." >&2; exit 1; }
    mkdir -p raw_variants logs/gatk
    python3 - "${sample_manifest}" "${bam}" <<'PY' > haplotypecaller.sh
import csv
import shlex
import sys
manifest, bam = sys.argv[1:3]
row = next(csv.DictReader(open(manifest), delimiter="\\t"))
sample_key = row["sample_key"]
cmd = [
    "gatk",
    "HaplotypeCaller",
    "-R", row["fasta"],
    "-I", bam,
    "-O", f"raw_variants/{sample_key}.raw.vcf.gz",
]
print(" ".join(shlex.quote(part) for part in cmd) + " > " + shlex.quote(f"logs/gatk/{sample_key}.haplotypecaller.stdout.log") + " 2> " + shlex.quote(f"logs/gatk/{sample_key}.haplotypecaller.stderr.log"))
PY
    bash haplotypecaller.sh
    gatk IndexFeatureFile -I "raw_variants/${sample_key}.raw.vcf.gz" >> "logs/gatk/${sample_key}.haplotypecaller.stdout.log" 2>> "logs/gatk/${sample_key}.haplotypecaller.stderr.log" || true
    test -s "raw_variants/${sample_key}.raw.vcf.gz"
    test -s "raw_variants/${sample_key}.raw.vcf.gz.tbi"
    """
}

process WGS_GATK_FILTER_VARIANTS_SAMPLE {
    label 'process_variant_calling'

    input:
    tuple val(sample_key), path(sample_manifest), path(raw_vcf), path(raw_tbi)
    val filtering_mode

    output:
    tuple val(sample_key), path(sample_manifest), path("variants/${sample_key}.vcf.gz"), path("variants/${sample_key}.vcf.gz.tbi"), emit: final_vcf
    path "variants/${sample_key}.vcf.gz", emit: vcf_files
    path "variants/${sample_key}.vcf.gz.tbi", emit: index_files
    path "logs/gatk/${sample_key}.variant_filtering.*", emit: logs

    script:
    """
    set -euo pipefail
    command -v gatk >/dev/null 2>&1 || { echo "ERROR: gatk executable not found for WGS real mode. Install GATK or run --wgs_mode stub." >&2; exit 1; }
    mkdir -p variants logs/gatk
    case "${filtering_mode}" in
      hard_filter)
        python3 - "${sample_manifest}" "${raw_vcf}" <<'PY' > variant_filtering.sh
import csv
import shlex
import sys
manifest, raw_vcf = sys.argv[1:3]
row = next(csv.DictReader(open(manifest), delimiter="\\t"))
sample_key = row["sample_key"]
cmd = [
    "gatk",
    "VariantFiltration",
    "-R", row["fasta"],
    "-V", raw_vcf,
    "-O", f"variants/{sample_key}.vcf.gz",
    "--filter-name", "LowQual",
    "--filter-expression", "QUAL < 30.0",
]
print(" ".join(shlex.quote(part) for part in cmd) + " > " + shlex.quote(f"logs/gatk/{sample_key}.variant_filtering.stdout.log") + " 2> " + shlex.quote(f"logs/gatk/{sample_key}.variant_filtering.stderr.log"))
PY
        bash variant_filtering.sh
        ;;
      none)
        cp "${raw_vcf}" "variants/${sample_key}.vcf.gz"
        cp "${raw_tbi}" "variants/${sample_key}.vcf.gz.tbi"
        printf 'Variant filtering disabled by --wgs_filtering_mode none\\n' > "logs/gatk/${sample_key}.variant_filtering.stdout.log"
        : > "logs/gatk/${sample_key}.variant_filtering.stderr.log"
        ;;
      *)
        echo "ERROR: Unsupported --wgs_filtering_mode '${filtering_mode}'. Supported values: hard_filter, none." >&2
        exit 1
        ;;
    esac
    gatk IndexFeatureFile -I "variants/${sample_key}.vcf.gz" >> "logs/gatk/${sample_key}.variant_filtering.stdout.log" 2>> "logs/gatk/${sample_key}.variant_filtering.stderr.log" || true
    test -s "variants/${sample_key}.vcf.gz"
    test -s "variants/${sample_key}.vcf.gz.tbi"
    """
}

workflow WGS_VARIANT_CALLING {
    take:
    bam_for_variants
    filtering_mode

    main:
    WGS_GATK_HAPLOTYPECALLER_SAMPLE(bam_for_variants)
    WGS_GATK_FILTER_VARIANTS_SAMPLE(WGS_GATK_HAPLOTYPECALLER_SAMPLE.out.raw_vcf, filtering_mode)

    emit:
    final_vcf = WGS_GATK_FILTER_VARIANTS_SAMPLE.out.final_vcf
    vcf_files = WGS_GATK_FILTER_VARIANTS_SAMPLE.out.vcf_files
    index_files = WGS_GATK_FILTER_VARIANTS_SAMPLE.out.index_files
    logs = WGS_GATK_HAPLOTYPECALLER_SAMPLE.out.logs.mix(WGS_GATK_FILTER_VARIANTS_SAMPLE.out.logs)
}
