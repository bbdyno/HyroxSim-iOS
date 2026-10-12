# HyroxSim Handoff

업데이트: 2026-10-12

## 개요

현재 상태: **2.0.0 (빌드 2026.10.12.1) — `release/2.0` 브랜치, main 미병합·미푸시.**
세 저장소(iOS · Android · Garmin) 모두 `release/2.0` 브랜치에서 작업했다.
이전 기록: `2026-10-07.md`(1.5.0), `2026-09-21.md`(1.4.0).

## 2.0 에서 한 일 (iOS)

- 디자인: 코스 맵을 구간 띠로 교체. 홈·결과 = 타이밍 표, 운동 중 = 큰 숫자. 규칙은 `CLAUDE.md`.
- 구독: 무료 전환 + Pro 구독, 유료 앱 구매자는 전부 열림. 상세는 `CLAUDE.md` "구독 (2.0)".
- 새 기능: 내 수준·약점 진단·예상 기록, 더블/릴레이 전략 추천, 대회까지 훈련 계획,
  대회 기록 보관함 + 결과 화면 사진 인식, 공유 카드 3종, 시즌 리포트, 백업 내보내기/복원,
  코치(기기 내 모델), 음성 안내, FitBoost 연결.
- 안정성: 워치 세션 유실 복구·미러링 재연결·실시간 전송 제한, 폰 Live Activity 갱신 제한,
  가민 기록 분할 수신(`workout.completed.part`).
- 워치: 운동 화면 단순화(구간 띠·큰 타이머·목표 대비).
- 홍보 페이지(`docs/`): 2.0 기능, 무료/Pro 비교표, 약관·개인정보의 구독 조항.

## 빌드·검증

- 이 맥에서는 `.mise.toml` 이 trust 되지 않아 `mise exec` 가 실패한다. `mise trust` 하거나
  `~/.local/share/mise/installs/tuist/<버전>/tuist` 를 직접 실행.
- 테스트: HyroxKitTests · HyroxSimTests · HyroxSimUITests 통과. 테스트 러너가 "hung before
  establishing connection" 으로 멈추거나 위젯 확장 크래시가 뜨면 시뮬레이터를 재부팅하고 다시 돌린다.
- 실제 결과 화면 캡처로 인식 테스트: `TEST_RUNNER_RACE_SAMPLE_DIR=<폴더> xcodebuild test …`
  (1.png = 구간 표, 2.png = 공유 카드). 캡처는 저장소에 넣지 않는다.
- 공유 카드 이미지를 눈으로 볼 때: `TEST_RUNNER_SHARE_OUT_DIR=<폴더>`.
- 화면 확인용 실행 인자는 `CLAUDE.md` "구독 (2.0)" 참고.

## 확인하지 못한 것

- **실제 결제**: 이 맥의 시뮬레이터에서 로컬 StoreKit 테스트가 붙지 않았다(`SKInternalErrorDomain Code=3`).
  구독 저장소는 가짜 스토어로 테스트했고, 실제 구매 테스트 1개는 건너뛴다. Xcode 에서 직접 실행해 확인 필요.
- 음성 안내가 실제로 들리는지(시뮬레이터에서 소리 확인 불가), 백그라운드에서 나오는지.
- 워치·폰의 세션 유실/연결 끊김 복구는 상황을 재현해 보지 못했다(빌드·기존 테스트까지).
- 실기기 전반: 1.3.0/1.5.0 → 2.0 업데이트, 가민 분할 전송, 워치 심박·GPS.
- 기기 내 모델 코치는 시뮬레이터(맥 호스트 모델)에서만 확인했다.

## 출시 전에 사람이 해야 하는 일

1. App Store Connect: 구독 그룹과 상품 2개 생성(`…pro.monthly` 4,900원, `…pro.yearly` 29,000원),
   앱 가격을 무료로 변경, 2.0 버전 생성, 릴리스 노트(`docs/release-notes/2.0.0.md`) 입력.
2. 첫 2.0 빌드 번호가 `2026.10.12.1` 이상인지 확인 (`LegacyPurchaseRule.firstFreeBuild`).
3. 백그라운드 오디오 모드(`audio`)를 추가했다 — 심사 메모에 "운동 중 음성 안내" 라고 적는다.
4. 스토어 스크린샷: `swift tools/generate_app_store_screenshots.swift` → `~/Desktop/HyroxSim-AppStore-Screenshots`.
   한국어 세트도 앱 화면 자체는 영어 캡처다.
5. 가민 스토어 업로드는 처음 올릴 때 쓴 `developer_key.der` 로 서명해야 한다(이 맥에는 없음).
6. Play Console: 구독 상품 생성, 내부 테스트로 결제 확인.
7. `release/2.0` → main 병합, 태그, 푸시.
