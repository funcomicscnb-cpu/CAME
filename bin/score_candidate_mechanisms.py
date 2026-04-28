#!/usr/bin/env python3
"""Score and rank CAME candidate mechanisms."""

import argparse
import csv
import math
import os
import sys
from collections import Counter, defaultdict


MISSING_VALUES = {"", "na", "n/a", "nan", "null", "none", "."}
DEFAULT_WEIGHTS = {
    "differential_expression": 1.0,
    "differential_accessibility": 1.0,
    "differential_gra_activity": 1.2,
    "phenotype_expression_association": 2.0,
    "phenotype_accessibility_association": 2.0,
    "phenotype_gra_association": 2.5,
    "response_cluster": 0.75,
    "pairwise_species_contrast": 1.0,
    "hypothesis_support": 1.0,
    "gra_membership": 0.5,
}
REQUIRED_EVIDENCE_FIELDS = [
    "candidate_id",
    "candidate_type",
    "evidence_type",
    "contrast_name",
    "species",
    "effect_size",
    "p_value",
    "padj",
    "score_input_value",
    "source_table",
    "evidence_scope",
    "source_evidence_key",
]
SCORED_FIELDS = [
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
    "evidence_weight",
    "propagation_factor",
    "normalized_score",
    "final_score",
    "scoring_rule",
    "duplicate_status",
]
RANKED_FIELDS = [
    "rank",
    "candidate_id",
    "candidate_type",
    "total_score",
    "n_evidence_types",
    "n_contrasts",
    "n_species",
    "top_evidence_type",
    "top_contrast",
    "mean_effect_size",
    "combined_direction",
    "support_summary",
    "linked_gene_orthogroup_id",
    "linked_re_orthogroup_id",
    "linked_gra_id",
]
WARNING_FIELDS = ["severity", "source", "evidence_type", "candidate_id", "message"]


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
    if not path or not os.path.exists(path):
        raise RuntimeError(f"Missing required table: {path}")
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


def warn(warnings, severity, source, evidence_type, candidate_id, message):
    warnings.append(
        {
            "severity": severity,
            "source": source,
            "evidence_type": evidence_type,
            "candidate_id": candidate_id,
            "message": message,
        }
    )


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


def fmt(value):
    if value is None:
        return "NA"
    return f"{value:.12g}"


def require_fields(fields, required, source):
    missing = [field for field in required if field not in fields]
    if missing:
        raise RuntimeError(f"{source} missing required column(s): {', '.join(missing)}")


def truthy(value):
    return norm(value).lower() in {"1", "true", "yes", "y", "enabled", "enable"}


def load_weights(path, warnings):
    weights = dict(DEFAULT_WEIGHTS)
    enabled = {key: True for key in DEFAULT_WEIGHTS}
    if not path or not os.path.exists(path):
        if path:
            warn(warnings, "WARNING", "candidate_scoring_config", "", "", f"Scoring config not found; using defaults: {path}")
        return weights, enabled
    fields, rows = read_table(path)
    require_fields(fields, ["evidence_type", "weight", "enabled"], "candidate_scoring_config")
    for row in rows:
        evidence_type = norm(row.get("evidence_type"))
        if evidence_type not in DEFAULT_WEIGHTS:
            warn(warnings, "WARNING", "candidate_scoring_config", evidence_type, "", "Ignoring unknown evidence_type in scoring config")
            continue
        weight = parse_float(row.get("weight"))
        if weight is None:
            warn(warnings, "WARNING", "candidate_scoring_config", evidence_type, "", "Ignoring non-numeric weight in scoring config")
            continue
        weights[evidence_type] = weight
        enabled[evidence_type] = truthy(row.get("enabled"))
    return weights, enabled


def significance_factor(p_value, padj):
    p = parse_float(p_value)
    q = parse_float(padj)
    if q is not None and q <= 0.05:
        return 2.0
    if p is not None and p <= 0.05:
        return 1.5
    return 1.0


def p_score(row, weight, cap, warnings):
    p_value = parse_float(row.get("p_value"))
    if p_value is not None:
        if p_value <= 0:
            return weight * cap, "p_value<=0 capped"
        return weight * min(-math.log10(p_value), cap), "-log10(p_value)"
    effect = parse_float(row.get("effect_size"))
    fallback = 0.25 * min(abs(effect), 1.0) if effect is not None else 0.0
    warn(warnings, "WARNING", row.get("source_table"), row.get("evidence_type"), row.get("candidate_id"), "Missing p_value; used small effect-size fallback")
    return weight * fallback, "missing p_value effect fallback"


def raw_score(row, weight, cap, warnings):
    evidence_type = norm(row.get("evidence_type"))
    if evidence_type in {"phenotype_expression_association", "phenotype_accessibility_association", "phenotype_gra_association", "hypothesis_support"}:
        return p_score(row, weight, cap, warnings)
    if evidence_type in {"differential_expression", "differential_accessibility", "differential_gra_activity"}:
        effect = parse_float(row.get("effect_size"))
        factor = significance_factor(row.get("p_value"), row.get("padj"))
        return weight * abs(effect or 0.0) * factor, f"abs(effect)*significance_factor({factor:g})"
    if evidence_type == "response_cluster":
        label = norm(row.get("score_input_value"))
        factors = {
            "shared_up": 1.0,
            "shared_down": 1.0,
            "species_specific": 0.75,
            "lineage_or_subset_specific": 0.75,
            "mixed": 0.25,
            "insufficient_data": 0.0,
        }
        factor = factors.get(label, 0.0)
        return weight * factor, f"cluster_label({label or 'missing'})"
    if evidence_type == "pairwise_species_contrast":
        label = norm(row.get("score_input_value"))
        factors = {"same": 1.0, "opposite": 0.25, "zero_or_missing": 0.0}
        factor = factors.get(label, 0.0)
        return weight * factor, f"direction_match({label or 'missing'})"
    if evidence_type == "gra_membership":
        return weight, "membership"
    return 0.0, "unsupported evidence_type"


def propagation_factor(row, linked_weight):
    scope = norm(row.get("evidence_scope"))
    if scope.startswith("linked_"):
        return linked_weight
    return 1.0


def dedupe_key(row):
    return tuple(
        norm(row.get(field))
        for field in [
            "candidate_id",
            "candidate_type",
            "evidence_type",
            "source_table",
            "source_evidence_key",
            "evidence_scope",
            "contrast_name",
            "species",
            "linked_gene_orthogroup_id",
            "linked_re_orthogroup_id",
            "linked_gra_id",
            "effect_size",
            "p_value",
            "padj",
            "score_input_value",
        ]
    )


def direction_class(row):
    effect = parse_float(row.get("effect_size"))
    if effect is not None:
        if effect > 0:
            return "positive"
        if effect < 0:
            return "negative"
    direction = norm(row.get("effect_direction")).lower()
    if direction in {"up", "positive", "shared_up"}:
        return "positive"
    if direction in {"down", "negative", "shared_down"}:
        return "negative"
    return ""


def summarize_links(values):
    return ",".join(sorted({norm(value) for value in values if norm(value)}))


def support_summary(counter):
    return ";".join(f"{key}:{counter[key]}" for key in sorted(counter))


def rank_rows(candidate_rows):
    ordered = sorted(candidate_rows, key=lambda row: (-parse_float(row["total_score"]), -int(row["n_evidence_types"]), row["candidate_id"]))
    for idx, row in enumerate(ordered, start=1):
        row["rank"] = str(idx)
    return ordered


def score(args):
    warnings = []
    weights, enabled = load_weights(args.candidate_scoring_config, warnings)
    fields, rows = read_table(args.candidate_evidence_long)
    require_fields(fields, REQUIRED_EVIDENCE_FIELDS, "candidate_evidence_long")

    scored = []
    seen = set()
    summaries = defaultdict(lambda: {
        "score": 0.0,
        "evidence_types": set(),
        "contrasts": set(),
        "species": set(),
        "evidence_scores": defaultdict(float),
        "contrast_scores": defaultdict(float),
        "effects": [],
        "directions": Counter(),
        "support": Counter(),
        "genes": set(),
        "res": set(),
        "gras": set(),
        "type": "",
    })
    for row in rows:
        evidence_type = norm(row.get("evidence_type"))
        candidate_id = norm(row.get("candidate_id"))
        candidate_type = norm(row.get("candidate_type"))
        if evidence_type not in weights:
            warn(warnings, "WARNING", row.get("source_table"), evidence_type, candidate_id, "Unsupported evidence_type skipped")
            continue
        if not enabled.get(evidence_type, True):
            continue
        weight = weights[evidence_type]
        normalized, rule = raw_score(row, weight, args.candidate_score_cap, warnings)
        prop = propagation_factor(row, args.candidate_linked_evidence_weight)
        final = normalized * prop
        key = dedupe_key(row)
        duplicate_status = "counted"
        if key in seen:
            duplicate_status = "duplicate_ignored"
            final = 0.0
        else:
            seen.add(key)

        scored_row = dict(row)
        scored_row.update(
            {
                "evidence_weight": fmt(weight),
                "propagation_factor": fmt(prop),
                "normalized_score": fmt(normalized),
                "final_score": fmt(final),
                "scoring_rule": rule,
                "duplicate_status": duplicate_status,
            }
        )
        scored.append(scored_row)

        if duplicate_status != "counted":
            continue
        summary = summaries[(candidate_type, candidate_id)]
        summary["type"] = candidate_type
        summary["score"] += final
        if final > 0:
            summary["evidence_types"].add(evidence_type)
        if norm(row.get("contrast_name")):
            summary["contrasts"].add(norm(row.get("contrast_name")))
            summary["contrast_scores"][norm(row.get("contrast_name"))] += final
        if norm(row.get("species")):
            summary["species"].add(norm(row.get("species")))
        summary["evidence_scores"][evidence_type] += final
        summary["support"][evidence_type] += 1
        effect = parse_float(row.get("effect_size"))
        if effect is not None:
            summary["effects"].append(effect)
        dclass = direction_class(row)
        if dclass:
            summary["directions"][dclass] += 1
        summary["genes"].add(row.get("linked_gene_orthogroup_id"))
        summary["res"].add(row.get("linked_re_orthogroup_id"))
        summary["gras"].add(row.get("linked_gra_id"))

    ranked = []
    for (candidate_type, candidate_id), data in summaries.items():
        top_evidence_type = ""
        if data["evidence_scores"]:
            top_evidence_type = sorted(data["evidence_scores"].items(), key=lambda item: (-item[1], item[0]))[0][0]
        top_contrast = ""
        if data["contrast_scores"]:
            top_contrast = sorted(data["contrast_scores"].items(), key=lambda item: (-item[1], item[0]))[0][0]
        positives = data["directions"].get("positive", 0)
        negatives = data["directions"].get("negative", 0)
        if positives and negatives:
            combined = "mixed"
        elif positives:
            combined = "up"
        elif negatives:
            combined = "down"
        else:
            combined = "none"
        effects = data["effects"]
        ranked.append(
            {
                "rank": "",
                "candidate_id": candidate_id,
                "candidate_type": candidate_type,
                "total_score": fmt(data["score"]),
                "n_evidence_types": str(len(data["evidence_types"])),
                "n_contrasts": str(len(data["contrasts"])),
                "n_species": str(len(data["species"])),
                "top_evidence_type": top_evidence_type,
                "top_contrast": top_contrast,
                "mean_effect_size": fmt(sum(effects) / len(effects) if effects else None),
                "combined_direction": combined,
                "support_summary": support_summary(data["support"]),
                "linked_gene_orthogroup_id": summarize_links(data["genes"]),
                "linked_re_orthogroup_id": summarize_links(data["res"]),
                "linked_gra_id": summarize_links(data["gras"]),
            }
        )

    all_ranked = rank_rows(ranked)
    by_type = defaultdict(list)
    for row in all_ranked:
        by_type[row["candidate_type"]].append(dict(row))
    genes = rank_rows(by_type.get("gene", []))
    res = rank_rows(by_type.get("regulatory_element", []))
    gras = rank_rows(by_type.get("gra", []))

    os.makedirs(args.output_dir, exist_ok=True)
    write_tsv(os.path.join(args.output_dir, "candidate_genes_ranked.tsv"), RANKED_FIELDS, genes)
    write_tsv(os.path.join(args.output_dir, "candidate_res_ranked.tsv"), RANKED_FIELDS, res)
    write_tsv(os.path.join(args.output_dir, "candidate_gras_ranked.tsv"), RANKED_FIELDS, gras)
    write_tsv(os.path.join(args.output_dir, "candidate_all_ranked.tsv"), RANKED_FIELDS, all_ranked)
    write_tsv(os.path.join(args.output_dir, "candidate_scoring_warnings.tsv"), WARNING_FIELDS, warnings)
    evidence_output = args.scored_evidence_output or os.path.join(os.path.dirname(args.output_dir), "evidence", "candidate_evidence_scored.tsv")
    write_tsv(evidence_output, SCORED_FIELDS, scored)
    print(f"CAME candidate scoring summary: candidates={len(all_ranked)} evidence_rows={len(scored)} warnings={len(warnings)}")
    return 0


def parse_args():
    parser = argparse.ArgumentParser(description="Score CAME Stage 10 candidate mechanisms.")
    parser.add_argument("--candidate_evidence_long", default="results/candidates/evidence/candidate_evidence_long.tsv")
    parser.add_argument("--candidate_scoring_config", default="")
    parser.add_argument("--candidate_linked_evidence_weight", type=float, default=0.5)
    parser.add_argument("--candidate_score_cap", type=float, default=50.0)
    parser.add_argument("--output_dir", default="results/candidates/ranked")
    parser.add_argument("--scored_evidence_output", default="")
    return parser.parse_args()


def main():
    try:
        return score(parse_args())
    except Exception as exc:
        print(f"ERROR\tscore_candidate_mechanisms\t{exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
