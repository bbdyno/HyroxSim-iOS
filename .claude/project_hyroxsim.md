---
name: HyroxSim 프로젝트 현황
description: HYROX 시뮬레이터 iOS+watchOS 앱 — 현재 구현 상태, 아키텍처, 주요 결정사항
type: project
---

HyroxSim — HYROX 경기 시뮬레이션 앱 (iOS + watchOS)

**프로젝트 경로:** `/Users/denny.k/Documents/Personal/HyroxSim/`
**GitHub:** `git@github.com:bbdyno/HyroxSim-iOS.git`

**구현 완료 단계:**
1. Tuist 프로젝트 스캐폴딩
2. 도메인 모델 + HYROX 디비전 프리셋 (31 세그먼트)
3. WorkoutEngine 상태머신
4. 측정 데이터 모델 (LocationSample, HeartRateSample, Haversine)
5. SwiftData 영속화
6. 센서 어댑터 (CoreLocation, HealthKit, HKWorkoutSession)
7. iOS UI (홈, 히스토리, 빌더, 운동 화면, 요약 화면)
8. watchOS UI (홈, 운동, 요약, 히스토리)
9. WatchConnectivity 동기화 (비실시간 + 실시간)
10. Live Activity + Dynamic Island
11. 블랙+옐로우 커스텀 디자인 시스템

**How to apply:** 프로젝트 루트의 CLAUDE.md에 빌드/규칙/아키텍처 상세 기록됨.
