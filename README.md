# HyroxSim

HYROX 시뮬레이션 앱 — iOS + Apple Watch 지원

## 개요

HYROX 경기를 시뮬레이션하고 운동을 추적하는 앱입니다.
- **iOS 앱**: UIKit 기반, MVVM + Coordinator 아키텍처
- **watchOS 앱**: SwiftUI 기반, iOS 앱과 페어링되는 companion app
- **HyroxCore**: 도메인 모델, 엔진, 포맷터, 센서/동기화 프로토콜
- **HyroxPersistenceApple**: SwiftData 기반 persistence
- **HyroxLiveActivityApple**: Live Activity / Dynamic Island 공유 타입

## 요구사항

| 항목 | 버전 |
|---|---|
| Xcode | 15.0+ |
| Tuist | 4.x |
| iOS | 17.0+ |
| watchOS | 10.0+ |
| Swift | 5.9+ |

## 빌드 방법

```bash
tuist install
tuist generate
```

생성된 `.xcworkspace` 파일을 Xcode에서 열어 빌드/실행합니다.

## 디렉터리 구조

```
HyroxSim/
├── Project.swift              # Tuist 프로젝트 정의
├── Tuist/Config.swift         # Tuist 설정
├── Targets/
│   ├── HyroxSim/              # iOS 앱 (UIKit)
│   │   ├── Sources/
│   │   │   ├── App/           # AppDelegate, SceneDelegate
│   │   │   ├── Coordinators/  # 화면 전환 코디네이터
│   │   │   ├── Features/      # 기능별 모듈 (Home, WorkoutBuilder 등)
│   │   │   └── Common/        # 공통 뷰, 익스텐션
│   │   └── Resources/         # Assets, LaunchScreen
│   ├── HyroxSimWatch/         # watchOS 앱 (SwiftUI)
│   │   ├── Sources/
│   │   └── Resources/
│   ├── HyroxCore/             # 플랫폼 독립 코어
│   │   └── Sources/
│   │       ├── Models/        # Workout, Segment, Station 등
│   │       ├── Engine/        # WorkoutEngine (상태머신)
│   │       ├── Presets/       # 기본 HYROX 프리셋
│   │       └── Sync/
│   ├── HyroxPersistenceApple/ # SwiftData persistence
│   │   └── Sources/
│   ├── HyroxLiveActivityApple/# Live Activity 공유 타입
│   │   └── Sources/
│   ├── HyroxSimTests/         # iOS 앱 테스트
│   └── HyroxKitTests/         # 공유 모듈 테스트
```

## 타겟

| 타겟 | 플랫폼 | 제품 타입 | 설명 |
|---|---|---|---|
| HyroxSim | iOS | App | 메인 iOS 앱 (UIKit) |
| HyroxSimWatch | watchOS | App | Apple Watch 앱 (SwiftUI) |
| HyroxCore | iOS + watchOS | Framework | 도메인 모델/엔진/포맷터/프로토콜 |
| HyroxPersistenceApple | iOS + watchOS | Framework | SwiftData persistence |
| HyroxLiveActivityApple | iOS | Framework | Live Activity 공유 타입 |
| HyroxSimWidgets | iOS | App Extension | Live Activity + Dynamic Island |
| HyroxSimTests | iOS | Unit Tests | iOS 앱 테스트 |
| HyroxKitTests | iOS | Unit Tests | 공유 모듈 테스트 |

## 참고

- 현재 단계는 빌드 가능한 빈 껍데기입니다. 비즈니스 로직과 실제 UI 구현은 이후 단계에서 진행됩니다.
- Capabilities: HealthKit, App Groups (`group.com.bbdyno.app.HyroxSim`)
- watchOS 앱에는 HealthKit Background Delivery가 추가 설정되어 있습니다.
