#!/usr/bin/env python3
"""Create deterministic stub outputs for CAME reference preparation."""

import argparse
import csv
import os
import re
import sys


MISSING_VALUES = {"", "na", "n/a", "nan", "null", "none", "."}
OUTPUT_FIELDS = ["reference_id", "species", "output_type", "path", "mode", "status", "description"]


def norm(value):
    text = str(value if value is not None else "").strip()
    return "" if text.lower() in MISSING_VALUES else text


def sanitize(value):
    text = norm(value) or "reference"
    text = re.sub(r"[^A-Za-z0-9_.-]+", "_", text)
    return text.strip("._") or "reference"


def read_manifest(path):
    with open(path, newline="") as handle:
        reader = csv.DictReader(handle, delimiter="\t")
        return [{key: norm(value) for key, value in row.items()} for row in reader]


def write_tsv(path, fields, rows):
    os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
    with open(path, "w", newline="") as handle:
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


def write_text(path, text):
    os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
    with open(path, "w", newline="") as handle:
        handle.write(text)


def reference_records(rows):
    seen = {}
    for row in rows:
        ref_id = norm(row.get("reference_id"))
        species = norm(row.get("species"))
        if not ref_id or not species:
            continue
        seen[(species, ref_id)] = {"species": species, "reference_id": ref_id}
    return [seen[key] for key in sorted(seen)]


def synthetic_sequence(seed):
    alphabet = "ACGT"
    offset = sum(ord(char) for char in seed) % len(alphabet)
    return "".join(alphabet[(offset + index) % len(alphabet)] for index in range(96))


def create_outputs(args):
    rows = read_manifest(args.prepared_manifest)
    refs = reference_records(rows)
    if not refs:
        raise SystemExit("No reference records found in prepared manifest")

    output_rows = []
    for record in refs:
        species = record["species"]
        ref_id = record["reference_id"]
        label = f"{sanitize(species)}.{sanitize(ref_id)}"
        sequence = synthetic_sequence(label)

        outputs = [
            (
                "corrected_reference_fasta",
                os.path.join("genomes", f"{label}.corrected.fa"),
                f">{label}_chrStub reference_id={ref_id} mode=stub\n{sequence}\n",
                "Deterministic corrected-reference FASTA stub",
            ),
            (
                "reliable_variants_vcf",
                os.path.join("variants", f"{label}.reliable_variants.vcf"),
                "##fileformat=VCFv4.2\n"
                "##source=CAME_reference_prepare_stub\n"
                "#CHROM\tPOS\tID\tREF\tALT\tQUAL\tFILTER\tINFO\n"
                f"{label}_chrStub\t16\t{label}_stub_variant\tA\tG\t60\tPASS\tREFERENCE_ID={ref_id};MODE=stub\n",
                "Deterministic reliable-variant VCF stub",
            ),
            (
                "problematic_sites_bed",
                os.path.join("masks", f"{label}.problematic_sites.bed"),
                f"{label}_chrStub\t20\t28\tproblematic_site_stub\n",
                "Problematic-site interval BED stub",
            ),
            (
                "nanoseq_exclusion_mask_bed",
                os.path.join("masks", f"{label}.nanoseq_exclusion_mask.bed"),
                f"{label}_chrStub\t40\t52\tnanoseq_exclusion_stub\n",
                "Future ultra-accurate sequencing exclusion BED stub",
            ),
            (
                "confirmed_cnvs_bed",
                os.path.join("cnv", f"{label}.confirmed_cnvs.bed"),
                f"{label}_chrStub\t64\t80\tconfirmed_cnv_stub\tcopy_number_gain\n",
                "Confirmed CNV interval BED stub",
            ),
        ]
        for output_type, rel_path, content, description in outputs:
            write_text(os.path.join(args.output_dir, rel_path), content)
            output_rows.append(
                {
                    "reference_id": ref_id,
                    "species": species,
                    "output_type": output_type,
                    "path": rel_path,
                    "mode": "stub",
                    "status": "OK",
                    "description": description,
                }
            )

    write_tsv(os.path.join(args.output_dir, "summary", "reference_prepare_outputs.tsv"), OUTPUT_FIELDS, output_rows)
    print(f"CAME synthetic reference outputs: references={len(refs)} outputs={len(output_rows)}")
    return 0


def parse_args():
    parser = argparse.ArgumentParser(description="Create synthetic CAME reference preparation outputs.")
    parser.add_argument("--prepared_manifest", required=True)
    parser.add_argument("--output_dir", default="results/reference")
    return parser.parse_args()


def main():
    try:
        return create_outputs(parse_args())
    except Exception as exc:
        print(f"ERROR\tmake_synthetic_reference_outputs\t{exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
