#!/usr/bin/env python3
"""Shard prepared coordinate-projection inputs for per-pair lift-over tasks."""

from __future__ import annotations

import argparse
import csv
import re
import shutil
import sys
from collections import OrderedDict
from pathlib import Path


MISSING_VALUES = {"", "na", "n/a", "nan", "null", "none", "."}
SHARD_FIELDS = [
    "shard_id",
    "projection_id",
    "source_species",
    "target_species",
    "prepared_manifest",
    "species_mask",
    "has_species_mask",
    "source_mask",
    "has_source_mask",
    "element_union",
    "has_element_union",
    "hal_file",
    "has_hal",
]
SELECTOR_FIELDS = ["source_species", "target_species", "slot", "has_asset", "path"]


def norm(value: object) -> str:
    text = str(value if value is not None else "").strip()
    return "" if text.lower() in MISSING_VALUES else text


def parse_bool(value: object) -> bool:
    return str(value).strip().lower() in {"1", "true", "t", "yes", "y"}


def safe_id(*parts: str) -> str:
    text = "_".join(norm(part) for part in parts if norm(part))
    text = re.sub(r"[^A-Za-z0-9_.-]+", "_", text).strip("_")
    return text or "coordinate_projection_shard"


def read_tsv(path: Path) -> tuple[list[str], list[dict[str, str]]]:
    with path.open(newline="") as handle:
        reader = csv.DictReader(handle, delimiter="\t")
        fields = [norm(field) for field in (reader.fieldnames or [])]
        rows = []
        for row in reader:
            cleaned = {}
            for field in fields:
                cleaned[field] = norm(row.get(field))
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


def link_or_copy(src: str, dst_dir: Path, placeholder: str) -> Path:
    dst_dir.mkdir(parents=True, exist_ok=True)
    if not norm(src):
        dst = dst_dir / placeholder
        dst.write_text("")
        return dst
    src_path = Path(src)
    dst = dst_dir / src_path.name
    if dst.exists() or dst.is_symlink():
        dst.unlink()
    shutil.copy2(src_path, dst)
    return dst


def selector_index(path: Path, assets_dir: Path) -> dict[tuple[str, str, str], tuple[bool, str]]:
    if not path.exists() or path.stat().st_size == 0:
        return {}
    fields, rows = read_tsv(path)
    if not rows:
        return {}
    missing = [field for field in SELECTOR_FIELDS if field not in fields]
    if missing:
        raise ValueError("pair asset selector is missing required column(s): " + ",".join(missing))
    index = {}
    for row in rows:
        source = norm(row.get("source_species"))
        target = norm(row.get("target_species"))
        slot = norm(row.get("slot"))
        if not (source and target and slot):
            continue
        key = (source, target, slot)
        has_asset = parse_bool(row.get("has_asset"))
        path_value = norm(row.get("path"))
        resolved = ""
        if path_value:
            candidate = Path(path_value)
            resolved = str(candidate if candidate.is_absolute() else assets_dir / candidate)
        if key in index and index[key] != (has_asset, resolved):
            raise ValueError(f"conflicting pair asset selector for {source}->{target} slot {slot}")
        index[key] = (has_asset, resolved)
    return index


def fallback_assets(args: argparse.Namespace) -> dict[str, tuple[bool, str]]:
    return {
        "species_mask": (parse_bool(args.has_species_mask), norm(args.species_mask)),
        "source_mask": (parse_bool(args.has_source_mask), norm(args.source_mask)),
        "element_union": (parse_bool(args.has_element_union), norm(args.element_union)),
        "hal_file": (parse_bool(args.has_hal), norm(args.hal_file)),
    }


def choose_asset(
    source: str,
    target: str,
    slot: str,
    pair_assets: dict[tuple[str, str, str], tuple[bool, str]],
    fallback: dict[str, tuple[bool, str]],
) -> tuple[bool, str]:
    pair_value = pair_assets.get((source, target, slot))
    if pair_value is not None:
        return pair_value
    return fallback[slot]


def shard_inputs(args: argparse.Namespace) -> int:
    manifest_path = Path(args.prepared_manifest)
    fields, rows = read_tsv(manifest_path)
    if not rows:
        print("ERROR\tshard_coordinate_projection_inputs\tEmpty prepared manifest", file=sys.stderr)
        return 1
    output_dir = Path(args.output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)
    assets_dir = Path(args.pair_assets_dir) if norm(args.pair_assets_dir) else Path(".")
    pair_assets = selector_index(Path(args.pair_asset_selectors), assets_dir)
    fallback = fallback_assets(args)

    groups: OrderedDict[tuple[str, str, str], list[dict[str, str]]] = OrderedDict()
    for row in rows:
        key = (norm(row.get("projection_id")), norm(row.get("source_species")), norm(row.get("target_species")))
        if all(key):
            groups.setdefault(key, []).append(row)
    if not groups:
        print("ERROR\tshard_coordinate_projection_inputs\tNo projection pair groups found", file=sys.stderr)
        return 1

    shard_rows = []
    used_ids = set()
    for index, ((projection_id, source, target), group_rows) in enumerate(sorted(groups.items()), start=1):
        base_shard_id = safe_id(projection_id, source, "to", target)
        shard_id = base_shard_id
        if shard_id in used_ids:
            shard_id = f"{base_shard_id}_{index}"
        used_ids.add(shard_id)
        shard_dir = output_dir / "shards" / shard_id
        manifest_out = shard_dir / "coordinate_projection_manifest.tsv"
        write_tsv(manifest_out, fields, group_rows)

        asset_paths = {}
        asset_flags = {}
        for slot, placeholder in [
            ("species_mask", "NO_FILE.species_mask"),
            ("source_mask", "NO_FILE.source_mask"),
            ("element_union", "NO_FILE.element_union"),
            ("hal_file", "NO_FILE.hal"),
        ]:
            has_asset, src = choose_asset(source, target, slot, pair_assets, fallback)
            if has_asset and (not src or not Path(src).exists()):
                raise FileNotFoundError(f"{slot} asset for {source}->{target} does not exist: {src}")
            staged = link_or_copy(src if has_asset else "", shard_dir / "assets" / slot, placeholder)
            asset_paths[slot] = str(staged.resolve())
            asset_flags[slot] = str(bool(has_asset)).lower()

        shard_rows.append(
            {
                "shard_id": shard_id,
                "projection_id": projection_id,
                "source_species": source,
                "target_species": target,
                "prepared_manifest": str(manifest_out.resolve()),
                "species_mask": asset_paths["species_mask"],
                "has_species_mask": asset_flags["species_mask"],
                "source_mask": asset_paths["source_mask"],
                "has_source_mask": asset_flags["source_mask"],
                "element_union": asset_paths["element_union"],
                "has_element_union": asset_flags["element_union"],
                "hal_file": asset_paths["hal_file"],
                "has_hal": asset_flags["hal_file"],
            }
        )
    write_tsv(output_dir / "shards.tsv", SHARD_FIELDS, shard_rows)
    print(f"CAME coordinate projection sharding: shards={len(shard_rows)}")
    return 0


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--prepared-manifest", "--prepared_manifest", required=True)
    parser.add_argument("--pair-asset-selectors", "--pair_asset_selectors", required=True)
    parser.add_argument("--pair-assets-dir", "--pair_assets_dir", required=True)
    parser.add_argument("--species-mask", "--species_mask", default="")
    parser.add_argument("--has-species-mask", "--has_species_mask", default="false")
    parser.add_argument("--source-mask", "--source_mask", default="")
    parser.add_argument("--has-source-mask", "--has_source_mask", default="false")
    parser.add_argument("--element-union", "--element_union", default="")
    parser.add_argument("--has-element-union", "--has_element_union", default="false")
    parser.add_argument("--hal-file", "--hal_file", default="")
    parser.add_argument("--has-hal", "--has_hal", default="false")
    parser.add_argument("--output-dir", "--output_dir", required=True)
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    try:
        return shard_inputs(parse_args(argv))
    except Exception as exc:
        print(f"ERROR\tshard_coordinate_projection_inputs\t{exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
