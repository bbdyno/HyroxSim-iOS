"""Validation gates. A failing gate must stop the pipeline before it writes."""

from __future__ import annotations

from collections import OrderedDict

from . import config
from .mathutil import interp_series, round_half_up


class Gate(object):
    def __init__(self, name, ok, detail, failures=None, warning=False):
        self.name = name
        self.ok = bool(ok)
        self.detail = detail
        self.failures = failures or []
        self.warning = warning

    @property
    def status(self):
        if self.ok:
            return "PASS"
        return "WARN" if self.warning else "FAIL"

    def __repr__(self):
        return "<Gate {n} {s}>".format(n=self.name, s=self.status)


def _fmt(failures, limit=6):
    shown = failures[:limit]
    extra = "" if len(failures) <= limit else " (+{n}건)".format(n=len(failures) - limit)
    return "; ".join(shown) + extra


# --- v3 gates ----------------------------------------------------------------


def gate_divisions(payload):
    missing = [d for d in config.DIVISION_MAP.values() if d not in payload.get("divisions", {})]
    extra = [d for d in payload.get("divisions", {}) if d not in config.DIVISION_MAP.values()]
    failures = []
    if missing:
        failures.append("누락: {m}".format(m=missing))
    if extra:
        failures.append("예상 밖 디비전: {e}".format(e=extra))
    return Gate(
        "divisions_present",
        not failures,
        "{n}/9 디비전".format(n=len(payload.get("divisions", {}))),
        failures,
    )


def gate_bucket_ladder(payload):
    failures = []
    total_buckets = 0
    for division, data in payload["divisions"].items():
        buckets = data["buckets"]
        total_buckets += len(buckets)
        if not buckets:
            failures.append("{d}: 버킷 없음".format(d=division))
            continue
        for index, bucket in enumerate(buckets):
            if bucket["hi_min"] <= bucket["lo_min"]:
                failures.append(
                    "{d}: {lo}-{hi} 구간이 뒤집힘".format(
                        d=division, lo=bucket["lo_min"], hi=bucket["hi_min"]
                    )
                )
            if index and buckets[index - 1]["hi_min"] != bucket["lo_min"]:
                failures.append(
                    "{d}: {a}분과 {b}분 사이 불연속".format(
                        d=division, a=buckets[index - 1]["hi_min"], b=bucket["lo_min"]
                    )
                )
            if index and buckets[index - 1]["lo_min"] >= bucket["lo_min"]:
                failures.append("{d}: 버킷 정렬 오류 {lo}".format(d=division, lo=bucket["lo_min"]))
            if bucket["count"] < config.MIN_CELL_N:
                failures.append(
                    "{d}: {lo}분 버킷 표본 {c}명 < 최소 셀 {m}".format(
                        d=division, lo=bucket["lo_min"], c=bucket["count"], m=config.MIN_CELL_N
                    )
                )
    return Gate(
        "bucket_ladder",
        not failures,
        "총 {n}개 버킷 (연속성/정렬/최소 셀 {m}명)".format(n=total_buckets, m=config.MIN_CELL_N),
        failures,
    )


def gate_pct_range(payload):
    failures = []
    for division, data in payload["divisions"].items():
        previous = None
        for bucket in data["buckets"]:
            lo, hi = bucket["pct_range"]
            if not (0.0 <= lo <= 100.0 and 0.0 <= hi <= 100.0):
                failures.append("{d}: {lo}분 pct_range 범위 이탈 {r}".format(d=division, lo=bucket["lo_min"], r=[lo, hi]))
            if lo > hi:
                failures.append("{d}: {lo}분 pct_range 역전 {r}".format(d=division, lo=bucket["lo_min"], r=[lo, hi]))
            if previous is not None and lo < previous - 1e-9:
                failures.append(
                    "{d}: {lo}분 pct_range 비단조 ({p} -> {c})".format(
                        d=division, lo=bucket["lo_min"], p=previous, c=lo
                    )
                )
            previous = hi
        if data["buckets"]:
            first = data["buckets"][0]["pct_range"][0]
            last = data["buckets"][-1]["pct_range"][1]
            if abs(first) > 0.05:
                failures.append("{d}: 첫 버킷이 {f}% 에서 시작".format(d=division, f=first))
            if abs(last - 100.0) > 0.05:
                failures.append("{d}: 마지막 버킷이 {l}% 에서 끝남".format(d=division, l=last))
    return Gate("pct_range_monotonic", not failures, "0~100% 단조 증가", failures)


def gate_count_total(payload):
    failures = []
    details = []
    for division, data in payload["divisions"].items():
        counted = sum(b["count"] for b in data["buckets"])
        total = data["total_athletes"]
        diff = counted - total
        tolerance = max(config.COUNT_TOTAL_TOL_ABS, int(config.COUNT_TOTAL_TOL_RATIO * total))
        details.append("{d}:{diff:+d}".format(d=division, diff=diff))
        if abs(diff) > tolerance:
            failures.append(
                "{d}: count 합 {c} vs total_athletes {t} (차이 {diff:+d}, 허용 ±{tol})".format(
                    d=division, c=counted, t=total, diff=diff, tol=tolerance
                )
            )
    return Gate(
        "count_vs_total_athletes",
        not failures,
        "허용치 ±max({a}, {r:.1%}) / 차이 {d}".format(
            a=config.COUNT_TOTAL_TOL_ABS, r=config.COUNT_TOTAL_TOL_RATIO, d=" ".join(details)
        ),
        failures,
    )


def gate_field_consistency(payload):
    split_failures, station_failures, residual_failures, pace_failures = [], [], [], []
    worst_residual = 0
    for division, data in payload["divisions"].items():
        for bucket in data["buckets"]:
            if bucket["avg_run"] + bucket["avg_rox"] != bucket["avg_run_rox"]:
                split_failures.append(
                    "{d}: {lo}분 run+rox({a}) != run_rox({b})".format(
                        d=division,
                        lo=bucket["lo_min"],
                        a=bucket["avg_run"] + bucket["avg_rox"],
                        b=bucket["avg_run_rox"],
                    )
                )
            station_sum = sum(bucket["stations"].values())
            if station_sum != bucket["avg_station_total"]:
                station_failures.append(
                    "{d}: {lo}분 stations 합({a}) != avg_station_total({b})".format(
                        d=division, lo=bucket["lo_min"], a=station_sum, b=bucket["avg_station_total"]
                    )
                )
            residual = bucket["avg_run_rox"] + bucket["avg_station_total"] - bucket["avg_overall"]
            worst_residual = max(worst_residual, abs(residual))
            if abs(residual) > config.RESIDUAL_GATE_S:
                residual_failures.append(
                    "{d}: {lo}분 잔차 {r}초".format(d=division, lo=bucket["lo_min"], r=residual)
                )
            expected_pace = round_half_up(bucket["avg_run_rox"] / config.RUN_ROX_DISTANCE_KM)
            if bucket["avg_pace_8_7"] != expected_pace:
                pace_failures.append(
                    "{d}: {lo}분 pace {a} != {b}".format(
                        d=division, lo=bucket["lo_min"], a=bucket["avg_pace_8_7"], b=expected_pace
                    )
                )
    return [
        Gate("run_rox_split_exact", not split_failures, "avg_run + avg_rox == avg_run_rox", split_failures),
        Gate("station_sum_exact", not station_failures, "stations 합 == avg_station_total", station_failures),
        Gate(
            "segment_residual",
            not residual_failures,
            "|run_rox + stations - overall| 최대 {w}초 (허용 {l}초)".format(
                w=worst_residual, l=config.RESIDUAL_GATE_S
            ),
            residual_failures,
        ),
        Gate(
            "pace_8_7_derived",
            not pace_failures,
            "avg_pace_8_7 == round(avg_run_rox / {d})".format(d=config.RUN_ROX_DISTANCE_KM),
            pace_failures,
        ),
    ]


def gate_dense_monotonic(payload):
    failures = []
    checked = 0
    for division, data in payload["divisions"].items():
        dense = [b for b in data["buckets"] if b["count"] >= config.DENSE_MIN_N]
        if len(dense) < 2:
            continue
        for station in config.STATION_KEYS:
            values = [b["stations"][station] for b in dense]
            for index in range(len(values) - 1):
                checked += 1
                if values[index] > values[index + 1]:
                    failures.append(
                        "{d}.{s}: {a}분 {va}초 -> {b}분 {vb}초 역전".format(
                            d=division,
                            s=station,
                            a=dense[index]["lo_min"],
                            va=values[index],
                            b=dense[index + 1]["lo_min"],
                            vb=values[index + 1],
                        )
                    )
    return Gate(
        "dense_station_monotonic",
        not failures,
        "표본 {n}명 이상 인접쌍 {c}건 검사".format(n=config.DENSE_MIN_N, c=checked),
        failures,
    )


def _sled_percentile_series(data, station):
    xs, ys = [], []
    for bucket in data["buckets"]:
        xs.append((bucket["pct_range"][0] + bucket["pct_range"][1]) / 2.0)
        ys.append(bucket["stations"][station])
    return xs, ys


def gate_cross_division_percentile(payload):
    failures, warnings = [], []
    lo, hi = config.CROSS_DIVISION_BAND
    grid = []
    p = lo
    while p <= hi + 1e-9:
        grid.append(p)
        p += config.CROSS_DIVISION_STEP
    pairs = (("menOpenSingle", "menProSingle"), ("womenOpenSingle", "womenProSingle"))
    for open_key, pro_key in pairs:
        open_data = payload["divisions"][open_key]
        pro_data = payload["divisions"][pro_key]
        for station in config.SLED_KEYS:
            oxs, oys = _sled_percentile_series(open_data, station)
            pxs, pys = _sled_percentile_series(pro_data, station)
            for percentile in grid:
                open_value = interp_series(oxs, oys, percentile)
                pro_value = interp_series(pxs, pys, percentile)
                if pro_value < open_value - config.CROSS_DIVISION_TOL_S:
                    failures.append(
                        "p{p:g} {s}: Pro {pv:.0f}초 < Open {ov:.0f}초".format(
                            p=percentile, s=station, pv=pro_value, ov=open_value
                        )
                    )
            for percentile in (1.0, 5.0, 10.0, 99.0):
                open_value = interp_series(oxs, oys, percentile)
                pro_value = interp_series(pxs, pys, percentile)
                if pro_value < open_value - config.CROSS_DIVISION_TOL_S:
                    warnings.append(
                        "p{p:g} {s}: Pro {pv:.0f}초 < Open {ov:.0f}초".format(
                            p=percentile, s=station, pv=pro_value, ov=open_value
                        )
                    )
    gates = [
        Gate(
            "cross_division_sled_percentile",
            not failures,
            "p{a:g}~p{b:g} 구간에서 Pro 썰매 >= Open 썰매 (허용 {t}초)".format(
                a=lo, b=hi, t=config.CROSS_DIVISION_TOL_S
            ),
            failures,
        ),
        Gate(
            "cross_division_sled_tails",
            not warnings,
            "구간 밖(p1/p5/p10/p99) 참고 검사 — Open 상위권에 엘리트가 섞여 경고만",
            warnings,
            warning=True,
        ),
    ]
    return gates


def gate_cross_division_bucket(payload):
    """Mirrors the shipped Swift test: same goal bucket, Open sled <= Pro sled."""
    failures = []
    checked = 0
    for open_key, pro_key in (("menOpenSingle", "menProSingle"), ("womenOpenSingle", "womenProSingle")):
        open_map = {
            b["lo_min"]: b for b in payload["divisions"][open_key]["buckets"] if b["count"] >= config.DENSE_MIN_N
        }
        pro_map = {
            b["lo_min"]: b for b in payload["divisions"][pro_key]["buckets"] if b["count"] >= config.DENSE_MIN_N
        }
        shared = sorted(set(open_map) & set(pro_map))
        if len(shared) <= 10 and open_key == "menOpenSingle":
            failures.append("{o}/{p}: 공통 dense 버킷 {n}개뿐".format(o=open_key, p=pro_key, n=len(shared)))
        for lo_min in shared:
            for station in config.SLED_KEYS:
                checked += 1
                open_value = open_map[lo_min]["stations"][station]
                pro_value = pro_map[lo_min]["stations"][station]
                if open_value > pro_value:
                    failures.append(
                        "{o}.{s} {lo}분: Open {ov}초 > Pro {pv}초".format(
                            o=open_key, s=station, lo=lo_min, ov=open_value, pv=pro_value
                        )
                    )
    return Gate(
        "cross_division_sled_same_bucket",
        not failures,
        "동일 목표 버킷 비교 {c}건 (앱 XCTest 와 동일 규칙)".format(c=checked),
        failures,
    )


def validate_v3(payload):
    gates = [gate_divisions(payload), gate_bucket_ladder(payload), gate_pct_range(payload), gate_count_total(payload)]
    gates.extend(gate_field_consistency(payload))
    gates.append(gate_dense_monotonic(payload))
    gates.extend(gate_cross_division_percentile(payload))
    gates.append(gate_cross_division_bucket(payload))
    return gates


# --- v4 gates ----------------------------------------------------------------


def validate_v4(payloads):
    increasing_failures, sum_failures, type_failures, grid_failures, age_failures = [], [], [], [], []
    for division, payload in payloads.items():
        grid = payload["grid_p"]
        if grid != list(config.GRID_P):
            grid_failures.append("{d}: grid_p 불일치".format(d=division))
        overall = payload["overall_s"]
        if len(overall) != len(grid):
            grid_failures.append("{d}: overall_s 길이 {a} != grid {b}".format(d=division, a=len(overall), b=len(grid)))
        for index in range(len(overall) - 1):
            if overall[index] >= overall[index + 1]:
                increasing_failures.append(
                    "{d}: p{a:g} {va}s >= p{b:g} {vb}s".format(
                        d=division, a=grid[index], va=overall[index], b=grid[index + 1], vb=overall[index + 1]
                    )
                )
        components = [payload["components"]["run_rox_s"]] + [
            payload["components"]["stations_s"][key] for key in config.STATION_KEYS
        ]
        for index in range(len(overall)):
            values = [series[index] for series in components]
            if any(not isinstance(v, int) for v in values) or not isinstance(overall[index], int):
                type_failures.append("{d}: p{p:g} 정수 아님".format(d=division, p=grid[index]))
            if sum(values) != overall[index]:
                sum_failures.append(
                    "{d}: p{p:g} 성분 합 {a} != overall {b}".format(
                        d=division, p=grid[index], a=sum(values), b=overall[index]
                    )
                )
        for group in payload["age_groups"]:
            if group["n"] < config.AGE_GROUP_MIN_N:
                age_failures.append("{d}: {g} 표본 {n}명".format(d=division, g=group["age_group"], n=group["n"]))
            series = group["overall_s"]
            for index in range(len(series) - 1):
                if series[index] >= series[index + 1]:
                    age_failures.append(
                        "{d}: {g} p{p:g} 비단조".format(d=division, g=group["age_group"], p=group["grid_p"][index])
                    )
    return [
        Gate("v4_grid", not grid_failures, "grid_p {n}포인트".format(n=len(config.GRID_P)), grid_failures),
        Gate("v4_overall_increasing", not increasing_failures, "overall_s 순증가", increasing_failures),
        Gate("v4_component_sum", not sum_failures, "run_rox + 8 스테이션 == overall_s", sum_failures),
        Gate("v4_integer_fields", not type_failures, "모든 값 정수", type_failures),
        Gate(
            "v4_age_groups",
            not age_failures,
            "표본 {n}명 이상 연령대만 / 순증가".format(n=config.AGE_GROUP_MIN_N),
            age_failures,
        ),
    ]


def summarize(gates):
    failed = [g for g in gates if not g.ok and not g.warning]
    warned = [g for g in gates if not g.ok and g.warning]
    return OrderedDict(
        [
            ("total", len(gates)),
            ("passed", len([g for g in gates if g.ok])),
            ("failed", len(failed)),
            ("warnings", len(warned)),
        ]
    )


def render(gates):
    lines = []
    for gate in gates:
        lines.append("  [{s}] {n}: {d}".format(s=gate.status, n=gate.name, d=gate.detail))
        if gate.failures:
            lines.append("         -> {f}".format(f=_fmt(gate.failures)))
    return "\n".join(lines)
