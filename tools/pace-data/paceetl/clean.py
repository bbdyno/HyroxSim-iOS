"""Cleaning stage: parse upstream buckets and make them publishable.

Every rule here is deterministic and records what it touched, so the
``cleaning`` block of the outputs is a full audit trail. The rules, in order:

R0  drop buckets with no athletes or missing station splits
R1  drop buckets whose component sum misses avg_overall by > 5 %
R2  repair contaminated station spikes in dense buckets (interpolation)
R3  merge buckets under the minimum cell size into a neighbour
R4  bridge leftover range gaps so the bucket ladder stays continuous
R5  rescale components onto avg_overall where the residual is too large
R6  isotonic fit of station times across dense buckets

R6 runs last on purpose: R5 rescales each bucket by its own factor, which can
re-introduce the wobble R6 exists to remove. Integer rounding downstream is
monotone (round-half-up per station), so the ladder stays ordered.
"""

from __future__ import annotations

from collections import OrderedDict

from . import config
from .mathutil import isotonic


class Bucket(object):
    """Mutable working copy of one time bucket (values kept as floats)."""

    __slots__ = ("lo_min", "hi_min", "count", "avg_overall", "avg_run_rox", "stations")

    def __init__(self, lo_min, hi_min, count, avg_overall, avg_run_rox, stations):
        self.lo_min = int(lo_min)
        self.hi_min = int(hi_min)
        self.count = int(count)
        self.avg_overall = float(avg_overall)
        self.avg_run_rox = float(avg_run_rox)
        self.stations = OrderedDict(stations)

    @property
    def mid_min(self):
        return (self.lo_min + self.hi_min) / 2.0

    @property
    def station_total(self):
        return sum(self.stations.values())

    @property
    def residual(self):
        return self.avg_run_rox + self.station_total - self.avg_overall

    def copy(self):
        return Bucket(
            self.lo_min, self.hi_min, self.count, self.avg_overall, self.avg_run_rox, self.stations
        )


def parse_buckets(raw_division, slug, log):
    """Upstream payload -> list[Bucket] with app station keys (rule R0)."""
    buckets = []
    dropped = []
    for raw in raw_division.get("buckets", []):
        count = int(raw.get("count", 0))
        raw_stations = raw.get("stations") or {}
        missing = [name for name in config.STATION_MAP if name not in raw_stations]
        if count <= 0 or missing:
            dropped.append(
                {
                    "rule": "R0_incomplete",
                    "lo_min": raw.get("lo_min"),
                    "count": count,
                    "detail": "missing stations: {m}".format(m=missing) if missing else "count<=0",
                }
            )
            continue
        stations = OrderedDict(
            (key, float(raw_stations[name])) for name, key in config.STATION_MAP.items()
        )
        buckets.append(
            Bucket(
                raw["lo_min"],
                raw["hi_min"],
                count,
                raw["avg_overall"],
                raw["avg_run_rox"],
                stations,
            )
        )
    buckets.sort(key=lambda b: b.lo_min)
    if dropped:
        log("  {s}: R0 로 {n}개 버킷 제외".format(s=slug, n=len(dropped)))
    return buckets, dropped


def drop_broken(buckets, log, slug):
    """R1 - components that miss avg_overall by more than 5 % are unusable."""
    kept, dropped = [], []
    for bucket in buckets:
        limit = config.BROKEN_RESIDUAL_RATIO * bucket.avg_overall
        if abs(bucket.residual) > limit:
            dropped.append(
                {
                    "rule": "R1_residual_out_of_range",
                    "lo_min": bucket.lo_min,
                    "hi_min": bucket.hi_min,
                    "count": bucket.count,
                    "residual_s": round(bucket.residual, 1),
                    "limit_s": round(limit, 1),
                }
            )
            continue
        kept.append(bucket)
    if dropped:
        log(
            "  {s}: R1 로 {n}개 버킷 제외 (표본 {a}명)".format(
                s=slug, n=len(dropped), a=sum(d["count"] for d in dropped)
            )
        )
    return kept, dropped


def repair_spikes(buckets, log, slug):
    """R2 - replace contaminated station values with neighbour interpolation."""
    dense_idx = [i for i, b in enumerate(buckets) if b.count >= config.DENSE_MIN_N]
    repairs = []
    for position in range(1, len(dense_idx) - 1):
        prev_b = buckets[dense_idx[position - 1]]
        cur_b = buckets[dense_idx[position]]
        next_b = buckets[dense_idx[position + 1]]
        span = next_b.mid_min - prev_b.mid_min
        if span <= 0:
            continue
        t = (cur_b.mid_min - prev_b.mid_min) / span
        for key in config.STATION_KEYS:
            low, high, value = prev_b.stations[key], next_b.stations[key], cur_b.stations[key]
            interpolated = low + (high - low) * t
            above = value - max(low, high)
            below = min(low, high) - value
            if above > config.SPIKE_TOL_S or below > config.SPIKE_TOL_S:
                repairs.append(
                    {
                        "rule": "R2_station_spike",
                        "lo_min": cur_b.lo_min,
                        "station": key,
                        "count": cur_b.count,
                        "original_s": round(value, 1),
                        "repaired_s": round(interpolated, 1),
                        "neighbours_s": [round(low, 1), round(high, 1)],
                        "method": "linear interpolation between adjacent dense buckets",
                    }
                )
                cur_b.stations[key] = interpolated
    if repairs:
        log("  {s}: R2 로 {n}개 스테이션 값 보정".format(s=slug, n=len(repairs)))
    return repairs


def _combine(left, right):
    total = left.count + right.count
    weight_l = left.count / float(total)
    weight_r = right.count / float(total)
    stations = OrderedDict(
        (key, left.stations[key] * weight_l + right.stations[key] * weight_r)
        for key in left.stations
    )
    return Bucket(
        min(left.lo_min, right.lo_min),
        max(left.hi_min, right.hi_min),
        total,
        left.avg_overall * weight_l + right.avg_overall * weight_r,
        left.avg_run_rox * weight_l + right.avg_run_rox * weight_r,
        stations,
    )


def merge_small_cells(buckets, log, slug, min_cell=None):
    """R3 - merge every bucket below the minimum cell size into a neighbour."""
    min_cell = config.MIN_CELL_N if min_cell is None else min_cell
    working = [b.copy() for b in buckets]
    merges = []
    while len(working) > 1:
        target, best = None, None
        for index, bucket in enumerate(working):
            if bucket.count < min_cell and (best is None or bucket.count < best):
                best = bucket.count
                target = index
        if target is None:
            break
        if target == 0:
            partner = 1
        elif target == len(working) - 1:
            partner = target - 1
        else:
            partner = target - 1 if working[target - 1].count <= working[target + 1].count else target + 1
        low, high = min(target, partner), max(target, partner)
        merged = _combine(working[low], working[high])
        merges.append(
            {
                "rule": "R3_min_cell_merge",
                "merged": [
                    {"lo_min": working[low].lo_min, "hi_min": working[low].hi_min, "count": working[low].count},
                    {"lo_min": working[high].lo_min, "hi_min": working[high].hi_min, "count": working[high].count},
                ],
                "result": {"lo_min": merged.lo_min, "hi_min": merged.hi_min, "count": merged.count},
            }
        )
        working[low : high + 1] = [merged]
    if merges:
        log("  {s}: R3 로 {n}회 병합 (최소 셀 {m}명)".format(s=slug, n=len(merges), m=min_cell))
    return working, merges


def bridge_gaps(buckets, log, slug):
    """R4 - widen a bucket's range so the ladder has no holes (range only)."""
    bridges = []
    for index in range(len(buckets) - 1):
        left, right = buckets[index], buckets[index + 1]
        if left.hi_min != right.lo_min:
            bridges.append(
                {
                    "rule": "R4_gap_bridge",
                    "from_min": left.hi_min,
                    "to_min": right.lo_min,
                    "extended_bucket_lo_min": left.lo_min,
                }
            )
            left.hi_min = right.lo_min
    if bridges:
        log("  {s}: R4 로 {n}개 구간 공백 연결".format(s=slug, n=len(bridges)))
    return bridges


def isotonize_stations(buckets, log, slug):
    """R6 - remove residual non-monotonic wobble across dense buckets."""
    dense_idx = [i for i, b in enumerate(buckets) if b.count >= config.DENSE_MIN_N]
    if len(dense_idx) < 2:
        return []
    weights = [float(buckets[i].count) for i in dense_idx]
    adjustments = []
    for key in config.STATION_KEYS:
        values = [buckets[i].stations[key] for i in dense_idx]
        fitted = isotonic(values, weights)
        for position, index in enumerate(dense_idx):
            delta = fitted[position] - values[position]
            if abs(delta) >= 0.5:
                adjustments.append(
                    {
                        "rule": "R6_isotonic",
                        "lo_min": buckets[index].lo_min,
                        "station": key,
                        "count": buckets[index].count,
                        "original_s": round(values[position], 1),
                        "fitted_s": round(fitted[position], 1),
                    }
                )
            buckets[index].stations[key] = fitted[position]
    if adjustments:
        log("  {s}: R6 로 {n}개 스테이션 값 단조화".format(s=slug, n=len(adjustments)))
    return adjustments


def reconcile_totals(buckets, log, slug):
    """R5 - scale run_rox and stations so their sum lands on avg_overall."""
    rescales = []
    for bucket in buckets:
        residual = bucket.residual
        if abs(residual) <= config.RECONCILE_TOL_S:
            continue
        parts = bucket.avg_run_rox + bucket.station_total
        if parts <= 0:
            continue
        factor = bucket.avg_overall / parts
        rescales.append(
            {
                "rule": "R5_component_rescale",
                "lo_min": bucket.lo_min,
                "count": bucket.count,
                "residual_s": round(residual, 1),
                "factor": round(factor, 5),
            }
        )
        bucket.avg_run_rox *= factor
        for key in bucket.stations:
            bucket.stations[key] *= factor
    if rescales:
        log("  {s}: R5 로 {n}개 버킷 성분 재정규화".format(s=slug, n=len(rescales)))
    return rescales


def clean_division(raw_division, slug, log):
    """Run the full cleaning chain. Returns (buckets, cleaning_record)."""
    buckets, dropped_r0 = parse_buckets(raw_division, slug, log)
    buckets, dropped_r1 = drop_broken(buckets, log, slug)
    repairs = repair_spikes(buckets, log, slug)
    buckets, merges = merge_small_cells(buckets, log, slug)
    bridges = bridge_gaps(buckets, log, slug)
    rescales = reconcile_totals(buckets, log, slug)
    adjustments = isotonize_stations(buckets, log, slug)

    dropped = dropped_r0 + dropped_r1
    cleaning = OrderedDict(
        [
            ("min_cell_n", config.MIN_CELL_N),
            ("dense_min_n", config.DENSE_MIN_N),
            (
                "rules",
                OrderedDict(
                    [
                        ("R0_incomplete", "count<=0 이거나 스테이션 스플릿이 없는 버킷 제외"),
                        (
                            "R1_residual_out_of_range",
                            "|run_rox + stations - overall| > {p}% * overall 인 버킷 제외".format(
                                p=int(config.BROKEN_RESIDUAL_RATIO * 100)
                            ),
                        ),
                        (
                            "R2_station_spike",
                            "표본 {n}명 이상 버킷에서 양 이웃보다 {t}초 넘게 튀는 스테이션 값을 이웃 선형보간으로 교체".format(
                                n=config.DENSE_MIN_N, t=config.SPIKE_TOL_S
                            ),
                        ),
                        (
                            "R3_min_cell_merge",
                            "표본 {n}명 미만 버킷을 인접 버킷과 가중 병합 (개인 식별 방지)".format(
                                n=config.MIN_CELL_N
                            ),
                        ),
                        ("R4_gap_bridge", "병합 후 남은 구간 공백을 이어 붙임 (범위 라벨만 변경)"),
                        (
                            "R5_component_rescale",
                            "|run_rox + stations - overall| > {t}초인 버킷의 성분을 비례 축소/확대해 overall 에 맞춤".format(
                                t=config.RECONCILE_TOL_S
                            ),
                        ),
                        (
                            "R6_isotonic",
                            "표본 {n}명 이상 버킷 구간에서 스테이션 시간을 가중 isotonic 회귀로 단조화 "
                            "(성분 재정규화 뒤에 실행)".format(n=config.DENSE_MIN_N),
                        ),
                    ]
                ),
            ),
            (
                "counts",
                OrderedDict(
                    [
                        ("dropped_buckets", len(dropped)),
                        ("dropped_athletes", sum(d.get("count") or 0 for d in dropped)),
                        ("station_spikes_repaired", len(repairs)),
                        ("merges", len(merges)),
                        ("gaps_bridged", len(bridges)),
                        ("component_rescales", len(rescales)),
                        ("isotonic_adjustments", len(adjustments)),
                    ]
                ),
            ),
            ("dropped", dropped),
            ("station_spikes_repaired", repairs),
            ("merges", merges),
            ("gaps_bridged", bridges),
            ("component_rescales", rescales),
            ("isotonic_adjustments", adjustments),
        ]
    )
    return buckets, cleaning
