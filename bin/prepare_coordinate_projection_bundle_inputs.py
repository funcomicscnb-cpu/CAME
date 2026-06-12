#!/usr/bin/env python3
"""Convert an orthology reference bundle manifest into coordinate-projection inputs."""

from __future__ import annotations

import argparse
import csv
import os
import re
import shutil
import sys
from collections import defaultdict
from pathlib import Path


MISSING_VALUES = {"", "na", "n/a", "nan", "null", "none", "."}
RESERVED_ID_DELIMITERS = ("::", "@@")
ALIGNMENT_FIELDS = [
    "source_species",
    "target_species",
    "alignment_id",
    "chain_file",
    "maf_file",
    "net_file",
    "alignment_type",
    "source",
    "notes",
]
CONFIG_FIELDS = ["projection_id", "source_species", "target_species", "method", "notes"]
SELECTOR_FIELDS = ["slot", "has_asset", "path"]


def norm(value: object) -> str:
    text = str(value if value is not None else "").strip()
    return "" if text.lower() in MISSING_VALUES else text


def lower_norm(value: object) -> str:
    return norm(value).lower()


def infer_delimiter(path: Path) -> str:
    if path.suffix.lower() == ".csv":
        return ","
    if path.suffix.lower() == ".tsv":
        return "\t"
    with path.open(newline="") as handle:
        sample = handle.read(min(65536, path.stat().st_size))
    return "\t" if sample.count("\t") > sample.count(",") else ","


def read_table(path: Path) -> tuple[list[str], list[dict[str, str]]]:
    delimiter = infer_delimiter(path)
    with path.open(newline="") as handle:
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


def write_tsv(path: Path, fields: list[str], rows: list[dict[str, str]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="") as handle:
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


def resolve_path(value: str, base_dir: Path) -> str:
    text = norm(value)
    if not text or "://" in text or os.path.isabs(text):
        return text
    return str((base_dir / text).resolve())


def safe_id(*parts: str) -> str:
    text = "_".join(part for part in parts if part)
    text = re.sub(r"[^A-Za-z0-9_.-]+", "_", text).strip("_")
    return text or "orthology_bundle"


def fail(message: str) -> None:
    print(f"ERROR\tprepare_coordinate_projection_bundle_inputs\t{message}", file=sys.stderr)
    raise SystemExit(1)


def rows_by_pair(rows: list[dict[str, str]]) -> dict[tuple[str, str], list[dict[str, str]]]:
    grouped: dict[tuple[str, str], list[dict[str, str]]] = defaultdict(list)
    for row in rows:
        source = norm(row.get("source_species"))
        target = norm(row.get("target_species"))
        if source and target:
            grouped[(source, target)].append(row)
    return grouped


def unique_values(rows: list[dict[str, str]], field: str) -> list[str]:
    return sorted({norm(row.get(field)) for row in rows if norm(row.get(field))})


def resolved_asset_path(row: dict[str, str], base_dir: Path) -> str:
    return resolve_path(norm(row.get("asset_path")), base_dir)


def role_rows(rows: list[dict[str, str]], role: str) -> list[dict[str, str]]:
    return [row for row in rows if lower_norm(row.get("asset_role")) == role]


def require_local_path(path: str, role: str) -> None:
    if "://" in path:
        fail(f"Cannot stage remote URI for {role}: {path}")
    if not os.path.exists(path):
        fail(f"Bundle asset for {role} does not exist: {path}")


def optional_singleton_path(rows: list[dict[str, str]], role: str, base_dir: Path) -> str:
    paths = sorted({resolved_asset_path(row, base_dir) for row in role_rows(rows, role)})
    if len(paths) > 1:
        fail(f"Current coordinate_projection bundle consumption supports one {role} asset per run; found {len(paths)} distinct paths")
    if not paths:
        return ""
    require_local_path(paths[0], role)
    return paths[0]


def link_or_copy(src: str, dst_dir: Path, placeholder: str) -> tuple[bool, Path]:
    dst_dir.mkdir(parents=True, exist_ok=True)
    if not src:
        dst = dst_dir / placeholder
        dst.write_text("")
        return False, dst
    src_path = Path(src)
    dst = dst_dir / src_path.name
    if dst.exists() or dst.is_symlink():
        dst.unlink()
    try:
        os.symlink(src_path, dst)
    except OSError:
        shutil.copy2(src_path, dst)
    return True, dst


def stage_optional_assets(rows: list[dict[str, str]], base_dir: Path, output_dir: Path) -> dict[str, tuple[bool, Path]]:
    slots = {
        "source_mask": ("source_callable_mask", "opt_source_mask", "NO_FILE.source_mask"),
        "species_mask": ("target_callable_mask", "opt_species_mask", "NO_FILE.species_mask"),
        "element_union": ("source_element_union", "opt_element_union", "NO_FILE.element_union"),
        "hal_file": ("hal_alignment", "opt_hal", "NO_FILE.hal"),
    }
    staged = {}
    selector_rows = []
    for slot, (role, subdir, placeholder) in slots.items():
        path = optional_singleton_path(rows, role, base_dir)
        has_asset, staged_path = link_or_copy(path, output_dir / subdir, placeholder)
        staged[slot] = (has_asset, staged_path)
        selector_rows.append({"slot": slot, "has_asset": str(has_asset).lower(), "path": str(staged_path)})
        (output_dir / f"has_{slot}.txt").write_text(str(has_asset).lower() + "\n")
    write_tsv(output_dir / "orthology_reference_bundle_asset_selectors.tsv", SELECTOR_FIELDS, selector_rows)
    return staged


def projection_id_for_pair(pair_rows: list[dict[str, str]], bundle_id: str, source: str, target: str) -> str:
    projection_ids = unique_values(pair_rows, "projection_id")
    if len(projection_ids) > 1:
        fail(f"Conflicting projection_id values for bundle pair {source}->{target}: {','.join(projection_ids)}")
    projection_id = projection_ids[0] if projection_ids else safe_id("rb", bundle_id, source, "to", target)
    bad_delim = next((delim for delim in RESERVED_ID_DELIMITERS if delim in projection_id), None)
    if bad_delim:
        fail(f"projection_id for bundle pair {source}->{target} contains reserved delimiter '{bad_delim}'")
    return projection_id


def build_projection_inputs(rows: list[dict[str, str]], base_dir: Path) -> tuple[list[dict[str, str]], list[dict[str, str]], str]:
    if not rows:
        fail("Bundle manifest has no rows")
    lift_tools = unique_values(rows, "orthology_lift_tool")
    lift_tools = [tool.lower() for tool in lift_tools]
    if len(set(lift_tools)) != 1:
        fail(f"Current coordinate_projection bundle consumption requires one orthology_lift_tool per run; found {','.join(sorted(set(lift_tools)))}")
    lift_tool = lift_tools[0]
    if lift_tool not in {"liftover", "halliftover"}:
        fail(f"Unsupported orthology_lift_tool in bundle: {lift_tool}")

    alignments = []
    configs = []
    for (source, target), pair_rows in sorted(rows_by_pair(rows).items()):
        bundle_ids = unique_values(pair_rows, "bundle_id")
        bundle_id = bundle_ids[0] if bundle_ids else "orthology_bundle"
        chain_paths = [resolved_asset_path(row, base_dir) for row in role_rows(pair_rows, "reciprocal_best_chain")]
        chain_file = ""
        if lift_tool == "liftover":
            if len(chain_paths) != 1:
                fail(f"liftover bundle pair {source}->{target} requires exactly one reciprocal_best_chain asset")
            chain_file = chain_paths[0]
            require_local_path(chain_file, "reciprocal_best_chain")
        projection_id = projection_id_for_pair(pair_rows, bundle_id, source, target)
        alignment_id = safe_id(bundle_id, source, "to", target)
        alignments.append(
            {
                "source_species": source,
                "target_species": target,
                "alignment_id": alignment_id,
                "chain_file": chain_file,
                "maf_file": "",
                "net_file": "",
                "alignment_type": "reciprocal_best_chain" if lift_tool == "liftover" else "hal_alignment",
                "source": f"orthology_reference_bundle:{bundle_id}",
                "notes": f"generated from orthology reference bundle; lift_tool={lift_tool}",
            }
        )
        configs.append(
            {
                "projection_id": projection_id,
                "source_species": source,
                "target_species": target,
                "method": "liftover_chain" if lift_tool == "liftover" else "precomputed_map",
                "notes": f"generated from orthology reference bundle {bundle_id}",
            }
        )
    return alignments, configs, lift_tool


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--bundle-manifest", "--bundle_manifest", required=True)
    parser.add_argument("--output-dir", "--output_dir", required=True)
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    manifest = Path(args.bundle_manifest)
    output_dir = Path(args.output_dir)
    fields, rows = read_table(manifest)
    base_dir = manifest.resolve().parent
    output_dir.mkdir(parents=True, exist_ok=True)
    stage_optional_assets(rows, base_dir, output_dir)
    alignments, configs, lift_tool = build_projection_inputs(rows, base_dir)
    write_tsv(output_dir / "genome_alignment_manifest.from_bundle.tsv", ALIGNMENT_FIELDS, alignments)
    write_tsv(output_dir / "coordinate_projection_config.from_bundle.tsv", CONFIG_FIELDS, configs)
    (output_dir / "effective_orthology_lift_tool.txt").write_text(lift_tool + "\n")
    print(
        "CAME coordinate projection bundle preparation: "
        f"pairs={len(configs)} lift_tool={lift_tool}"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
