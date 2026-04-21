# Frameworks/

외부 이진 프레임워크를 드롭하는 위치. gitignore됨.

## ConnectIQ.xcframework (가민 워치 연동)

### 자동 설치 (권장)

```bash
./scripts/setup-garmin-sdk.sh
```

이 스크립트는 가민 공식 GitHub 리포지토리(https://github.com/garmin/connectiq-companion-app-sdk-ios)에서 최신 태그의 `ConnectIQ.xcframework`를 복사해 여기에 설치합니다.

### 수동 설치 (대안)

1. https://github.com/garmin/connectiq-companion-app-sdk-ios 에서 특정 태그 체크아웃
2. 리포지토리의 `ConnectIQ.xcframework` 폴더를 이 디렉토리에 복사

### Tuist 연결

`Projects/HyroxSim/Project.swift`의 `HyroxSim` 타겟에 이미 아래 의존성이 등록되어 있습니다:

```swift
.xcframework(path: "../../Frameworks/ConnectIQ.xcframework")
```

설치 후 프로젝트 재생성:
```bash
tuist install && tuist generate
```

### 왜 커밋하지 않는가

- 가민 SDK는 공식 라이선스 동의 하에 사용. 재배포는 공식 GitHub 경로를 따르는 것이 안전
- 1.7MB 바이너리를 매 커밋에 포함시키지 않아 repo 크기 유지
- 새 개발자는 setup 스크립트 한 번만 실행

### Info.plist 의존 (이미 반영됨)

`LSApplicationQueriesSchemes`의 `gcm-ciq`, URL scheme `ciq-bbdyno-hyroxsim`, `CFBundleDisplayName`이 `Project.swift`에 등록되어 있습니다. Garmin Connect Mobile 앱 핸드오프와 디바이스 선택에 필요합니다.
