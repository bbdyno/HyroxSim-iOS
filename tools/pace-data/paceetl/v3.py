"""Build the v3 bundle payload (Targets/HyroxCore/.../pace_planner.json).

The public planner data has no Run vs RoxZone split and no per-run splits, so
two fields are carried over from the 2026-04-17 snapshot that used to ship:

* ``avg_run`` / ``avg_rox`` - split with a rox-share curve interpolated from
  the snapshot's dense buckets (``avg_rox / avg_run_rox`` by finish time).
* ``run_ratio_table`` - copied verbatim.

Both are frozen in ``tools/pace-data/reference/legacy_v3_reference.json`` so
re-running the pipeline never depends on the file it is about to overwrite.
"""

from __future__ import annotations

import json
import os
from collections import OrderedDict

from . import config
from .mathutil import interp_series, round_half_up

ROX_FRACTION_FLOOR = 0.10
ROX_FRACTION_CEIL = 0.25


# --- frozen legacy reference -------------------------------------------------


def extract_legacy_reference(bundle_path):
    """Read the shipped v3 bundle and distil the two legacy-only pieces."""
    with open(bundle_path, "r", encoding="utf-8") as fh:
        legacy = json.load(fh)
    fractions = OrderedDict()
    for division, payload in legacy.get("divisions", {}).items():
        points = []
        for bucket in payload.get("buckets", []):
            if bucket.get("count", 0) < config.DENSE_MIN_N:
                continue
            run_rox = bucket.get("avg_run_rox") or 0
            if run_rox <= 0:
                continue
            mid = (bucket["lo_min"] + bucket["hi_min"]) / 2.0
            points.append([mid, round(bucket["avg_rox"] / float(run_rox), 5)])
        points.sort(key=lambda p: p[0])
        if points:
            fractions[division] = points
    return OrderedDict(
        [
            (
                "source",
                OrderedDict(
                    [
                        ("file", config.rel(bundle_path)),
                        ("schema_version", legacy.get("schema_version")),
                        ("updated_at", legacy.get("updated_at")),
                        ("source", legacy.get("source")),
                    ]
                ),
            ),
            (
                "note",
                "공개 데이터에 없는 두 항목(Run/RoxZone 분리 비율, run_ratio_table)을 "
                "2026-04-17 스냅샷에서 고정한 파일. 파이프라인 입력이므로 삭제/수정하지 말 것.",
            ),
            ("dense_min_n", config.DENSE_MIN_N),
            (
                "rox_fraction_method",
                "표본 {n}명 이상 버킷의 avg_rox/avg_run_rox 를 버킷 중앙 시간(분) 축에서 "
                "선형 보간, 양 끝은 상수 외삽".format(n=config.DENSE_MIN_N),
            ),
            ("rox_fraction", fractions),
            ("run_ratio_table", legacy.get("run_ratio_table", [])),
        ]
    )


def load_legacy_reference(reference_path=None, bundle_path=None, log=print):
    """Load the frozen reference, creating it once from the shipped bundle."""
    reference_path = reference_path or config.LEGACY_REFERENCE_PATH
    bundle_path = bundle_path or config.V3_OUTPUT_PATH
    if os.path.exists(reference_path):
        with open(reference_path, "r", encoding="utf-8") as fh:
            return json.load(fh), False
    if not os.path.exists(bundle_path):
        raise RuntimeError(
            "legacy reference 도 번들 파일도 없습니다: {r}".format(r=config.rel(reference_path))
        )
    reference = extract_legacy_reference(bundle_path)
    os.makedirs(os.path.dirname(reference_path), exist_ok=True)
    with open(reference_path, "w", encoding="utf-8") as fh:
        json.dump(reference, fh, ensure_ascii=False, indent=1, sort_keys=False)
        fh.write("\n")
    log("  legacy reference 생성: {p}".format(p=config.rel(reference_path)))
    return reference, True


def rox_fraction_for(reference, division, mid_min):
    points = reference.get("rox_fraction", {}).get(division)
    if not points:
        pooled = []
        for series in reference.get("rox_fraction", {}).values():
            pooled.extend(series)
        pooled.sort(key=lambda p: p[0])
        points = pooled
    if not points:
        return 0.13
    xs = [p[0] for p in points]
    ys = [p[1] for p in points]
    value = interp_series(xs, ys, mid_min)
    return min(ROX_FRACTION_CEIL, max(ROX_FRACTION_FLOOR, value))


# --- bucket assembly ---------------------------------------------------------


def finalize_buckets(buckets, division, reference):
    """Float working buckets -> the 11 integer fields the app decodes."""
    total_counted = sum(b.count for b in buckets)
    out = []
    cumulative = 0
    for bucket in buckets:
        pct_lo = 100.0 * cumulative / total_counted if total_counted else 0.0
        cumulative += bucket.count
        pct_hi = 100.0 * cumulative / total_counted if total_counted else 0.0

        avg_overall = round_half_up(bucket.avg_overall)
        avg_run_rox = round_half_up(bucket.avg_run_rox)
        # Round every station independently: round-half-up is monotone, so a
        # station that never decreases across the float ladder can never
        # decrease across the integer one either. avg_station_total is then the
        # exact sum of the published parts.
        station_ints = [round_half_up(bucket.stations[key]) for key in config.STATION_KEYS]
        avg_station_total = sum(station_ints)

        fraction = rox_fraction_for(reference, division, bucket.mid_min)
        avg_rox = round_half_up(fraction * avg_run_rox)
        avg_rox = max(1, min(avg_run_rox - 1, avg_rox))
        avg_run = avg_run_rox - avg_rox

        out.append(
            OrderedDict(
                [
                    ("lo_min", bucket.lo_min),
                    ("hi_min", bucket.hi_min),
                    ("count", bucket.count),
                    ("pct_range", [round(pct_lo, 1), round(pct_hi, 1)]),
                    ("avg_overall", avg_overall),
                    ("avg_run", avg_run),
                    ("avg_rox", avg_rox),
                    ("avg_run_rox", avg_run_rox),
                    (
                        "avg_pace_8_7",
                        round_half_up(avg_run_rox / config.RUN_ROX_DISTANCE_KM),
                    ),
                    ("avg_station_total", avg_station_total),
                    (
                        "stations",
                        OrderedDict(zip(config.STATION_KEYS, station_ints)),
                    ),
                ]
            )
        )
    return out


# --- coverage ----------------------------------------------------------------


def build_coverage(raw, cleaned, log):
    """Season / event / sample coverage derived from events_meta + divisions."""
    events_meta = raw.get("events_meta") or {}
    weekly = raw.get("weekly_index") or {}
    seasons = sorted({int(v.get("season")) for v in events_meta.values() if v.get("season")})
    years = sorted({str(name).split(" ")[0] for name in events_meta if str(name)[:4].isdigit()})

    # Only the nine divisions this pipeline publishes; relay/elite/adaptive
    # rows exist upstream but would just be noise in the shipped bundle.
    published_names = {slug.replace("_", " ") for slug in config.DIVISION_MAP}
    events_by_division = OrderedDict()
    for payload in events_meta.values():
        for name, count in (payload.get("counts") or {}).items():
            if count and name in published_names:
                events_by_division[name] = events_by_division.get(name, 0) + 1
    events_by_division = OrderedDict(
        (slug.replace("_", " "), events_by_division.get(slug.replace("_", " "), 0))
        for slug in config.DIVISION_MAP
    )

    upstream_total = 0
    published_total = 0
    for slug, division in config.DIVISION_MAP.items():
        upstream_total += int(raw["divisions"][slug].get("total_athletes", 0))
        published_total += sum(b.count for b in cleaned[division]["buckets"])

    log(
        "  coverage: 시즌 {s}, 대회 {e}개, 표본 {a:,}명".format(
            s="-".join("S{n}".format(n=n) for n in (seasons[:1] + seasons[-1:])) if seasons else "?",
            e=len(events_meta),
            a=published_total,
        )
    )
    return OrderedDict(
        [
            ("seasons", seasons),
            (
                "season_label",
                "S{a}-S{b}".format(a=seasons[0], b=seasons[-1]) if seasons else "unknown",
            ),
            ("years", [years[0], years[-1]] if years else []),
            ("events", len(events_meta)),
            ("divisions", len(config.DIVISION_MAP)),
            ("excluded_divisions", list(config.EXCLUDED_SLUGS)),
            ("athletes_upstream", upstream_total),
            ("athletes_published", published_total),
            ("upstream_version", weekly.get("version")),
            ("upstream_generated", weekly.get("generated")),
            ("events_by_division", events_by_division),
        ]
    )


def dataset_version_from(raw, override=None):
    """Dataset version follows the upstream build date, not the wall clock."""
    if override:
        return override
    generated = (raw.get("weekly_index") or {}).get("generated")
    if generated and len(generated) == 10:
        return generated.replace("-", ".")
    raise RuntimeError("weekly index 에 generated 날짜가 없어 dataset_version 을 정할 수 없습니다")


# --- top level ---------------------------------------------------------------


def build_sources():
    return [
        OrderedDict(
            [
                ("name", "planner_divisions"),
                ("url", config.BASE_URL + "/planner_divisions/<slug>.json"),
                ("used_fields", ["total_athletes", "buckets", "ageStats", "ageGroups"]),
                ("note", "5분 단위 버킷 평균과 연령대별 완주 시간 배열 (개인 식별 정보 없음)"),
            ]
        ),
        OrderedDict(
            [
                ("name", "planner_meta"),
                ("url", config.BASE_URL + "/planner_meta.json"),
                ("used_fields", ["slug", "total_athletes"]),
            ]
        ),
        OrderedDict(
            [
                ("name", "events_meta"),
                ("url", config.BASE_URL + "/events_meta.json"),
                ("used_fields", ["season", "counts"]),
                ("note", "시즌/대회 수 커버리지 산출에만 사용"),
            ]
        ),
        OrderedDict(
            [
                ("name", "weekly_index"),
                ("url", config.BASE_URL + "/weekly/index.json"),
                ("used_fields", ["version", "generated"]),
                ("note", "개인 이름(highlight.nm) 필드는 읽지도 내보내지도 않음"),
            ]
        ),
        OrderedDict(
            [
                ("name", "legacy_v3_snapshot"),
                ("path", config.rel(config.LEGACY_REFERENCE_PATH)),
                ("origin", "pace_planner.json 2026-04-17 스냅샷 (201개 대회, S6-S8)"),
                ("used_for", ["avg_run/avg_rox 분리 비율", "run_ratio_table"]),
                (
                    "method",
                    "rox 비율 = avg_rox/avg_run_rox 를 표본 {n}명 이상 버킷에서 뽑아 "
                    "버킷 중앙 시간 축으로 선형 보간(양 끝 상수 외삽) 후 신규 avg_run_rox 에 적용. "
                    "avg_run = avg_run_rox - avg_rox 로 두어 합이 항상 정확히 일치.".format(
                        n=config.DENSE_MIN_N
                    ),
                ),
                (
                    "caveat",
                    "run_ratio_table 은 Run 1-8 개별 스플릿이 공개 데이터에 없어 갱신하지 못함 "
                    "(S6-S8 기준값 유지).",
                ),
            ]
        ),
    ]


def build_v3(raw, cleaned, reference, coverage, dataset_version):
    divisions = OrderedDict()
    for slug, division in config.DIVISION_MAP.items():
        buckets = finalize_buckets(cleaned[division]["buckets"], division, reference)
        divisions[division] = OrderedDict(
            [
                ("total_athletes", int(raw["divisions"][slug].get("total_athletes", 0))),
                ("buckets", buckets),
            ]
        )

    cleaning_summary = OrderedDict()
    for division in config.DIVISION_MAP.values():
        cleaning_summary[division] = cleaned[division]["cleaning"]["counts"]

    return OrderedDict(
        [
            ("schema_version", config.V3_SCHEMA_VERSION),
            ("updated_at", dataset_version.replace(".", "-")),
            ("dataset_version", dataset_version),
            (
                "source",
                "HYROX public planner data ({e} events, {s}) — {u}".format(
                    e=coverage["events"], s=coverage["season_label"], u=config.BASE_URL
                ),
            ),
            ("sources", build_sources()),
            ("coverage", coverage),
            (
                "cleaning",
                OrderedDict(
                    [
                        ("min_cell_n", config.MIN_CELL_N),
                        ("dense_min_n", config.DENSE_MIN_N),
                        (
                            "note",
                            "규칙 전문과 버킷별 감사 로그는 docs/pace/v4/{v}/<division>.json 의 "
                            "cleaning 블록 참고".format(v=dataset_version),
                        ),
                        ("summary", cleaning_summary),
                    ]
                ),
            ),
            (
                "generator",
                OrderedDict(
                    [
                        ("script", config.GENERATOR),
                        ("version", config.GENERATOR_VERSION),
                        ("command", "python3 {s}".format(s=config.GENERATOR)),
                    ]
                ),
            ),
            ("bucket_size_min", config.BUCKET_SIZE_MIN),
            ("run_ratio_table", reference.get("run_ratio_table", [])),
            ("divisions", divisions),
        ]
    )


def dumps_v3(payload):
    """Match the shipped formatting exactly: compact, no trailing newline."""
    return json.dumps(payload, ensure_ascii=False, separators=(",", ":"))
