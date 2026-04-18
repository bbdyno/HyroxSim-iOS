# Frameworks/

외부에서 받은 이진 프레임워크를 드롭하는 위치입니다. Tuist 프로젝트는 이 폴더에 있는 프레임워크를 **자동으로 링크하지 않습니다** — 사용 여부는 Project.swift에서 명시합니다.

## ConnectIQ.xcframework (가민 워치 연동)

### 필요성
`Targets/HyroxSim/Sources/Integration/Garmin/` 아래의 Swift 파일들은 `#if canImport(ConnectIQ)` 가드로 감싸져 있어 **프레임워크가 없어도 빌드는 성공**합니다. 실제 가민 연동을 활성화하려면 이 프레임워크를 여기에 드롭하고 Project.swift에 의존성으로 추가해야 합니다.

### 다운로드
1. https://developer.garmin.com/connect-iq/overview/ 에서 가민 개발자 계정 로그인
2. "Connect IQ Mobile SDK (iOS)" 최신 버전 다운로드 (zip)
3. 압축 해제 → `ConnectIQ.framework` 확인

### XCFramework 변환
가민 공식 배포는 `.framework` 하나뿐이라 Apple Silicon + Intel + simulator 혼합 지원을 위해 **XCFramework로 래핑** 권장:

```bash
cd Frameworks
xcodebuild -create-xcframework \
    -framework /path/to/ConnectIQ.framework \
    -output ConnectIQ.xcframework
```

(만약 가민이 여러 슬라이스(iphoneos + iphonesimulator) 분리 배포로 바뀌면 각각 `-framework` 인자로 묶음)

### Project.swift 반영

`Projects/HyroxSim/Project.swift`의 `HyroxSim` 타겟 dependencies에 추가:

```swift
dependencies: [
    // ... existing
    .xcframework(path: "../../Frameworks/ConnectIQ.xcframework"),
],
```

그리고:

```bash
tuist install && tuist generate
```

### Info.plist 추가 키

`.extendingDefault` 딕셔너리에 추가:

```swift
"LSApplicationQueriesSchemes": ["gcm-ciq"],
"CFBundleURLTypes": [[
    "CFBundleURLSchemes": ["ciq-bbdyno-hyroxsim"]
]]
```

### 빌드 검증
- ConnectIQ.xcframework 드롭 후 `tuist generate`
- `Garmin/GarminBridge.swift` 등 `#if canImport` 블록이 활성화됨
- `xcodebuild build -workspace HyroxSim.xcworkspace -scheme HyroxSim ...` 성공 확인

### 주의사항
- 프레임워크는 **gitignore됨** — 공식 재배포 라이선스 이슈 회피
- 새 개발자 환경에선 이 문서 보고 각자 다운로드
- CI에서는 환경변수나 secrets로 프리빌트 아티팩트 주입 필요 (추후 별도 문서화)
