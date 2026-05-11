#!/usr/bin/env python3
"""Validate CAME Stage 2 study profiles."""

import argparse
import ast
import csv
import json
import os
import re
import sys
from collections import Counter
from pathlib import Path

try:
    import yaml
except ImportError:
    yaml = None

try:
    import jsonschema
except ImportError:
    jsonschema = None


REQUIRED_TOP = ["study", "phenotype_index", "hypotheses", "reporting"]
REQUIRED_STUDY = ["profile_id", "name", "description", "version"]
REQUIRED_INDEX = ["name", "formula", "components", "aggregation", "contrasts"]
REQUIRED_REPORTING = [
    "phenotype_label",
    "condition_label",
    "response_label",
    "external_trait_label",
    "candidate_mechanism_label",
]
REQUIRED_HYPOTHESIS = ["name", "model_type", "response", "predictors"]
CONTRAST_TYPES = {"baseline_vs_response", "treated_vs_control", "timepoint_contrast", "condition_contrast"}
ALLOWED_FUNCTIONS = {"abs", "min", "max"}
ALLOWED_AST = (
    ast.Expression,
    ast.BinOp,
    ast.UnaryOp,
    ast.Name,
    ast.Load,
    ast.Constant,
    ast.Add,
    ast.Sub,
    ast.Mult,
    ast.Div,
    ast.USub,
    ast.UAdd,
    ast.Call,
)
SAFE_NAME = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*$")
STRICT_PROMOTIONS = {"PROFILE_CONTRAST_LOW_REPLICATES"}


def norm(value):
    return str(value or "").strip()


def report_text(value):
    return " ".join(norm(value).split())


def add(records, severity, source, field, row, message, rule_id="", suggestion=""):
    records.append(
        {
            "severity": severity,
            "rule_id": rule_id or "",
            "source": source,
            "field": field or "",
            "row": str(row or ""),
            "message": report_text(message),
            "suggestion": report_text(suggestion),
        }
    )


def infer_delimiter(path):
    ext = os.path.splitext(path)[1].lower()
    if ext == ".tsv":
        return "\t"
    if ext == ".csv":
        return ","
    with open(path, newline="") as handle:
        sample = handle.read(min(65536, os.path.getsize(path)))
    return "\t" if sample.count("\t") > sample.count(",") else ","


def read_table(path, source, records):
    if not path:
        add(records, "ERROR", source, "", "", "File path was not provided")
        return [], []
    if not os.path.exists(path):
        add(records, "ERROR", source, "", "", f"File does not exist: {path}")
        return [], []
    try:
        with open(path, newline="") as handle:
            reader = csv.DictReader(handle, delimiter=infer_delimiter(path))
            return reader.fieldnames or [], list(reader)
    except Exception as exc:
        add(records, "ERROR", source, "", "", f"Could not read table: {exc}")
        return [], []


def load_yaml(path, records):
    if yaml is None:
        add(records, "ERROR", "study_profile", "", "", "PyYAML is required to read study_profile YAML files")
        return {}
    if not os.path.exists(path):
        add(records, "ERROR", "study_profile", "", "", f"File does not exist: {path}")
        return {}
    try:
        with open(path) as handle:
            data = yaml.safe_load(handle)
    except Exception as exc:
        add(records, "ERROR", "study_profile", "", "", f"Could not read YAML: {exc}")
        return {}
    if not isinstance(data, dict):
        add(records, "ERROR", "study_profile", "", "", "Study profile must be a YAML mapping")
        return {}
    return data


def default_schema_dir():
    return Path(__file__).resolve().parents[1] / "assets" / "schema"


def schema_dir_path(value):
    return Path(value).resolve() if value else default_schema_dir()


def load_schema(schema_dir, filename, records):
    path = schema_dir / filename
    if jsonschema is None:
        add(records, "WARNING", "study_profile", "", "", "jsonschema is unavailable; schema validation was skipped", rule_id="PROFILE_SCHEMA_VALIDATION_UNAVAILABLE", suggestion="Install jsonschema to enable schema validation.")
        return None
    if not path.is_file():
        add(records, "WARNING", "study_profile", "", "", f"Schema file not found: {path}", rule_id="PROFILE_SCHEMA_VALIDATION_UNAVAILABLE", suggestion="Provide --schema_dir pointing to assets/schema.")
        return None
    try:
        with path.open() as handle:
            return json.load(handle)
    except Exception as exc:
        add(records, "WARNING", "study_profile", "", "", f"Could not read schema file {path}: {exc}", rule_id="PROFILE_SCHEMA_VALIDATION_UNAVAILABLE", suggestion="Check that the schema file is valid JSON.")
        return None


def schema_error_field(error):
    return ".".join(str(part) for part in error.path)


def validate_profile_schema(profile, schema_dir, records):
    schema = load_schema(schema_dir, "study_profile.schema.json", records)
    if schema is None or jsonschema is None:
        return False
    validator = jsonschema.Draft202012Validator(schema)
    errors = sorted(validator.iter_errors(profile), key=lambda item: [str(p) for p in item.path])
    for error in errors:
        add(
            records,
            "ERROR",
            "study_profile",
            schema_error_field(error),
            "",
            error.message,
            rule_id="PROFILE_SCHEMA_VIOLATION",
            suggestion="Check study_profile.schema.json for required fields and types.",
        )
    return not errors


def as_list(value):
    if value is None:
        return []
    if isinstance(value, list):
        return value
    return [value]


def profile_indexes(profile):
    indexes = profile.get("phenotype_indexes")
    if indexes is not None:
        if not isinstance(indexes, list):
            return []
        return [index for index in indexes if isinstance(index, dict)]
    index = profile.get("phenotype_index")
    return [index] if isinstance(index, dict) else []


def primary_index(profile):
    indexes = profile_indexes(profile)
    if not indexes:
        return {}
    for index in indexes:
        if index.get("primary") is True:
            return index
    return indexes[0]


def declared_names(profile, section):
    names = set()
    for item in as_list(profile.get(section)):
        if isinstance(item, str):
            if norm(item):
                names.add(norm(item))
        elif isinstance(item, dict):
            for key in ["name", "id", "trait", "variable", "covariate"]:
                if norm(item.get(key)):
                    names.add(norm(item.get(key)))
    return names


def check_required_mapping(mapping, keys, source, records):
    if not isinstance(mapping, dict):
        add(records, "ERROR", source, "", "", "Expected a mapping")
        return
    for key in keys:
        if key not in mapping or norm(mapping.get(key)) == "":
            add(records, "ERROR", source, key, "", "Missing required field")


def normalized_contrasts(value):
    contrasts = value
    if isinstance(contrasts, dict):
        contrasts = [contrasts]
    if not isinstance(contrasts, list):
        return []
    output = []
    for contrast in contrasts:
        if not isinstance(contrast, dict):
            output.append({})
            continue
        output.append({key: norm(contrast.get(key)) for key in sorted(contrast)})
    return output


def normalized_index_definition(index):
    if not isinstance(index, dict):
        return {}
    return {
        "name": norm(index.get("name")),
        "formula": norm(index.get("formula")),
        "components": sorted(norm(item) for item in as_list(index.get("components")) if norm(item)),
        "aggregation": norm(index.get("aggregation")),
        "contrasts": normalized_contrasts(index.get("contrasts")),
        "response_metric": norm(index.get("response_metric")),
    }


def structural_validation(profile, records, skip_schema_covered=False):
    if not skip_schema_covered:
        for section in REQUIRED_TOP:
            if section not in profile:
                add(records, "ERROR", "study_profile", section, "", "Missing required top-level section")
        check_required_mapping(profile.get("study"), REQUIRED_STUDY, "study", records)
        check_required_mapping(profile.get("phenotype_index"), REQUIRED_INDEX, "phenotype_index", records)
        check_required_mapping(profile.get("reporting"), REQUIRED_REPORTING, "reporting", records)

    index = profile.get("phenotype_index") if isinstance(profile.get("phenotype_index"), dict) else {}
    components = index.get("components")
    if not isinstance(components, list) or not components:
        add(records, "ERROR", "phenotype_index", "components", "", "components must be a non-empty array")
    else:
        for item in components:
            if not isinstance(item, str) or not norm(item):
                add(records, "ERROR", "phenotype_index", "components", "", "Each component must be a non-empty string")
    if not isinstance(index.get("formula"), str) or not norm(index.get("formula")):
        add(records, "ERROR", "phenotype_index", "formula", "", "formula must be a non-empty string")

    if "phenotype_indexes" in profile:
        indexes = profile.get("phenotype_indexes")
        if not isinstance(indexes, list) or not indexes:
            add(
                records,
                "ERROR",
                "phenotype_indexes",
                "",
                "",
                "phenotype_indexes must be a non-empty array when present",
                rule_id="PROFILE_INDEXES_EMPTY",
            )
        else:
            names = Counter()
            primary_count = 0
            for idx, index_def in enumerate(indexes, start=1):
                if not isinstance(index_def, dict):
                    add(records, "ERROR", "phenotype_indexes", "", idx, "Each phenotype_indexes item must be a mapping")
                    continue
                check_required_mapping(index_def, REQUIRED_INDEX, "phenotype_indexes", records)
                name = norm(index_def.get("name"))
                if name:
                    names[name] += 1
                if index_def.get("primary") is True:
                    primary_count += 1
            for name, count in sorted(names.items()):
                if count > 1:
                    add(
                        records,
                        "ERROR",
                        "phenotype_indexes",
                        "name",
                        "",
                        f"Duplicate phenotype index name: {name}",
                        rule_id="PROFILE_DUPLICATE_INDEX_NAME",
                    )
            if primary_count > 1:
                add(
                    records,
                    "ERROR",
                    "phenotype_indexes",
                    "primary",
                    "",
                    "Only one phenotype index may set primary: true",
                    rule_id="PROFILE_MULTIPLE_PRIMARY",
                )
            primary = primary_index(profile)
            top_name = norm(index.get("name"))
            primary_name = norm(primary.get("name"))
            if top_name and primary_name and top_name != primary_name:
                add(
                    records,
                    "ERROR",
                    "phenotype_indexes",
                    "name",
                    "",
                    f"Primary phenotype index name '{primary_name}' does not match top-level phenotype_index.name '{top_name}'",
                    rule_id="PROFILE_PRIMARY_INDEX_MISMATCH",
                )
            elif normalized_index_definition(index) != normalized_index_definition(primary):
                add(
                    records,
                    "ERROR",
                    "phenotype_indexes",
                    "phenotype_index",
                    "",
                    "Top-level phenotype_index must duplicate the selected primary phenotype_indexes entry",
                    rule_id="PROFILE_PRIMARY_INDEX_MISMATCH",
                )

    hypotheses = profile.get("hypotheses")
    if not isinstance(hypotheses, list) or not hypotheses:
        add(records, "ERROR", "hypotheses", "", "", "hypotheses must be a non-empty array")
    else:
        for idx, hyp in enumerate(hypotheses, start=1):
            if not isinstance(hyp, dict):
                add(records, "ERROR", "hypotheses", "", idx, "Hypothesis must be a mapping")
                continue
            if not skip_schema_covered:
                check_required_mapping(hyp, REQUIRED_HYPOTHESIS, "hypotheses", records)
            if "predictors" in hyp:
                if not isinstance(hyp.get("predictors"), list) or not hyp.get("predictors"):
                    add(records, "ERROR", "hypotheses", "predictors", idx, "predictors must be a non-empty array")
                elif not all(isinstance(x, str) and norm(x) for x in hyp.get("predictors")):
                    add(records, "ERROR", "hypotheses", "predictors", idx, "predictors must contain non-empty strings")
            if "covariates" in hyp:
                if not isinstance(hyp.get("covariates"), list):
                    add(records, "ERROR", "hypotheses", "covariates", idx, "covariates must be an array")
                elif not all(isinstance(x, str) and norm(x) for x in hyp.get("covariates")):
                    add(records, "ERROR", "hypotheses", "covariates", idx, "covariates must contain strings")
            if "stratify_by" in hyp:
                if not isinstance(hyp.get("stratify_by"), list):
                    add(records, "ERROR", "hypotheses", "stratify_by", idx, "stratify_by must be an array")
                elif not all(isinstance(x, str) and norm(x) for x in hyp.get("stratify_by")):
                    add(records, "ERROR", "hypotheses", "stratify_by", idx, "stratify_by must contain strings")
            if "phylogenetic" in hyp and not isinstance(hyp.get("phylogenetic"), bool):
                add(records, "ERROR", "hypotheses", "phylogenetic", idx, "phylogenetic must be boolean")


def parse_formula(formula, records, source="phenotype_index", field="formula", row=""):
    try:
        tree = ast.parse(formula, mode="eval")
    except SyntaxError as exc:
        add(records, "ERROR", source, field, row, f"Unsupported formula syntax: {exc.msg}")
        return set()
    names = set()
    function_name_nodes = {
        id(node.func)
        for node in ast.walk(tree)
        if isinstance(node, ast.Call) and isinstance(node.func, ast.Name)
    }
    for node in ast.walk(tree):
        if not isinstance(node, ALLOWED_AST):
            add(records, "ERROR", source, field, row, f"Unsafe or unsupported formula element: {type(node).__name__}")
            continue
        if isinstance(node, ast.Call):
            if not isinstance(node.func, ast.Name) or node.func.id not in ALLOWED_FUNCTIONS:
                add(records, "ERROR", source, field, row, "Unsafe or unsupported formula element: Call")
            if node.keywords:
                add(records, "ERROR", source, field, row, "Formula functions do not support keyword arguments")
            if not node.args:
                add(records, "ERROR", source, field, row, "Formula functions require at least one argument")
        if isinstance(node, ast.Name):
            if id(node) in function_name_nodes:
                continue
            if not SAFE_NAME.match(node.id):
                add(records, "ERROR", source, field, row, f"Unsafe variable name: {node.id}")
            names.add(node.id)
        if isinstance(node, ast.Constant) and (isinstance(node.value, bool) or not isinstance(node.value, (int, float))):
            add(records, "ERROR", source, field, row, "Formula constants must be numeric")
    return names


def phenotype_symbols(fields, rows):
    symbols = set(fields)
    for row in rows:
        for column in ["measurement", "assay"]:
            value = norm(row.get(column))
            if value:
                symbols.add(value)
    return symbols


def trait_symbols(fields, rows):
    symbols = set(fields)
    for row in rows:
        for column in ["external_trait", "covariate", "trait", "trait_name"]:
            value = norm(row.get(column))
            if value:
                symbols.add(value)
    return symbols


def formula_validation(profile, pheno_fields, pheno_rows, records):
    available = phenotype_symbols(pheno_fields, pheno_rows)
    for idx, index in enumerate(profile_indexes(profile), start=1):
        formula = norm(index.get("formula"))
        components = set(norm(x) for x in as_list(index.get("components")) if norm(x))
        source = "phenotype_indexes" if "phenotype_indexes" in profile else "phenotype_index"
        row = idx if source == "phenotype_indexes" else ""
        if not formula:
            continue
        names = parse_formula(formula, records, source=source, field="formula", row=row)
        for name in sorted(names - components):
            add(records, "ERROR", source, "formula", row, f"Formula variable is not listed in components: {name}")
        for component in sorted(components):
            if component not in available:
                add(records, "ERROR", "phenotype_samplesheet", "measurement/assay", row, f"Profile component is absent from phenotype metadata for index {norm(index.get('name'))}: {component}")


def contrast_group_specs(contrast):
    ctype = norm(contrast.get("type"))
    empty = ({}, {})
    if ctype == "baseline_vs_response":
        if not all(norm(contrast.get(field)) for field in ["baseline_condition", "baseline_timepoint", "response_condition", "response_timepoint"]):
            return empty
        left = {"condition": norm(contrast.get("baseline_condition")), "timepoint": norm(contrast.get("baseline_timepoint"))}
        right = {"condition": norm(contrast.get("response_condition")), "timepoint": norm(contrast.get("response_timepoint"))}
    elif ctype == "treated_vs_control":
        left_condition = norm(contrast.get("baseline_condition") or contrast.get("control_condition"))
        right_condition = norm(contrast.get("response_condition") or contrast.get("treated_condition"))
        if not left_condition or not right_condition:
            return empty
        if bool(norm(contrast.get("baseline_timepoint"))) != bool(norm(contrast.get("response_timepoint"))):
            return empty
        timepoint = norm(contrast.get("baseline_timepoint"))
        left = {"condition": left_condition, "timepoint": timepoint}
        right = {"condition": right_condition, "timepoint": norm(contrast.get("response_timepoint"))}
    elif ctype == "timepoint_contrast":
        left_timepoint = norm(contrast.get("from_timepoint")) or norm(contrast.get("baseline_timepoint"))
        right_timepoint = norm(contrast.get("to_timepoint")) or norm(contrast.get("response_timepoint"))
        if not left_timepoint:
            return empty
        if not right_timepoint:
            return empty
        if bool(norm(contrast.get("baseline_condition"))) != bool(norm(contrast.get("response_condition"))):
            return empty
        condition = norm(contrast.get("baseline_condition"))
        left = {"condition": condition, "timepoint": left_timepoint}
        right = {"condition": norm(contrast.get("response_condition") or condition), "timepoint": right_timepoint}
    elif ctype == "condition_contrast":
        left_condition = norm(contrast.get("control_condition") or contrast.get("baseline_condition"))
        right_condition = norm(contrast.get("treated_condition") or contrast.get("response_condition"))
        if not left_condition or not right_condition:
            return empty
        if bool(norm(contrast.get("baseline_timepoint"))) != bool(norm(contrast.get("response_timepoint"))):
            return empty
        timepoint = norm(contrast.get("baseline_timepoint"))
        left = {"condition": left_condition, "timepoint": timepoint}
        right = {"condition": right_condition, "timepoint": norm(contrast.get("response_timepoint"))}
    else:
        return empty
    return ({key: value for key, value in left.items() if value}, {key: value for key, value in right.items() if value})


def row_matches_group(row, spec):
    return all(norm(row.get(field)) == value for field, value in spec.items())


def row_component(row, component):
    return norm(row.get("measurement")) == component or norm(row.get("assay")) == component


def contrast_pair_specs(contrast, pheno_rows):
    ctype = norm(contrast.get("type"))
    if ctype == "baseline_vs_response":
        left, right = contrast_group_specs(contrast)
        return None if not left or not right else [(left, right)]
    if ctype in {"treated_vs_control", "condition_contrast"}:
        left, right = contrast_group_specs(contrast)
        if not left or not right:
            return None
        if left.get("timepoint") or right.get("timepoint"):
            return [(left, right)]
        left_condition = left.get("condition")
        right_condition = right.get("condition")
        left_timepoints = {norm(row.get("timepoint")) for row in pheno_rows if norm(row.get("condition")) == left_condition and norm(row.get("timepoint"))}
        right_timepoints = {norm(row.get("timepoint")) for row in pheno_rows if norm(row.get("condition")) == right_condition and norm(row.get("timepoint"))}
        timepoints = sorted(left_timepoints & right_timepoints)
        return [({"condition": left_condition, "timepoint": timepoint}, {"condition": right_condition, "timepoint": timepoint}) for timepoint in timepoints]
    if ctype == "timepoint_contrast":
        left, right = contrast_group_specs(contrast)
        if not left or not right:
            return None
        if left.get("condition") or right.get("condition"):
            return [(left, right)]
        left_timepoint = left.get("timepoint")
        right_timepoint = right.get("timepoint")
        left_conditions = {norm(row.get("condition")) for row in pheno_rows if norm(row.get("timepoint")) == left_timepoint and norm(row.get("condition"))}
        right_conditions = {norm(row.get("condition")) for row in pheno_rows if norm(row.get("timepoint")) == right_timepoint and norm(row.get("condition"))}
        conditions = sorted(left_conditions & right_conditions)
        return [({"condition": condition, "timepoint": left_timepoint}, {"condition": condition, "timepoint": right_timepoint}) for condition in conditions]
    return None


def effective_group_key(profile):
    design = profile.get("phenotype_design")
    if not isinstance(design, dict):
        return ["species", "condition", "timepoint"]
    raw_group_key = design.get("group_key")
    if not isinstance(raw_group_key, list):
        return ["species", "condition", "timepoint"]
    group_key = [norm(field) for field in raw_group_key if norm(field)]
    return group_key or ["species", "condition", "timepoint"]


def paired_strata_present(species_rows, pair_specs, group_key):
    for left_spec, right_spec in pair_specs:
        axis_fields = set(left_spec) | set(right_spec)
        strata_fields = [field for field in group_key if field != "species" and field not in axis_fields]
        left_strata = {
            tuple(norm(row.get(field)) for field in strata_fields)
            for row in species_rows
            if row_matches_group(row, left_spec)
        }
        right_strata = {
            tuple(norm(row.get(field)) for field in strata_fields)
            for row in species_rows
            if row_matches_group(row, right_spec)
        }
        if left_strata & right_strata:
            return True
    return False


def validate_contrast_executability(contrast, idx, components, pheno_rows, records, source="phenotype_index", group_key=None):
    if not components:
        return
    group_key = group_key or ["species", "condition", "timepoint"]
    all_pair_specs = contrast_pair_specs(contrast, pheno_rows)
    if all_pair_specs is None:
        add(
            records,
            "ERROR",
            source,
            "contrasts",
            idx,
            f"Contrast lacks enough condition/timepoint fields to derive two groups: {norm(contrast.get('name'))}",
            rule_id="PROFILE_CONTRAST_INCOMPLETE",
            suggestion="Add the required condition/timepoint fields for this contrast type.",
        )
        return
    broad_left, broad_right = contrast_group_specs(contrast)
    relevant_species = set()
    for row in pheno_rows:
        species = norm(row.get("species"))
        if not species or not any(row_component(row, component) for component in components):
            continue
        if row_matches_group(row, broad_left) or row_matches_group(row, broad_right):
            relevant_species.add(species)
    if not relevant_species:
        add(
            records,
            "ERROR",
            "phenotype_samplesheet",
            "condition/timepoint",
            idx,
            f"Contrast is not executable because no phenotype rows contain profile components: {norm(contrast.get('name'))}",
            rule_id="PROFILE_CONTRAST_NOT_EXECUTABLE",
            suggestion="Add phenotype rows for profile components or remove the contrast.",
        )
        return
    any_executable_pair = False
    for species in sorted(relevant_species):
        species_rows_all = [row for row in pheno_rows if norm(row.get("species")) == species]
        pair_specs = contrast_pair_specs(contrast, species_rows_all)
        if pair_specs is None:
            add(
                records,
                "ERROR",
                source,
                "contrasts",
                idx,
                f"Contrast lacks enough condition/timepoint fields to derive two groups: {norm(contrast.get('name'))}",
                rule_id="PROFILE_CONTRAST_INCOMPLETE",
                suggestion="Add the required condition/timepoint fields for this contrast type.",
            )
            continue
        if not pair_specs or not paired_strata_present(species_rows_all, pair_specs, group_key):
            add(
                records,
                "ERROR",
                "phenotype_samplesheet",
                "condition/timepoint",
                idx,
                f"Contrast is not executable for species {species} because no shared phenotype groups match within configured phenotype_design.group_key strata: {norm(contrast.get('name'))}",
                rule_id="PROFILE_CONTRAST_NOT_EXECUTABLE",
                suggestion="Add phenotype rows for matching baseline/response groups within the same configured group strata or remove the contrast.",
            )
            continue
        for left_spec, right_spec in pair_specs:
            left_rows = [row for row in species_rows_all if row_matches_group(row, left_spec)]
            right_rows = [row for row in species_rows_all if row_matches_group(row, right_spec)]
            group_rows = [("baseline", left_rows), ("response", right_rows)]
            species_pair_complete = True
            for _, rows in group_rows:
                if not rows:
                    species_pair_complete = False
            if species_pair_complete:
                any_executable_pair = True
            for group_name, rows in group_rows:
                if not rows:
                    add(
                        records,
                        "ERROR",
                        "phenotype_samplesheet",
                        "species/condition/timepoint",
                        idx,
                        f"Contrast group {group_name} has no rows for species {species}: {norm(contrast.get('name'))}",
                        rule_id="PROFILE_CONTRAST_NOT_EXECUTABLE",
                        suggestion="Add phenotype rows for the missing group or remove the contrast.",
                    )
                    continue
                for component in sorted(components):
                    component_rows = [row for row in rows if row_component(row, component)]
                    if not component_rows:
                        add(
                            records,
                            "ERROR",
                            "phenotype_samplesheet",
                            "measurement/assay",
                            idx,
                            f"Contrast group {group_name} lacks component {component} for species {species}: {norm(contrast.get('name'))}",
                            rule_id="PROFILE_CONTRAST_COMPONENT_MISSING",
                            suggestion="Add phenotype rows for each profile component in each contrast group.",
                        )
                        continue
                    replicate_pairs = {
                        (norm(row.get("individual_id")), norm(row.get("replicate_id")))
                        for row in component_rows
                        if norm(row.get("individual_id")) or norm(row.get("replicate_id"))
                    }
                    if len(replicate_pairs) < 2:
                        add(
                            records,
                            "WARNING",
                            "phenotype_samplesheet",
                            "individual_id/replicate_id",
                            idx,
                            f"Low replicate coverage for {species}/{group_name}/{component}: {len(replicate_pairs)} replicate pair(s)",
                            rule_id="PROFILE_CONTRAST_LOW_REPLICATES",
                            suggestion="Use at least two distinct individual_id/replicate_id pairs per species, group, and component for strict validation.",
                        )
    if not any_executable_pair:
        add(
            records,
            "ERROR",
            "phenotype_samplesheet",
            "condition/timepoint",
            idx,
            f"Contrast is not executable because no paired phenotype groups match: {norm(contrast.get('name'))}",
            rule_id="PROFILE_CONTRAST_NOT_EXECUTABLE",
            suggestion="Add phenotype rows for matching baseline/response groups or remove the contrast.",
        )


def contrast_validation(profile, pheno_rows, records):
    conditions = {norm(row.get("condition")) for row in pheno_rows if norm(row.get("condition"))}
    timepoints = {norm(row.get("timepoint")) for row in pheno_rows if norm(row.get("timepoint"))}
    source = "phenotype_indexes" if "phenotype_indexes" in profile else "phenotype_index"
    group_key = effective_group_key(profile)
    for index_number, index in enumerate(profile_indexes(profile), start=1):
        components = set(norm(x) for x in as_list(index.get("components")) if norm(x))
        contrasts = index.get("contrasts")
        if isinstance(contrasts, dict):
            contrasts = [contrasts]
        if not isinstance(contrasts, list):
            add(records, "ERROR", source, "contrasts", index_number if source == "phenotype_indexes" else "", "contrasts must be an array or object")
            continue
        if not contrasts:
            add(records, "ERROR", source, "contrasts", index_number if source == "phenotype_indexes" else "", "contrasts must not be empty")
            continue
        for contrast_number, contrast in enumerate(contrasts, start=1):
            row_id = f"{index_number}.{contrast_number}" if source == "phenotype_indexes" else contrast_number
            if not isinstance(contrast, dict):
                add(records, "ERROR", source, "contrasts", row_id, "Contrast must be a mapping")
                continue
            ctype = norm(contrast.get("type"))
            if not norm(contrast.get("name")):
                add(records, "ERROR", source, "contrasts.name", row_id, "Contrast name is required")
            if ctype not in CONTRAST_TYPES:
                add(records, "ERROR", source, "contrasts.type", row_id, f"Unsupported contrast type: {ctype}")
            for field in ["baseline_condition", "response_condition", "control_condition", "treated_condition"]:
                value = norm(contrast.get(field))
                if value and value not in conditions:
                    add(records, "ERROR", "phenotype_samplesheet", field, row_id, f"Contrast condition not found in phenotype metadata: {value}")
            for field in ["baseline_timepoint", "response_timepoint", "from_timepoint", "to_timepoint"]:
                value = norm(contrast.get(field))
                if value and value not in timepoints:
                    add(records, "ERROR", "phenotype_samplesheet", field, row_id, f"Contrast timepoint not found in phenotype metadata: {value}")
            if ctype in CONTRAST_TYPES:
                validate_contrast_executability(contrast, row_id, components, pheno_rows, records, source=source, group_key=group_key)


def hypothesis_validation(profile, pheno_fields, pheno_rows, trait_fields, trait_rows, records):
    allowed = set()
    allowed |= phenotype_symbols(pheno_fields, pheno_rows)
    allowed |= trait_symbols(trait_fields, trait_rows)
    for index in profile_indexes(profile):
        allowed |= set(norm(x) for x in as_list(index.get("components")) if norm(x))
        if norm(index.get("name")):
            allowed.add(norm(index.get("name")))
    for section in ["derived_variables", "external_traits", "covariates", "mechanistic_proxies", "feature_association_targets"]:
        allowed |= declared_names(profile, section)

    for idx, hyp in enumerate(as_list(profile.get("hypotheses")), start=1):
        if not isinstance(hyp, dict):
            continue
        variables = []
        if norm(hyp.get("response")):
            variables.append(("response", norm(hyp.get("response"))))
        for value in as_list(hyp.get("predictors")):
            if norm(value):
                variables.append(("predictors", norm(value)))
        for value in as_list(hyp.get("covariates")):
            if norm(value):
                variables.append(("covariates", norm(value)))
        for value in as_list(hyp.get("stratify_by")):
            if norm(value):
                variables.append(("stratify_by", norm(value)))
        for field, variable in variables:
            if variable not in allowed:
                add(records, "ERROR", "hypotheses", field, idx, f"Variable is not resolvable or declared as derived: {variable}")


def _contrast_required_axes(contrast):
    ctype = norm(contrast.get("type"))
    if ctype == "baseline_vs_response":
        return ["condition", "timepoint"]
    if ctype in {"treated_vs_control", "condition_contrast"}:
        axes = ["condition"]
        if norm(contrast.get("baseline_timepoint")) or norm(contrast.get("response_timepoint")):
            axes.append("timepoint")
        return axes
    if ctype == "timepoint_contrast":
        axes = ["timepoint"]
        if norm(contrast.get("baseline_condition")) or norm(contrast.get("response_condition")):
            axes.append("condition")
        return axes
    return []


def design_validation(profile, pheno_fields, records):
    if "phenotype_design" not in profile:
        return
    design = profile.get("phenotype_design")
    if not isinstance(design, dict):
        add(
            records,
            "ERROR",
            "phenotype_design",
            "",
            "",
            "phenotype_design must be a mapping",
            rule_id="PROFILE_DESIGN_INVALID_SECTION",
        )
        return

    allowed_keys = {"replicate_key", "group_key", "normalization_scope"}
    for key in sorted(design):
        if key not in allowed_keys:
            add(
                records,
                "ERROR",
                "phenotype_design",
                key,
                "",
                f"Unsupported phenotype_design key: {key}",
                rule_id="PROFILE_DESIGN_UNKNOWN_KEY",
                suggestion="Use only replicate_key, group_key, and normalization_scope in phenotype_design.",
            )

    field_set = {norm(field) for field in pheno_fields}
    design_values = {}
    for key_name in ["replicate_key", "group_key", "normalization_scope"]:
        if key_name not in design:
            continue
        raw_values = design.get(key_name)
        if not isinstance(raw_values, list):
            add(
                records,
                "ERROR",
                "phenotype_design",
                key_name,
                "",
                f"{key_name} must be a non-empty list",
                rule_id="PROFILE_DESIGN_EMPTY_KEY",
            )
            continue
        values = [norm(value) for value in raw_values]
        design_values[key_name] = values
        if not values or any(not value for value in values):
            add(
                records,
                "ERROR",
                "phenotype_design",
                key_name,
                "",
                f"{key_name} must contain non-empty field names",
                rule_id="PROFILE_DESIGN_EMPTY_KEY",
            )
        duplicates = sorted({value for value in values if value and values.count(value) > 1})
        for duplicate in duplicates:
            add(
                records,
                "ERROR",
                "phenotype_design",
                key_name,
                "",
                f"{key_name} contains duplicate field: {duplicate}",
                rule_id="PROFILE_DESIGN_DUPLICATE_FIELD",
            )
        for col in values:
            if col and col not in field_set:
                add(
                    records,
                    "ERROR",
                    "phenotype_design",
                    key_name,
                    "",
                    f"Configured {key_name} field is absent from phenotype samplesheet columns: {col}",
                    rule_id="PROFILE_DESIGN_UNKNOWN_FIELD",
                    suggestion=f"Add '{col}' as a column to the phenotype samplesheet or correct the {key_name} list.",
                )

        if key_name == "group_key" and "species" not in set(values):
            add(
                records,
                "ERROR",
                "phenotype_design",
                key_name,
                "",
                "group_key must include species",
                rule_id="PROFILE_DESIGN_MISSING_GROUP_FIELD",
                suggestion="Include species in phenotype_design.group_key.",
            )

    replicate_values = design_values.get("replicate_key", ["species", "individual_id", "replicate_id", "condition", "timepoint"])
    group_values = design_values.get("group_key", ["species", "condition", "timepoint"])
    if replicate_values and group_values:
        missing = sorted(set(group_values) - set(replicate_values))
        for field in missing:
            add(
                records,
                "ERROR",
                "phenotype_design",
                "replicate_key",
                "",
                f"replicate_key must include group_key field: {field}",
                rule_id="PROFILE_DESIGN_MISSING_GROUP_FIELD",
                suggestion="Include every phenotype_design.group_key field in phenotype_design.replicate_key.",
            )

    group_key_set = set(group_values)
    for index in profile_indexes(profile):
        contrasts = index.get("contrasts")
        if isinstance(contrasts, dict):
            contrasts = [contrasts]
        if not isinstance(contrasts, list):
            continue
        for contrast in contrasts:
            if not isinstance(contrast, dict):
                continue
            required_axes = _contrast_required_axes(contrast)
            missing_axes = sorted(f for f in required_axes if f not in group_key_set)
            if missing_axes:
                add(
                    records,
                    "ERROR",
                    "phenotype_design",
                    "group_key",
                    "",
                    f"Contrast '{norm(contrast.get('name'))}' (type={norm(contrast.get('type'))}) requires group_key field(s): {','.join(missing_axes)}",
                    rule_id="PROFILE_DESIGN_MISSING_CONTRAST_AXIS",
                    suggestion=f"Add {','.join(missing_axes)} to phenotype_design.group_key, or change the contrast type.",
                )


def promote_warnings(records, strict, rule_ids):
    if not strict:
        return
    for row in records:
        if row.get("rule_id") in rule_ids and row.get("severity") == "WARNING":
            row["severity"] = "ERROR"


def write_report(path, records):
    os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
    fields = ["severity", "rule_id", "source", "field", "row", "message", "suggestion"]
    with open(path, "w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fields, delimiter="\t", extrasaction="ignore", quoting=csv.QUOTE_NONE, escapechar="\\", lineterminator="\n")
        writer.writeheader()
        writer.writerows(records)


def print_summary(records):
    counts = Counter(row["severity"] for row in records)
    print("CAME study profile validation summary")
    for severity in ["ERROR", "WARNING", "INFO"]:
        print(f"{severity}: {counts.get(severity, 0)}")
    for severity in ["ERROR", "WARNING"]:
        shown = 0
        for row in records:
            if row["severity"] == severity:
                loc = f"{row['source']}:{row['row']}" if row["row"] else row["source"]
                print(f"{severity}\t{loc}\t{row['field']}\t{row['message']}")
                shown += 1
                if shown == 20:
                    remaining = counts[severity] - shown
                    if remaining > 0:
                        print(f"{severity}\t...\t...\t{remaining} more")
                    break


def severity_summary(records):
    counts = Counter(row["severity"] for row in records)
    return {severity: counts.get(severity, 0) for severity in ["ERROR", "WARNING", "INFO"]}


def parse_args():
    parser = argparse.ArgumentParser(description="Validate a CAME Stage 2 study profile.")
    parser.add_argument("--study_profile", required=True)
    parser.add_argument("--phenotype_samplesheet", required=True)
    parser.add_argument("--species_traits", required=True)
    parser.add_argument("--output", default="results/validation/study_profile_validation_report.tsv")
    parser.add_argument("--json_summary", default="")
    parser.add_argument("--schema_dir", default="")
    parser.add_argument("--validation_strict", action="store_true", default=False)
    return parser.parse_args()


def main():
    args = parse_args()
    records = []
    profile = load_yaml(args.study_profile, records)
    pheno_fields, pheno_rows = read_table(args.phenotype_samplesheet, "phenotype_samplesheet", records)
    trait_fields, trait_rows = read_table(args.species_traits, "species_traits", records)
    if profile:
        schema_ok = validate_profile_schema(profile, schema_dir_path(args.schema_dir), records)
        structural_validation(profile, records, skip_schema_covered=schema_ok)
        formula_validation(profile, pheno_fields, pheno_rows, records)
        contrast_validation(profile, pheno_rows, records)
        hypothesis_validation(profile, pheno_fields, pheno_rows, trait_fields, trait_rows, records)
        design_validation(profile, pheno_fields, records)
    add(records, "INFO", "validation", "", "", f"Validated study profile: {args.study_profile}")
    promote_warnings(records, args.validation_strict, STRICT_PROMOTIONS)
    write_report(args.output, records)
    if args.json_summary:
        with open(args.json_summary, "w") as handle:
            json.dump(severity_summary(records), handle, indent=2, sort_keys=True)
    print_summary(records)
    return 1 if any(row["severity"] == "ERROR" for row in records) else 0


if __name__ == "__main__":
    sys.exit(main())
