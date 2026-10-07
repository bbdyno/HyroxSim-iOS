#!/usr/bin/env python3
"""HYROX 기록 데이터 ETL — 공개 planner JSON -> 앱 번들(v3) + 퍼센타일 데이터셋(v4).

사용 예:
    python3 tools/pace-data/build_pace_data.py              # 내려받아 재생성
    python3 tools/pace-data/build_pace_data.py --dry-run    # 검증만, 파일 쓰기 없음
    python3 tools/pace-data/build_pace_data.py --offline    # 캐시만 사용
    python3 tools/pace-data/build_pace_data.py --verify     # 커밋된 산출물과 재현 결과 비교

검증 게이트가 하나라도 실패하면 아무것도 쓰지 않고 종료 코드 1 로 끝난다.
표준 라이브러리만 사용한다 (urllib 포함).
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from paceetl import clean, config, fetch, report, v3, v4, validate  # noqa: E402


def make_logger(quiet):
    def log(message=""):
        if not quiet:
            print(message)

    return log


def build_everything(args, log):
    """Fetch + clean + build. Returns a dict with every artefact in memory."""
    log("== 1. 소스 수집 ({m})".format(m="offline" if args.offline else "online"))
    fetcher = fetch.Fetcher(cache_dir=args.cache_dir, offline=args.offline, timeout=args.timeout, log=log)
    raw = fetch.fetch_all(fetcher)
    log(
        "  다운로드 {d}건 / 캐시 {c}건, {b:.1f} MB".format(
            d=fetcher.stats["downloaded"], c=fetcher.stats["cached"], b=fetcher.stats["bytes"] / 1e6
        )
    )
    for slug in config.EXCLUDED_SLUGS:
        log("  제외(앱에 없는 디비전): {s}".format(s=slug))

    log("")
    log("== 2. 정제")
    reference, created = v3.load_legacy_reference(bundle_path=args.bundle, log=log)
    if created:
        log("  (현재 번들에서 legacy 값을 1회 추출했습니다)")
    cleaned = {}
    for slug, division in config.DIVISION_MAP.items():
        buckets, cleaning = clean.clean_division(raw["divisions"][slug], division, log)
        cleaned[division] = {"buckets": buckets, "cleaning": cleaning}

    coverage = v3.build_coverage(raw, cleaned, log)
    dataset_version = v3.dataset_version_from(raw, args.dataset_version)
    log("  dataset_version = {v} (업스트림 생성일 기준)".format(v=dataset_version))

    log("")
    log("== 3. v3 번들 생성")
    v3_payload = v3.build_v3(raw, cleaned, reference, coverage, dataset_version)
    v3_bytes = v3.dumps_v3(v3_payload).encode("utf-8")
    log("  {p} ({b:,} bytes)".format(p=config.rel(config.V3_OUTPUT_PATH), b=len(v3_bytes)))

    log("")
    log("== 4. v4 퍼센타일 데이터 생성")
    v4_payloads, v4_files = {}, []
    for slug, division in config.DIVISION_MAP.items():
        payload = v4.build_division(
            raw["divisions"][slug], cleaned[division], division, slug, coverage, dataset_version, log
        )
        v4_payloads[division] = payload
        name = v4.v4_relative_name(dataset_version, division)
        v4_files.append((name, v4.dumps(payload).encode("utf-8")))
    manifest = v4.build_manifest(v4_files, dataset_version, coverage)
    manifest_bytes = v4.dumps_manifest(manifest).encode("utf-8")

    return {
        "raw": raw,
        "cleaned": cleaned,
        "coverage": coverage,
        "dataset_version": dataset_version,
        "v3_payload": v3_payload,
        "v3_bytes": v3_bytes,
        "v4_payloads": v4_payloads,
        "v4_files": v4_files,
        "manifest": manifest,
        "manifest_bytes": manifest_bytes,
    }


def write_outputs(built, args, log):
    written = []
    v3_path = args.bundle
    os.makedirs(os.path.dirname(v3_path), exist_ok=True)
    with open(v3_path, "wb") as fh:
        fh.write(built["v3_bytes"])
    written.append(v3_path)

    version_dir = os.path.join(config.V4_DIR, built["dataset_version"])
    os.makedirs(version_dir, exist_ok=True)
    expected = set()
    for name, payload in built["v4_files"]:
        path = os.path.join(config.DOCS_PACE_DIR, name)
        expected.add(os.path.basename(path))
        with open(path, "wb") as fh:
            fh.write(payload)
        written.append(path)
    for stale in sorted(os.listdir(version_dir)):
        if stale.endswith(".json") and stale not in expected:
            os.remove(os.path.join(version_dir, stale))
            log("  제거(더 이상 생성되지 않는 파일): {p}".format(p=config.rel(os.path.join(version_dir, stale))))

    with open(config.MANIFEST_PATH, "wb") as fh:
        fh.write(built["manifest_bytes"])
    written.append(config.MANIFEST_PATH)
    return written


def verify_outputs(built, args, log):
    """Compare the rebuilt artefacts with what is on disk."""
    problems = []
    checks = [(args.bundle, built["v3_bytes"])]
    for name, payload in built["v4_files"]:
        checks.append((os.path.join(config.DOCS_PACE_DIR, name), payload))
    checks.append((config.MANIFEST_PATH, built["manifest_bytes"]))

    for path, payload in checks:
        if not os.path.exists(path):
            problems.append("없음: {p}".format(p=config.rel(path)))
            continue
        with open(path, "rb") as fh:
            on_disk = fh.read()
        if on_disk != payload:
            problems.append(
                "불일치: {p} (디스크 {a:,}B / 재현 {b:,}B)".format(
                    p=config.rel(path), a=len(on_disk), b=len(payload)
                )
            )

    if os.path.exists(config.MANIFEST_PATH):
        with open(config.MANIFEST_PATH, "r", encoding="utf-8") as fh:
            manifest = json.load(fh)
        for entry in manifest.get("files", []):
            path = os.path.join(config.DOCS_PACE_DIR, entry["name"])
            if not os.path.exists(path):
                problems.append("manifest 가 가리키는 파일 없음: {n}".format(n=entry["name"]))
                continue
            with open(path, "rb") as fh:
                data = fh.read()
            if hashlib.sha256(data).hexdigest() != entry["sha256"]:
                problems.append("manifest sha256 불일치: {n}".format(n=entry["name"]))
            if len(data) != entry["bytes"]:
                problems.append("manifest bytes 불일치: {n}".format(n=entry["name"]))
    else:
        problems.append("manifest 없음: {p}".format(p=config.rel(config.MANIFEST_PATH)))
    return problems


def main(argv=None):
    parser = argparse.ArgumentParser(
        description="HYROX 공개 기록 데이터로 pace_planner.json(v3) 과 v4 퍼센타일 데이터셋을 재생성",
    )
    parser.add_argument("--dry-run", action="store_true", help="검증까지만 하고 파일을 쓰지 않음")
    parser.add_argument("--verify", action="store_true", help="재현 결과를 커밋된 산출물과 비교 (쓰기 없음)")
    parser.add_argument("--offline", action="store_true", help="네트워크를 쓰지 않고 캐시만 사용")
    parser.add_argument("--cache-dir", default=config.CACHE_DIR, help="다운로드 캐시 경로")
    parser.add_argument("--bundle", default=config.V3_OUTPUT_PATH, help="v3 번들 출력 경로")
    parser.add_argument("--dataset-version", default=None, help="dataset_version 강제 지정 (YYYY.MM.DD)")
    parser.add_argument("--timeout", type=int, default=180, help="HTTP 타임아웃(초)")
    parser.add_argument("-q", "--quiet", action="store_true", help="진행 로그 숨김")
    args = parser.parse_args(argv)

    log = make_logger(args.quiet)
    previous = report.load_previous(args.bundle)

    try:
        built = build_everything(args, log)
    except (fetch.FetchError, RuntimeError) as exc:
        print("오류: {e}".format(e=exc), file=sys.stderr)
        return 1

    log("")
    log("== 5. 검증 게이트")
    gates = validate.validate_v3(built["v3_payload"]) + validate.validate_v4(built["v4_payloads"])
    log(validate.render(gates))
    summary = validate.summarize(gates)
    log(
        "  요약: {p}/{t} 통과, 실패 {f}, 경고 {w}".format(
            p=summary["passed"], t=summary["total"], f=summary["failed"], w=summary["warnings"]
        )
    )

    log("")
    log("== 6. 이전 번들 대비 변화")
    rows = report.compare(previous, built["v3_payload"])
    log(report.render(rows))
    for warning in report.warnings(rows):
        log("  ! p50 급변: {w}".format(w=warning))

    if summary["failed"]:
        print("", file=sys.stderr)
        print("검증 실패 {n}건 — 산출물을 쓰지 않고 종료합니다.".format(n=summary["failed"]), file=sys.stderr)
        for gate in gates:
            if not gate.ok and not gate.warning:
                print("  - {n}: {f}".format(n=gate.name, f=validate._fmt(gate.failures)), file=sys.stderr)
        return 1

    log("")
    if args.verify:
        log("== 7. 재현성 검증 (--verify)")
        problems = verify_outputs(built, args, log)
        if problems:
            print("재현 결과가 커밋된 산출물과 다릅니다:", file=sys.stderr)
            for problem in problems:
                print("  - {p}".format(p=problem), file=sys.stderr)
            return 1
        log("  모든 산출물이 재현 결과와 바이트 단위로 일치합니다.")
        return 0

    if args.dry_run:
        log("== 7. --dry-run: 쓰기 생략")
        log("  {p} ({b:,} bytes)".format(p=config.rel(args.bundle), b=len(built["v3_bytes"])))
        for name, payload in built["v4_files"]:
            log(
                "  {p} ({b:,} bytes)".format(
                    p=config.rel(os.path.join(config.DOCS_PACE_DIR, name)), b=len(payload)
                )
            )
        log(
            "  {p} ({b:,} bytes)".format(
                p=config.rel(config.MANIFEST_PATH), b=len(built["manifest_bytes"])
            )
        )
        return 0

    log("== 7. 산출물 기록")
    for path in write_outputs(built, args, log):
        log("  wrote {p} ({b:,} bytes)".format(p=config.rel(path), b=os.path.getsize(path)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
