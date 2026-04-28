#!/usr/bin/env python3
"""Prepare CAME phenotype-omics integration input tables."""

import argparse
import csv
import math
import os
import sys
from collections import Counter, defaultdict

try:
    from phenotype_utils import load_profile, norm as profile_norm, phenotype_index
except Exception:  # pragma: no cover - direct fallback for unusual execution paths
    load_profile = None
    profile_norm = None
    phenotype_index = None


MISSING_VALUES = {"", "na", "n/a", "nan", "null", "none", "."}
PHENOTYPE_METRICS = {"difference", "fold_change", "log2_fold_change"}
WARNING_FIELDS = [
    "severity",
    "source",
    "feature_layer",
    "species",
    "contrast_name",
    "feature_id",
    "phenotype_response_id",
    "message",
]
PHENOTYPE_FIELDS = [
    "species",
    "contrast_name",
    "contrast_type",
    "baseline_label",
    "response_label",
    "phenotype_index_name",
    "phenotype_response_id",
    "phenotype_response_type",
    "phenotype_response_metric",
    "phenotype_response_value",
    "status",
    "message",
]
MOLECULAR_FIELDS = [
    "species",
    "contrast_name",
    "contrast_type",
    "baseline_label",
    "response_label",
    "feature_layer",
    "feature_id",
    "feature_response_metric",
    "feature_response_value",
    "status",
    "message",
    "source_feature_ids",
]
MODEL_FIELDS = [
    "species",
    "contrast_name",
    "phenotype_index_name",
    "phenotype_response_id",
    "phenotype_response_type",
    "phenotype_response_metric",
    "phenotype_response_value",
    "feature_layer",
    "feature_id",
    "feature_response_metric",
    "feature_response_value",
    "baseline_label",
    "response_label",
    "contrast_type",
    "phenotype_status",
    "feature_status",
]


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


def read_table(path, required=True):
    if not path or not os.path.exists(path):
        if required:
            raise RuntimeError(f"Missing required input table: {path}")
        return [], []
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


def warn(warnings, severity, source, message, feature_layer="", species="", contrast_name="", feature_id="", phenotype_response_id=""):
    warnings.append(
        {
            "severity": severity,
            "source": source,
            "feature_layer": feature_layer,
            "species": species,
            "contrast_name": contrast_name,
            "feature_id": feature_id,
            "phenotype_response_id": phenotype_response_id,
            "message": message,
        }
    )


def parse_float(value):
    text = norm(value)
    if not text:
        return None
    try:
        value = float(text)
    except ValueError:
        return None
    if math.isnan(value) or math.isinf(value):
        return None
    return value


def profile_index_name(path, warnings):
    if not path:
        return "phenotype_index"
    if load_profile is None or phenotype_index is None:
        warn(warnings, "WARNING", "study_profile", "Could not import study profile helpers; using phenotype_index as the index name")
        return "phenotype_index"
    try:
        profile = load_profile(path)
        index = phenotype_index(profile)
        name = profile_norm(index.get("name")) if profile_norm else norm(index.get("name"))
        return name or "phenotype_index"
    except Exception as exc:
        warn(warnings, "WARNING", "study_profile", f"Could not read study profile index name: {exc}")
        return "phenotype_index"


def require_fields(fields, required, source):
    missing = [field for field in required if field not in fields]
    if missing:
        raise RuntimeError(f"{source} missing required column(s): {', '.join(missing)}")


def phenotype_rows(index_path, component_path, metric, index_name, warnings):
    if metric not in PHENOTYPE_METRICS:
        raise RuntimeError(f"Unsupported phenotype response metric: {metric}")
    fields, rows = read_table(index_path)
    require_fields(fields, ["species", "contrast_name", "baseline_label", "response_label", metric], "phenotype_index_contrasts")
    output = []
    for row in rows:
        output.append(
            {
                "species": norm(row.get("species")),
                "contrast_name": norm(row.get("contrast_name")),
                "contrast_type": norm(row.get("contrast_type")),
                "baseline_label": norm(row.get("baseline_label")),
                "response_label": norm(row.get("response_label")),
                "phenotype_index_name": index_name,
                "phenotype_response_id": index_name,
                "phenotype_response_type": "phenotype_index",
                "phenotype_response_metric": metric,
                "phenotype_response_value": norm(row.get(metric)),
                "status": norm(row.get("status")),
                "message": norm(row.get("message")),
            }
        )

    fields, rows = read_table(component_path)
    require_fields(fields, ["trait", "species", "contrast_name", "baseline_label", "response_label", metric], "component_trait_contrasts")
    for row in rows:
        trait = norm(row.get("trait"))
        if not trait:
            warn(warnings, "WARNING", "component_trait_contrasts", "Component contrast row lacks trait name", species=norm(row.get("species")), contrast_name=norm(row.get("contrast_name")))
            continue
        output.append(
            {
                "species": norm(row.get("species")),
                "contrast_name": norm(row.get("contrast_name")),
                "contrast_type": norm(row.get("contrast_type")),
                "baseline_label": norm(row.get("baseline_label")),
                "response_label": norm(row.get("response_label")),
                "phenotype_index_name": index_name,
                "phenotype_response_id": trait,
                "phenotype_response_type": "component_trait",
                "phenotype_response_metric": metric,
                "phenotype_response_value": norm(row.get(metric)),
                "status": norm(row.get("status")),
                "message": norm(row.get("message")),
            }
        )
    return output


def normalize_expression_or_accessibility(path, layer, metric, warnings):
    fields, rows = read_table(path)
    source = f"differential_{layer}_orthogroups"
    require_fields(fields, ["orthogroup_id", "species", "contrast_name", "baseline_label", "response_label", metric], source)
    output = []
    for row in rows:
        feature_id = norm(row.get("orthogroup_id"))
        if not feature_id:
            warn(warnings, "WARNING", source, "Molecular row lacks orthogroup_id", feature_layer=layer, species=norm(row.get("species")), contrast_name=norm(row.get("contrast_name")))
        output.append(
            {
                "species": norm(row.get("species")),
                "contrast_name": norm(row.get("contrast_name")),
                "contrast_type": norm(row.get("contrast_type")),
                "baseline_label": norm(row.get("baseline_label")),
                "response_label": norm(row.get("response_label")),
                "feature_layer": layer,
                "feature_id": feature_id,
                "feature_response_metric": metric,
                "feature_response_value": norm(row.get(metric)),
                "status": norm(row.get("status")),
                "message": norm(row.get("message")),
                "source_feature_ids": norm(row.get("source_feature_ids")),
            }
        )
    return output


def normalize_gra(path, metric, warnings):
    fields, rows = read_table(path)
    source = "differential_gra_activity"
    require_fields(fields, ["gra_id", "contrast_name", "baseline_label", "response_label", metric], source)
    if "species" not in fields:
        warn(warnings, "WARNING", source, "GRA differential table lacks species column; GRA rows cannot be joined to phenotype responses", feature_layer="gra_activity")
    output = []
    for row in rows:
        species = norm(row.get("species"))
        feature_id = norm(row.get("gra_id"))
        if not species:
            warn(warnings, "WARNING", source, "GRA molecular row lacks species and cannot be modeled", feature_layer="gra_activity", contrast_name=norm(row.get("contrast_name")), feature_id=feature_id)
        output.append(
            {
                "species": species,
                "contrast_name": norm(row.get("contrast_name")),
                "contrast_type": norm(row.get("contrast_type")),
                "baseline_label": norm(row.get("baseline_label")),
                "response_label": norm(row.get("response_label")),
                "feature_layer": "gra_activity",
                "feature_id": feature_id,
                "feature_response_metric": metric,
                "feature_response_value": norm(row.get(metric)),
                "status": norm(row.get("status")),
                "message": norm(row.get("message")),
                "source_feature_ids": norm(row.get("gene_orthogroup_id")),
            }
        )
    return output


def molecular_rows(args, warnings):
    if args.molecular_response_metric != "log2_fold_change":
        warn(warnings, "WARNING", "params", f"Using non-default molecular response metric: {args.molecular_response_metric}")
    output = []
    output.extend(normalize_expression_or_accessibility(args.differential_expression_orthogroups, "expression", args.molecular_response_metric, warnings))
    output.extend(normalize_expression_or_accessibility(args.differential_accessibility_orthogroups, "accessibility", args.molecular_response_metric, warnings))
    output.extend(normalize_gra(args.differential_gra_activity, args.molecular_response_metric, warnings))
    return output


def join_key(row):
    return (
        norm(row.get("species")),
        norm(row.get("contrast_name")),
        norm(row.get("baseline_label")),
        norm(row.get("response_label")),
    )


def selected_phenotypes(rows, scope):
    if scope == "index":
        return [row for row in rows if row.get("phenotype_response_type") == "phenotype_index"]
    if scope == "all":
        return list(rows)
    raise RuntimeError(f"Unsupported phenotype_response_scope: {scope}")


def build_model_rows(phenotypes, molecular, scope, warnings):
    selected = selected_phenotypes(phenotypes, scope)
    phenotypes_by_key = defaultdict(list)
    molecular_by_key = defaultdict(list)
    for row in selected:
        phenotypes_by_key[join_key(row)].append(row)
    for row in molecular:
        molecular_by_key[join_key(row)].append(row)

    for key, rows in sorted(phenotypes_by_key.items()):
        if key not in molecular_by_key:
            species, contrast_name, _, _ = key
            for row in rows:
                warn(warnings, "WARNING", "join", "No molecular response matched phenotype response", species=species, contrast_name=contrast_name, phenotype_response_id=row.get("phenotype_response_id"))
    for key, rows in sorted(molecular_by_key.items()):
        if key not in phenotypes_by_key:
            species, contrast_name, _, _ = key
            for row in rows:
                warn(warnings, "WARNING", "join", "No phenotype response matched molecular response", feature_layer=row.get("feature_layer"), species=species, contrast_name=contrast_name, feature_id=row.get("feature_id"))

    output = []
    for key in sorted(set(phenotypes_by_key) & set(molecular_by_key)):
        for phenotype in phenotypes_by_key[key]:
            phenotype_value = parse_float(phenotype.get("phenotype_response_value"))
            if phenotype_value is None:
                warn(warnings, "WARNING", "model_table", "Phenotype response value is not numeric; matched rows were not modeled", species=phenotype.get("species"), contrast_name=phenotype.get("contrast_name"), phenotype_response_id=phenotype.get("phenotype_response_id"))
                continue
            for feature in molecular_by_key[key]:
                feature_value = parse_float(feature.get("feature_response_value"))
                if feature_value is None:
                    warn(warnings, "WARNING", "model_table", "Feature response value is not numeric; matched row was not modeled", feature_layer=feature.get("feature_layer"), species=feature.get("species"), contrast_name=feature.get("contrast_name"), feature_id=feature.get("feature_id"), phenotype_response_id=phenotype.get("phenotype_response_id"))
                    continue
                if not feature.get("feature_id"):
                    warn(warnings, "WARNING", "model_table", "Feature id is missing; matched row was not modeled", feature_layer=feature.get("feature_layer"), species=feature.get("species"), contrast_name=feature.get("contrast_name"), phenotype_response_id=phenotype.get("phenotype_response_id"))
                    continue
                output.append(
                    {
                        "species": phenotype["species"],
                        "contrast_name": phenotype["contrast_name"],
                        "phenotype_index_name": phenotype["phenotype_index_name"],
                        "phenotype_response_id": phenotype["phenotype_response_id"],
                        "phenotype_response_type": phenotype["phenotype_response_type"],
                        "phenotype_response_metric": phenotype["phenotype_response_metric"],
                        "phenotype_response_value": phenotype["phenotype_response_value"],
                        "feature_layer": feature["feature_layer"],
                        "feature_id": feature["feature_id"],
                        "feature_response_metric": feature["feature_response_metric"],
                        "feature_response_value": feature["feature_response_value"],
                        "baseline_label": phenotype["baseline_label"],
                        "response_label": phenotype["response_label"],
                        "contrast_type": phenotype.get("contrast_type") or feature.get("contrast_type"),
                        "phenotype_status": phenotype.get("status", ""),
                        "feature_status": feature.get("status", ""),
                    }
                )
    return output


def parse_args():
    parser = argparse.ArgumentParser(description="Prepare CAME Stage 9 phenotype-omics inputs.")
    parser.add_argument("--phenotype_index_contrasts", default="results/phenotype/contrasts/phenotype_index_contrasts.tsv")
    parser.add_argument("--component_trait_contrasts", default="results/phenotype/contrasts/component_trait_contrasts.tsv")
    parser.add_argument("--differential_expression_orthogroups", default="results/orthology/differential_expression_orthogroups.tsv")
    parser.add_argument("--differential_accessibility_orthogroups", default="results/orthology/differential_accessibility_orthogroups.tsv")
    parser.add_argument("--differential_gra_activity", default="results/gra/differential/differential_gra_activity.tsv")
    parser.add_argument("--study_profile", default="")
    parser.add_argument("--phenotype_response_metric", default="difference")
    parser.add_argument("--molecular_response_metric", default="log2_fold_change")
    parser.add_argument("--phenotype_response_scope", default="index", choices=["index", "all"])
    parser.add_argument("--output_dir", default="results/integration/input")
    return parser.parse_args()


def main():
    args = parse_args()
    warnings = []
    try:
        index_name = profile_index_name(args.study_profile, warnings)
        phenotypes = phenotype_rows(
            args.phenotype_index_contrasts,
            args.component_trait_contrasts,
            args.phenotype_response_metric,
            index_name,
            warnings,
        )
        molecular = molecular_rows(args, warnings)
        model_rows = build_model_rows(phenotypes, molecular, args.phenotype_response_scope, warnings)
        os.makedirs(args.output_dir, exist_ok=True)
        write_tsv(os.path.join(args.output_dir, "phenotype_response_table.tsv"), PHENOTYPE_FIELDS, phenotypes)
        write_tsv(os.path.join(args.output_dir, "molecular_response_long.tsv"), MOLECULAR_FIELDS, molecular)
        write_tsv(os.path.join(args.output_dir, "phenotype_omics_model_table.tsv"), MODEL_FIELDS, model_rows)
        write_tsv(os.path.join(args.output_dir, "phenotype_omics_input_warnings.tsv"), WARNING_FIELDS, warnings)
    except Exception as exc:
        os.makedirs(args.output_dir, exist_ok=True)
        warn(warnings, "ERROR", "prepare_phenotype_omics_inputs", str(exc))
        write_tsv(os.path.join(args.output_dir, "phenotype_omics_input_warnings.tsv"), WARNING_FIELDS, warnings)
        print(f"ERROR\tprepare_phenotype_omics_inputs\t{exc}", file=sys.stderr)
        return 1

    counts = Counter(row["severity"] for row in warnings)
    print(
        "CAME phenotype-omics input summary: "
        f"phenotype_rows={len(phenotypes)} molecular_rows={len(molecular)} model_rows={len(model_rows)} "
        f"WARNING={counts.get('WARNING', 0)}"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
