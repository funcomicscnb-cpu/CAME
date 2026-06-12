#!/usr/bin/env python3
"""Shared interval and alignment-record helpers for CAME orthology projection.

This module is intentionally dependency-free (standard library only) so that the
reciprocal-best orthology scripts remain unit-testable without external genomics
binaries. It provides:

- minimal BED parsing tolerant of comment/track lines;
- per-chromosome interval merging, intersection, and coverage measurement;
- UCSC chain-file identifier extraction and filtering.

Coordinates follow the BED convention: zero-based, half-open [start, end).
"""

import bisect
import csv
import gzip
import os


MISSING_VALUES = {"", "na", "n/a", "nan", "null", "none", "."}


def _norm(value):
    text = str(value if value is not None else "").strip()
    return "" if text.lower() in MISSING_VALUES else text


def open_text(path):
    """Open a file for text reading, transparently handling gzip by extension."""
    if str(path).endswith(".gz"):
        return gzip.open(path, "rt", newline="")
    return open(path, newline="")


def is_metadata_line(stripped):
    """True if a (stripped) line is a UCSC comment/track/browser metadata line.

    Recognizes ``#...`` comments and ``track``/``browser`` only as whole leading
    tokens (followed by whitespace or end of line) — not any line that merely
    starts with those letters (e.g. ``tracking ...`` or ``browserX ...``), which
    would otherwise let malformed data be silently skipped as "metadata".
    """
    if not stripped:
        return False
    if stripped.startswith("#"):
        return True
    return stripped.split(None, 1)[0] in ("track", "browser")


def parse_bed(path, name_required=False):
    """Parse a BED-like file into a list of interval dicts.

    Returns dicts with keys chrom, start, end, name, strand, and extra (any
    columns beyond the fourth). Gzipped files (``.gz``) are read transparently.
    Lines that are blank, comments, or UCSC track/browser headers are skipped.
    Rows with non-integer or inverted coordinates are skipped silently; callers
    that need strict validation should check counts.
    """
    intervals = []
    if not path or not os.path.exists(path):
        return intervals
    with open_text(path) as handle:
        for line in handle:
            stripped = line.rstrip("\n")
            if not stripped.strip() or is_metadata_line(stripped.strip()):
                continue
            fields = stripped.split("\t")
            if len(fields) < 3:
                fields = stripped.split()
            if len(fields) < 3:
                continue
            chrom = _norm(fields[0])
            try:
                start = int(fields[1])
                end = int(fields[2])
            except ValueError:
                continue
            if not chrom or start < 0 or end <= start:
                continue
            name = _norm(fields[3]) if len(fields) > 3 else ""
            if name_required and not name:
                continue
            strand = _norm(fields[5]) if len(fields) > 5 else ""
            intervals.append(
                {
                    "chrom": chrom,
                    "start": start,
                    "end": end,
                    "name": name,
                    "strand": strand,
                    "extra": [f.strip() for f in fields[4:]],
                }
            )
    return intervals


def count_data_lines(path):
    """Count non-blank, non-comment, non-track lines in a BED-like file."""
    if not path or not os.path.exists(path):
        return 0
    count = 0
    with open_text(path) as handle:
        for line in handle:
            stripped = line.strip()
            if stripped and not is_metadata_line(stripped):
                count += 1
    return count


class IntervalIndex:
    """Chromosome-indexed, merged interval set for fast overlap queries.

    Built once from an interval-dict list (e.g. a genome-scale callable mask),
    it answers point/range overlap with binary search rather than a linear scan
    over every interval.
    """

    def __init__(self, intervals):
        self._by_chrom = {}
        for chrom, ranges in merge_intervals(intervals).items():
            starts = [start for start, _ in ranges]
            ends = [end for _, end in ranges]
            self._by_chrom[chrom] = (starts, ends)

    def overlaps(self, chrom, start, end):
        entry = self._by_chrom.get(chrom)
        if not entry:
            return False
        starts, ends = entry
        i = bisect.bisect_right(starts, start) - 1
        if i >= 0 and ends[i] > start:
            return True
        j = i + 1
        return j < len(starts) and starts[j] < end

    def chrom_ranges(self, chrom):
        """Merged (start, end) ranges on a single chromosome (empty if none)."""
        entry = self._by_chrom.get(chrom)
        if not entry:
            return []
        starts, ends = entry
        return list(zip(starts, ends))


def group_by_chrom(intervals):
    grouped = {}
    for interval in intervals:
        grouped.setdefault(interval["chrom"], []).append((interval["start"], interval["end"]))
    return grouped


def merge_ranges(ranges):
    """Merge a list of (start, end) tuples on a single chromosome."""
    if not ranges:
        return []
    ordered = sorted(ranges)
    merged = [list(ordered[0])]
    for start, end in ordered[1:]:
        if start <= merged[-1][1]:
            merged[-1][1] = max(merged[-1][1], end)
        else:
            merged.append([start, end])
    return [(start, end) for start, end in merged]


def merge_intervals(intervals):
    """Merge intervals across chromosomes; returns {chrom: [(start, end), ...]}."""
    return {chrom: merge_ranges(ranges) for chrom, ranges in group_by_chrom(intervals).items()}


def total_length(intervals):
    """Total covered bp after merging (no double counting of overlaps)."""
    merged = merge_intervals(intervals)
    return sum(end - start for ranges in merged.values() for start, end in ranges)


def intersect_ranges(a_ranges, b_ranges):
    """Intersection of two single-chromosome merged range lists."""
    a = merge_ranges(a_ranges)
    b = merge_ranges(b_ranges)
    result = []
    i = j = 0
    while i < len(a) and j < len(b):
        lo = max(a[i][0], b[j][0])
        hi = min(a[i][1], b[j][1])
        if lo < hi:
            result.append((lo, hi))
        if a[i][1] < b[j][1]:
            i += 1
        else:
            j += 1
    return result


def intersect_intervals(a, b):
    """Intersection across chromosomes; returns {chrom: [(start, end), ...]}."""
    a_grouped = merge_intervals(a)
    b_grouped = merge_intervals(b)
    result = {}
    for chrom in set(a_grouped) & set(b_grouped):
        ranges = intersect_ranges(a_grouped[chrom], b_grouped[chrom])
        if ranges:
            result[chrom] = ranges
    return result


def overlap_length(a, b):
    """Total bp of overlap between two interval collections."""
    intersection = intersect_intervals(a, b)
    return sum(end - start for ranges in intersection.values() for start, end in ranges)


def overlaps_any(interval, others):
    """True if `interval` (dict) overlaps any interval in `others` on its chrom."""
    chrom = interval["chrom"]
    start, end = interval["start"], interval["end"]
    for other in others:
        if other["chrom"] == chrom and start < other["end"] and other["start"] < end:
            return True
    return False


def filter_min_length(intervals, min_length):
    return [iv for iv in intervals if (iv["end"] - iv["start"]) >= min_length]


# --- UCSC chain helpers -----------------------------------------------------
#
# A UCSC chain block starts with a header line:
#     chain score tName tSize tStrand tStart tEnd qName qSize qStrand qStart qEnd id
# All chain logic (header detection, id extraction, filtering) shares the two
# predicates below so the notion of "a header" is identical everywhere — an
# inconsistent predicate (e.g. startswith vs first-token) would let a bogus
# "chainX" line leak an id, or count a header as parseable yet extract no id.


def is_chain_header(line):
    """True if `line` purports to start a chain block (first token is 'chain')."""
    fields = line.split()
    return bool(fields) and fields[0] == "chain"


def _is_int(value):
    try:
        int(value)
        return True
    except ValueError:
        return False


def chain_header_id(line):
    """The chain id if `line` is a structurally valid UCSC chain header, else None.

    A header has exactly the 13 fields::

        chain score tName tSize tStrand tStart tEnd qName qSize qStrand qStart qEnd id

    with an integer score, non-negative integer sizes/coordinates satisfying
    ``0 <= start <= end <= size`` on both sides, ``+``/``-`` strands, and a
    non-empty id. A header-looking line that fails any of these is not a
    parseable header (and is reported as malformed upstream) rather than yielding
    a bogus id.
    """
    fields = line.split()
    if len(fields) != 13 or fields[0] != "chain":
        return None
    score, t_strand, q_strand, chain_id = fields[1], fields[4], fields[9], fields[12]
    sizes_coords = (fields[3], fields[5], fields[6], fields[8], fields[10], fields[11])
    if not _is_int(score):
        return None
    if not all(value.isdigit() for value in sizes_coords):
        return None
    if t_strand not in ("+", "-") or q_strand not in ("+", "-"):
        return None
    if not chain_id:
        return None
    # Coordinate consistency (guaranteed by the chain format): the aligned span
    # must lie within the sequence on each side. isdigit() already ensured >= 0.
    t_size, t_start, t_end = int(fields[3]), int(fields[5]), int(fields[6])
    q_size, q_start, q_end = int(fields[8]), int(fields[10]), int(fields[11])
    if not (t_start <= t_end <= t_size) or not (q_start <= q_end <= q_size):
        return None
    return chain_id


def extract_chain_ids(path):
    """Return the set of chain identifiers from a UCSC chain file."""
    ids = set()
    if not path or not os.path.exists(path):
        return ids
    with open_text(path) as handle:
        for line in handle:
            chain_id = chain_header_id(line)
            if chain_id is not None:
                ids.add(chain_id)
    return ids


def chain_header_stats(path):
    """Return (header_lines, parseable_headers) for a UCSC chain file.

    A header line is any line whose first token is ``chain``; it is parseable
    only if it is a structurally valid UCSC header (see ``chain_header_id``). A
    file with header-looking lines that are not all parseable is malformed.
    """
    headers = 0
    parseable = 0
    if not path or not os.path.exists(path):
        return (0, 0)
    with open_text(path) as handle:
        for line in handle:
            if is_chain_header(line):
                headers += 1
                if chain_header_id(line) is not None:
                    parseable += 1
    return (headers, parseable)


def duplicate_chain_ids(path):
    """Return the set of chain ids that appear more than once in a chain file.

    UCSC chain ids are unique within a file, and the id is the join key used to
    pair orientations for reciprocal-best definition, so a duplicate is an
    ambiguity (e.g. concatenated files) that must be rejected upstream.
    """
    seen = set()
    dups = set()
    if not path or not os.path.exists(path):
        return dups
    with open_text(path) as handle:
        for line in handle:
            chain_id = chain_header_id(line)
            if chain_id is not None:
                if chain_id in seen:
                    dups.add(chain_id)
                else:
                    seen.add(chain_id)
    return dups


def _chain_block_end_issue(in_block, body_rows, saw_final, header_lineno):
    """Issue (if any) when a chain block closes (blank line / next header / EOF)."""
    if not in_block or saw_final:
        return None
    if body_rows == 0:
        return f"chain block at line {header_lineno} has no body rows"
    return f"chain block at line {header_lineno} has no final size row"


def chain_body_issue(path):
    """Return a message for the first malformed chain block/body, else None.

    Validates the UCSC chain block grammar structurally: each block is a header
    followed by zero or more 3-field ``size dt dq`` continuation rows and then
    exactly one 1-field ``size`` final row, before a blank line / next header /
    EOF. Non-integer rows, rows with other field counts, a missing final row, a
    body-less header, and any row after the final row are all rejected. This is a
    structural check only; it does not verify that block sizes sum to the header
    span (chain-arithmetic verification is out of scope for this helper).
    """
    if not path or not os.path.exists(path):
        return None
    in_block = False
    body_rows = 0
    saw_final = False
    header_lineno = None
    with open_text(path) as handle:
        for lineno, raw in enumerate(handle, start=1):
            stripped = raw.strip()
            if not stripped:
                # A blank line is the only legitimate block terminator.
                issue = _chain_block_end_issue(in_block, body_rows, saw_final, header_lineno)
                if issue:
                    return issue
                in_block, body_rows, saw_final, header_lineno = False, 0, False, None
                continue
            if is_metadata_line(stripped):
                # Metadata is allowed only outside a block (before the first
                # header or between blank-separated blocks), never inside one.
                if in_block:
                    return f"non-chain metadata line inside a chain block at line {lineno}: {stripped}"
                continue
            if is_chain_header(raw):
                issue = _chain_block_end_issue(in_block, body_rows, saw_final, header_lineno)
                if issue:
                    return issue
                in_block, body_rows, saw_final, header_lineno = True, 0, False, lineno
                continue
            if not in_block:
                return f"chain body record outside any block at line {lineno}: {stripped}"
            if saw_final:
                return f"chain block at line {header_lineno} has a row after its final size (line {lineno})"
            fields = stripped.split()
            if not all(value.isdigit() for value in fields):
                return f"malformed chain body record at line {lineno}: {stripped}"
            if len(fields) == 3:
                body_rows += 1
            elif len(fields) == 1:
                body_rows += 1
                saw_final = True
            else:
                return f"malformed chain body record at line {lineno}: {stripped}"
    issue = _chain_block_end_issue(in_block, body_rows, saw_final, header_lineno)
    if issue:
        return issue
    return None


def filter_chain_by_ids(in_path, ids, out_path):
    """Write only chain blocks whose header id is in `ids`. Returns kept count."""
    os.makedirs(os.path.dirname(out_path) or ".", exist_ok=True)
    kept = 0
    keep_block = False
    with open_text(in_path) as src, open(out_path, "w") as dst:
        for line in src:
            if is_chain_header(line):
                chain_id = chain_header_id(line)
                keep_block = chain_id is not None and chain_id in ids
                if keep_block:
                    kept += 1
                    dst.write(line)
            elif keep_block:
                stripped = line.strip()
                # Metadata ends the copied region (consistent with chain_body_issue,
                # which forbids it inside a block) and is never copied through.
                if is_metadata_line(stripped):
                    keep_block = False
                    continue
                dst.write(line)
                if stripped == "":
                    keep_block = False
    return kept


def write_bed(path, intervals_by_chrom, name=None):
    os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
    with open(path, "w", newline="") as handle:
        for chrom in sorted(intervals_by_chrom):
            for start, end in intervals_by_chrom[chrom]:
                row = [chrom, str(start), str(end)]
                if name is not None:
                    row.append(name)
                handle.write("\t".join(row) + "\n")


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
