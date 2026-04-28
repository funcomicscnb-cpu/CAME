#!/usr/bin/env python3
"""Prepare model-ready phylogenetic and hypothesis input tables for CAME."""

import argparse
import os
import sys
from collections import defaultdict

from phenotype_utils import (
    as_list,
    format_value,
    load_profile,
    norm,
    parse_float,
    phenotype_index,
    profile_components,
    read_table,
    write_tsv,
)


METRICS = {"difference", "fold_change", "log2_fold_change"}
BASE_TRAIT_FIELDS = ["species", "phylogeny_label", "common_name", "clade"]
PHYLOGENY_FIELDS = ["phylogeny_id", "phylogeny_file"]


def stderr(message):
    print(message, file=sys.stderr)


def selected_response_metric(profile):
    index = phenotype_index(profile)
    metric = norm(profile.get("response_metric")) or norm(index.get("response_metric")) or "difference"
    if metric not in METRICS:
        raise RuntimeError(f"Unsupported response_metric: {metric}. Supported values: {', '.join(sorted(METRICS))}")
    return metric


def variable_name(row):
    for field in ["trait", "trait_name", "variable", "covariate", "external_trait"]:
        value = norm(row.get(field))
        if value:
            return value
    return ""


def same_numeric_or_text(left, right):
    left_num = parse_float(left)
    right_num = parse_float(right)
    if left_num is not None and right_num is not None:
        return abs(left_num - right_num) < 1e-12
    return norm(left) == norm(right)


def read_species_traits(path):
    fields, rows = read_table(path)
    required = {"species", "phylogeny_label", "trait_value"}
    missing = sorted(required - set(fields))
    if missing:
        raise RuntimeError("species_traits is missing required columns: " + ", ".join(missing))

    species_meta = {}
    values = defaultdict(dict)
    metadata = defaultdict(dict)
    labels_by_species = defaultdict(set)
    variables = set()
    warnings = []

    for row_number, row in enumerate(rows, start=2):
        species = norm(row.get("species"))
        label = norm(row.get("phylogeny_label"))
        trait = variable_name(row)
        value = norm(row.get("trait_value"))
        if not species or not label:
            raise RuntimeError(f"species_traits row {row_number} is missing species or phylogeny_label")
        labels_by_species[species].add(label)
        species_meta.setdefault(
            species,
            {
                "species": species,
                "phylogeny_label": label,
                "common_name": norm(row.get("common_name")),
                "clade": norm(row.get("clade")),
            },
        )
        for field in ["common_name", "clade"]:
            current = species_meta[species].get(field, "")
            incoming = norm(row.get(field))
            if incoming and current and incoming != current:
                warnings.append(f"WARNING\tprepare_phylo_inputs\tConflicting {field} for {species}; keeping first value")
            elif incoming and not current:
                species_meta[species][field] = incoming
        if not trait:
            warnings.append(f"WARNING\tprepare_phylo_inputs\tSkipping trait row without variable name for species {species}")
            continue
        variables.add(trait)
        if trait in values[species] and not same_numeric_or_text(values[species][trait], value):
            raise RuntimeError(f"Conflicting values for trait {trait} in species {species}")
        values[species][trait] = value
        metadata[species][f"{trait}_unit"] = norm(row.get("trait_unit"))
        metadata[species][f"{trait}_source"] = norm(row.get("trait_source"))
        metadata[species][f"{trait}_confidence"] = norm(row.get("trait_confidence"))

    conflicts = {
        species: sorted(labels)
        for species, labels in labels_by_species.items()
        if len(labels) > 1
    }
    if conflicts:
        details = "; ".join(f"{species}: {', '.join(labels)}" for species, labels in sorted(conflicts.items()))
        raise RuntimeError("Multiple phylogeny labels in species_traits: " + details)

    trait_fields = []
    for trait in sorted(variables):
        trait_fields.extend([trait, f"{trait}_unit", f"{trait}_source", f"{trait}_confidence"])

    wide_rows = []
    for species in sorted(species_meta):
        row = dict(species_meta[species])
        for trait in sorted(variables):
            row[trait] = values[species].get(trait, "")
            row[f"{trait}_unit"] = metadata[species].get(f"{trait}_unit", "")
            row[f"{trait}_source"] = metadata[species].get(f"{trait}_source", "")
            row[f"{trait}_confidence"] = metadata[species].get(f"{trait}_confidence", "")
        wide_rows.append(row)
    return wide_rows, BASE_TRAIT_FIELDS + trait_fields, sorted(variables), warnings


def resolve_phylogeny_file(manifest_path, phylogeny_file, base_dir=""):
    path = norm(phylogeny_file)
    if not path:
        return ""
    if os.path.isabs(path):
        return path
    root = norm(base_dir) or os.path.dirname(os.path.abspath(manifest_path))
    return os.path.normpath(os.path.join(root, path))


def read_phylogeny_manifest(path, species_rows, base_dir=""):
    fields, rows = read_table(path)
    required = {"phylogeny_id", "phylogeny_file"}
    missing = sorted(required - set(fields))
    if missing:
        raise RuntimeError("phylogeny_manifest is missing required columns: " + ", ".join(missing))

    by_species = defaultdict(list)
    defaults = []
    for row in rows:
        record = {
            "phylogeny_id": norm(row.get("phylogeny_id")),
            "phylogeny_file": resolve_phylogeny_file(path, row.get("phylogeny_file"), base_dir),
            "species": norm(row.get("species")),
            "phylogeny_label": norm(row.get("phylogeny_label")),
        }
        if record["species"]:
            by_species[record["species"]].append(record)
        else:
            defaults.append(record)

    warnings = []
    phylogeny_by_species = {}
    for species_row in species_rows:
        species = species_row["species"]
        trait_label = species_row["phylogeny_label"]
        candidates = by_species.get(species) or defaults
        if not candidates:
            warnings.append(f"WARNING\tprepare_phylo_inputs\tSpecies lacks phylogeny_manifest row: {species}")
            phylogeny_by_species[species] = {"phylogeny_id": "", "phylogeny_file": ""}
            continue
        candidate = candidates[0]
        manifest_label = candidate.get("phylogeny_label", "")
        if manifest_label and manifest_label != trait_label:
            raise RuntimeError(f"Phylogeny label mismatch for {species}: species_traits={trait_label}, phylogeny_manifest={manifest_label}")
        phylogeny_by_species[species] = {
            "phylogeny_id": candidate["phylogeny_id"],
            "phylogeny_file": candidate["phylogeny_file"],
        }
        if candidate["phylogeny_file"] and not os.path.exists(candidate["phylogeny_file"]):
            warnings.append(f"WARNING\tprepare_phylo_inputs\tPhylogeny file does not exist yet: {candidate['phylogeny_file']}")

    for row in species_rows:
        row.update(phylogeny_by_species[row["species"]])
    return warnings


def mean(values):
    numeric = [value for value in values if value is not None]
    if not numeric:
        return None
    return sum(numeric) / len(numeric)


def index_mean_by_species(path):
    _, rows = read_table(path)
    values = defaultdict(list)
    for row in rows:
        species = norm(row.get("species"))
        value = parse_float(row.get("index_value"))
        if species and value is not None and norm(row.get("status")) != "ERROR":
            values[species].append(value)
    return {species: format_value(mean(items)) for species, items in values.items()}


def keyed_trait_rows(species_rows):
    return {row["species"]: row for row in species_rows}


def contrast_key(row):
    return (norm(row.get("species")), norm(row.get("contrast_name")), norm(row.get("group_id")))


def build_phenotype_model_rows(index_contrast_path, species_rows, metric, index_means):
    _, rows = read_table(index_contrast_path)
    traits = keyed_trait_rows(species_rows)
    output = []
    warnings = []
    for row in rows:
        species = norm(row.get("species"))
        if not species:
            continue
        if species not in traits:
            warnings.append(f"WARNING\tprepare_phylo_inputs\tContrast species absent from species_traits: {species}")
            continue
        out = dict(traits[species])
        for field in [
            "contrast_name",
            "contrast_type",
            "group_id",
            "baseline_label",
            "response_label",
            "n_baseline",
            "n_response",
            "status",
            "message",
        ]:
            out[field] = norm(row.get(field))
        out["phenotype_index"] = index_means.get(species, "")
        for candidate in sorted(METRICS):
            out[f"phenotype_index_{candidate}"] = norm(row.get(candidate))
        out["phenotype_index_response"] = norm(row.get(metric))
        out["phenotype_index_response_metric"] = metric
        output.append(out)
    return output, warnings


def build_component_pivot(component_contrast_path, metric):
    _, rows = read_table(component_contrast_path)
    by_key = defaultdict(dict)
    for row in rows:
        trait = norm(row.get("trait"))
        if not trait:
            continue
        key = contrast_key(row)
        by_key[key][f"{trait}_response"] = norm(row.get(metric))
        for candidate in sorted(METRICS):
            by_key[key][f"{trait}_{candidate}"] = norm(row.get(candidate))
    return by_key


def hypothesis_variables(profile):
    variables = set()
    for section in ["derived_variables", "external_traits", "covariates", "mechanistic_proxies"]:
        for value in as_list(profile.get(section)):
            if isinstance(value, str) and norm(value):
                variables.add(norm(value))
            elif isinstance(value, dict):
                for field in ["name", "id", "trait", "variable", "covariate"]:
                    if norm(value.get(field)):
                        variables.add(norm(value.get(field)))
    for hypothesis in as_list(profile.get("hypotheses")):
        if not isinstance(hypothesis, dict):
            continue
        for value in [hypothesis.get("response")] + as_list(hypothesis.get("predictors")) + as_list(hypothesis.get("covariates")) + as_list(hypothesis.get("stratify_by")):
            if norm(value):
                variables.add(norm(value))
    return variables


def decompose_component_response(variable, components):
    if variable == "component_response":
        return list(components)
    if not variable.endswith("_response") or variable == "phenotype_index_response":
        return []
    prefix = variable[: -len("_response")]
    if prefix in components:
        return [prefix]
    remaining = prefix
    parts = []
    ordered_components = sorted(components, key=len, reverse=True)
    while remaining:
        match = None
        for component in ordered_components:
            if remaining == component or remaining.startswith(component + "_"):
                match = component
                break
        if match is None:
            return []
        parts.append(match)
        remaining = remaining[len(match) :]
        if remaining.startswith("_"):
            remaining = remaining[1:]
    return parts


def add_composite_component_responses(rows, profile):
    components = profile_components(profile)
    candidates = hypothesis_variables(profile)
    for variable in sorted(candidates):
        parts = decompose_component_response(variable, components)
        if not parts:
            continue
        source_columns = [f"{part}_response" for part in parts]
        for row in rows:
            values = [parse_float(row.get(column)) for column in source_columns]
            if any(value is None for value in values):
                row.setdefault(variable, "")
            else:
                row[variable] = format_value(sum(values) / len(values) if variable == "component_response" else sum(values))


def build_hypothesis_model_rows(phenotype_rows, component_pivot, profile):
    output = []
    for row in phenotype_rows:
        out = dict(row)
        key = contrast_key(row)
        out.update(component_pivot.get(key, {}))
        output.append(out)
    add_composite_component_responses(output, profile)
    return output


def stable_fields(rows, preferred):
    fields = list(preferred)
    seen = set(fields)
    for row in rows:
        for field in row:
            if field not in seen:
                fields.append(field)
                seen.add(field)
    return fields


def parse_args():
    parser = argparse.ArgumentParser(description="Prepare CAME Stage 4 phylogenetic model inputs.")
    parser.add_argument("--species_traits", required=True)
    parser.add_argument("--phylogeny_manifest", required=True)
    parser.add_argument("--phylogeny_base_dir", default="")
    parser.add_argument("--study_profile", required=True)
    parser.add_argument("--phenotype_index_by_group", required=True)
    parser.add_argument("--phenotype_index_contrasts", required=True)
    parser.add_argument("--component_trait_contrasts", required=True)
    parser.add_argument("--species_traits_wide", default="results/phylo/input/species_traits_wide.tsv")
    parser.add_argument("--phenotype_model_table", default="results/phylo/input/phenotype_model_table.tsv")
    parser.add_argument("--hypothesis_model_table", default="results/phylo/input/hypothesis_model_table.tsv")
    return parser.parse_args()


def main():
    args = parse_args()
    warnings = []
    try:
        profile = load_profile(args.study_profile)
        metric = selected_response_metric(profile)
        species_rows, trait_fields, _, trait_warnings = read_species_traits(args.species_traits)
        warnings.extend(trait_warnings)
        warnings.extend(read_phylogeny_manifest(args.phylogeny_manifest, species_rows, args.phylogeny_base_dir))
        index_means = index_mean_by_species(args.phenotype_index_by_group)
        phenotype_rows, phenotype_warnings = build_phenotype_model_rows(
            args.phenotype_index_contrasts,
            species_rows,
            metric,
            index_means,
        )
        warnings.extend(phenotype_warnings)
        component_pivot = build_component_pivot(args.component_trait_contrasts, metric)
        hypothesis_rows = build_hypothesis_model_rows(phenotype_rows, component_pivot, profile)

        species_fields = BASE_TRAIT_FIELDS + PHYLOGENY_FIELDS + [field for field in trait_fields if field not in BASE_TRAIT_FIELDS]
        model_preferred = species_fields + [
            "contrast_name",
            "contrast_type",
            "group_id",
            "baseline_label",
            "response_label",
            "phenotype_index",
            "phenotype_index_response",
            "phenotype_index_response_metric",
            "phenotype_index_difference",
            "phenotype_index_fold_change",
            "phenotype_index_log2_fold_change",
            "n_baseline",
            "n_response",
            "status",
            "message",
        ]
        write_tsv(args.species_traits_wide, stable_fields(species_rows, species_fields), species_rows)
        write_tsv(args.phenotype_model_table, stable_fields(phenotype_rows, model_preferred), phenotype_rows)
        write_tsv(args.hypothesis_model_table, stable_fields(hypothesis_rows, model_preferred), hypothesis_rows)
    except Exception as exc:
        stderr(f"ERROR\tprepare_phylo_inputs\t{exc}")
        return 1

    for warning in warnings:
        stderr(warning)
    print(
        "CAME phylogenetic input summary: "
        f"species={len(species_rows)} phenotype_rows={len(phenotype_rows)} "
        f"hypothesis_rows={len(hypothesis_rows)} warnings={len(warnings)}"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
