#!/usr/bin/env python3
"""Validate CAME Stage 2 study profiles."""

import argparse
import ast
import csv
import os
import re
import sys
from collections import Counter

try:
    import yaml
except ImportError:
    yaml = None


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


def norm(value):
    return str(value or "").strip()


def add(records, severity, source, field, row, message):
    records.append(
        {
            "severity": severity,
            "source": source,
            "field": field or "",
            "row": str(row or ""),
            "message": message,
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


def as_list(value):
    if value is None:
        return []
    if isinstance(value, list):
        return value
    return [value]


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


def structural_validation(profile, records):
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

    hypotheses = profile.get("hypotheses")
    if not isinstance(hypotheses, list) or not hypotheses:
        add(records, "ERROR", "hypotheses", "", "", "hypotheses must be a non-empty array")
    else:
        for idx, hyp in enumerate(hypotheses, start=1):
            if not isinstance(hyp, dict):
                add(records, "ERROR", "hypotheses", "", idx, "Hypothesis must be a mapping")
                continue
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


def parse_formula(formula, records):
    try:
        tree = ast.parse(formula, mode="eval")
    except SyntaxError as exc:
        add(records, "ERROR", "phenotype_index", "formula", "", f"Unsupported formula syntax: {exc.msg}")
        return set()
    names = set()
    function_name_nodes = {
        id(node.func)
        for node in ast.walk(tree)
        if isinstance(node, ast.Call) and isinstance(node.func, ast.Name)
    }
    for node in ast.walk(tree):
        if not isinstance(node, ALLOWED_AST):
            add(records, "ERROR", "phenotype_index", "formula", "", f"Unsafe or unsupported formula element: {type(node).__name__}")
            continue
        if isinstance(node, ast.Call):
            if not isinstance(node.func, ast.Name) or node.func.id not in ALLOWED_FUNCTIONS:
                add(records, "ERROR", "phenotype_index", "formula", "", "Unsafe or unsupported formula element: Call")
            if node.keywords:
                add(records, "ERROR", "phenotype_index", "formula", "", "Formula functions do not support keyword arguments")
            if not node.args:
                add(records, "ERROR", "phenotype_index", "formula", "", "Formula functions require at least one argument")
        if isinstance(node, ast.Name):
            if id(node) in function_name_nodes:
                continue
            if not SAFE_NAME.match(node.id):
                add(records, "ERROR", "phenotype_index", "formula", "", f"Unsafe variable name: {node.id}")
            names.add(node.id)
        if isinstance(node, ast.Constant) and (isinstance(node.value, bool) or not isinstance(node.value, (int, float))):
            add(records, "ERROR", "phenotype_index", "formula", "", "Formula constants must be numeric")
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
    index = profile.get("phenotype_index") if isinstance(profile.get("phenotype_index"), dict) else {}
    formula = norm(index.get("formula"))
    components = set(norm(x) for x in as_list(index.get("components")) if norm(x))
    if not formula:
        return
    names = parse_formula(formula, records)
    for name in sorted(names - components):
        add(records, "ERROR", "phenotype_index", "formula", "", f"Formula variable is not listed in components: {name}")
    available = phenotype_symbols(pheno_fields, pheno_rows)
    for component in sorted(components):
        if component not in available:
            add(records, "ERROR", "phenotype_samplesheet", "measurement/assay", "", f"Profile component is absent from phenotype metadata: {component}")


def contrast_validation(profile, pheno_rows, records):
    index = profile.get("phenotype_index") if isinstance(profile.get("phenotype_index"), dict) else {}
    contrasts = index.get("contrasts")
    if isinstance(contrasts, dict):
        contrasts = [contrasts]
    if not isinstance(contrasts, list):
        add(records, "ERROR", "phenotype_index", "contrasts", "", "contrasts must be an array or object")
        return
    if not contrasts:
        add(records, "ERROR", "phenotype_index", "contrasts", "", "contrasts must not be empty")
        return
    conditions = {norm(row.get("condition")) for row in pheno_rows if norm(row.get("condition"))}
    timepoints = {norm(row.get("timepoint")) for row in pheno_rows if norm(row.get("timepoint"))}
    for idx, contrast in enumerate(contrasts, start=1):
        if not isinstance(contrast, dict):
            add(records, "ERROR", "phenotype_index", "contrasts", idx, "Contrast must be a mapping")
            continue
        ctype = norm(contrast.get("type"))
        if not norm(contrast.get("name")):
            add(records, "ERROR", "phenotype_index", "contrasts.name", idx, "Contrast name is required")
        if ctype not in CONTRAST_TYPES:
            add(records, "ERROR", "phenotype_index", "contrasts.type", idx, f"Unsupported contrast type: {ctype}")
        for field in ["baseline_condition", "response_condition", "control_condition", "treated_condition"]:
            value = norm(contrast.get(field))
            if value and value not in conditions:
                add(records, "ERROR", "phenotype_samplesheet", field, idx, f"Contrast condition not found in phenotype metadata: {value}")
        for field in ["baseline_timepoint", "response_timepoint", "from_timepoint", "to_timepoint"]:
            value = norm(contrast.get(field))
            if value and value not in timepoints:
                add(records, "ERROR", "phenotype_samplesheet", field, idx, f"Contrast timepoint not found in phenotype metadata: {value}")


def hypothesis_validation(profile, pheno_fields, pheno_rows, trait_fields, trait_rows, records):
    index = profile.get("phenotype_index") if isinstance(profile.get("phenotype_index"), dict) else {}
    allowed = set()
    allowed |= phenotype_symbols(pheno_fields, pheno_rows)
    allowed |= trait_symbols(trait_fields, trait_rows)
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


def write_report(path, records):
    os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
    fields = ["severity", "source", "field", "row", "message"]
    with open(path, "w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fields, delimiter="\t", quoting=csv.QUOTE_NONE, escapechar="\\", lineterminator="\n")
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


def parse_args():
    parser = argparse.ArgumentParser(description="Validate a CAME Stage 2 study profile.")
    parser.add_argument("--study_profile", required=True)
    parser.add_argument("--phenotype_samplesheet", required=True)
    parser.add_argument("--species_traits", required=True)
    parser.add_argument("--output", default="results/validation/study_profile_validation_report.tsv")
    return parser.parse_args()


def main():
    args = parse_args()
    records = []
    profile = load_yaml(args.study_profile, records)
    pheno_fields, pheno_rows = read_table(args.phenotype_samplesheet, "phenotype_samplesheet", records)
    trait_fields, trait_rows = read_table(args.species_traits, "species_traits", records)
    if profile:
        structural_validation(profile, records)
        formula_validation(profile, pheno_fields, pheno_rows, records)
        contrast_validation(profile, pheno_rows, records)
        hypothesis_validation(profile, pheno_fields, pheno_rows, trait_fields, trait_rows, records)
    add(records, "INFO", "validation", "", "", f"Validated study profile: {args.study_profile}")
    write_report(args.output, records)
    print_summary(records)
    return 1 if any(row["severity"] == "ERROR" for row in records) else 0


if __name__ == "__main__":
    sys.exit(main())
