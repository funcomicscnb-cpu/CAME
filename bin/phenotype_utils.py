#!/usr/bin/env python3
"""Shared helpers for CAME phenotype processing."""

import ast
import csv
import math
import os
import statistics
import sys
from collections import defaultdict

try:
    import yaml
except ImportError:
    yaml = None


MISSING_VALUES = {"", "na", "n/a", "nan", "null", "none", "."}
ALLOWED_FUNCTIONS = {"abs": abs, "min": min, "max": max}
ALLOWED_AGGREGATIONS = {"mean", "median", "sum", "first"}
REPLICATE_KEY = ["species", "individual_id", "replicate_id", "condition", "timepoint"]
GROUP_KEY = ["species", "condition", "timepoint"]


class FormulaError(Exception):
    pass


class FormulaDivisionByZero(FormulaError):
    pass


def norm(value):
    return str(value if value is not None else "").strip()


def normalize_missing(value):
    text = norm(value)
    return "" if text.lower() in MISSING_VALUES else text


def normalize_species_label(value):
    return "_".join(norm(value).split())


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
                cleaned[field] = normalize_missing(row.get(raw_field))
            rows.append(cleaned)
    return fields, rows


def write_tsv(path, fields, rows):
    os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
    with open(path, "w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fields, delimiter="\t", extrasaction="ignore", quoting=csv.QUOTE_NONE, escapechar="\\", lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)


def load_profile(path):
    if yaml is None:
        raise RuntimeError("PyYAML is required to read study_profile YAML files")
    with open(path) as handle:
        data = yaml.safe_load(handle)
    if not isinstance(data, dict):
        raise RuntimeError("Study profile must be a YAML mapping")
    return data


def as_list(value):
    if value is None:
        return []
    if isinstance(value, list):
        return value
    return [value]


def profile_id(profile):
    study = profile.get("study") if isinstance(profile.get("study"), dict) else {}
    return norm(study.get("profile_id"))


def phenotype_index(profile):
    index = profile.get("phenotype_index")
    if not isinstance(index, dict):
        raise RuntimeError("Study profile is missing phenotype_index mapping")
    return index


def profile_components(profile):
    return [norm(item) for item in as_list(phenotype_index(profile).get("components")) if norm(item)]


def profile_contrasts(profile):
    contrasts = phenotype_index(profile).get("contrasts")
    if isinstance(contrasts, dict):
        contrasts = [contrasts]
    if not isinstance(contrasts, list):
        raise RuntimeError("phenotype_index.contrasts must be a list or mapping")
    return contrasts


def normalize_aggregation(value):
    text = norm(value).lower()
    if text in ALLOWED_AGGREGATIONS:
        return text
    for method in ALLOWED_AGGREGATIONS:
        if text.startswith(method + "_"):
            return method
    if not text:
        return "mean"
    raise RuntimeError(f"Unsupported aggregation method: {value}")


def aggregate(values, method):
    numeric = [float(value) for value in values if value is not None]
    if not numeric:
        return None
    if method == "mean":
        return sum(numeric) / len(numeric)
    if method == "median":
        return statistics.median(numeric)
    if method == "sum":
        return sum(numeric)
    if method == "first":
        return numeric[0]
    raise RuntimeError(f"Unsupported aggregation method: {method}")


def parse_float(value):
    text = norm(value)
    if text == "" or text.lower() in MISSING_VALUES:
        return None
    return float(text)


def format_value(value):
    if value is None:
        return "NA"
    if isinstance(value, str):
        return value
    if math.isnan(value) or math.isinf(value):
        return "NA"
    return f"{value:.12g}"


def component_name_for_row(row, components):
    measurement = norm(row.get("measurement"))
    assay = norm(row.get("assay"))
    if measurement in components:
        return measurement
    if assay in components:
        return assay
    return ""


def replicate_id_for_row(row):
    return "|".join(norm(row.get(field)) for field in REPLICATE_KEY)


def group_id_for_row(row):
    return "|".join(norm(row.get(field)) for field in GROUP_KEY)


def validate_formula_tree(formula, components):
    component_set = set(components)
    try:
        tree = ast.parse(formula, mode="eval")
    except SyntaxError as exc:
        raise FormulaError(f"Unsupported formula syntax: {exc.msg}") from exc

    names = set()
    function_name_nodes = {
        id(node.func)
        for node in ast.walk(tree)
        if isinstance(node, ast.Call) and isinstance(node.func, ast.Name)
    }
    for node in ast.walk(tree):
        if isinstance(node, ast.Expression):
            continue
        if isinstance(node, ast.BinOp):
            if not isinstance(node.op, (ast.Add, ast.Sub, ast.Mult, ast.Div)):
                raise FormulaError(f"Unsupported formula operator: {type(node.op).__name__}")
            continue
        if isinstance(node, ast.UnaryOp):
            if not isinstance(node.op, (ast.UAdd, ast.USub)):
                raise FormulaError(f"Unsupported formula operator: {type(node.op).__name__}")
            continue
        if isinstance(node, (ast.Add, ast.Sub, ast.Mult, ast.Div, ast.UAdd, ast.USub, ast.Load)):
            continue
        if isinstance(node, ast.Name):
            if id(node) in function_name_nodes:
                continue
            if node.id not in component_set:
                raise FormulaError(f"Formula variable is not listed in components: {node.id}")
            names.add(node.id)
            continue
        if isinstance(node, ast.Constant):
            if isinstance(node.value, bool) or not isinstance(node.value, (int, float)):
                raise FormulaError("Formula constants must be numeric")
            continue
        if isinstance(node, ast.Call):
            if not isinstance(node.func, ast.Name) or node.func.id not in ALLOWED_FUNCTIONS:
                raise FormulaError("Unsupported formula function")
            if node.keywords:
                raise FormulaError("Formula functions do not support keyword arguments")
            if not node.args:
                raise FormulaError("Formula functions require at least one argument")
            continue
        raise FormulaError(f"Unsafe or unsupported formula element: {type(node).__name__}")
    return tree, names


def evaluate_formula_tree(tree, values):
    def eval_node(node):
        if isinstance(node, ast.Expression):
            return eval_node(node.body)
        if isinstance(node, ast.Constant):
            return float(node.value)
        if isinstance(node, ast.Name):
            if node.id not in values:
                raise FormulaError(f"Missing formula value: {node.id}")
            return float(values[node.id])
        if isinstance(node, ast.UnaryOp):
            operand = eval_node(node.operand)
            if isinstance(node.op, ast.UAdd):
                return operand
            if isinstance(node.op, ast.USub):
                return -operand
        if isinstance(node, ast.BinOp):
            left = eval_node(node.left)
            right = eval_node(node.right)
            if isinstance(node.op, ast.Add):
                return left + right
            if isinstance(node.op, ast.Sub):
                return left - right
            if isinstance(node.op, ast.Mult):
                return left * right
            if isinstance(node.op, ast.Div):
                if right == 0:
                    raise FormulaDivisionByZero("Division by zero")
                return left / right
        if isinstance(node, ast.Call):
            func = ALLOWED_FUNCTIONS[node.func.id]
            args = [eval_node(arg) for arg in node.args]
            return float(func(*args))
        raise FormulaError(f"Unsafe or unsupported formula element: {type(node).__name__}")

    return eval_node(tree)


def stderr(message):
    print(message, file=sys.stderr)
