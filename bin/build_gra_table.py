#!/usr/bin/env python3
"""Build gene regulatory architecture tables from CAME RE-to-gene links."""

import argparse
import csv
import os
import sys
from collections import defaultdict


MISSING_VALUES = {"", "na", "n/a", "nan", "null", "none", "."}
REQUIRED_LINK_FIELDS = ["species", "re_feature_id", "gene_feature_id", "link_type"]
OPTIONAL_LINK_FIELDS = [
    "re_orthogroup_id",
    "gene_orthogroup_id",
    "distance_to_tss",
    "contact_score",
    "link_confidence",
    "source",
    "notes",
]
SUPPORTED_LINK_TYPES = {"promoter", "proximal", "distal_contact", "nearest_gene", "curated"}
ARCHITECTURE_FIELDS = [
    "gra_id",
    "gene_orthogroup_id",
    "feature_type",
    "n_res",
    "n_links",
    "n_species",
    "species_members",
    "link_types",
    "mapping_status",
    "is_ambiguous",
    "ambiguity_reason",
]
MEMBERSHIP_FIELDS = [
    "gra_id",
    "gene_orthogroup_id",
    "re_orthogroup_id",
    "link_type",
    "species_members",
    "n_species",
    "n_res",
    "mapping_status",
    "is_ambiguous",
    "source_gene_feature_ids",
    "source_re_feature_ids",
    "distance_to_tss",
    "contact_score",
    "link_confidence",
    "source",
    "notes",
]
WARNING_FIELDS = ["severity", "row", "gra_id", "gene_orthogroup_id", "re_orthogroup_id", "message"]


def norm(value):
    text = str(value if value is not None else "").strip()
    return "" if text.lower() in MISSING_VALUES else text


def infer_delimiter(path):
    ext = os.path.splitext(path)[1].lower()
    if ext == ".tsv":
        return "\t"
    if ext == ".csv":
        return ","
    with open(path, newline="") as handle:
        sample = handle.read(min(65536, os.path.getsize(path)))
    return "\t" if sample.count("\t") > sample.count(",") else ","


def read_table(path):
    delimiter = infer_delimiter(path)
    with open(path, newline="") as handle:
        reader = csv.DictReader(handle, delimiter=delimiter)
        raw_fields = reader.fieldnames or []
        fields = [norm(field) for field in raw_fields]
        rows = []
        for row in reader:
            cleaned = {}
            for raw_field, field in zip(raw_fields, fields):
                cleaned[field] = norm(row.get(raw_field))
            rows.append(cleaned)
    return fields, rows


def write_tsv(path, fields, rows):
    os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
    with open(path, "w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fields, delimiter="\t", extrasaction="ignore", quoting=csv.QUOTE_NONE, escapechar="\\", lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)


def warning(rows, severity, row, gra_id, gene_id, re_id, message):
    rows.append(
        {
            "severity": severity,
            "row": str(row or ""),
            "gra_id": gra_id,
            "gene_orthogroup_id": gene_id,
            "re_orthogroup_id": re_id,
            "message": message,
        }
    )


def load_orthogroups(path, label):
    fields, rows = read_table(path)
    if "orthogroup_id" not in fields:
        raise RuntimeError(f"{label} missing required column: orthogroup_id")
    return {norm(row.get("orthogroup_id")) for row in rows if norm(row.get("orthogroup_id"))}


def load_feature_map(path):
    fields, rows = read_table(path)
    missing = [field for field in ["feature_type", "species", "feature_id", "orthogroup_id"] if field not in fields]
    if missing:
        raise RuntimeError(f"{path} missing required column(s): {', '.join(missing)}")
    by_type_key = defaultdict(lambda: defaultdict(set))
    for row in rows:
        feature_type = norm(row.get("feature_type"))
        species = norm(row.get("species"))
        feature_id = norm(row.get("feature_id"))
        orthogroup_id = norm(row.get("orthogroup_id"))
        if feature_type and species and feature_id and orthogroup_id:
            by_type_key[feature_type][(species, feature_id)].add(orthogroup_id)
    return by_type_key


def resolve(link, kind, known_orthogroups, feature_map):
    if kind == "gene":
        supplied = norm(link.get("gene_orthogroup_id"))
        feature_id = norm(link.get("gene_feature_id"))
        feature_type = "gene"
    else:
        supplied = norm(link.get("re_orthogroup_id"))
        feature_id = norm(link.get("re_feature_id"))
        feature_type = "regulatory_element"
    if supplied:
        return {supplied} if supplied in known_orthogroups else set()
    species = norm(link.get("species"))
    return set(feature_map.get(feature_type, {}).get((species, feature_id), set()))


def parse_float(value):
    text = norm(value)
    if not text:
        return None
    try:
        return float(text)
    except ValueError:
        return None


def format_number(value):
    if value is None:
        return ""
    if abs(value - round(value)) < 1e-9:
        return str(int(round(value)))
    return format(value, ".12g")


def unique_join(values, sep=","):
    return sep.join(sorted({norm(value) for value in values if norm(value)}))


def summarize_numeric(values):
    numeric = [parse_float(value) for value in values]
    numeric = [value for value in numeric if value is not None]
    if not numeric:
        return ""
    return format_number(sum(numeric) / len(numeric))


def build(args):
    link_fields, raw_links = read_table(args.re_to_gene_links)
    missing_link_fields = [field for field in REQUIRED_LINK_FIELDS if field not in link_fields]
    if missing_link_fields:
        raise RuntimeError(f"re_to_gene_links missing required column(s): {', '.join(missing_link_fields)}")
    gene_orthogroups = load_orthogroups(args.gene_orthogroup_counts, "gene_orthogroup_counts")
    re_orthogroups = load_orthogroups(args.re_orthogroup_counts, "re_orthogroup_counts")
    feature_map = load_feature_map(args.feature_to_orthogroup_map)

    expanded = []
    warnings = []
    for idx, row in enumerate(raw_links, start=2):
        link = {field: norm(row.get(field)) for field in REQUIRED_LINK_FIELDS + OPTIONAL_LINK_FIELDS}
        empty_required = [field for field in REQUIRED_LINK_FIELDS if not link.get(field)]
        if empty_required:
            warning(warnings, "ERROR", idx, "", "", "", f"Skipping link with empty required value(s): {', '.join(empty_required)}")
            continue
        if link["link_type"] not in SUPPORTED_LINK_TYPES:
            warning(warnings, "WARNING", idx, "", "", "", f"Unsupported link_type retained: {link['link_type']}")
        gene_ids = resolve(link, "gene", gene_orthogroups, feature_map)
        re_ids = resolve(link, "re", re_orthogroups, feature_map)
        if not gene_ids or not re_ids:
            warning(
                warnings,
                "WARNING",
                idx,
                "",
                unique_join(gene_ids),
                unique_join(re_ids),
                "Skipping unresolved RE-to-gene link during GRA construction",
            )
            continue
        is_resolution_ambiguous = len(gene_ids) > 1 or len(re_ids) > 1
        for gene_id in sorted(gene_ids):
            for re_id in sorted(re_ids):
                gra_id = f"GRA_{gene_id}"
                expanded.append(
                    {
                        "row": str(idx),
                        "gra_id": gra_id,
                        "gene_orthogroup_id": gene_id,
                        "re_orthogroup_id": re_id,
                        "link_type": link["link_type"],
                        "species": link["species"],
                        "gene_feature_id": link["gene_feature_id"],
                        "re_feature_id": link["re_feature_id"],
                        "distance_to_tss": link.get("distance_to_tss", ""),
                        "contact_score": link.get("contact_score", ""),
                        "link_confidence": link.get("link_confidence", ""),
                        "source": link.get("source", ""),
                        "notes": link.get("notes", ""),
                        "resolution_ambiguous": is_resolution_ambiguous,
                    }
                )

    genes_by_re = defaultdict(set)
    for row in expanded:
        genes_by_re[row["re_orthogroup_id"]].add(row["gene_orthogroup_id"])
    multi_gene_res = {re_id for re_id, genes in genes_by_re.items() if len(genes) > 1}
    for re_id in sorted(multi_gene_res):
        warning(
            warnings,
            "WARNING",
            "",
            "",
            unique_join(genes_by_re[re_id]),
            re_id,
            "RE orthogroup is linked to multiple gene orthogroups and was duplicated across GRAs",
        )

    membership_groups = defaultdict(list)
    for row in expanded:
        key = (row["gra_id"], row["gene_orthogroup_id"], row["re_orthogroup_id"], row["link_type"])
        membership_groups[key].append(row)

    membership_rows = []
    architecture = defaultdict(lambda: {"res": set(), "links": 0, "species": set(), "link_types": set(), "ambiguous": set()})
    for key in sorted(membership_groups):
        gra_id, gene_id, re_id, link_type = key
        rows = membership_groups[key]
        species = {row["species"] for row in rows if row["species"]}
        re_features = {row["re_feature_id"] for row in rows if row["re_feature_id"]}
        gene_features = {row["gene_feature_id"] for row in rows if row["gene_feature_id"]}
        reasons = set()
        if any(row["resolution_ambiguous"] for row in rows):
            reasons.add("multiple_orthogroup_resolutions")
        if re_id in multi_gene_res:
            reasons.add("re_linked_to_multiple_genes")
        is_ambiguous = bool(reasons)
        membership_rows.append(
            {
                "gra_id": gra_id,
                "gene_orthogroup_id": gene_id,
                "re_orthogroup_id": re_id,
                "link_type": link_type,
                "species_members": unique_join(species),
                "n_species": str(len(species)),
                "n_res": str(len(re_features) if re_features else 1),
                "mapping_status": "ambiguous" if is_ambiguous else "mapped",
                "is_ambiguous": "true" if is_ambiguous else "false",
                "source_gene_feature_ids": unique_join(gene_features),
                "source_re_feature_ids": unique_join(re_features),
                "distance_to_tss": summarize_numeric([row.get("distance_to_tss", "") for row in rows]),
                "contact_score": summarize_numeric([row.get("contact_score", "") for row in rows]),
                "link_confidence": summarize_numeric([row.get("link_confidence", "") for row in rows]),
                "source": unique_join([row.get("source", "") for row in rows]),
                "notes": unique_join([row.get("notes", "") for row in rows], sep="; "),
            }
        )
        arch = architecture[(gra_id, gene_id)]
        arch["res"].add(re_id)
        arch["links"] += len(rows)
        arch["species"].update(species)
        arch["link_types"].add(link_type)
        arch["ambiguous"].update(reasons)

    architecture_rows = []
    for gra_id, gene_id in sorted(architecture):
        entry = architecture[(gra_id, gene_id)]
        is_ambiguous = bool(entry["ambiguous"])
        architecture_rows.append(
            {
                "gra_id": gra_id,
                "gene_orthogroup_id": gene_id,
                "feature_type": "gene_regulatory_architecture",
                "n_res": str(len(entry["res"])),
                "n_links": str(entry["links"]),
                "n_species": str(len(entry["species"])),
                "species_members": unique_join(entry["species"]),
                "link_types": unique_join(entry["link_types"]),
                "mapping_status": "ambiguous" if is_ambiguous else "mapped",
                "is_ambiguous": "true" if is_ambiguous else "false",
                "ambiguity_reason": unique_join(entry["ambiguous"]),
            }
        )

    os.makedirs(args.output_dir, exist_ok=True)
    write_tsv(os.path.join(args.output_dir, "gene_regulatory_architectures.tsv"), ARCHITECTURE_FIELDS, architecture_rows)
    write_tsv(os.path.join(args.output_dir, "gra_re_membership.tsv"), MEMBERSHIP_FIELDS, membership_rows)
    write_tsv(os.path.join(args.output_dir, "gra_link_warnings.tsv"), WARNING_FIELDS, warnings)
    errors = sum(1 for row in warnings if row["severity"] == "ERROR")
    print(
        "CAME GRA construction summary: "
        f"input_links={len(raw_links)} resolved_memberships={len(membership_rows)} GRAs={len(architecture_rows)} ERROR={errors}"
    )
    return 1 if errors else 0


def parse_args():
    parser = argparse.ArgumentParser(description="Build CAME gene regulatory architecture tables.")
    parser.add_argument("--re_to_gene_links", required=True)
    parser.add_argument("--gene_orthogroup_counts", required=True)
    parser.add_argument("--re_orthogroup_counts", required=True)
    parser.add_argument("--feature_to_orthogroup_map", required=True)
    parser.add_argument("--validation_report", default="")
    parser.add_argument("--output_dir", default="results/gra/tables")
    return parser.parse_args()


def main():
    try:
        return build(parse_args())
    except Exception as exc:
        print(f"ERROR\tbuild_gra_table\t{exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
