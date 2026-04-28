#!/usr/bin/env python3
"""Collect CAME candidate prioritization evidence into one long table."""

import argparse
import csv
import math
import os
import sys
from collections import defaultdict


MISSING_VALUES = {"", "na", "n/a", "nan", "null", "none", "."}
EVIDENCE_FIELDS = [
    "candidate_id",
    "candidate_type",
    "linked_gene_orthogroup_id",
    "linked_re_orthogroup_id",
    "linked_gra_id",
    "feature_layer",
    "evidence_type",
    "contrast_name",
    "species",
    "effect_direction",
    "effect_size",
    "p_value",
    "padj",
    "score_input_value",
    "evidence_status",
    "source_table",
    "evidence_scope",
    "source_feature_id",
    "source_evidence_key",
    "scoring_rule_hint",
]
WARNING_FIELDS = ["severity", "source_table", "evidence_type", "candidate_id", "message"]
MAJOR_EVIDENCE_TYPES = {
    "differential_expression",
    "differential_accessibility",
    "differential_gra_activity",
    "phenotype_expression_association",
    "phenotype_accessibility_association",
    "phenotype_gra_association",
    "response_cluster",
    "pairwise_species_contrast",
    "hypothesis_support",
}


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


def warn(warnings, severity, source_table, evidence_type, message, candidate_id=""):
    warnings.append(
        {
            "severity": severity,
            "source_table": source_table,
            "evidence_type": evidence_type,
            "candidate_id": candidate_id,
            "message": message,
        }
    )


def optional_table(path, source_table, evidence_type, warnings):
    path = norm(path)
    if not path or not os.path.exists(path):
        warn(warnings, "WARNING", source_table, evidence_type, f"Missing optional evidence layer: {path or source_table}")
        return [], []
    try:
        return read_table(path)
    except Exception as exc:
        warn(warnings, "WARNING", source_table, evidence_type, f"Could not read evidence layer: {exc}")
        return [], []


def require_fields(fields, required, source_table, evidence_type, warnings):
    missing = [field for field in required if field not in fields]
    if missing:
        warn(warnings, "WARNING", source_table, evidence_type, f"Skipping table with missing required column(s): {', '.join(missing)}")
        return False
    return True


def parse_float(value):
    text = norm(value)
    if not text:
        return None
    try:
        parsed = float(text)
    except ValueError:
        return None
    if math.isnan(parsed) or math.isinf(parsed):
        return None
    return parsed


def direction(value):
    parsed = parse_float(value)
    if parsed is None:
        return ""
    if parsed > 0:
        return "up"
    if parsed < 0:
        return "down"
    return "none"


def key_from(source_table, row, fields):
    return source_table + "|" + "|".join(f"{field}={norm(row.get(field))}" for field in fields)


def edge(gra_id="", gene_id="", re_id=""):
    return {
        "linked_gra_id": norm(gra_id),
        "linked_gene_orthogroup_id": norm(gene_id),
        "linked_re_orthogroup_id": norm(re_id),
    }


def build_links(args, warnings):
    fields, rows = optional_table(args.gra_re_membership, "gra_re_membership", "gra_membership", warnings)
    by_gene = defaultdict(list)
    by_re = defaultdict(list)
    by_gra = defaultdict(list)
    all_edges = []
    if not fields:
        return by_gene, by_re, by_gra, all_edges
    if not require_fields(fields, ["gra_id", "gene_orthogroup_id", "re_orthogroup_id"], "gra_re_membership", "gra_membership", warnings):
        return by_gene, by_re, by_gra, all_edges
    seen = set()
    for row in rows:
        item = edge(row.get("gra_id"), row.get("gene_orthogroup_id"), row.get("re_orthogroup_id"))
        if not item["linked_gra_id"] or not item["linked_gene_orthogroup_id"] or not item["linked_re_orthogroup_id"]:
            continue
        key = (item["linked_gra_id"], item["linked_gene_orthogroup_id"], item["linked_re_orthogroup_id"], norm(row.get("link_type")))
        if key in seen:
            continue
        seen.add(key)
        all_edges.append(item)
        by_gene[item["linked_gene_orthogroup_id"]].append(item)
        by_re[item["linked_re_orthogroup_id"]].append(item)
        by_gra[item["linked_gra_id"]].append(item)
    return by_gene, by_re, by_gra, all_edges


def add_evidence(rows, candidate_id, candidate_type, link, feature_layer, evidence_type, row, source_table,
                 evidence_scope, source_feature_id, source_evidence_key, scoring_rule_hint,
                 contrast_name="", species="", effect_size="", p_value="", padj="", score_input_value="",
                 evidence_status="", effect_direction=""):
    if not norm(candidate_id):
        return
    rows.append(
        {
            "candidate_id": norm(candidate_id),
            "candidate_type": candidate_type,
            "linked_gene_orthogroup_id": norm(link.get("linked_gene_orthogroup_id")),
            "linked_re_orthogroup_id": norm(link.get("linked_re_orthogroup_id")),
            "linked_gra_id": norm(link.get("linked_gra_id")),
            "feature_layer": feature_layer,
            "evidence_type": evidence_type,
            "contrast_name": norm(contrast_name or row.get("contrast_name")),
            "species": norm(species or row.get("species")),
            "effect_direction": norm(effect_direction) or direction(effect_size),
            "effect_size": norm(effect_size),
            "p_value": norm(p_value),
            "padj": norm(padj),
            "score_input_value": norm(score_input_value if score_input_value != "" else effect_size),
            "evidence_status": norm(evidence_status or row.get("status")),
            "source_table": source_table,
            "evidence_scope": evidence_scope,
            "source_feature_id": norm(source_feature_id),
            "source_evidence_key": source_evidence_key,
            "scoring_rule_hint": scoring_rule_hint,
        }
    )


def add_gene_evidence(rows, gene_id, feature_layer, evidence_type, row, source_table, source_key, links_by_gene,
                      scoring_rule_hint, effect_size="", p_value="", padj="", score_input_value="",
                      evidence_status="", effect_direction="", species=""):
    direct = edge(gene_id=gene_id)
    add_evidence(
        rows, gene_id, "gene", direct, feature_layer, evidence_type, row, source_table,
        "direct", gene_id, source_key, scoring_rule_hint, effect_size=effect_size,
        p_value=p_value, padj=padj, score_input_value=score_input_value,
        evidence_status=evidence_status, effect_direction=effect_direction, species=species
    )
    for item in links_by_gene.get(gene_id, []):
        add_evidence(
            rows, item["linked_re_orthogroup_id"], "regulatory_element", item, feature_layer, evidence_type,
            row, source_table, "linked_gene", gene_id, source_key, scoring_rule_hint,
            effect_size=effect_size, p_value=p_value, padj=padj, score_input_value=score_input_value,
            evidence_status=evidence_status, effect_direction=effect_direction, species=species
        )
        add_evidence(
            rows, item["linked_gra_id"], "gra", item, feature_layer, evidence_type,
            row, source_table, "linked_gene", gene_id, source_key, scoring_rule_hint,
            effect_size=effect_size, p_value=p_value, padj=padj, score_input_value=score_input_value,
            evidence_status=evidence_status, effect_direction=effect_direction, species=species
        )


def add_re_evidence(rows, re_id, feature_layer, evidence_type, row, source_table, source_key, links_by_re,
                    scoring_rule_hint, effect_size="", p_value="", padj="", score_input_value="",
                    evidence_status="", effect_direction="", species=""):
    direct = edge(re_id=re_id)
    add_evidence(
        rows, re_id, "regulatory_element", direct, feature_layer, evidence_type, row, source_table,
        "direct", re_id, source_key, scoring_rule_hint, effect_size=effect_size,
        p_value=p_value, padj=padj, score_input_value=score_input_value,
        evidence_status=evidence_status, effect_direction=effect_direction, species=species
    )
    for item in links_by_re.get(re_id, []):
        add_evidence(
            rows, item["linked_gene_orthogroup_id"], "gene", item, feature_layer, evidence_type,
            row, source_table, "linked_re", re_id, source_key, scoring_rule_hint,
            effect_size=effect_size, p_value=p_value, padj=padj, score_input_value=score_input_value,
            evidence_status=evidence_status, effect_direction=effect_direction, species=species
        )
        add_evidence(
            rows, item["linked_gra_id"], "gra", item, feature_layer, evidence_type,
            row, source_table, "linked_re", re_id, source_key, scoring_rule_hint,
            effect_size=effect_size, p_value=p_value, padj=padj, score_input_value=score_input_value,
            evidence_status=evidence_status, effect_direction=effect_direction, species=species
        )


def add_gra_evidence(rows, gra_id, gene_id, feature_layer, evidence_type, row, source_table, source_key,
                     links_by_gra, scoring_rule_hint, effect_size="", p_value="", padj="",
                     score_input_value="", evidence_status="", effect_direction="", species=""):
    direct = edge(gra_id=gra_id, gene_id=gene_id)
    add_evidence(
        rows, gra_id, "gra", direct, feature_layer, evidence_type, row, source_table,
        "direct", gra_id, source_key, scoring_rule_hint, effect_size=effect_size,
        p_value=p_value, padj=padj, score_input_value=score_input_value,
        evidence_status=evidence_status, effect_direction=effect_direction, species=species
    )
    linked = links_by_gra.get(gra_id, [])
    if not linked and gene_id:
        linked = [edge(gra_id=gra_id, gene_id=gene_id)]
    for item in linked:
        add_evidence(
            rows, item["linked_gene_orthogroup_id"], "gene", item, feature_layer, evidence_type,
            row, source_table, "linked_gra", gra_id, source_key, scoring_rule_hint,
            effect_size=effect_size, p_value=p_value, padj=padj, score_input_value=score_input_value,
            evidence_status=evidence_status, effect_direction=effect_direction, species=species
        )
        if item["linked_re_orthogroup_id"]:
            add_evidence(
                rows, item["linked_re_orthogroup_id"], "regulatory_element", item, feature_layer, evidence_type,
                row, source_table, "linked_gra", gra_id, source_key, scoring_rule_hint,
                effect_size=effect_size, p_value=p_value, padj=padj, score_input_value=score_input_value,
                evidence_status=evidence_status, effect_direction=effect_direction, species=species
            )


def collect_differential(args, rows, warnings, links_by_gene, links_by_re, links_by_gra):
    configs = [
        (args.differential_expression, "differential_expression_orthogroups", "differential_expression", "expression", "gene"),
        (args.differential_accessibility, "differential_accessibility_orthogroups", "differential_accessibility", "accessibility", "regulatory_element"),
    ]
    required = ["orthogroup_id", "contrast_name", "log2_fold_change"]
    for path, source_table, evidence_type, layer, candidate_type in configs:
        fields, table_rows = optional_table(path, source_table, evidence_type, warnings)
        if not fields or not require_fields(fields, required, source_table, evidence_type, warnings):
            continue
        for item in table_rows:
            feature_id = norm(item.get("orthogroup_id"))
            source_key = key_from(source_table, item, ["orthogroup_id", "species", "contrast_name", "log2_fold_change", "p_value", "padj"])
            kwargs = {
                "effect_size": item.get("log2_fold_change"),
                "p_value": item.get("p_value"),
                "padj": item.get("padj"),
                "score_input_value": item.get("log2_fold_change"),
                "evidence_status": item.get("status"),
            }
            if candidate_type == "gene":
                add_gene_evidence(rows, feature_id, layer, evidence_type, item, source_table, source_key, links_by_gene, "differential", **kwargs)
            else:
                add_re_evidence(rows, feature_id, layer, evidence_type, item, source_table, source_key, links_by_re, "differential", **kwargs)

    fields, table_rows = optional_table(args.differential_gra_activity, "differential_gra_activity", "differential_gra_activity", warnings)
    if fields and require_fields(fields, ["gra_id", "contrast_name", "log2_fold_change"], "differential_gra_activity", "differential_gra_activity", warnings):
        for item in table_rows:
            gra_id = norm(item.get("gra_id"))
            source_key = key_from("differential_gra_activity", item, ["gra_id", "gene_orthogroup_id", "species", "contrast_name", "log2_fold_change", "p_value", "padj"])
            add_gra_evidence(
                rows, gra_id, item.get("gene_orthogroup_id"), "gra_activity", "differential_gra_activity",
                item, "differential_gra_activity", source_key, links_by_gra, "differential",
                effect_size=item.get("log2_fold_change"), p_value=item.get("p_value"), padj=item.get("padj"),
                score_input_value=item.get("log2_fold_change"), evidence_status=item.get("status")
            )


def collect_associations(args, rows, warnings, links_by_gene, links_by_re, links_by_gra):
    configs = [
        (args.phenotype_expression_associations, "phenotype_expression_associations", "phenotype_expression_association", "expression", "gene"),
        (args.phenotype_accessibility_associations, "phenotype_accessibility_associations", "phenotype_accessibility_association", "accessibility", "regulatory_element"),
        (args.phenotype_gra_associations, "phenotype_gra_associations", "phenotype_gra_association", "gra_activity", "gra"),
    ]
    for path, source_table, evidence_type, layer, candidate_type in configs:
        fields, table_rows = optional_table(path, source_table, evidence_type, warnings)
        if not fields or not require_fields(fields, ["feature_id", "contrast_name", "estimate"], source_table, evidence_type, warnings):
            continue
        for item in table_rows:
            feature_id = norm(item.get("feature_id"))
            source_key = key_from(source_table, item, ["feature_id", "contrast_name", "phenotype_response_id", "model_type", "estimate", "p_value", "status"])
            kwargs = {
                "effect_size": item.get("estimate"),
                "p_value": item.get("p_value"),
                "padj": item.get("padj"),
                "score_input_value": item.get("p_value"),
                "evidence_status": item.get("status"),
            }
            if candidate_type == "gene":
                add_gene_evidence(rows, feature_id, layer, evidence_type, item, source_table, source_key, links_by_gene, "association", **kwargs)
            elif candidate_type == "regulatory_element":
                add_re_evidence(rows, feature_id, layer, evidence_type, item, source_table, source_key, links_by_re, "association", **kwargs)
            else:
                add_gra_evidence(rows, feature_id, "", layer, evidence_type, item, source_table, source_key, links_by_gra, "association", **kwargs)


def collect_clusters(args, rows, warnings, links_by_gene, links_by_re, links_by_gra):
    configs = [
        (args.response_clusters_expression, "response_clusters_expression", "expression", "gene"),
        (args.response_clusters_accessibility, "response_clusters_accessibility", "accessibility", "regulatory_element"),
        (args.response_clusters_gra_activity, "response_clusters_gra_activity", "gra_activity", "gra"),
    ]
    for path, source_table, layer, candidate_type in configs:
        fields, table_rows = optional_table(path, source_table, "response_cluster", warnings)
        if not fields or not require_fields(fields, ["feature_id", "contrast_name", "cluster_label"], source_table, "response_cluster", warnings):
            continue
        for item in table_rows:
            feature_id = norm(item.get("feature_id"))
            source_key = key_from(source_table, item, ["feature_id", "contrast_name", "cluster_label", "species_pattern"])
            label = norm(item.get("cluster_label"))
            kwargs = {
                "effect_size": item.get("mean_response"),
                "score_input_value": label,
                "evidence_status": "OK" if label != "insufficient_data" else "WARNING",
                "effect_direction": item.get("response_direction"),
            }
            if candidate_type == "gene":
                add_gene_evidence(rows, feature_id, layer, "response_cluster", item, source_table, source_key, links_by_gene, "cluster", **kwargs)
            elif candidate_type == "regulatory_element":
                add_re_evidence(rows, feature_id, layer, "response_cluster", item, source_table, source_key, links_by_re, "cluster", **kwargs)
            else:
                add_gra_evidence(rows, feature_id, "", layer, "response_cluster", item, source_table, source_key, links_by_gra, "cluster", **kwargs)


def collect_pairwise(args, rows, warnings, links_by_gene, links_by_re, links_by_gra):
    fields, table_rows = optional_table(args.pairwise_species_molecular_contrasts, "pairwise_species_molecular_contrasts", "pairwise_species_contrast", warnings)
    if not fields or not require_fields(fields, ["feature_layer", "feature_id", "contrast_name", "direction_match"], "pairwise_species_molecular_contrasts", "pairwise_species_contrast", warnings):
        return
    for item in table_rows:
        layer = norm(item.get("feature_layer"))
        feature_id = norm(item.get("feature_id"))
        source_key = key_from("pairwise_species_molecular_contrasts", item, ["species_a", "species_b", "feature_layer", "feature_id", "contrast_name", "direction_match", "delta_feature_response"])
        pair_species = ",".join(x for x in [norm(item.get("species_a")), norm(item.get("species_b"))] if x)
        kwargs = {
            "effect_size": item.get("delta_feature_response"),
            "score_input_value": item.get("direction_match"),
            "evidence_status": item.get("status"),
            "species": pair_species,
        }
        if layer == "expression":
            add_gene_evidence(rows, feature_id, layer, "pairwise_species_contrast", item, "pairwise_species_molecular_contrasts", source_key, links_by_gene, "pairwise", **kwargs)
        elif layer == "accessibility":
            add_re_evidence(rows, feature_id, layer, "pairwise_species_contrast", item, "pairwise_species_molecular_contrasts", source_key, links_by_re, "pairwise", **kwargs)
        elif layer == "gra_activity":
            add_gra_evidence(rows, feature_id, "", layer, "pairwise_species_contrast", item, "pairwise_species_molecular_contrasts", source_key, links_by_gra, "pairwise", **kwargs)


def collect_membership(rows, all_edges):
    for item in all_edges:
        source_key = "gra_re_membership|" + "|".join([item["linked_gra_id"], item["linked_gene_orthogroup_id"], item["linked_re_orthogroup_id"]])
        stub = {}
        for candidate_id, candidate_type in [
            (item["linked_gene_orthogroup_id"], "gene"),
            (item["linked_re_orthogroup_id"], "regulatory_element"),
            (item["linked_gra_id"], "gra"),
        ]:
            add_evidence(
                rows, candidate_id, candidate_type, item, "gra_membership", "gra_membership",
                stub, "gra_re_membership", "direct_membership", item["linked_gra_id"], source_key,
                "membership", effect_size="1", score_input_value="membership", evidence_status="OK",
                effect_direction="none"
            )


def hypothesis_candidate(row):
    candidate_type = norm(row.get("candidate_type"))
    candidate_id = norm(row.get("candidate_id"))
    gene_id = norm(row.get("gene_orthogroup_id"))
    re_id = norm(row.get("re_orthogroup_id"))
    gra_id = norm(row.get("gra_id"))
    layer = norm(row.get("feature_layer"))
    feature_id = norm(row.get("feature_id"))
    orthogroup_id = norm(row.get("orthogroup_id"))
    if candidate_type and candidate_id:
        return candidate_type, candidate_id, gene_id, re_id, gra_id
    if gene_id:
        return "gene", gene_id, gene_id, re_id, gra_id
    if re_id:
        return "regulatory_element", re_id, gene_id, re_id, gra_id
    if gra_id:
        return "gra", gra_id, gene_id, re_id, gra_id
    if layer == "expression" and feature_id:
        return "gene", feature_id, feature_id, re_id, gra_id
    if layer == "accessibility" and feature_id:
        return "regulatory_element", feature_id, gene_id, feature_id, gra_id
    if layer == "gra_activity" and feature_id:
        return "gra", feature_id, gene_id, re_id, feature_id
    if orthogroup_id:
        return "gene", orthogroup_id, orthogroup_id, re_id, gra_id
    return "", "", "", "", ""


def collect_hypothesis(args, rows, warnings):
    fields, table_rows = optional_table(args.hypothesis_model_results, "hypothesis_model_results", "hypothesis_support", warnings)
    if not fields:
        return
    candidate_rows = 0
    for item in table_rows:
        candidate_type, candidate_id, gene_id, re_id, gra_id = hypothesis_candidate(item)
        if not candidate_id:
            continue
        candidate_rows += 1
        source_key = key_from("hypothesis_model_results", item, ["candidate_id", "candidate_type", "feature_id", "orthogroup_id", "gra_id", "model_id", "model_type", "term", "estimate", "p_value"])
        add_evidence(
            rows, candidate_id, candidate_type, edge(gra_id, gene_id, re_id),
            norm(item.get("feature_layer")) or "hypothesis", "hypothesis_support",
            item, "hypothesis_model_results", "direct", candidate_id, source_key,
            "association", contrast_name=item.get("hypothesis_name"), species=item.get("stratum"),
            effect_size=item.get("estimate"), p_value=item.get("p_value"),
            score_input_value=item.get("p_value"), evidence_status=item.get("status")
        )
    if table_rows and candidate_rows == 0:
        warn(warnings, "WARNING", "hypothesis_model_results", "hypothesis_support", "Hypothesis results are global and lack candidate identifiers; not scored against candidates")


def touch_context_layers(args, warnings):
    optional_table(args.phenotype_index_contrasts, "phenotype_index_contrasts", "phenotype_context", warnings)
    optional_table(args.gene_regulatory_architectures, "gene_regulatory_architectures", "gra_context", warnings)
    optional_table(args.feature_to_orthogroup_map, "feature_to_orthogroup_map", "orthology_context", warnings)


def collect(args):
    warnings = []
    rows = []
    links_by_gene, links_by_re, links_by_gra, all_edges = build_links(args, warnings)
    touch_context_layers(args, warnings)
    collect_membership(rows, all_edges)
    collect_differential(args, rows, warnings, links_by_gene, links_by_re, links_by_gra)
    collect_associations(args, rows, warnings, links_by_gene, links_by_re, links_by_gra)
    collect_clusters(args, rows, warnings, links_by_gene, links_by_re, links_by_gra)
    collect_pairwise(args, rows, warnings, links_by_gene, links_by_re, links_by_gra)
    collect_hypothesis(args, rows, warnings)

    major_count = sum(1 for row in rows if row["evidence_type"] in MAJOR_EVIDENCE_TYPES)
    write_tsv(os.path.join(args.output_dir, "candidate_evidence_long.tsv"), EVIDENCE_FIELDS, rows)
    write_tsv(os.path.join(args.output_dir, "candidate_evidence_warnings.tsv"), WARNING_FIELDS, warnings)
    if major_count == 0:
        raise RuntimeError("No major candidate evidence tables were available or readable; only membership/global context evidence was found")
    print(f"CAME candidate evidence collection summary: rows={len(rows)} major_evidence_rows={major_count} warnings={len(warnings)}")
    return 0


def parse_args():
    parser = argparse.ArgumentParser(description="Collect CAME Stage 10 candidate evidence.")
    parser.add_argument("--phenotype_index_contrasts", default="results/phenotype/contrasts/phenotype_index_contrasts.tsv")
    parser.add_argument("--hypothesis_model_results", default="results/hypotheses/hypothesis_model_results.tsv")
    parser.add_argument("--differential_expression", default="results/orthology/differential_expression_orthogroups.tsv")
    parser.add_argument("--differential_accessibility", default="results/orthology/differential_accessibility_orthogroups.tsv")
    parser.add_argument("--differential_gra_activity", default="results/gra/differential/differential_gra_activity.tsv")
    parser.add_argument("--gene_regulatory_architectures", default="results/gra/tables/gene_regulatory_architectures.tsv")
    parser.add_argument("--gra_re_membership", default="results/gra/tables/gra_re_membership.tsv")
    parser.add_argument("--feature_to_orthogroup_map", default="results/orthology/feature_to_orthogroup_map.tsv")
    parser.add_argument("--phenotype_expression_associations", default="results/integration/associations/phenotype_expression_associations.tsv")
    parser.add_argument("--phenotype_accessibility_associations", default="results/integration/associations/phenotype_accessibility_associations.tsv")
    parser.add_argument("--phenotype_gra_associations", default="results/integration/associations/phenotype_gra_associations.tsv")
    parser.add_argument("--response_clusters_expression", default="results/integration/clustering/response_clusters_expression.tsv")
    parser.add_argument("--response_clusters_accessibility", default="results/integration/clustering/response_clusters_accessibility.tsv")
    parser.add_argument("--response_clusters_gra_activity", default="results/integration/clustering/response_clusters_gra_activity.tsv")
    parser.add_argument("--pairwise_species_molecular_contrasts", default="results/integration/pairwise/pairwise_species_molecular_contrasts.tsv")
    parser.add_argument("--output_dir", default="results/candidates/evidence")
    return parser.parse_args()


def main():
    try:
        return collect(parse_args())
    except Exception as exc:
        print(f"ERROR\tcollect_candidate_evidence\t{exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
