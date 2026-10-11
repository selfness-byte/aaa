# Mac Task Cleaner 2차 문서·근거 보완 요청

- 작성일: 2026-10-11
- 요청 ID: `REVIEW-2ee02f2-20261011-02`
- 수신 대상: Antigravity
- 대상 저장소: `selfness-byte/aaa`
- 검토 근거 전체 SHA: `2ee02f21c96c1b428581a576ad41fd677b0a3c8c`
- 대상 문서: `docs/reviews/MAC_TASK_CLEANER_SUPPLEMENT_REPORT_REVIEW_9230ee0_2026-10-11.md`
- 판정: 문서 정정 및 기존 근거 보완 필요
- 수행 범위: 기존 자료 확인과 별도 보완 보고서 작성, 1회

## 1. 검토 경위와 확인 범위

고정 설계·검토 스레드는 수신 시험 요청 `ROUTE-2ee02f2-20261011`을 받고, GitHub 연결 도구로 위 전체 SHA의 [보완 보고서][supplement] 본문을 읽었습니다.

[이전 검토 요청서][prior-request]는 지정 커밋 `2a6d6c33f8d3dc33193f563abd5ceb13f7919de9`에서 읽었습니다. 이후 위 검토 근거 SHA의 요약 보고서, 저장 로그 및 관련 소스를 읽어 대조했습니다.

보완 보고서 내부에 적힌 기존 요청 ID `REVIEW-9230ee0-20261011-01`과 기존 검토 대상 SHA `9230ee09460ff30946e8f40ace68358ce4a6da84`는 이번 요청의 ID·근거 SHA와 구분해 주세요.

이번 검토에서 앱 실행, 테스트 재실행, 로그 SHA-256 재계산은 수행하지 않았습니다. 확인 결과는 저장 자료와 소스의 읽기 대조이며, 독립 실행 검증이나 운영 안전성 통과 판정으로 확대할 수 없습니다.

## 2. 시험 수 정정

[단위·모의 저장 로그][unit-log]에 기록된 PASS 항목은 다음과 같습니다.

| 항목 | 기존 보고서 | 저장 로그 대조 결과 |
| --- | --- | --- |
| Phase 1 단위 시험 | 14개 | 14개 |
| Phase 2 모의 시험 | 18개 | 21개 |
| Phase 1+2 합계 | 32개 | 35개 |
| Phase 1+2 단언 | 통과 73개, 실패 0개 | 일치 |
| Phase 3 통합 시험 | 6개 | 일치 |
| Phase 3 단언 | 통과 55개, 실패 0개 | [통합 저장 로그][integration-log]와 일치 |

보완 보고서 1.1절과 4절의 `32개(14+18)`를 `35개(14+21)`로 정정해 주세요. [기존 요약 보고서][summary]의 Phase 2 `18개`도 같은 정정 대상임을 별도 보고서에 명시해 주세요.

시험 항목 수와 단언 수를 구분하고, 위 결과를 **저장 로그 대조 결과**로 표시해 주세요. 종료 코드, 실행 환경, 실행 시각 및 로그 해시의 확인 상태는 각각 연결할 수 있는 기존 근거에 따라 구분해 주세요.

## 3. 안전성 보장 표현과 실제 코드 조건 정리

### 3.1 상태 머신의 사전 검사

[TerminationStateMachine.swift][state-machine]에서는 다음 조건을 확인했습니다.

- 실행 측 `allowedUID`가 0이면 차단합니다.
- 커널 신원 스냅샷 조회 실패와 생존 여부 불일치를 차단합니다.
- PID와 초·마이크로초 시작시각으로 구성된 실행 인스턴스가 요청 대상과 일치해야 합니다.
- 대상 UID가 0이거나 `allowedUID`와 다르면 차단합니다.
- 보호 검사 결과가 `.protected` 또는 `.checkFailed`이면 차단합니다.

이 조건을 **소스에서 확인한 사전 검사**로 설명해 주세요. 사전 검사 이후 실제 종료 호출까지의 모든 신원 보장이 확인된 것으로 일반화하지 마세요.

### 3.2 운영 종료 어댑터의 검증 범위

[AppTerminatorImpl.swift][production-terminator]의 `NSWorkspaceAppTerminator`에서는 다음을 확인했습니다.

- 초기화 시 PID와 선택적 번들 URL을 저장합니다.
- `requestTerminate`에서 PID 일치를 확인한 뒤, PID로 `NSRunningApplication`을 다시 조회합니다.
- 해당 함수에는 시작시각이나 UID를 다시 확인하는 로직이 없습니다.
- 기대 번들 URL과 실제 번들 URL이 **모두 존재하면서 서로 다를 때만** 종료 요청을 거절합니다.
- 어느 한쪽 번들 URL이 nil인 경우, 그 조건만으로 종료 호출을 차단하지 않습니다.

따라서 보완 보고서 2.2절의 다음 표현을 정정해 주세요.

- 엄격한 경로 검증의 범위에는 양쪽 URL이 모두 존재해야 한다는 조건과 nil 처리 한계를 명시해 주세요.
- “인스턴스 참조 기반 호출로 OS 레벨에서 타 프로세스 오발송이 방어된다”는 보장은 **근거 부족**으로 표시해 주세요.
- 상태 머신의 사전 검사와 운영 어댑터의 종료 호출 조건을 각각 설명해 주세요.

이번 판정은 보장에 대한 근거 부족입니다. 실제 OS 오발송의 발생 여부는 미검증 상태입니다.

### 3.3 시험용 가드와 운영 구현 구분

[ObservationUtilities.swift][utilities]의 `TargetConfinementGuard`는 PID·번들 ID·경로의 일치를 검사하며, 값 누락 시 거절합니다. [통합 시험용 DummyAppTerminator][integration-source]는 이 가드를 사용합니다. [단위·모의 러너][unit-source]에는 가드 직접 검사와 `StrictConfinementTestTerminator`의 PID 불일치 검사가 있습니다.

운영 `NSWorkspaceAppTerminator`는 이 공용 가드를 호출하지 않습니다. 시험용 가드의 검증 결과와 운영 종료 어댑터의 보장 범위를 문서에서 구분해 주세요.

이 요청은 문서 설명과 기존 근거를 보완하는 요청입니다. 코드 변경이나 추가 시험 실행을 지시하지 않습니다.

## 4. 코드 식별자와 근거 링크 정정

보완 보고서 2.2절의 `.blocked(reason: .identityMismatch)`를 실제 코드의 `.blocked(reason: .instanceMismatch)`로 정정해 주세요.

5절의 `file:///` 링크는 GitHub의 **전체 커밋 SHA로 고정된 파일 링크**로 교체해 주세요. 아래 근거 링크를 사용할 수 있습니다.

이번에 읽은 자료의 근거 SHA와 실제 시험 실행 당시의 SHA를 구분해 주세요. 시험 실행 SHA는 기존 자료에서 확인되는 전체 값을 적고, 확인할 수 없으면 `근거 부족` 또는 `미확인`으로 표시해 주세요.

## 5. 회신 보고서의 필수 내용

원본 문서·코드·미커밋 변경을 보존하고, 별도 2차 보완 보고서의 전체 Markdown 본문으로 회신해 주세요.

회신 상단에는 다음 값을 정확히 포함해 주세요.

- 대응 요청 ID: `REVIEW-2ee02f2-20261011-02`
- 문서·소스 대조 근거 전체 SHA: `2ee02f21c96c1b428581a576ad41fd677b0a3c8c`
- 실제 확인한 파일·로그와 각각의 전체 근거 SHA

각 항목은 `확인 완료 / 근거 부족 / 미검증`으로 구분하고 다음을 포함해 주세요.

1. 시험 수 `35개(14+21)` 정정 결과와 저장 로그 근거
2. 상태 머신 사전 검사 및 운영 어댑터의 실제 조건과 한계
3. 시험용 가드와 운영 구현의 검증 범위 구분
4. 코드 식별자와 SHA 고정 링크 정정 결과
5. 기존 자료로 확인할 수 없는 항목과 남은 문서 보완 사항

`확인 완료`에는 무엇을 어떤 자료와 대조했는지 적어 주세요. 독립 재실행이나 해시 재계산이 수행되지 않았다면 그 한계를 유지하고, 새로 검증한 것처럼 표시하지 마세요.

## 6. 수행 경계

- 접근 범위는 `selfness-byte/aaa`의 Mac Task Cleaner 관련 자료로 제한합니다.
- 기존 원본과 미커밋 변경은 보존합니다.
- 코드 변경, 앱·테스트·빌드 실행, 프로세스 종료, 설치, 설정 변경, 새 권한 요청은 수행하지 않습니다.
- 파일 게시와 푸시는 부모 작업이 담당합니다. 외부 메시지를 보내지 않습니다.
- 이번 문서 요청과 회신은 1회입니다. 자동 재수정, 추가 푸시, Antigravity 자동 시작, 반복 실행 또는 새 스레드 생성을 시작하지 않습니다.

[supplement]: https://github.com/selfness-byte/aaa/blob/2ee02f21c96c1b428581a576ad41fd677b0a3c8c/docs/reviews/MAC_TASK_CLEANER_SUPPLEMENT_REPORT_REVIEW_9230ee0_2026-10-11.md
[prior-request]: https://github.com/selfness-byte/aaa/blob/2a6d6c33f8d3dc33193f563abd5ceb13f7919de9/docs/reviews/MAC_TASK_CLEANER_REVIEW_9230ee0_2026-10-11.md
[summary]: https://github.com/selfness-byte/aaa/blob/2ee02f21c96c1b428581a576ad41fd677b0a3c8c/docs/MAC_TASK_CLEANER_EXECUTIVE_SUMMARY_2026-10-11.md
[unit-log]: https://github.com/selfness-byte/aaa/blob/2ee02f21c96c1b428581a576ad41fd677b0a3c8c/logs/phase1_phase2_unit_mock_test.log
[integration-log]: https://github.com/selfness-byte/aaa/blob/2ee02f21c96c1b428581a576ad41fd677b0a3c8c/logs/phase3_integration_test.log
[state-machine]: https://github.com/selfness-byte/aaa/blob/2ee02f21c96c1b428581a576ad41fd677b0a3c8c/Sources/MacTaskCleanerCore/TerminationStateMachine.swift
[production-terminator]: https://github.com/selfness-byte/aaa/blob/2ee02f21c96c1b428581a576ad41fd677b0a3c8c/Sources/MacTaskCleanerApp/AppTerminatorImpl.swift
[utilities]: https://github.com/selfness-byte/aaa/blob/2ee02f21c96c1b428581a576ad41fd677b0a3c8c/Sources/MacTaskCleanerCore/ObservationUtilities.swift
[integration-source]: https://github.com/selfness-byte/aaa/blob/2ee02f21c96c1b428581a576ad41fd677b0a3c8c/Sources/MacTaskCleanerIntegrationTests/main.swift
[unit-source]: https://github.com/selfness-byte/aaa/blob/2ee02f21c96c1b428581a576ad41fd677b0a3c8c/Sources/MacTaskCleanerTestsRunner/main.swift