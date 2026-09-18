#!/usr/bin/env python3
"""Repair contaminated station values in pace_planner.json.

Two 5-minute buckets carry sled times that are far outside the trend of their
neighbours, which makes the pace planner hand out sled targets that are slower
than the next (heavier) division:

  menOpenSingle   65-70 min  sledPush 234s / sledPull 314s  (neighbours 138/207 and 156/247)
  womenOpenSingle 155-160 min sledPush 378s                 (neighbours 260 and 265)

This is a *temporary* correction: the affected station values are replaced with a
linear interpolation of the adjacent buckets, `avg_station_total` is recomputed so
it keeps matching the sum of `stations`, and the original values are recorded in a
top-level `patched_note` so the change can be reverted (`--revert`) or audited.
The real fix is to re-derive the buckets from clean source data.

Guarantees:
  * idempotent — neighbours are never touched, so re-running recomputes the same
    values and rewrites byte-identical JSON
  * schema preserved — only existing keys are written (all ints, as the Swift
    decoder expects) plus the ignored `patched_note` metadata

Usage:
    python3 tools/pace-data/patch_contaminated_buckets.py            # apply
    python3 tools/pace-data/patch_contaminated_buckets.py --dry-run  # report only
    python3 tools/pace-data/patch_contaminated_buckets.py --verify   # invariants only
    python3 tools/pace-data/patch_contaminated_buckets.py --revert   # restore originals
"""

from __future__ import annotations

import argparse
import json
import math
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
JSON_PATH = REPO_ROOT / "Targets/HyroxCore/Resources/PaceReference/pace_planner.json"

# Fixed so repeated runs produce identical bytes.
PATCH_DATE = "2026-09-18"
NOTE_KEY = "patched_note"
NOTE_AFTER_KEY = "source"  # `patched_note` is inserted right after this top-level key

# Buckets to repair: (division, lo_min, [station keys])
TARGETS = [
    (
        "menOpenSingle",
        65,
        ["sledPush", "sledPull"],
        "sled times break the trend of the 60-65 and 70-75 buckets and push the "
        "segment sum 186s past avg_overall",
    ),
    (
        "womenOpenSingle",
        155,
        ["sledPush"],
        "sledPush spikes 118s above both neighbours and pushes the segment sum "
        "136s past avg_overall",
    ),
]

STATION_ORDER = [
    "skiErg",
    "sledPush",
    "sledPull",
    "burpeeBroadJumps",
    "rowing",
    "farmersCarry",
    "sandbagLunges",
    "wallBalls",
]

# Buckets with enough athletes for the average to be meaningful. The long tail
# (a handful of athletes per bucket) is noisy by nature and is not checked.
# Kept in sync with `denseBucketMinCount` in PacePlannerTests.swift.
DENSE_BUCKET_MIN_COUNT = 250


def load(path: Path) -> dict:
    with path.open("rb") as handle:
        return json.load(handle)


def dump(data: dict, path: Path) -> None:
    # Matches the existing file: minified, no trailing newline.
    path.write_text(json.dumps(data, separators=(",", ":"), ensure_ascii=False), encoding="utf-8")


def bucket_mid(bucket: dict) -> float:
    return (bucket["lo_min"] + bucket["hi_min"]) / 2.0


def find_bucket(data: dict, division: str, lo_min: int) -> tuple[int, list]:
    buckets = data["divisions"][division]["buckets"]
    for index, bucket in enumerate(buckets):
        if bucket["lo_min"] == lo_min:
            return index, buckets
    raise SystemExit(f"bucket not found: {division} lo_min={lo_min}")


def interpolated(prev: dict, target: dict, nxt: dict, station: str) -> int:
    """Linear interpolation of `station` between the two neighbouring buckets."""
    lo_mid, mid, hi_mid = bucket_mid(prev), bucket_mid(target), bucket_mid(nxt)
    ratio = (mid - lo_mid) / (hi_mid - lo_mid)
    lo_val, hi_val = prev["stations"][station], nxt["stations"][station]
    # floor(x + 0.5): round half up, so the result never depends on the platform's
    # banker's rounding and stays identical across runs.
    return int(math.floor(lo_val + (hi_val - lo_val) * ratio + 0.5))


def previous_note_entry(data: dict, division: str, lo_min: int, station: str) -> dict | None:
    for entry in data.get(NOTE_KEY, {}).get("patches", []):
        if (
            entry.get("division") == division
            and entry.get("lo_min") == lo_min
            and entry.get("station") == station
        ):
            return entry
    return None


def segment_sum_gap(bucket: dict) -> int:
    """(run + roxzone + stations) - overall. Should sit near zero."""
    return bucket["avg_run_rox"] + sum(bucket["stations"].values()) - bucket["avg_overall"]


def report_invariants(data: dict, label: str) -> None:
    print(f"\n[{label}] bucket invariants")
    for division, lo_min, stations, _ in TARGETS:
        index, buckets = find_bucket(data, division, lo_min)
        for offset in (-1, 0, 1):
            bucket = buckets[index + offset]
            marker = " <- target" if offset == 0 else ""
            values = " ".join(f"{s}={bucket['stations'][s]}" for s in stations)
            print(
                f"  {division:<16} {bucket['lo_min']:>3}-{bucket['hi_min']:<3} "
                f"{values}  station_total={bucket['avg_station_total']} "
                f"sum-overall={segment_sum_gap(bucket):+d}{marker}"
            )

    print(f"\n[{label}] monotonicity over dense buckets (count >= {DENSE_BUCKET_MIN_COUNT})")
    for division in ("menOpenSingle", "womenOpenSingle"):
        buckets = [b for b in data["divisions"][division]["buckets"] if b["count"] >= DENSE_BUCKET_MIN_COUNT]
        for station in ("sledPush", "sledPull"):
            values = [b["stations"][station] for b in buckets]
            breaks = [
                f"{buckets[i]['lo_min']}->{buckets[i + 1]['lo_min']} ({values[i]}->{values[i + 1]})"
                for i in range(len(values) - 1)
                if values[i] > values[i + 1]
            ]
            status = "OK" if not breaks else "BROKEN: " + ", ".join(breaks)
            print(f"  {division:<16} {station:<9} n={len(values):<3} {status}")


def sync_station_total(bucket: dict) -> int:
    """`avg_station_total` is the sum of `stations` everywhere in this file."""
    total = sum(bucket["stations"].values())
    bucket["avg_station_total"] = total
    return total


def apply_patches(data: dict) -> dict:
    entries: list[dict] = []

    for division, lo_min, stations, reason in TARGETS:
        index, buckets = find_bucket(data, division, lo_min)
        if index == 0 or index == len(buckets) - 1:
            raise SystemExit(f"{division} lo_min={lo_min} has no neighbour on both sides")
        prev, target, nxt = buckets[index - 1], buckets[index], buckets[index + 1]

        for station in stations:
            current = target["stations"][station]
            patched = interpolated(prev, target, nxt, station)
            recorded = previous_note_entry(data, division, lo_min, station)
            # On a re-run `current` is already the patched value — keep the very
            # first original so the note stays a faithful revert record.
            original = recorded["original"] if recorded else current

            if current != patched:
                print(
                    f"  patch {division} {lo_min}-{target['hi_min']} {station}: "
                    f"{current} -> {patched} "
                    f"(lerp of {prev['lo_min']}-{prev['hi_min']}={prev['stations'][station]} and "
                    f"{nxt['lo_min']}-{nxt['hi_min']}={nxt['stations'][station]})"
                )
                target["stations"][station] = patched
            else:
                print(f"  keep  {division} {lo_min}-{target['hi_min']} {station}: already {patched}")

            entries.append(
                {
                    "division": division,
                    "lo_min": lo_min,
                    "station": station,
                    "original": original,
                    "patched": patched,
                    "method": "linear interpolation of the adjacent buckets",
                    "reason": reason,
                }
            )

        before_total = target["avg_station_total"]
        after_total = sync_station_total(target)
        if before_total != after_total:
            print(
                f"  patch {division} {lo_min}-{target['hi_min']} avg_station_total: "
                f"{before_total} -> {after_total} (sum of stations)"
            )

    note = {
        "patched_at": PATCH_DATE,
        "tool": "tools/pace-data/patch_contaminated_buckets.py",
        "summary": (
            "Temporary correction of contaminated sled buckets. Station values were "
            "replaced by a linear interpolation of the adjacent buckets and "
            "avg_station_total recomputed. Revert with --revert once the buckets are "
            "re-derived from clean source data."
        ),
        "patches": entries,
    }
    return reorder_with_note(data, note)


def reorder_with_note(data: dict, note: dict | None) -> dict:
    """Rebuild the dict so `patched_note` sits near the top (after `source`)."""
    rebuilt: dict = {}
    for key, value in data.items():
        if key == NOTE_KEY:
            continue
        rebuilt[key] = value
        if key == NOTE_AFTER_KEY and note is not None:
            rebuilt[NOTE_KEY] = note
    if note is not None and NOTE_KEY not in rebuilt:
        rebuilt[NOTE_KEY] = note
    return rebuilt


def revert(data: dict) -> dict:
    note = data.get(NOTE_KEY)
    if not note:
        raise SystemExit("nothing to revert: no patched_note in the JSON")

    for entry in note.get("patches", []):
        _, buckets = find_bucket(data, entry["division"], entry["lo_min"])
        bucket = next(b for b in buckets if b["lo_min"] == entry["lo_min"])
        print(
            f"  revert {entry['division']} {entry['lo_min']} {entry['station']}: "
            f"{bucket['stations'][entry['station']]} -> {entry['original']}"
        )
        bucket["stations"][entry["station"]] = entry["original"]
        sync_station_total(bucket)

    return reorder_with_note(data, None)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dry-run", action="store_true", help="report without writing")
    parser.add_argument("--verify", action="store_true", help="only print invariants")
    parser.add_argument("--revert", action="store_true", help="restore the original values")
    parser.add_argument("--path", type=Path, default=JSON_PATH)
    args = parser.parse_args()

    data = load(args.path)
    report_invariants(data, "before")

    if args.verify:
        return

    print()
    if args.revert:
        data = revert(data)
    else:
        data = apply_patches(data)

    report_invariants(data, "after")

    if args.dry_run:
        print("\n(dry run — file untouched)")
        return

    dump(data, args.path)
    print(f"\nwrote {args.path.relative_to(REPO_ROOT)}")


if __name__ == "__main__":
    main()
