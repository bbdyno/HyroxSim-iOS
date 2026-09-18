"""Build the v4 percentile dataset (docs/pace/v4/<version>/<division>.json).

``overall_s`` is the empirical (type 7) quantile curve of the pooled
``ageStats`` finish times. The component curves come from the cleaned bucket
ladder, mapped onto percentile coordinates, isotonised, and then forced to sum
exactly to ``overall_s`` with a largest-remainder correction.
"""

from __future__ import annotations

import hashlib
import json
import os
from collections import OrderedDict

from . import config
from .mathutil import (
    interp_series,
    isotonic,
    largest_remainder,
    quantile_type7,
    round_half_up,
    strictly_increasing,
)

COMPONENT_KEYS = ("run_rox_s",) + config.STATION_KEYS


def pooled_finish_times(raw_division):
    values = []
    for series in (raw_division.get("ageStats") or {}).values():
        values.extend(float(v) for v in series)
    values.sort()
    return values


def percentile_coordinates(buckets):
    """Midpoint percentile of each bucket, from the cleaned counts."""
    total = float(sum(b.count for b in buckets)) or 1.0
    coords = []
    cumulative = 0
    for bucket in buckets:
        coords.append(100.0 * (cumulative + bucket.count / 2.0) / total)
        cumulative += bucket.count
    return coords


def build_division(raw_division, cleaned, division, slug, coverage, dataset_version, log):
    buckets = cleaned["buckets"]
    cleaning = cleaned["cleaning"]
    grid = config.GRID_P

    samples = pooled_finish_times(raw_division)
    if len(samples) < config.DENSE_MIN_N:
        raise RuntimeError("{d}: ageStats 표본이 너무 적습니다 ({n})".format(d=division, n=len(samples)))
    overall = strictly_increasing(
        [round_half_up(quantile_type7(samples, p)) for p in grid]
    )

    coords = percentile_coordinates(buckets)
    raw_components = OrderedDict()
    series = {"run_rox_s": [b.avg_run_rox for b in buckets]}
    for key in config.STATION_KEYS:
        series[key] = [b.stations[key] for b in buckets]
    for key in COMPONENT_KEYS:
        interpolated = [interp_series(coords, series[key], p) for p in grid]
        raw_components[key] = isotonic(interpolated)

    scales = []
    columns = OrderedDict((key, []) for key in COMPONENT_KEYS)
    for index, target in enumerate(overall):
        values = [raw_components[key][index] for key in COMPONENT_KEYS]
        total = sum(values)
        scales.append(target / total if total > 0 else 1.0)
        for key, value in zip(COMPONENT_KEYS, largest_remainder(values, target)):
            columns[key].append(int(value))

    age_groups = []
    for name in raw_division.get("ageGroups") or sorted((raw_division.get("ageStats") or {}).keys()):
        series_values = (raw_division.get("ageStats") or {}).get(name) or []
        if len(series_values) < config.AGE_GROUP_MIN_N:
            continue
        ordered = sorted(float(v) for v in series_values)
        age_groups.append(
            OrderedDict(
                [
                    ("age_group", name),
                    ("n", len(ordered)),
                    ("grid_p", list(config.AGE_GRID_P)),
                    (
                        "overall_s",
                        strictly_increasing(
                            [round_half_up(quantile_type7(ordered, p)) for p in config.AGE_GRID_P]
                        ),
                    ),
                ]
            )
        )

    division_coverage = OrderedDict(
        [
            ("division", division),
            ("source_division", slug.replace("_", " ")),
            ("seasons", coverage["seasons"]),
            ("season_label", coverage["season_label"]),
            ("events", coverage["events"]),
            ("events_with_division", coverage["events_by_division"].get(slug.replace("_", " "), 0)),
            ("athletes_upstream", int(raw_division.get("total_athletes", 0))),
            ("athletes_in_buckets", sum(b.count for b in buckets)),
            ("athletes_with_finish_time", len(samples)),
            ("buckets", len(buckets)),
            ("bucket_range_min", [buckets[0].lo_min, buckets[-1].hi_min]),
            ("upstream_version", coverage["upstream_version"]),
            ("upstream_generated", coverage["upstream_generated"]),
        ]
    )

    log(
        "  {d}: 표본 {n:,}명, 버킷 {b}개, p50 {p}s, 성분 스케일 {lo:.4f}~{hi:.4f}".format(
            d=division,
            n=len(samples),
            b=len(buckets),
            p=overall[grid.index(50.0)],
            lo=min(scales),
            hi=max(scales),
        )
    )

    return OrderedDict(
        [
            ("schema_version", config.V4_SCHEMA_VERSION),
            ("dataset_version", dataset_version),
            ("division", division),
            ("source_division", slug.replace("_", " ")),
            (
                "generator",
                OrderedDict(
                    [("script", config.GENERATOR), ("version", config.GENERATOR_VERSION)]
                ),
            ),
            ("min_cell_n", config.MIN_CELL_N),
            ("coverage", division_coverage),
            ("sources", _division_sources(slug)),
            ("cleaning", cleaning),
            (
                "method",
                OrderedDict(
                    [
                        ("overall_s", "ageStats 전체를 합친 경험적 분위수 (type 7), 정수 반올림 후 순증가 보정"),
                        (
                            "components",
                            "정제된 버킷을 퍼센타일 좌표(누적 count 중앙값)로 선형 보간 → 성분별 "
                            "isotonic 단조화 → overall_s 에 비례 스케일 → 최대 잔여(Hare) 정수 배분",
                        ),
                        ("age_groups", "표본 {n}명 이상 연령대만, 5pp 간격".format(n=config.AGE_GROUP_MIN_N)),
                        (
                            "component_scale",
                            OrderedDict(
                                [
                                    ("min", round(min(scales), 5)),
                                    ("max", round(max(scales), 5)),
                                    (
                                        "note",
                                        "버킷 기반 성분 합을 ageStats 기반 overall_s 로 맞추는 배율. "
                                        "1.0 에서 크게 벗어나면 두 소스가 어긋난 것.",
                                    ),
                                ]
                            ),
                        ),
                    ]
                ),
            ),
            ("grid_p", list(grid)),
            ("overall_s", overall),
            (
                "components",
                OrderedDict(
                    [
                        ("run_rox_s", columns["run_rox_s"]),
                        (
                            "stations_s",
                            OrderedDict((key, columns[key]) for key in config.STATION_KEYS),
                        ),
                    ]
                ),
            ),
            ("age_groups", age_groups),
        ]
    )


def _division_sources(slug):
    return [
        OrderedDict(
            [
                ("name", "planner_divisions"),
                ("url", config.division_url(slug)),
                ("used_fields", ["total_athletes", "buckets", "ageStats", "ageGroups"]),
            ]
        ),
        OrderedDict(
            [
                ("name", "events_meta"),
                ("url", config.BASE_URL + "/events_meta.json"),
                ("used_fields", ["season", "counts"]),
            ]
        ),
        OrderedDict(
            [
                ("name", "weekly_index"),
                ("url", config.BASE_URL + "/weekly/index.json"),
                ("used_fields", ["version", "generated"]),
                ("note", "개인 이름 필드는 사용하지 않음"),
            ]
        ),
    ]


def dumps(payload):
    return json.dumps(payload, ensure_ascii=False, separators=(",", ":"))


def build_manifest(files, dataset_version, coverage):
    """files: list of (relative name, encoded bytes)."""
    entries = []
    for name, payload in sorted(files, key=lambda item: item[0]):
        entries.append(
            OrderedDict(
                [
                    ("name", name),
                    ("sha256", hashlib.sha256(payload).hexdigest()),
                    ("bytes", len(payload)),
                ]
            )
        )
    return OrderedDict(
        [
            ("manifest_version", config.MANIFEST_VERSION),
            ("published_at", coverage.get("upstream_generated") or dataset_version.replace(".", "-")),
            ("dataset_version", dataset_version),
            ("schema_version", config.V4_SCHEMA_VERSION),
            (
                "generator",
                OrderedDict(
                    [("script", config.GENERATOR), ("version", config.GENERATOR_VERSION)]
                ),
            ),
            ("files", entries),
            ("coverage", coverage),
        ]
    )


def dumps_manifest(payload):
    return json.dumps(payload, ensure_ascii=False, indent=2) + "\n"


def v4_relative_name(dataset_version, division):
    return os.path.join("v4", dataset_version, division + ".json")
