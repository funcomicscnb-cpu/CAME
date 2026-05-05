#!/usr/bin/env python3
"""Create tiny deterministic real-mode fixtures for CAME Stage 28."""

from __future__ import annotations

import argparse
import csv
import hashlib
import os
from pathlib import Path


REFERENCE_ID = "tiny_real_ref"
SPECIES = "Tiny_mammal"
ASSEMBLY = "TinyRealAsm1"
CHROM = "chrTiny"
MITO = "chrM"
WRAP = 80


def deterministic_sequence(length: int, seed: int) -> str:
    state = seed
    bases = "ACGT"
    out: list[str] = []
    for idx in range(length):
        state = (1103515245 * state + 12345 + idx) & 0x7FFFFFFF
        out.append(bases[(state >> 8) & 3])
    return "".join(out)


def reverse_complement(sequence: str) -> str:
    table = str.maketrans("ACGTNacgtn", "TGCANtgcan")
    return sequence.translate(table)[::-1].upper()


def wrap_sequence(sequence: str, width: int = WRAP) -> str:
    return "\n".join(sequence[idx : idx + width] for idx in range(0, len(sequence), width))


def relative(path: Path, base: Path) -> str:
    return os.path.relpath(path, base).replace(os.sep, "/")


def write_text(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8", newline="\n")


def write_fasta(path: Path, records: list[tuple[str, str]]) -> list[dict[str, str]]:
    path.parent.mkdir(parents=True, exist_ok=True)
    offset = 0
    fai_rows: list[dict[str, str]] = []
    with path.open("w", encoding="utf-8", newline="\n") as handle:
        for name, sequence in records:
            header = f">{name}\n"
            handle.write(header)
            offset += len(header.encode("utf-8"))
            line_bases = min(WRAP, len(sequence))
            line_width = line_bases + 1
            fai_rows.append(
                {
                    "name": name,
                    "length": str(len(sequence)),
                    "offset": str(offset),
                    "line_bases": str(line_bases),
                    "line_width": str(line_width),
                }
            )
            for idx in range(0, len(sequence), WRAP):
                line = sequence[idx : idx + WRAP] + "\n"
                handle.write(line)
                offset += len(line.encode("utf-8"))
    return fai_rows


def write_fai(path: Path, rows: list[dict[str, str]]) -> None:
    lines = [
        "\t".join([row["name"], row["length"], row["offset"], row["line_bases"], row["line_width"]])
        for row in rows
    ]
    write_text(path, "\n".join(lines) + "\n")


def write_dict(path: Path, rows: list[dict[str, str]]) -> None:
    lines = ["@HD\tVN:1.6\tSO:unsorted"]
    for row in rows:
        lines.append(f"@SQ\tSN:{row['name']}\tLN:{row['length']}")
    write_text(path, "\n".join(lines) + "\n")


def read_fragment(sequence: str, start_1based: int, insert_size: int, read_length: int = 50) -> tuple[str, str]:
    start = start_1based - 1
    fragment = sequence[start : start + insert_size]
    if len(fragment) < insert_size:
        raise ValueError("Requested fragment extends beyond sequence")
    return fragment[:read_length], reverse_complement(fragment[-read_length:])


def write_fastq_pair(r1_path: Path, r2_path: Path, sample: str, pairs: list[tuple[str, str]]) -> None:
    r1_path.parent.mkdir(parents=True, exist_ok=True)
    r2_path.parent.mkdir(parents=True, exist_ok=True)
    with r1_path.open("w", encoding="utf-8", newline="\n") as r1, r2_path.open("w", encoding="utf-8", newline="\n") as r2:
        for idx, (r1_seq, r2_seq) in enumerate(pairs, start=1):
            quality_1 = "I" * len(r1_seq)
            quality_2 = "I" * len(r2_seq)
            read_id = f"{sample}_{idx:03d}"
            r1.write(f"@{read_id}/1\n{r1_seq}\n+\n{quality_1}\n")
            r2.write(f"@{read_id}/2\n{r2_seq}\n+\n{quality_2}\n")


def write_tsv(path: Path, fields: list[str], rows: list[dict[str, str]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(
            handle,
            fieldnames=fields,
            delimiter="\t",
            extrasaction="ignore",
            quoting=csv.QUOTE_NONE,
            escapechar="\\",
            lineterminator="\n",
        )
        writer.writeheader()
        writer.writerows(rows)


def write_csv(path: Path, fields: list[str], rows: list[dict[str, str]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=fields, extrasaction="ignore", lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)


def fixture_paths(outdir: Path) -> dict[str, Path]:
    return {
        "readme": outdir / "README.md",
        "fasta": outdir / "tiny_reference" / "tiny.fa",
        "fai": outdir / "tiny_reference" / "tiny.fa.fai",
        "dict": outdir / "tiny_reference" / "tiny.dict",
        "gtf": outdir / "tiny_reference" / "tiny.gtf",
        "gff3": outdir / "tiny_reference" / "tiny.gff3",
        "assembly_report": outdir / "tiny_reference" / "assembly_report.txt",
        "alias_map": outdir / "tiny_reference" / "alias_map.tsv",
        "chrom_sizes": outdir / "tiny_reference" / "tiny.chrom.sizes",
        "tss_bed": outdir / "tiny_reference" / "tiny.tss.bed",
        "repeatmasker": outdir / "tiny_reference" / "repeatmasker.bed",
        "mappability": outdir / "tiny_reference" / "mappability.bed",
        "blacklist": outdir / "tiny_reference" / "blacklist.bed",
        "rna_r1": outdir / "tiny_rna" / "tiny_rna_1_R1.fastq",
        "rna_r2": outdir / "tiny_rna" / "tiny_rna_1_R2.fastq",
        "atac_r1": outdir / "tiny_atac" / "tiny_atac_1_R1.fastq",
        "atac_r2": outdir / "tiny_atac" / "tiny_atac_1_R2.fastq",
        "wgs_r1": outdir / "tiny_wgs" / "tiny_wgs_1_R1.fastq",
        "wgs_r2": outdir / "tiny_wgs" / "tiny_wgs_1_R2.fastq",
        "reference_manifest": outdir / "manifests" / "reference_manifest.tsv",
        "real_mode_metadata": outdir / "manifests" / "real_mode_metadata.tsv",
        "wgs_samplesheet": outdir / "manifests" / "wgs_samplesheet.csv",
        "contracts": outdir / "manifests" / "expected_output_contracts.tsv",
    }


def ensure_can_write(paths: dict[str, Path], force: bool) -> None:
    existing = [path for path in paths.values() if path.exists()]
    if existing and not force:
        rendered = "\n".join(str(path) for path in existing[:20])
        raise SystemExit(f"Refusing to overwrite existing fixture files without --force:\n{rendered}")


def create_fixtures(outdir: Path, force: bool = False) -> None:
    paths = fixture_paths(outdir)
    ensure_can_write(paths, force)
    outdir.mkdir(parents=True, exist_ok=True)

    nuclear = deterministic_sequence(2400, 28)
    mito = deterministic_sequence(160, 2801)
    fai_rows = write_fasta(paths["fasta"], [(CHROM, nuclear), (MITO, mito)])
    write_fai(paths["fai"], fai_rows)
    write_dict(paths["dict"], fai_rows)

    write_text(
        paths["gtf"],
        "\n".join(
            [
                f'{CHROM}\tCAME\tgene\t101\t520\t.\t+\t.\tgene_id "tiny_gene_1"; gene_name "tiny_gene_1";',
                f'{CHROM}\tCAME\ttranscript\t101\t520\t.\t+\t.\tgene_id "tiny_gene_1"; transcript_id "tiny_tx_1";',
                f'{CHROM}\tCAME\texon\t101\t260\t.\t+\t.\tgene_id "tiny_gene_1"; transcript_id "tiny_tx_1"; exon_number "1";',
                f'{CHROM}\tCAME\texon\t321\t520\t.\t+\t.\tgene_id "tiny_gene_1"; transcript_id "tiny_tx_1"; exon_number "2";',
                "",
            ]
        ),
    )
    write_text(
        paths["gff3"],
        "\n".join(
            [
                "##gff-version 3",
                f"{CHROM}\tCAME\tgene\t101\t520\t.\t+\t.\tID=tiny_gene_1;Name=tiny_gene_1",
                f"{CHROM}\tCAME\tmRNA\t101\t520\t.\t+\t.\tID=tiny_tx_1;Parent=tiny_gene_1",
                f"{CHROM}\tCAME\texon\t101\t260\t.\t+\t.\tID=tiny_exon_1;Parent=tiny_tx_1",
                f"{CHROM}\tCAME\texon\t321\t520\t.\t+\t.\tID=tiny_exon_2;Parent=tiny_tx_1",
                "",
            ]
        ),
    )
    write_text(
        paths["assembly_report"],
        "\n".join(
            [
                "# Sequence-Name\tSequence-Role\tAssigned-Molecule\tAssigned-Molecule-Location/Type\tGenBank-Accn\tRelationship\tRefSeq-Accn\tAssembly-Unit\tSequence-Length\tUCSC-style-name",
                f"{CHROM}\tassembled-molecule\t{CHROM}\tChromosome\tCMSTAGE280001.1\t=\tNCSTAGE280001.1\tPrimary Assembly\t{len(nuclear)}\t{CHROM}",
                f"{MITO}\tassembled-molecule\t{MITO}\tMitochondrion\tCMSTAGE280002.1\t=\tNCSTAGE280002.1\tnon-nuclear\t{len(mito)}\t{MITO}",
                "",
            ]
        ),
    )
    write_tsv(
        paths["alias_map"],
        ["sequence_name", "sequence_role", "assigned_molecule", "genbank_accession", "refseq_accession", "ucsc_style_name"],
        [
            {
                "sequence_name": CHROM,
                "sequence_role": "assembled-molecule",
                "assigned_molecule": CHROM,
                "genbank_accession": "CMSTAGE280001.1",
                "refseq_accession": "NCSTAGE280001.1",
                "ucsc_style_name": CHROM,
            },
            {
                "sequence_name": MITO,
                "sequence_role": "assembled-molecule",
                "assigned_molecule": MITO,
                "genbank_accession": "CMSTAGE280002.1",
                "refseq_accession": "NCSTAGE280002.1",
                "ucsc_style_name": MITO,
            },
        ],
    )
    write_text(paths["chrom_sizes"], f"{CHROM}\t{len(nuclear)}\n{MITO}\t{len(mito)}\n")
    write_text(paths["tss_bed"], f"{CHROM}\t95\t155\ttiny_gene_1_tss\n")
    write_text(paths["repeatmasker"], f"{CHROM}\t720\t780\ttiny_repeat_1\n")
    write_text(paths["mappability"], f"{CHROM}\t1\t{len(nuclear)}\t1.0\n")
    write_text(paths["blacklist"], f"{MITO}\t0\t{len(mito)}\ttiny_mito_blacklist\n")

    rna_pairs = [read_fragment(nuclear, 121, 180), read_fragment(nuclear, 340, 150)]
    atac_pairs = [read_fragment(nuclear, start, 120) for start in range(760, 960, 10)]
    wgs_pairs = [read_fragment(nuclear, start, 160) for start in [1180, 1320, 1460, 1600]]
    write_fastq_pair(paths["rna_r1"], paths["rna_r2"], "tiny_rna_1", rna_pairs)
    write_fastq_pair(paths["atac_r1"], paths["atac_r2"], "tiny_atac_1", atac_pairs)
    write_fastq_pair(paths["wgs_r1"], paths["wgs_r2"], "tiny_wgs_1", wgs_pairs)

    manifest_dir = outdir / "manifests"
    reference_fields = [
        "reference_id",
        "species",
        "species_name",
        "assembly_name",
        "assembly_accession",
        "assembly_source",
        "assembly_release",
        "assembly_report",
        "fasta",
        "fai",
        "dict",
        "sequence_dict",
        "annotation_file",
        "gtf",
        "gff3",
        "annotation_format",
        "annotation_source",
        "annotation_release",
        "seqname_style",
        "mitochondrial_name",
        "genome_fasta",
        "transcript_fasta",
        "star_index",
        "bwa_index",
        "bwa_index_prefix",
        "bowtie2_index",
        "chrom_sizes",
        "tss_bed",
        "blacklist_bed",
        "repeatmasker_bed",
        "repeatmask_bed",
        "mappability_bed",
        "busco_lineage",
        "busco_complete",
        "annotation_version",
        "source",
        "notes",
    ]
    ref_row = {
        "reference_id": REFERENCE_ID,
        "species": SPECIES,
        "species_name": "Tiny mammal",
        "assembly_name": ASSEMBLY,
        "assembly_accession": "CAME_STAGE28_TINY_1",
        "assembly_source": "Custom",
        "assembly_release": "stage28",
        "assembly_report": relative(paths["assembly_report"], manifest_dir),
        "fasta": relative(paths["fasta"], manifest_dir),
        "fai": relative(paths["fai"], manifest_dir),
        "dict": relative(paths["dict"], manifest_dir),
        "sequence_dict": relative(paths["dict"], manifest_dir),
        "annotation_file": relative(paths["gtf"], manifest_dir),
        "gtf": relative(paths["gtf"], manifest_dir),
        "gff3": relative(paths["gff3"], manifest_dir),
        "annotation_format": "gtf",
        "annotation_source": "CAME",
        "annotation_release": "stage28",
        "seqname_style": "custom",
        "mitochondrial_name": MITO,
        "genome_fasta": relative(paths["fasta"], manifest_dir),
        "chrom_sizes": relative(paths["chrom_sizes"], manifest_dir),
        "tss_bed": relative(paths["tss_bed"], manifest_dir),
        "blacklist_bed": relative(paths["blacklist"], manifest_dir),
        "repeatmasker_bed": relative(paths["repeatmasker"], manifest_dir),
        "repeatmask_bed": relative(paths["repeatmasker"], manifest_dir),
        "mappability_bed": relative(paths["mappability"], manifest_dir),
        "busco_lineage": "mammalia_odb10",
        "busco_complete": "95.0",
        "annotation_version": "stage28",
        "source": "synthetic",
        "notes": "tiny deterministic Stage 28 fixture; not a biological benchmark",
    }
    write_tsv(paths["reference_manifest"], reference_fields, [ref_row])

    metadata_fields = [
        "sample_id",
        "study_id",
        "species",
        "individual_id",
        "biological_replicate",
        "assay",
        "tissue",
        "condition",
        "platform",
        "library_protocol",
        "read_layout",
        "fastq_1",
        "fastq_2",
        "reference_id",
        "strandedness",
        "batch",
        "read_length",
        "library_id",
        "run_id",
        "lane",
        "timepoint",
        "notes",
    ]
    metadata_rows = [
        {
            "sample_id": "tiny_rna_1",
            "study_id": "stage28_fixture",
            "species": SPECIES,
            "individual_id": "tiny_individual_1",
            "biological_replicate": "rep1",
            "assay": "rna",
            "tissue": "synthetic_tissue",
            "condition": "control",
            "platform": "Illumina",
            "library_protocol": "RNA-seq",
            "read_layout": "paired",
            "fastq_1": relative(paths["rna_r1"], manifest_dir),
            "fastq_2": relative(paths["rna_r2"], manifest_dir),
            "reference_id": REFERENCE_ID,
            "strandedness": "unstranded",
            "batch": "stage28_batch",
            "read_length": "50",
            "library_id": "tiny_rna_lib",
            "run_id": "tiny_run",
            "lane": "1",
            "timepoint": "0h",
            "notes": "synthetic contract fixture; not biological validation",
        },
        {
            "sample_id": "tiny_atac_1",
            "study_id": "stage28_fixture",
            "species": SPECIES,
            "individual_id": "tiny_individual_2",
            "biological_replicate": "rep1",
            "assay": "atac",
            "tissue": "synthetic_tissue",
            "condition": "control",
            "platform": "Illumina",
            "library_protocol": "ATAC-seq",
            "read_layout": "paired",
            "fastq_1": relative(paths["atac_r1"], manifest_dir),
            "fastq_2": relative(paths["atac_r2"], manifest_dir),
            "reference_id": REFERENCE_ID,
            "batch": "stage28_batch",
            "read_length": "50",
            "library_id": "tiny_atac_lib",
            "run_id": "tiny_run",
            "lane": "1",
            "timepoint": "0h",
            "notes": "synthetic contract fixture; not biological validation",
        },
        {
            "sample_id": "tiny_wgs_1",
            "study_id": "stage28_fixture",
            "species": SPECIES,
            "individual_id": "tiny_individual_3",
            "biological_replicate": "rep1",
            "assay": "wgs",
            "tissue": "synthetic_tissue",
            "condition": "control",
            "platform": "Illumina",
            "library_protocol": "short_read_wgs",
            "read_layout": "paired",
            "fastq_1": relative(paths["wgs_r1"], manifest_dir),
            "fastq_2": relative(paths["wgs_r2"], manifest_dir),
            "reference_id": REFERENCE_ID,
            "batch": "stage28_batch",
            "read_length": "50",
            "library_id": "tiny_wgs_lib",
            "run_id": "tiny_run",
            "lane": "1",
            "timepoint": "0h",
            "notes": "synthetic WGS SNP/indel contract fixture; not biological validation",
        },
    ]
    write_tsv(paths["real_mode_metadata"], metadata_fields, metadata_rows)

    wgs_fields = [
        "sample_id",
        "species",
        "individual_id",
        "reference_id",
        "fastq_1",
        "fastq_2",
        "read_layout",
        "batch",
        "platform",
        "library_id",
        "coverage_estimate",
        "notes",
        "study_id",
        "biological_replicate",
        "assay",
        "library_protocol",
        "tissue",
        "condition",
        "timepoint",
    ]
    write_csv(
        paths["wgs_samplesheet"],
        wgs_fields,
        [
            {
                "sample_id": "tiny_wgs_1",
                "species": SPECIES,
                "individual_id": "tiny_individual_3",
                "reference_id": REFERENCE_ID,
                "fastq_1": relative(paths["wgs_r1"], manifest_dir),
                "fastq_2": relative(paths["wgs_r2"], manifest_dir),
                "read_layout": "paired",
                "batch": "stage28_batch",
                "platform": "Illumina",
                "library_id": "tiny_wgs_lib",
                "coverage_estimate": "0.01",
                "notes": "synthetic contract fixture; not biological validation",
                "study_id": "stage28_fixture",
                "biological_replicate": "rep1",
                "assay": "wgs",
                "library_protocol": "short_read_wgs",
                "tissue": "synthetic_tissue",
                "condition": "control",
                "timepoint": "0h",
            }
        ],
    )

    write_tsv(
        paths["contracts"],
        ["assay", "artifact", "required_pattern", "mode", "assertion"],
        [
            {"assay": "rna", "artifact": "gene_counts", "required_pattern": "rnaseq/counts/gene_counts.tsv", "mode": "real", "assertion": "header contains tiny_rna_1 and at least one feature row"},
            {"assay": "atac", "artifact": "re_counts", "required_pattern": "atacseq/counts/re_counts.tsv", "mode": "real", "assertion": "header contains tiny_atac_1 and intervals are valid BED-like rows"},
            {"assay": "wgs", "artifact": "vcf", "required_pattern": "wgs/variants/tiny_wgs_1.vcf.gz", "mode": "real", "assertion": "VCF header contains tiny_wgs_1 and validation has no ERROR rows"},
            {"assay": "reference_quality", "artifact": "summary", "required_pattern": "reference_quality/reference_quality_summary.tsv", "mode": "contract", "assertion": "overall_status is not ERROR"},
        ],
    )

    write_text(
        paths["readme"],
        "\n".join(
            [
                "# Real-Mode Fixtures",
                "",
                "These Stage 28 fixtures are tiny synthetic contract fixtures for CAME real-mode plumbing.",
                "They are deterministic, local, and safe to keep in git. They are not biological benchmarks.",
                "",
                "Generated contents:",
                "",
                "- `tiny_reference/`: FASTA, FAI, sequence dictionary, GTF, GFF3, assembly report, alias map, and small BED helpers.",
                "- `tiny_rna/`: paired RNA FASTQ files.",
                "- `tiny_atac/`: paired ATAC FASTQ files.",
                "- `tiny_wgs/`: paired WGS FASTQ files.",
                "- `manifests/`: reference, real-mode metadata, WGS sample sheet, and expected contract records.",
                "",
                "Regenerate with:",
                "",
                "```bash",
                "python3 bin/make_real_mode_fixtures.py --outdir assets/test_data/real_mode_fixtures --force",
                "```",
                "",
            ]
        ),
    )


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--outdir", default="assets/test_data/real_mode_fixtures")
    parser.add_argument("--force", action="store_true", help="Overwrite existing generated fixture files.")
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    outdir = Path(args.outdir)
    create_fixtures(outdir, args.force)
    files = [path for path in fixture_paths(outdir).values() if path.exists()]
    total = sum(path.stat().st_size for path in files)
    digest = hashlib.sha256()
    for path in sorted(files):
        digest.update(path.relative_to(outdir).as_posix().encode("utf-8"))
        digest.update(path.read_bytes())
    print(f"CAME real-mode fixtures written to {outdir}")
    print(f"files={len(files)} bytes={total} sha256={digest.hexdigest()[:16]}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
