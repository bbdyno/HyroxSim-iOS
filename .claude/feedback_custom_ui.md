---
name: 커스텀 UI 선호
description: 시스템 기본 컴포넌트 대신 항상 커스텀 컴포넌트 사용. 디자인 품질에 민감.
type: feedback
---

시스템 기본 UI 사용 금지. 항상 커스텀 컴포넌트 사용.

**Why:** 사용자가 시스템 UI(UIAlertController, 기본 테이블뷰 셀 등)를 "불친절하다", "시스템 UI다"라며 여러 차례 지적. 모든 화면을 블랙+옐로우 커스텀 테마로 통일하라고 요청.

**How to apply:**
- UIAlertController → `DarkAlertController` 사용
- UITableViewCell 기본 스타일 → 커스텀 셀 (카드 형태)
- 색상은 `DesignTokens` 경유
- 캐러셀은 페이징 스냅 필수
- 마진/정렬 통일 (20pt)
- watchOS도 동일한 컬러 스킴 적용
