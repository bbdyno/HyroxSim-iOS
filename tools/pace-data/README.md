# pace-data — HYROX 기록 데이터 ETL

공개된 HYROX 기록 집계 데이터를 받아 **앱 번들용 v3 페이스 데이터**와 **다음 엔진용 v4 퍼센타일
데이터셋**을 재생성하는 파이프라인. 예전 스냅샷(2026-04-17, S6–S8 201개 대회)은 생성 스크립트가
유실돼 재현이 불가능했고, 이 디렉터리가 그 자리를 대신한다.

- 표준 라이브러리만 사용한다(`urllib` 포함). 외부 패키지 설치 금지.
- Python 3.9 / 3.14 에서 동작을 확인했다(3.12 표준 라이브러리 범위 안에서 작성).
- 같은 업스트림 데이터면 **몇 번을 돌려도 바이트 단위로 같은 결과**가 나온다.

## 1. 실행 방법

```bash
# 최신 공개 데이터를 내려받아 산출물 재생성
python3 tools/pace-data/build_pace_data.py

# 검증까지만 하고 파일은 쓰지 않음 (변화량 리포트 확인용)
python3 tools/pace-data/build_pace_data.py --dry-run

# 네트워크 없이 캐시(.cache/)만으로 재생성
python3 tools/pace-data/build_pace_data.py --offline

# 커밋된 산출물이 정말 이 스크립트로 재현되는지 검사 (CI 용, 쓰기 없음)
python3 tools/pace-data/build_pace_data.py --verify --offline
```

기타 옵션: `--dataset-version YYYY.MM.DD`(버전 강제), `--cache-dir`, `--bundle`(v3 출력 경로),
`--timeout`, `-q`.

**검증 게이트가 하나라도 실패하면 아무 파일도 쓰지 않고 종료 코드 1 로 끝난다.**
`--verify` 는 재현 결과가 디스크의 산출물과 다르거나 manifest 의 sha256 이 어긋나도 1 로 끝난다.

### 산출물

| 경로 | 내용 |
|---|---|
| `Targets/HyroxCore/Resources/PaceReference/pace_planner.json` | 앱이 읽는 v3 번들(스키마 불변) |
| `docs/pace/v4/<dataset_version>/<division>.json` | 디비전별 퍼센타일 데이터셋(v4) |
| `docs/pace/manifest.json` | v4 파일 목록 + sha256 + 크기 + 커버리지 |
| `tools/pace-data/reference/legacy_v3_reference.json` | 공개 데이터에 없는 값을 고정해 둔 **입력** 파일 |
| `tools/pace-data/.cache/` | 원본 다운로드 캐시(gitignore) |

`dataset_version` 은 실행 시각이 아니라 **업스트림 생성일**(`weekly/index.json` 의 `generated`)에서
따온다. 그래야 같은 소스로 며칠 뒤에 돌려도 같은 파일이 나온다.

### 파일 구성

```
tools/pace-data/
  build_pace_data.py     # CLI 진입점
  paceetl/
    config.py            # 엔드포인트, 디비전/스테이션 매핑, 임계값, 경로
    fetch.py             # 다운로드 + 캐시(offline 지원)
    mathutil.py          # 분위수(type 7), isotonic(PAVA), 최대 잔여 배분
    clean.py             # 정제 규칙 R0~R6
    v3.py                # 앱 번들 조립 + 커버리지
    v4.py                # 퍼센타일 데이터셋 + manifest
    validate.py          # 검증 게이트
    report.py            # 이전 번들 대비 p50 변화 리포트
  reference/             # 고정 입력(아래 참고)
```

## 2. 데이터 출처와 주의사항

베이스 URL: `https://pub-13135300967546fd87973feae3df0bdc.r2.dev`

| 엔드포인트 | 쓰는 필드 |
|---|---|
| `/planner_meta.json` | 디비전 목록, `total_athletes` |
| `/planner_divisions/<slug>.json` | `total_athletes`, `buckets`, `ageStats`, `ageGroups` |
| `/events_meta.json` | `season`, `counts` (시즌·대회 수 커버리지) |
| `/weekly/index.json` | `version`, `generated` **만** |

### 반드시 지킬 것

- **`results.hyrox.com` 스크레이핑 금지.** robots.txt 로 봇을 차단한다. 이 파이프라인은 위 정적
  JSON 외에는 어떤 호스트에도 접속하지 않는다(`paceetl/config.py` 의 `BASE_URL` 하나뿐).
- **개인 식별 정보 금지.** `/weekly/index.json` 에는 개인 이름(`highlight.nm`)이 들어 있다. 이
  파이프라인은 `version`/`generated` 만 읽고 산출물에 절대 담지 않는다. 새 필드를 쓸 때도 같은 기준을
  지킬 것.
- **최소 셀 30명.** 표본 30명 미만 버킷은 인접 버킷과 병합해 개인이 특정되지 않게 한다(규칙 R3).
  `ageStats` 는 이름 없는 완주 시간 배열이지만, v4 의 연령대 곡선도 표본 200명 이상만 낸다.
- **라이선스.** 공개 엔드포인트지만 명시적 라이선스 문구는 확인되지 않았다. 소유자가 "오픈 데이터로
  사용 가능"으로 판단해 도입했다. 출처 표기를 유지하고(각 산출물의 `sources` 블록), 원본 전체를 그대로
  재배포하지 말 것(이 저장소가 배포하는 것은 집계·정제 결과물뿐이다).

### 갱신 주기

업스트림은 주 단위로 갱신된다(`weekly/index.json`). 실제 반영 기준:

- **시즌 종료 후 / 분기 1회**를 권장. 대회가 대량으로 추가되면 p50 이 눈에 띄게 움직인다.
- 갱신 시 `--dry-run` 으로 **6번 리포트(이전 번들 대비 p50 변화)** 를 먼저 확인한다. 디비전별
  변화가 5% 를 넘으면 `<= 급변 경고` 가 붙는다. 경고가 뜨면 업스트림 디비전 구성이 바뀐 건 아닌지
  확인하고 나서 반영할 것.
- 반영 후에는 `xcodebuild test -scheme HyroxSim` 으로 `PacePlannerTests` 를 돌려본다(이 데이터에
  직접 걸리는 XCTest 가 있다).

## 3. 정제 규칙

업스트림 버킷은 그대로 쓸 수 없다. 스테이션 스플릿이 있는 선수와 없는 선수의 평균 모집단이 달라
성분 합이 완주 시간과 어긋나고, 일부 버킷에는 오염된 썰매 값이 남아 있다. 규칙은 모두 결정적이고,
버킷 단위 감사 로그가 `docs/pace/v4/.../<division>.json` 의 `cleaning` 블록에 그대로 들어간다.

| 규칙 | 내용 |
|---|---|
| R0 | `count<=0` 이거나 스테이션 스플릿이 없는 버킷 제외 |
| R1 | `\|run_rox + stations − overall\| > overall × 5%` 인 버킷 제외(업스트림 스플릿이 망가진 구간) |
| R2 | 표본 250명 이상 버킷에서 **양 이웃보다 10초 넘게 튀는** 스테이션 값을 이웃 선형보간으로 교체 |
| R3 | 표본 **30명 미만** 버킷을 인접 버킷과 가중 병합(작은 쪽 이웃 우선) |
| R4 | 병합 후 남은 구간 공백을 이어 붙임(범위 라벨만 변경) |
| R5 | 잔차가 15초를 넘는 버킷의 `run_rox`/스테이션을 비례 조정해 `avg_overall` 에 맞춤 |
| R6 | 표본 250명 이상 구간의 스테이션 시간을 가중 isotonic 회귀(PAVA)로 단조화 |

R6 를 마지막에 두는 이유: R5 가 버킷마다 다른 배율을 적용하기 때문에 순서를 바꾸면 R6 가 없앤 흔들림이
되살아난다. 이후 정수화는 스테이션별 **round-half-up**(단조 함수)으로 하고 `avg_station_total` 을 그
합으로 두기 때문에, 실수 사다리에서 단조면 정수 사다리에서도 단조다.

### 공개 데이터에 없어 스냅샷에서 가져오는 값

`reference/legacy_v3_reference.json` (2026-04-17 스냅샷에서 1회 추출, **삭제/수정 금지**):

- **`avg_run` / `avg_rox` 분리 비율** — 공개 데이터에는 `avg_run_rox`(Run+RoxZone 합)만 있다.
  스냅샷의 표본 250명 이상 버킷에서 `avg_rox / avg_run_rox` 를 뽑아 버킷 중앙 시간(분) 축으로 선형
  보간(양 끝 상수 외삽)해 새 `avg_run_rox` 에 적용한다. `avg_run = avg_run_rox − avg_rox` 로 두어
  **합이 항상 정확히 일치**한다.
- **`run_ratio_table`** — Run 1–8 개별 스플릿이 공개 데이터에 없어 스냅샷 값(S6–S8)을 그대로 유지한다.

이 파일을 파이프라인 입력으로 고정해 둔 이유는, 덮어쓸 대상 파일(`pace_planner.json`)을 입력으로
삼으면 재실행마다 값이 조금씩 흘러가기 때문이다. 파일이 없으면 현재 번들에서 1회 자동 추출하는데,
이미 새 데이터로 덮어쓴 뒤라면 **v3 재생성 이전 번들**(git 이력)에서 만들어야 한다.

## 4. 검증 게이트

v3 (앱 번들):

| 게이트 | 기준 |
|---|---|
| `divisions_present` | 9개 디비전 존재(ADAPTIVE 2개는 앱에 없어 제외, 로그만) |
| `bucket_ladder` | 정렬·연속성(`hi_min == 다음 lo_min`)·최소 셀 30명 |
| `pct_range_monotonic` | 0~100% 범위, 단조 증가, 첫 0% / 끝 100% |
| `count_vs_total_athletes` | `count` 합과 `total_athletes` 차이 ≤ max(60명, 0.1%) |
| `run_rox_split_exact` | `avg_run + avg_rox == avg_run_rox` (정확히) |
| `station_sum_exact` | `stations` 합 `== avg_station_total` (정확히) |
| `segment_residual` | `\|avg_run_rox + avg_station_total − avg_overall\| ≤ 30초` |
| `pace_8_7_derived` | `avg_pace_8_7 == round(avg_run_rox / 8.7)` |
| `dense_station_monotonic` | 표본 250명 이상 인접 버킷 쌍에서 8종 스테이션 시간 역전 없음 |
| `cross_division_sled_percentile` | p25~p95 에서 Pro 썰매 ≥ Open 썰매(허용 3초) |
| `cross_division_sled_same_bucket` | 같은 목표 버킷에서 Open 썰매 ≤ Pro 썰매(앱 XCTest 와 동일 규칙) |
| `cross_division_sled_tails` | p1/p5/p10/p99 는 **경고만** — Open 상위권에 엘리트가 섞여 실제로 역전이 난다 |

v4: `v4_grid`, `v4_overall_increasing`(순증가), `v4_component_sum`(성분 합 == `overall_s`),
`v4_integer_fields`, `v4_age_groups`(표본 200명 이상 · 순증가).

`count` 합이 `total_athletes` 에 미치지 못하는 건 업스트림에서 이미 몇 명이 버킷에 안 들어가 있고(디비전당
1~10명), 여기에 R1 로 제외한 표본이 더해지기 때문이다. `pct_range` 의 분모는 발행된 `count` 합이라 항상
100% 로 끝난다.

### 오염 버킷 패치 스크립트는 삭제됐다

예전 `tools/pace-data/patch_contaminated_buckets.py` 는 오염된 썰매 버킷 3곳을 수동 목록으로 보정하고
`patched_note` 를 남기던 임시 스크립트였다. 새 파이프라인의 **R2(스파이크 자동 탐지·보정)** 와
**R6(단조화)** 가 같은 일을 소스 단계에서 일반화해 처리하고, `dense_station_monotonic` 게이트가 통과하는
것을 확인했으므로 **스크립트를 삭제했다**. 새 번들에는 `patched_note` 키도 없다.

> 참고: 업스트림에는 여전히 `menOpenSingle` 65–70분 버킷의 썰매 오염(push 200s / pull 279s, 이웃 140·157 /
> 206·245)이 남아 있다. 지금은 R2 가 매번 자동으로 잡아낸다.

## 5. 산출물 스키마

### v3 (`pace_planner.json`)

앱의 `PacePlannerData` 가 디코드하는 스키마는 그대로다. 상단 메타만 정비했다:
`schema_version`, `updated_at`, `dataset_version`, `source`(URL 포함), `sources`(엔드포인트별 출처와
분리 비율 산출 방법), `coverage`(시즌·대회 수·표본 수), `cleaning`(임계값 + 디비전별 요약),
`generator`(스크립트 경로·버전), `bucket_size_min`, `run_ratio_table`, `divisions`.
버킷은 11개 필드 전부 정수다: `lo_min, hi_min, count, pct_range, avg_overall, avg_run, avg_rox,
avg_run_rox, avg_pace_8_7, avg_station_total, stations`.

### v4 (`docs/pace/v4/<dataset_version>/<division>.json`)

- `grid_p` — 0.1, 0.5, 1, 2, …, 98, 99, 99.5, 99.9 (103 포인트)
- `overall_s` — `ageStats` 전체를 합친 경험적 분위수(type 7), 정수, 순증가
- `components.run_rox_s`, `components.stations_s{8종}` — 정제된 버킷을 퍼센타일 좌표로 보간 →
  성분별 isotonic → `overall_s` 에 비례 스케일 → 최대 잔여(Hare) 방식 정수 배분.
  **모든 퍼센타일에서 `run_rox_s + 스테이션 8종 == overall_s`.**
- `age_groups` — 표본 200명 이상 연령대만, 5pp 간격(`grid_p` 5~95)
- `coverage`, `sources`, `cleaning`(규칙 설명 + 제외/보정 건수와 항목), `min_cell_n`, `method`

`method.component_scale` 은 버킷 기반 성분 합을 `ageStats` 기반 `overall_s` 에 맞출 때 쓴 배율의
최소/최대다. 1.0 에서 크게 벗어나면 두 소스가 어긋난 것이니 확인할 것.

`docs/pace/manifest.json` 은 `{manifest_version, published_at, dataset_version, schema_version,
generator, files:[{name, sha256, bytes}], coverage}` 구조다. 새 `dataset_version` 으로 생성하면 이전
버전 폴더는 그대로 남고 manifest 만 최신 버전을 가리킨다.

## 6. 알려진 한계

- **Run 1–8 개별 스플릿이 없다.** 공개 데이터는 Run+RoxZone 합계만 준다. `run_ratio_table` 은 S6–S8
  스냅샷 값 그대로이고, 갱신하려면 다른 소스가 필요하다.
- **Run/RoxZone 분리는 추정이다.** 2026-04-17 스냅샷의 rox 비율 곡선을 새 데이터에 적용한 값이라,
  `avg_rox` 는 측정값이 아니라 보간값이다(합은 정확히 맞는다).
- **성분 합과 완주 시간의 미세한 불일치.** 업스트림 평균의 모집단이 항목마다 조금씩 달라 잔차가 남는다.
  15초를 넘으면 R5 가 비례 보정하고, 게이트는 30초까지 허용한다.
- **Pro/Open 썰매 역전(상위권).** p10 이하에서는 Open 필드에 섞인 엘리트 때문에 Open 썰매가 Pro 보다
  느리게 나오는 구간이 실제로 있다. 게이트는 p25~p95 만 강제하고 나머지는 경고로 남긴다.
- **더블 디비전 표본이 줄었다.** 이전 스냅샷 대비 `menProDouble`(43,586 → 34,378),
  `womenProDouble`(31,004 → 20,002)은 오히려 감소했다. 업스트림의 Pro/Open 더블 분류 기준이 달라진
  것으로 보이며, 다른 디비전은 모두 늘었다.
- **ADAPTIVE 2개 디비전은 제외한다.** 앱의 `HyroxDivision` 에 대응 케이스가 없다(로그로만 남긴다).
