# Mac Task Cleaner 검토 보완 보고서 (REVIEW-9230ee0-20261011-01 대응)

- 문서 작성일: 2026-10-11 (Asia/Seoul)
- 대응 요청 ID: `REVIEW-9230ee0-20261011-01`
- 검토 대상 커밋: `9230ee09460ff30946e8f40ace68358ce4a6da84`
- 기준 원격 커밋: `2a6d6c3`
- 대상 저장소: `selfness-byte/aaa`
- 작성 주체: Antigravity

---

## 1. 시험 결과에 대한 재현 가능한 근거 [확인 완료]

보고서 `docs/MAC_TASK_CLEANER_EXECUTIVE_SUMMARY_2026-10-11.md`에 기재된 시험 결과의 원본 로그, 커밋 해시, 실행 환경 및 체크섬 내역은 다음과 같습니다.

### 1.1 단위 및 모의 상태 머신 시험 (Phase 1 & Phase 2)
* **판정**: **확인 완료**
* **시험 대상 커밋**: `3a4ab62532eaeda174dc57c2cd33f6bf17704bb9` (및 후속 `e3159de`)
* **실행 명령**: `swift run MacTaskCleanerTestsRunner`
* **기록 시각**: 2026-10-11 15:52:21 KST (최초 통과) / 15:59:26 KST (로그 저장 커밋) / 16:09:42 KST (통합 전체 재검증)
* **실행 환경**:
  * OS: macOS 27.0.1 (Build 26A434, Apple Silicon arm64)
  * 컴파일러: Apple Swift version 6.4 (`swiftlang-6.4.0.34.1 clang-2100.3.34.1`)
  * SDK: `/Library/Developer/CommandLineTools/SDKs/MacOSX27.0.sdk`
* **저장 로그 파일**: `logs/phase1_phase2_unit_mock_test.log`
* **로그 SHA-256 해시**:
  ```text
  7e248139eb74f6ec7363c613e756b97657ab3883044577097170663489a3ad80  logs/phase1_phase2_unit_mock_test.log
  ```
* **실행 결과**:
  * 종료 코드: **`0`**
  * 시험 수: **32개** (Phase 1 순수 계산 14개 + Phase 2 모의 상태 머신 18개)
  * 단언문 통과: **73개**, 실패: **0개**
  * 테스트 러너 경과시간: 1.726 ms (저장 로그 기준)

### 1.2 AppKit macOS 통합 시험 (Phase 3)
* **판정**: **확인 완료**
* **시험 대상 커밋**: `3a4ab62532eaeda174dc57c2cd33f6bf17704bb9` (및 후속 `e3159de`)
* **사전 빌드 명령**: `./scripts/build_dummy_app.sh` (`DummyTestTarget.app` 생성)
* **실행 명령**: `swift run MacTaskCleanerIntegrationTests`
* **기록 시각**: 2026-10-11 15:52:39 KST / 15:59:26 KST (로그 저장 커밋) / 16:09:42 KST (통합 전체 재검증)
* **실행 환경**: macOS 27.0.1, Apple Swift 6.4, Apple Silicon arm64
* **저장 로그 파일**: `logs/phase3_integration_test.log`
* **로그 SHA-256 해시**:
  ```text
  c68bde7c792c2de90b8869ad8d57716066eabb20312fa3fb1649091117e73cab  logs/phase3_integration_test.log
  ```
* **실행 결과**:
  * 종료 코드: **`0`**
  * 시험 시나리오: **6개** (읽기전용 메트릭, 시작시각 검증, 더미 실행/관측, 정상 종료, 지연 종료 및 타임아웃, 재실행 격리)
  * 단언문 통과: **55개**, 실패: **0개**
  * 테스트 러너 경과시간: 4,964.549 ms (더미 앱 실제 기동 및 종료 대기 포함)

### 1.3 외부 코드 리뷰(7c2086f) 회귀 지적 사항 반영
* **V1 (통합시험 단언문 0개 거부 복구)**: `Sources/MacTaskCleanerIntegrationTests/main.swift`에 `assertionsCount == 0` 방어 로직 복구 확인.
* **V2 (공용 포맷터 실사용 연결)**: 단위 러너 및 통합 러너가 모두 `ChronologyFormatter.format(observedNs:requestNs:)`를 호출하도록 통합.
* **V3 (실제 어댑터 격리 가드 검증)**: `TargetConfinementGuard` 공유 규칙과 `StrictConfinementTestTerminator`에 대한 PID 불일치 분기 및 OS 종료 호출 0회 검증 추가.

---

## 2. 안전 보장의 조건과 한계 [확인 완료]

절대적 표현('원천 차단' 등)을 지양하고, 실제 구현된 코드 위치와 검증된 조건 및 명확한 한계를 명시합니다.

### 2.1 보호 대상 식별 기준 및 신원 조회 실패 시 동작
* **코드 위치**:
  * `Sources/MacTaskCleanerApp/AppTerminatorImpl.swift` (`DefaultProtectionChecker`)
  * `Sources/MacTaskCleanerCore/TerminationStateMachine.swift` (`checkProtection`)
* **식별 기준**:
  1. 시스템 필수 번들 ID (`com.apple.finder`, `com.apple.dock`, `com.apple.systemuiserver`, `com.apple.WindowManager`, `com.apple.Spotlight`, `com.apple.loginwindow`, `com.apple.ActivityMonitor`).
  2. 개발 도구 및 터미널 번들 ID (`com.apple.Terminal`, `com.googlecode.iterm2`, `com.microsoft.VSCode`, `com.apple.dt.Xcode`, `com.google.antigravity-ide`).
  3. 프로세스 이름 일치 (`Finder`, `Dock`, `WindowServer`, `Activity Monitor`, `Terminal`, `iTerm`, `Code`, `Xcode`, `Antigravity IDE`, `MacTaskCleanerApp` 등).
  4. 앱 활성화 정책: `activationPolicy != .regular` (백그라운드 데몬, 메뉴바 액세서리 등은 보호).
  5. 자체 프로세스: `pid == getpid()` 즉시 보호.
* **신원 조회 실패 처리 (Fail-Closed)**:
  * `NSRunningApplication(processIdentifier:)` 조회 실패 시 `.checkFailed(reason:)` 반환.
  * `TerminationStateMachine.initiateTermination`은 보호 검사 결과가 `.unprotected`가 아닌 모든 경우(`.protected` 또는 `.checkFailed`)에 대해 즉시 `.blocked`로 전이하여 **종료 요청을 거절(Default Deny)**.
* **한계**:
  * 사용자가 임의로 이름을 바꾼 바이너리나, `.regular`가 아닌 CLI 도구는 GUI 종료 대상에서 제외되어 관찰 전용으로만 취급됩니다.

### 2.2 종료 직전 PID 재사용 및 프로세스 속성 재검증 범위
* **코드 위치**:
  * `Sources/MacTaskCleanerCore/TerminationStateMachine.swift` (라인 131–180)
  * `Sources/MacTaskCleanerCore/DarwinStatusCollector.swift` (`currentSnapshot`)
  * `Sources/MacTaskCleanerCore/ObservationUtilities.swift` (`TargetConfinementGuard`)
* **검증 단계**:
  1. **커널 시작 시각 검증**: `proc_pidinfo(PROC_PIDTBSDINFO)`에서 마이크로초 단위 시작 시각(`pbi_start_tvsec`, `pbi_start_tvusec`)을 읽어 요청 시점의 `targetInstance`와 일치하는지 대조. 불일치 시(이미 종료되고 새 프로세스가 PID를 재사용한 경우) `.blocked(reason: .identityMismatch)`로 차단.
  2. **소유권 및 Root 차단**: `snapshot.uid == allowedUID`를 검증하며, `snapshot.uid == 0`(root 소유)이거나 `allowedUID == 0`(root 권한 실행)인 경우 `.blocked`로 차단.
  3. **생존 여부**: `snapshot.isAlive == true` 및 좀비(`SZOMB`) 상태 배제.
  4. **바이너리 경로 일치 검증**: `TargetConfinementGuard.validate` 및 `NSWorkspaceAppTerminator`에서 기대 번들 URL과 실제 `runningApp.bundleURL` 일치 확인. 불일치 시 종료 호출 횟수 0회 보장.
* **한계**:
  * 커널 메트릭 조회 시점과 실제 `terminate()` 함수 호출 시점 사이에 미세한 시간 간극(kernel race window)이 이론적으로 존재할 수 있으나, AppKit의 `NSRunningApplication` 인스턴스 참조 기반 호출로 OS 레벨에서 타 프로세스 오발송이 방어됩니다.

### 2.3 미저장 문서, 종료 거부, 타임아웃 및 재실행 처리
* **코드 위치**:
  * `Sources/MacTaskCleanerApp/SystemMonitorController.swift` (라인 240–305)
  * `Sources/MacTaskCleanerCore/TerminationStateMachine.swift`
* **동작 원리**:
  1. **미저장 문서 및 사용자 취소**: `runningApp.terminate()` 호출 시 미저장 문서가 있는 앱은 AppKit 표준 "저장하시겠습니까?" 대화상자를 띄웁니다. 사용자가 저장을 취소하면 앱은 종료되지 않고 실행을 유지합니다. 본 앱은 **어떠한 경우에도 `SIGKILL`이나 `forceTerminate()`로 강제 종료하지 않습니다**.
  2. **타임아웃(3초) 초과 시**: 3초 이내에 종료가 관측되지 않으면 상태를 `.unconfirmedWithinTimeout`으로 변경하고 대기를 종료합니다.
  3. **늦은 종료 및 재실행(Respawn) 격리**: 타임아웃 이후 앱이 종료되면 `confirmed(.lateNotification)`으로 갱신됩니다. 만약 동일 번들의 새 인스턴스가 즉시 재실행되더라도 새 `ExecutionInstanceID`(PID + 시작시각)로 격리되어 이전 종료 요청의 영향이 새 프로세스로 전이되지 않습니다.
* **한계**:
  * 먹통(Hang) 상태이거나 사용자가 저장을 취소한 프로세스는 v1에서 강제로 종료할 수 없습니다(설계된 정상 제약).

### 2.4 사용자 선택 이후 대상 상태 변경 시
* UI에서 [정리 요청] 클릭 후 모달 확인창이 떠 있는 동안 앱이 스스로 종료되었을 경우:
  * `runningApp.isTerminated`가 즉시 감지되어 상태 머신 호출 없이 "이미 종료됨" 메시지를 표시하고 종료 요청을 생략합니다.
  * 상태 머신 내부에서도 `terminator.isAlreadyTerminated`에 의해 `.targetAlreadyTerminated`로 처리됩니다.

---

## 3. 성능 측정 조건 및 데이터 한계 [확인 완료]

보고서에 기재된 `RSS 17.5 MB`, `CPU 0.0%` 수치의 구체적인 측정 조건과 데이터의 한계를 명시합니다.

* **측정 도구 및 명령**: `ps -o pid,rss,%cpu,command -p 6691`
* **측정 시각**: 2026-10-11 16:10:11 KST (Asia/Seoul)
* **측정 대상 프로세스**: `MacTaskCleaner` (Release 빌드, PID `6691`)
* **측정 환경 및 상태**:
  * 실행 형태: macOS 메뉴 막대 상주 앱 (`LSUIElement = true`)
  * 대시보드 갱신 상태: 백그라운드 타이머(2초 주기) 활성 상태에서 상세 창을 열지 않고 메뉴바 대기 중인 상태.
  * 관측 대상 앱 수: 활성 `.regular` 앱 약 8~10개 (Finder, Activity Monitor, Antigravity IDE, ChatGPT, Brave, Terminal, Slack 등).
  * 측정 수치: **`RSS 17,952 KB` (약 17.5 MB)**, **`%CPU 0.0%`**.
* **데이터의 한계 및 주의사항**:
  * **단일 시점 스냅샷(Point-in-Time Snapshot)** 수치입니다.
  * 10분 이상의 장시간 연속 사용, 프로세스 100개 이상의 과부하 환경, 상세 창(Table View)을 지속 스크롤하거나 연속 종료 요청을 수행할 때의 **최대 사용량(Peak Footprint)을 측정한 결과가 아닙니다**.
  * 따라서 이 수치는 "대기 상태의 초기 정적 점유율"로만 해석해야 하며, 장기 운영 성능은 추후 별도 부하 시험을 통해 검증되어야 합니다.

---

## 4. 검증 항목 종합 요약표

| 검증 항목 | 판정 | 근거 자료 및 위치 |
| :--- | :---: | :--- |
| **Phase 1~2 단위·모의 시험 결과 (32개/73개)** | **확인 완료** | `logs/phase1_phase2_unit_mock_test.log` (해시 일치, 커밋 `3a4ab62`) |
| **Phase 3 macOS 통합 시험 결과 (6개/55개)** | **확인 완료** | `logs/phase3_integration_test.log` (해시 일치, 커밋 `3a4ab62`) |
| **코드 리뷰 V1~V3 회귀 지적 사항 반영** | **확인 완료** | `Sources/MacTaskCleanerCore/ObservationUtilities.swift`, `main.swift` |
| **안전 보호 가드 및 Fail-Closed 설계 명시** | **확인 완료** | `DefaultProtectionChecker`, `TerminationStateMachine.initiateTermination` |
| **PID 재사용 및 커널 마이크로초 재검증** | **확인 완료** | `proc_pidinfo(PROC_PIDTBSDINFO)` 일치 검증 로직 |
| **미저장 문서·타임아웃·강제종료 배제 한계** | **확인 완료** | `SIGKILL`/`forceTerminate()` 배제 원칙 및 AppKit 대화상자 위임 |
| **메모리(17.5MB) 및 CPU(0.0%) 측정 조건** | **확인 완료** | 단일 시점 스냅샷(`ps -o pid,rss,%cpu` @ 16:10:11 KST)으로 한정 명시 |
| **장시간(10분+) 누적 및 고부하 성능** | **미검증** | v1 스냅샷 이후 장기 연속 부하 프로파일링 미수행 |
| **실제 업무용 앱 대상 강제 중단 시험** | **해당 없음 (설계 제외)** | v1 안전 철학에 따라 전용 더미 앱(`DummyTestTarget.app`)으로만 한정 검증 |

---

## 5. 확인 파일 목록

- 검토 요청서: [`docs/reviews/MAC_TASK_CLEANER_REVIEW_9230ee0_2026-10-11.md`](file:///Users/mj/.gemini/antigravity-ide/scratch/aaa_repo/docs/reviews/MAC_TASK_CLEANER_REVIEW_9230ee0_2026-10-11.md)
- 기존 요약 보고서: [`docs/MAC_TASK_CLEANER_EXECUTIVE_SUMMARY_2026-10-11.md`](file:///Users/mj/.gemini/antigravity-ide/scratch/aaa_repo/docs/MAC_TASK_CLEANER_EXECUTIVE_SUMMARY_2026-10-11.md)
- 검증 로그:
  - [`logs/phase1_phase2_unit_mock_test.log`](file:///Users/mj/.gemini/antigravity-ide/scratch/aaa_repo/logs/phase1_phase2_unit_mock_test.log)
  - [`logs/phase3_integration_test.log`](file:///Users/mj/.gemini/antigravity-ide/scratch/aaa_repo/logs/phase3_integration_test.log)
- 소스 코드:
  - [`Sources/MacTaskCleanerCore/DarwinStatusCollector.swift`](file:///Users/mj/.gemini/antigravity-ide/scratch/aaa_repo/Sources/MacTaskCleanerCore/DarwinStatusCollector.swift)
  - [`Sources/MacTaskCleanerCore/TerminationStateMachine.swift`](file:///Users/mj/.gemini/antigravity-ide/scratch/aaa_repo/Sources/MacTaskCleanerCore/TerminationStateMachine.swift)
  - [`Sources/MacTaskCleanerCore/ObservationUtilities.swift`](file:///Users/mj/.gemini/antigravity-ide/scratch/aaa_repo/Sources/MacTaskCleanerCore/ObservationUtilities.swift)
  - [`Sources/MacTaskCleanerApp/AppTerminatorImpl.swift`](file:///Users/mj/.gemini/antigravity-ide/scratch/aaa_repo/Sources/MacTaskCleanerApp/AppTerminatorImpl.swift)
  - [`Sources/MacTaskCleanerApp/SystemMonitorController.swift`](file:///Users/mj/.gemini/antigravity-ide/scratch/aaa_repo/Sources/MacTaskCleanerApp/SystemMonitorController.swift)
