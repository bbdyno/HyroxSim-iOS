"""Comparison report between the previous and the newly built v3 bundle."""

from __future__ import annotations

import json
import os
from collections import OrderedDict

from . import config
from .mathutil import interp_series

#: Relative p50 move that is called out as a warning.
P50_WARN_RATIO = 0.05


def percentile_overall(division_payload, percentile=50.0):
    xs, ys = [], []
    for bucket in division_payload["buckets"]:
        xs.append((bucket["pct_range"][0] + bucket["pct_range"][1]) / 2.0)
        ys.append(bucket["avg_overall"])
    if not xs:
        return None
    return interp_series(xs, ys, percentile)


def load_previous(path=None):
    path = path or config.V3_OUTPUT_PATH
    if not os.path.exists(path):
        return None
    with open(path, "r", encoding="utf-8") as fh:
        return json.load(fh)


def compare(previous, current):
    rows = []
    for division in config.DIVISION_MAP.values():
        new = current["divisions"][division]
        new_p50 = percentile_overall(new)
        old = (previous or {}).get("divisions", {}).get(division)
        old_p50 = percentile_overall(old) if old else None
        delta = (new_p50 - old_p50) if (old_p50 and new_p50) else None
        rows.append(
            OrderedDict(
                [
                    ("division", division),
                    ("old_total", old["total_athletes"] if old else None),
                    ("new_total", new["total_athletes"]),
                    ("old_buckets", len(old["buckets"]) if old else None),
                    ("new_buckets", len(new["buckets"])),
                    ("old_p50_s", round(old_p50) if old_p50 else None),
                    ("new_p50_s", round(new_p50) if new_p50 else None),
                    ("delta_s", round(delta) if delta is not None else None),
                    ("delta_pct", round(100.0 * delta / old_p50, 2) if delta is not None else None),
                    (
                        "warn",
                        bool(delta is not None and abs(delta) / old_p50 > P50_WARN_RATIO),
                    ),
                ]
            )
        )
    return rows


def _mmss(seconds):
    if seconds is None:
        return "-"
    seconds = int(seconds)
    return "{m}:{s:02d}".format(m=seconds // 60, s=seconds % 60)


def render(rows):
    lines = [
        "  {d:<18} {ot:>9} {nt:>9} {ob:>4} {nb:>4} {op:>8} {np:>8} {ds:>7} {dp:>7}".format(
            d="division", ot="old_n", nt="new_n", ob="old_b", nb="new_b",
            op="old_p50", np="new_p50", ds="delta", dp="delta%",
        )
    ]
    for row in rows:
        lines.append(
            "  {d:<18} {ot:>9} {nt:>9} {ob:>4} {nb:>4} {op:>8} {np:>8} {ds:>7} {dp:>6}%{w}".format(
                d=row["division"],
                ot=row["old_total"] if row["old_total"] is not None else "-",
                nt=row["new_total"],
                ob=row["old_buckets"] if row["old_buckets"] is not None else "-",
                nb=row["new_buckets"],
                op=_mmss(row["old_p50_s"]),
                np=_mmss(row["new_p50_s"]),
                ds="{v:+d}s".format(v=row["delta_s"]) if row["delta_s"] is not None else "-",
                dp="{v:+.2f}".format(v=row["delta_pct"]) if row["delta_pct"] is not None else "-",
                w="  <= 급변 경고" if row["warn"] else "",
            )
        )
    return "\n".join(lines)


def warnings(rows):
    return [
        "{d}: p50 {o}s -> {n}s ({p:+.2f}%)".format(
            d=row["division"], o=row["old_p50_s"], n=row["new_p50_s"], p=row["delta_pct"]
        )
        for row in rows
        if row["warn"]
    ]
