#!/usr/bin/env python3
"""Prepare optional advanced-statistics model manifests for CAME."""

import argparse
import csv
import os
import sys


MISSING_VALUES = {"", "na", "n/a", "nan", "null", "none", "."}
REQUIRED_COLUMNS = ["model_id", "analysis_target", "model_family", "enabled"]
OPTIONAL_COLUMNS = [
    "response",
    "predictors",
    "covariates",
    "phylogenetic_model",
    "min_species",
    "notes",
]
MANIFEST_FIELDS = REQUIRED_COLUMNS + OPTIONAL_COLUMNS + [
    "status",
    "input_table",
    "species_traits",
    "phylogeny_manifest",
    "message",
]
WARNING_FIELDS = ["severity", "model_id", "analysis_target", "model_family", "message"]

ALLOWED_MODEL_FAMILIES = {
    "lm",
    "pgls_brownian",
    "pgls_pagel_lambda",
    "ou_placeholder",
    "robust_lm_placeholder",
    "multivariate_placeholder",
    "permutation_placeholder",
}
ALLOWED_TARGETS = {
    "hypothesis_model_table",
    "hypothesis_model_results",
    "phenotype_omics_model_table",
    "phenotype_index_contrasts",
    "component_trait_contrasts",
    "species_traits",
    "phylogeny_manifest",
}
TARGET_ALIASES = {
    "phylo_hypothesis_model_table": "hypothesis_model_table",
    "hypothesis_results": "hypothesis_model_results",
    "phenotype_omics_models": "phenotype_omics_model_table",
    "phenotype_omics_association_model_table": "phenotype_omics_model_table",
    "phenotype_contrasts": "phenotype_index_contrasts",
    "component_contrasts": "component_trait_contrasts",
}
TRUE_VALUES = {"1", "true", "t", "yes", "y", "enabled"}
FALSE_VALUES = {"0", "false", "f", "no", "n", "disabled"}


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


def warning_row(severity, model_id, target, family, message):
    return {
        "severity": severity,
        "model_id": model_id,
        "analysis_target": target,
        "model_family": family,
        "message": message,
    }


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


def read_config(path):
    if not path or not os.path.exists(path):
        raise RuntimeError(f"advanced_model_config does not exist: {path}")
    delimiter = infer_delimiter(path)
    with open(path, newline="") as handle:
        reader = csv.DictReader(handle, delimiter=delimiter)
        raw_fields = reader.fieldnames or []
        fields = [norm(field) for field in raw_fields]
        duplicate_fields = sorted({field for field in fields if fields.count(field) > 1})
        if duplicate_fields:
            raise RuntimeError("advanced_model_config has duplicate column(s): " + ", ".join(duplicate_fields))
        missing = sorted(set(REQUIRED_COLUMNS) - set(fields))
        if missing:
            raise RuntimeError("advanced_model_config is missing required column(s): " + ", ".join(missing))
        rows = []
        for row_number, raw_row in enumerate(reader, start=2):
            row = {field: norm(raw_row.get(raw_field)) for raw_field, field in zip(raw_fields, fields)}
            row["_row_number"] = str(row_number)
            rows.append(row)
    return rows


def parse_enabled(value):
    text = norm(value).lower()
    if text in TRUE_VALUES:
        return "true"
    if text in FALSE_VALUES:
        return "false"
    raise ValueError(f"enabled must be true/false-like, got '{value}'")


def clean_min_species(value):
    text = norm(value)
    if not text:
        return "3"
    try:
        parsed = int(float(text))
    except ValueError as exc:
        raise ValueError(f"min_species must be an integer, got '{value}'") from exc
    if parsed < 1:
        raise ValueError("min_species must be at least 1")
    return str(parsed)


def resolve_optional(path):
    text = norm(path)
    if text and os.path.exists(text):
        return os.path.abspath(text)
    return text


def first_existing(*paths):
    for path in paths:
        text = norm(path)
        if text and os.path.exists(text):
            return os.path.abspath(text)
    for path in paths:
        text = norm(path)
        if text:
            return text
    return ""


def target_paths(args):
    outdir = norm(args.outdir) or "results"
    return {
        "hypothesis_model_table": first_existing(
            args.hypothesis_model_table,
            os.path.join(outdir, "phylo", "input", "hypothesis_model_table.tsv"),
        ),
        "hypothesis_model_results": first_existing(
            args.hypothesis_model_results,
            os.path.join(outdir, "hypotheses", "hypothesis_model_results.tsv"),
        ),
        "phenotype_omics_model_table": first_existing(
            args.phenotype_omics_model_table,
            os.path.join(outdir, "integration", "input", "phenotype_omics_model_table.tsv"),
        ),
        "phenotype_index_contrasts": first_existing(
            args.phenotype_index_contrasts,
            os.path.join(outdir, "phenotype", "contrasts", "phenotype_index_contrasts.tsv"),
        ),
        "component_trait_contrasts": first_existing(
            args.component_trait_contrasts,
            os.path.join(outdir, "phenotype", "contrasts", "component_trait_contrasts.tsv"),
        ),
        "species_traits": first_existing(
            args.species_traits,
            os.path.join(outdir, "phylo", "input", "species_traits_wide.tsv"),
        ),
        "phylogeny_manifest": first_existing(args.phylogeny_manifest),
    }


def prepare(args):
    rows = read_config(args.config)
    paths = target_paths(args)
    manifest = []
    warnings = []
    seen_ids = set()
    errors = []

    for row in rows:
        model_id = norm(row.get("model_id"))
        raw_target = norm(row.get("analysis_target"))
        target = TARGET_ALIASES.get(raw_target, raw_target)
        family = norm(row.get("model_family"))
        if not model_id:
            errors.append(warning_row("ERROR", "", target, family, f"row {row['_row_number']} is missing model_id"))
            continue
        if model_id in seen_ids:
            errors.append(warning_row("ERROR", model_id, target, family, "Duplicate model_id"))
        seen_ids.add(model_id)
        if target not in ALLOWED_TARGETS:
            errors.append(warning_row("ERROR", model_id, target, family, f"Unsupported analysis_target: {target}"))
        if family not in ALLOWED_MODEL_FAMILIES:
            errors.append(warning_row("ERROR", model_id, target, family, f"Unsupported model_family: {family}"))
        try:
            enabled = parse_enabled(row.get("enabled"))
        except ValueError as exc:
            errors.append(warning_row("ERROR", model_id, target, family, str(exc)))
            enabled = ""
        try:
            min_species = clean_min_species(row.get("min_species"))
        except ValueError as exc:
            errors.append(warning_row("ERROR", model_id, target, family, str(exc)))
            min_species = norm(row.get("min_species"))

        input_table = paths.get(target, "")
        status = "DISABLED"
        message = "Model disabled in advanced_model_config."
        if enabled == "true":
            if input_table and os.path.exists(input_table):
                status = "READY"
                message = "Input target is available."
            else:
                status = "UNAVAILABLE"
                message = f"Input target is unavailable for analysis_target '{target}'."
                warnings.append(warning_row("WARNING", model_id, target, family, message))

        manifest.append(
            {
                "model_id": model_id,
                "analysis_target": target,
                "model_family": family,
                "enabled": enabled,
                "response": norm(row.get("response")),
                "predictors": norm(row.get("predictors")),
                "covariates": norm(row.get("covariates")),
                "phylogenetic_model": norm(row.get("phylogenetic_model")),
                "min_species": min_species,
                "notes": norm(row.get("notes")),
                "status": status,
                "input_table": input_table,
                "species_traits": resolve_optional(paths.get("species_traits")),
                "phylogeny_manifest": resolve_optional(paths.get("phylogeny_manifest")),
                "message": message,
            }
        )

    warnings = errors + warnings
    output_dir = args.output_dir
    write_tsv(os.path.join(output_dir, "advanced_model_manifest.tsv"), MANIFEST_FIELDS, manifest)
    write_tsv(os.path.join(output_dir, "advanced_model_warnings.tsv"), WARNING_FIELDS, warnings)
    if errors:
        raise RuntimeError(f"advanced_model_config validation failed with {len(errors)} error(s)")
    return manifest, warnings


def parse_args():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", required=True)
    parser.add_argument("--outdir", default="results")
    parser.add_argument("--species_traits", default="")
    parser.add_argument("--phylogeny_manifest", default="")
    parser.add_argument("--phenotype_index_contrasts", default="")
    parser.add_argument("--component_trait_contrasts", default="")
    parser.add_argument("--hypothesis_model_table", default="")
    parser.add_argument("--hypothesis_model_results", default="")
    parser.add_argument("--phenotype_omics_model_table", default="")
    parser.add_argument("--output_dir", default="results/advanced_statistics/input")
    return parser.parse_args()


def main():
    try:
        manifest, warnings = prepare(parse_args())
    except Exception as exc:
        print(f"ERROR\tprepare_advanced_model_inputs\t{exc}", file=sys.stderr)
        return 1
    ready = sum(1 for row in manifest if row["status"] == "READY")
    print(f"CAME advanced statistics input summary: models={len(manifest)} ready={ready} warnings={len(warnings)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
