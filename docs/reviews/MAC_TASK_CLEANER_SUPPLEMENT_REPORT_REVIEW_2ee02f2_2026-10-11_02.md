# Mac Task Cleaner 2차 문서·근거 보완 보고서 (REVIEW-2ee02f2-20261011-02 대응)

- 문서 작성일: 2026-10-11 (Asia/Seoul)
- 대응 요청 ID: `REVIEW-2ee02f2-20261011-02`
- 문서·소스 대조 근거 전체 SHA: `2ee02f21c96c1b428581a576ad41fd677b0a3c8c`
- 시험 실행 당시 전체 SHA: `3a4ab62532eaeda174dc57c2cd33f6bf17704bb9`
- 대상 저장소: `selfness-byte/aaa`
- 작성 주체: Antigravity
- 수행 범위: 기존 저장 자료와 소스 코드 대조 기반의 2차 보완 보고서 작성 (1회)

---

## 실제 확인한 파일·로그 및 전체 근거 SHA

| 항목 | 확인 파일 경로 | 기준 커밋 SHA | 확인 방법 |
| :--- | :--- | :--- | :--- |
| **2차 검토 요청서** | [`docs/reviews/MAC_TASK_CLEANER_REVIEW_2ee02f2_2026-10-11_02.md`](https://github.com/selfness-byte/aaa/blob/5f3092a95c93d931fbfffe41940cb62d29487c63/docs/reviews/MAC_TASK_CLEANER_REVIEW_2ee02f2_2026-10-11_02.md) | `5f3092a95c93d931fbfffe41940cb62d29487c63` | 원격 패치 수신 후 전문 대조 |
| **1차 보완 보고서** | [`docs/reviews/MAC_TASK_CLEANER_SUPPLEMENT_REPORT_REVIEW_9230ee0_2026-10-11.md`](https://github.com/selfness-byte/aaa/blob/2ee02f21c96c1b428581a576ad41fd677b0a3c8c/docs/reviews/MAC_TASK_CLEANER_SUPPLEMENT_REPORT_REVIEW_9230ee0_2026-10-11.md) | `2ee02f21c96c1b428581a576ad41fd677b0a3c8c` | 정정 대상 텍스트 대조 |
| **기존 요약 보고서** | [`docs/MAC_TASK_CLEANER_EXECUTIVE_SUMMARY_2026-10-11.md`](https://github.com/selfness-byte/aaa/blob/2ee02f21c96c1b428581a576ad41fd677b0a3c8c/docs/MAC_TASK_CLEANER_EXECUTIVE_SUMMARY_2026-10-11.md) | `2ee02f21c96c1b428581a576ad41fd677b0a3c8c` | 정정 대상 텍스트 대조 |
| **단위·모의 시험 로그** | [`logs/phase1_phase2_unit_mock_test.log`](https://github.com/selfness-byte/aaa/blob/2ee02f21c96c1b428581a576ad41fd677b0a3c8c/logs/phase1_phase2_unit_mock_test.log) | `2ee02f21c96c1b428581a576ad41fd677b0a3c8c` | 항목별 PASS 라인 및 단언 카운트 대조 |
| **macOS 통합 시험 로그** | [`logs/phase3_integration_test.log`](https://github.com/selfness-byte/aaa/blob/2ee02f21c96c1b428581a576ad41fd677b0a3c8c/logs/phase3_integration_test.log) | `2ee02f21c96c1b428581a576ad41fd677b0a3c8c` | 항목별 PASS 라인 및 단언 카운트 대조 |
| **상태 머신 소스** | [`Sources/MacTaskCleanerCore/TerminationStateMachine.swift`](https://github.com/selfness-byte/aaa/blob/2ee02f21c96c1b428581a576ad41fd677b0a3c8c/Sources/MacTaskCleanerCore/TerminationStateMachine.swift) | `2ee02f21c96c1b428581a576ad41fd677b0a3c8c` | 사전 검사 분기 및 enum 심볼 대조 |
| **운영 어댑터 소스** | [`Sources/MacTaskCleanerApp/AppTerminatorImpl.swift`](https://github.com/selfness-byte/aaa/blob/2ee02f21c96c1b428581a576ad41fd677b0a3c8c/Sources/MacTaskCleanerApp/AppTerminatorImpl.swift) | `2ee02f21c96c1b428581a576ad41fd677b0a3c8c` | `requestTerminate` 분기 및 URL 검사 대조 |
| **공용 가드 소스** | [`Sources/MacTaskCleanerCore/ObservationUtilities.swift`](https://github.com/selfness-byte/aaa/blob/2ee02f21c96c1b428581a576ad41fd677b0a3c8c/Sources/MacTaskCleanerCore/ObservationUtilities.swift) | `2ee02f21c96c1b428581a576ad41fd677b0a3c8c` | `TargetConfinementGuard` 구현 대조 |
| **통합 시험 러너 소스** | [`Sources/MacTaskCleanerIntegrationTests/main.swift`](https://github.com/selfness-byte/aaa/blob/2ee02f21c96c1b428581a576ad41fd677b0a3c8c/Sources/MacTaskCleanerIntegrationTests/main.swift) | `2ee02f21c96c1b428581a576ad41fd677b0a3c8c` | `DummyAppTerminator`의 가드 호출 대조 |
| **단위 시험 러너 소스** | [`Sources/MacTaskCleanerTestsRunner/main.swift`](https://github.com/selfness-byte/aaa/blob/2ee02f21c96c1b428581a576ad41fd677b0a3c8c/Sources/MacTaskCleanerTestsRunner/main.swift) | `2ee02f21c96c1b428581a576ad41fd677b0a3c8c` | 러너 내부의 가드 직접 시험 대조 |

---

## 1. 시험 수 정정 및 저장 로그 대조 결과 [확인 완료]

저장 로그 파일([`logs/phase1_phase2_unit_mock_test.log`](https://github.com/selfness-byte/aaa/blob/2ee02f21c96c1b428581a576ad41fd677b0a3c8c/logs/phase1_phase2_unit_mock_test.log))의 실제 `✅ [PASS]` 출력 라인을 전수 대조한 결과는 다음과 같습니다.

### 1.1 저장 로그 대조 표
| 구분 | 기존 보고서 기재 | 저장 로그 실제 대조 결과 | 비고 |
| :--- | :---: | :---: | :--- |
| **Phase 1 단위 시험** | 14개 | **14개** | 일치 |
| **Phase 2 모의 시험** | 18개 | **21개** | **3개 증가 확인** (R1, R2, R4 추가 시험 반영) |
| **Phase 1+2 시험 합계** | 32개 | **35개** (14 + 21) | **정정 대상** |
| **Phase 1+2 단언문** | 통과 73개, 실패 0개 | **통과 73개, 실패 0개** | 일치 |
| **Phase 3 통합 시험** | 6개 | **6개** | 일치 ([`logs/phase3_integration_test.log`](https://github.com/selfness-byte/aaa/blob/2ee02f21c96c1b428581a576ad41fd677b0a3c8c/logs/phase3_integration_test.log)) |
| **Phase 3 단언문** | 통과 55개, 실패 0개 | **통과 55개, 실패 0개** | 일치 |

### 1.2 정정 사항
* 1차 보완 보고서 1.1절 및 4절 종합 요약표에 기재된 `32개 (Phase 1: 14개 + Phase 2: 18개)` 표기를 **`35개 (Phase 1: 14개 + Phase 2: 21개)`**로 정정합니다.
* 기존 요약 보고서([`docs/MAC_TASK_CLEANER_EXECUTIVE_SUMMARY_2026-10-11.md`](https://github.com/selfness-byte/aaa/blob/2ee02f21c96c1b428581a576ad41fd677b0a3c8c/docs/MAC_TASK_CLEANER_EXECUTIVE_SUMMARY_2026-10-11.md)) 2절 표에 기재된 Phase 2 `모의 시험 18개` 역시 저장 로그에 부합하도록 **`21개`**로 정정 대상임을 명시합니다.
* 이 수치는 저장 로그에 보존된 실행 결과를 읽기 대조한 것이며, 이번 문서 작성 과정에서 시험을 독립 재실행하거나 해시를 재계산한 것은 아닙니다.

---

## 2. 안전성 보장 표현과 실제 코드 조건 정리 [확인 완료 / 근거 부족 구분]

### 2.1 상태 머신의 사전 검사 (`TerminationStateMachine.swift`) [확인 완료]
소스 코드 확인 결과, `TerminationStateMachine.initiateTermination` 내부에는 다음과 같은 **5단계의 엄격한 사전 검사**가 구현되어 있습니다:
1. **실행 컨텍스트 안전성 검사**: 호출 측 `allowedUID == 0`인 경우 즉시 `.blocked(reason: .invalidAllowedUID)`로 차단.
2. **사전 생존 상태 확인**: `terminator.isAlreadyTerminated` 또는 이미 종료 관측된 인스턴스인 경우 즉시 `.targetAlreadyTerminated`로 중단.
3. **커널 신원 스냅샷 검증**: `identityProvider.currentSnapshot(for: targetInstance)` 호출 실패 시 `.blocked(reason: .missingIdentityInfo)`, `snapshot.isAlive == false`인 경우 `.blocked(reason: .processNotAlive)`로 차단.
4. **실행 인스턴스 불일치 검증**: `snapshot.instanceID != targetInstance` (PID 또는 커널 마이크로초 시작 시각 불일치) 시 `.blocked(reason: .instanceMismatch)`로 차단.
5. **소유권 및 보호 규칙 검사**: `snapshot.uid == 0`인 경우 `.blocked(reason: .rootProcessBlocked)`, `snapshot.uid != allowedUID`인 경우 `.blocked(reason: .otherUserProcessBlocked)`, 보호 검사 결과가 `.unprotected`가 아닌 경우(`.protected` 또는 `.checkFailed`) `.blocked`로 차단.

> **한계 명시**: 위 조건은 상태 머신 진입 시점에 수행되는 **"소스에서 확인한 사전 검사"**에 한정되며, 사전 검사 이후 실제 종료 신호 전달 순간까지 프로세스 상태의 불변성이 커널 수준에서 절대적으로 보장된다는 뜻으로 일반화할 수 없습니다.

### 2.2 운영 종료 어댑터의 검증 범위 (`AppTerminatorImpl.swift`) [확인 완료 및 근거 부족 명시]
운영 코드 `NSWorkspaceAppTerminator.requestTerminate`를 대조한 결과는 다음과 같습니다:
* **초기화 및 PID 확인**: 초기화 시 `allowedPID`와 선택적 `expectedBundleURL`을 보존하고, `instanceID.pid == allowedPID`를 확인한 후 `NSRunningApplication(processIdentifier:)`를 조회합니다.
* **시작 시각 및 UID 미재확인**: `requestTerminate` 메서드 내부에는 시작 시각(`startTimeSec`, `startTimeUsec`)이나 UID를 독자적으로 다시 조회하여 검증하는 로직이 없습니다 (상태 머신의 사전 검사에 의존).
* **번들 URL 일치 검사 조건과 nil 한계**:
  ```swift
  if let expected = expectedBundleURL, let actual = app.bundleURL, expected != actual {
      return false
  }
  return app.terminate()
  ```
  * `expectedBundleURL`과 `actual(app.bundleURL)`이 **모두 nil이 아니고 둘 다 존재하면서 서로 다를 때만** false를 반환하여 종료를 거절합니다.
  * **한계**: 만약 어느 한쪽 번들 URL이 `nil`인 경우(예: 번들 식별이 불가한 프로세스이거나 URL이 주어지지 않은 경우), 이 조건문은 거짓이 되어 거절하지 않고 `app.terminate()`를 호출하게 됩니다.
* **"OS 레벨 타 프로세스 오발송 방어" 표현의 정정**:
  * 1차 보고서 2.2절의 *“NSRunningApplication 인스턴스 참조 기반 호출로 OS 레벨에서 타 프로세스 오발송이 방어된다”*는 기술은 공인 문서나 커널 동작에 기반한 증명이 부족하므로 **[근거 부족]**으로 정정합니다.
  * 실제 운영 환경에서 Mach 포트/audit token 기반의 오발송 방지 신뢰성 여부는 **[미검증]** 상태입니다.

### 2.3 시험용 가드와 운영 구현의 검증 범위 구분 [확인 완료]
* **시험용 공용 가드 (`ObservationUtilities.swift`)**:
  * `TargetConfinementGuard.validate`는 PID, 번들 ID, 번들 경로를 모두 대조하며, 인자 중 하나라도 누락(nil)되거나 불일치하면 엄격히 거절합니다.
  * 통합 시험용 `DummyAppTerminator`와 단위 러너의 회귀 시험은 이 공용 가드를 직접 호출하여 검증합니다.
* **운영 종료 어댑터 (`NSWorkspaceAppTerminator`)**:
  * 운영 어댑터는 `TargetConfinementGuard`를 호출하지 않고 자체 `expected != actual` 검사만 수행합니다.
* **구분 요약**: 공용 가드의 엄격한 nil 거절 검증 결과가 운영 어댑터의 보장 범위로 직접 전이되지 않음을 명시합니다.

---

## 3. 코드 식별자 및 SHA 고정 링크 정정 [확인 완료]

### 3.1 코드 식별자 정정
* 1차 보완 보고서 2.2절에 기술된 에러 분기 식별자 `.blocked(reason: .identityMismatch)`를 실제 소스 코드([`TerminationStateMachine.swift` 라인 180](https://github.com/selfness-byte/aaa/blob/2ee02f21c96c1b428581a576ad41fd677b0a3c8c/Sources/MacTaskCleanerCore/TerminationStateMachine.swift#L180))의 심볼인 **`.blocked(reason: .instanceMismatch)`**로 정정합니다.

### 3.2 GitHub 전체 커밋 SHA 고정 근거 링크 (로컬 file:/// 링크 대체)
* 검토 요청서 1차: [`docs/reviews/MAC_TASK_CLEANER_REVIEW_9230ee0_2026-10-11.md`](https://github.com/selfness-byte/aaa/blob/2a6d6c33f8d3dc33193f563abd5ceb13f7919de9/docs/reviews/MAC_TASK_CLEANER_REVIEW_9230ee0_2026-10-11.md)
* 검토 요청서 2차: [`docs/reviews/MAC_TASK_CLEANER_REVIEW_2ee02f2_2026-10-11_02.md`](https://github.com/selfness-byte/aaa/blob/5f3092a95c93d931fbfffe41940cb62d29487c63/docs/reviews/MAC_TASK_CLEANER_REVIEW_2ee02f2_2026-10-11_02.md)
* 1차 보완 보고서: [`docs/reviews/MAC_TASK_CLEANER_SUPPLEMENT_REPORT_REVIEW_9230ee0_2026-10-11.md`](https://github.com/selfness-byte/aaa/blob/2ee02f21c96c1b428581a576ad41fd677b0a3c8c/docs/reviews/MAC_TASK_CLEANER_SUPPLEMENT_REPORT_REVIEW_9230ee0_2026-10-11.md)
* 요약 보고서: [`docs/MAC_TASK_CLEANER_EXECUTIVE_SUMMARY_2026-10-11.md`](https://github.com/selfness-byte/aaa/blob/2ee02f21c96c1b428581a576ad41fd677b0a3c8c/docs/MAC_TASK_CLEANER_EXECUTIVE_SUMMARY_2026-10-11.md)
* 단위 시험 로그: [`logs/phase1_phase2_unit_mock_test.log`](https://github.com/selfness-byte/aaa/blob/2ee02f21c96c1b428581a576ad41fd677b0a3c8c/logs/phase1_phase2_unit_mock_test.log)
* 통합 시험 로그: [`logs/phase3_integration_test.log`](https://github.com/selfness-byte/aaa/blob/2ee02f21c96c1b428581a576ad41fd677b0a3c8c/logs/phase3_integration_test.log)
* 상태 머신 구현: [`Sources/MacTaskCleanerCore/TerminationStateMachine.swift`](https://github.com/selfness-byte/aaa/blob/2ee02f21c96c1b428581a576ad41fd677b0a3c8c/Sources/MacTaskCleanerCore/TerminationStateMachine.swift)
* 운영 어댑터 구현: [`Sources/MacTaskCleanerApp/AppTerminatorImpl.swift`](https://github.com/selfness-byte/aaa/blob/2ee02f21c96c1b428581a576ad41fd677b0a3c8c/Sources/MacTaskCleanerApp/AppTerminatorImpl.swift)
* 공용 가드 구현: [`Sources/MacTaskCleanerCore/ObservationUtilities.swift`](https://github.com/selfness-byte/aaa/blob/2ee02f21c96c1b428581a576ad41fd677b0a3c8c/Sources/MacTaskCleanerCore/ObservationUtilities.swift)
* 통합 시험 러너: [`Sources/MacTaskCleanerIntegrationTests/main.swift`](https://github.com/selfness-byte/aaa/blob/2ee02f21c96c1b428581a576ad41fd677b0a3c8c/Sources/MacTaskCleanerIntegrationTests/main.swift)
* 단위 시험 러너: [`Sources/MacTaskCleanerTestsRunner/main.swift`](https://github.com/selfness-byte/aaa/blob/2ee02f21c96c1b428581a576ad41fd677b0a3c8c/Sources/MacTaskCleanerTestsRunner/main.swift)

---

## 4. 기존 자료로 확인할 수 없는 항목 및 남은 보완 사항 [미검증 / 근거 부족 요약]

| 항목 | 판정 | 설명 및 남은 한계 |
| :--- | :---: | :--- |
| **운영 어댑터의 OS 레벨 오발송 방어력** | **근거 부족** | Mach 포트/audit token 기반 OS 안전성에 대한 실증적 증빙 부재 (실제 오발송 발생 여부는 **미검증**) |
| **운영 어댑터의 URL nil 발생 시 격리** | **근거 부족** | `expectedBundleURL` 또는 `bundleURL` 중 하나가 nil일 때 종료를 차단하지 않는 구현상의 한계 존재 |
| **장시간(10분 이상) 연속 부하 자원 점유** | **미검증** | 16:10:11 KST 단일 시점 스냅샷(17.5MB RSS, 0.0% CPU) 외 장기 누적 부하 시험 데이터 미보존 |
| **100개 이상 대규모 프로세스 환경 성능** | **미검증** | 다수 프로세스 상주 시의 최대(Peak) 메모리 및 타이머 오버헤드 미측정 |
| **실제 업무 앱 강제 중단** | **해당 없음** | v1 안전 설계 원칙상 전용 더미 앱(`DummyTestTarget.app`)으로만 한정하여 시험함 |

---

## 5. 수행 경계 확인

* 본 보고서 작성에 있어 기존 제품 코드의 임의 수정, 앱 및 테스트 재실행, 시스템 권한 변경은 일체 수행하지 않았습니다.
* 기존 소스 코드 및 저장 로그, 기존 보고서 원본은 그대로 보존되었습니다.
