# Mac Task Cleaner (맥 작업정리)

Apple Silicon M1 macOS 환경(8GB RAM)을 위한 안전한 프로세스 관찰 및 정상 종료 관리 도구입니다.

## 1. 핵심 철학 및 안전 설계

1. **단순 고점유와 불필요한 프로세스의 엄격한 구분**:
   - 무분별한 메모리 퍼지(RAM Purge)나 비GUI 프로세스(Python, Node, CLI 데몬)의 강제 종료를 배제합니다.
   - 창이 닫혀 있더라도 백그라운드 작업을 정상 수행할 수 있는 AppKit 특성을 존중하여, "창이 없음"을 "사용 종료"로 추정하지 않습니다.
   - 비GUI 프로세스는 **관찰 전용(Observation-Only)**으로 한정합니다.
2. **보호 정보 부족 시 Fail-Safe 차단 (Default Deny)**:
   - PID, 마이크로초 단위 프로세스 시작 시각(`pbi_start_tvsec`, `pbi_start_tvusec`), UID, 보호 규칙 조회 실패 시 종료 요청을 원천 차단합니다.
   - `UID == 0` (root/시스템 프로세스) 및 root 컨텍스트 실행(`allowedUID == 0`)은 무조건 차단합니다.
3. **AppKit 정상 종료(`terminate()`) 경로 전용**:
   - 사용자가 명시적으로 선택한 `.regular` GUI 앱에 한하여 `NSRunningApplication.terminate()`를 통해서만 종료를 요청합니다.
   - `sudo`, `kill`, `killall`, `pkill`, `forceTerminate()` 등의 강제 수단을 일체 배제합니다.
   - 지연 종료 시 타임아웃이 초과되더라도 강제 종료로 전환하지 않고 '종료 미확인'(`unconfirmedWithinTimeout`) 상태를 유지하며, 이후 정상 종료 관측 시 늦은 확인(`confirmed(.lateNotification)`)으로 갱신합니다.

---

## 2. 패키지 타깃 구조

- **`MacTaskCleanerCore`**:
  - `CPUUsageCalculator.swift`: Swift 표준 라이브러리 128비트 전폭 정수 곱셈·나눗셈(`multipliedFullWidth`, `dividingFullWidth`) 기반의 정확한 나노초 환산($\lfloor \frac{\text{ticks} \times \text{numer}}{\text{denom}} \rfloor$, 부동소수점 오차 0, 절사 차이 $<1\text{ns}$), 단조 시계 역전 및 슬립/웨이크 리셋 감지.
  - `DarwinStatusCollector.swift`: 커널 API(`proc_pidinfo` 바이트 수 일치 검증, `host_statistics64` $\frac{\text{sizeof}(\text{vm\_statistics64\_data\_t})}{\text{sizeof}(\text{integer\_t})}$ 요소 수 일치 검증, `sysctl vm.swapusage` 바이트 수 일치 검증, `PROC_PIDTASKINFO` 누적 CPU 시간 수집).
  - `TerminationStateMachine.swift`: `RequestID`와 `ExecutionInstanceID` 이중 상관관계를 직렬화하여 원자적 중복 방지, 사전 안전 검증, 비동기 타임아웃 레이스를 처리하는 Actor 기반 상태 머신.
- **`MacTaskCleanerTestsRunner`**:
  - 1단계(CPU 계산, Mach timebase, 단조 시계, 오버플로 거부) 14개 테스트 + 2단계(모의 상태 머신, root 차단, 중복 차단, 타임아웃 레이스, 재실행 격리) 18개 테스트 = 총 32개 테스트, 53개 단언문 실행 러너.
- **`DummyTestTarget`**:
  - AppKit 생명주기(`NSApplication`, `setActivationPolicy(.regular)`, `applicationShouldTerminate:`)를 갖춘 시험용 `.app` 번들 실행체. 일반 즉시 종료 및 `--delay-terminate` 인자를 통한 지연 종료(`.terminateLater`) 지원.
- **`MacTaskCleanerIntegrationTests`**:
  - 실제 macOS 환경에서 실행되는 3단계 통합 시험 러너. `NSWorkspace.openApplication` 실행, `NSWorkspace.shared.notificationCenter` 알림 수신, 런루프 동기 이벤트 처리, 커널 메트릭 수집 및 실제 타임스탬프 이벤트 크로놀로지 검증.

---

## 3. 빌드 및 테스트 방법

### 3.1 더미 앱 번들 준비
통합 시험 실행 전, AppKit 앱 번들(`DummyTestTarget.app`)을 빌드하고 패키징합니다.
```bash
./scripts/build_dummy_app.sh
```

### 3.2 1~2단계 단위 및 모의 상태 테스트 실행
```bash
swift run MacTaskCleanerTestsRunner
echo "EXIT_CODE=$?"
```

### 3.3 3단계 macOS 통합 시험 실행
```bash
swift run MacTaskCleanerIntegrationTests
echo "EXIT_CODE=$?"
```

---

## 4. 검증 로그

- 1~2단계 단위/모의 시험: [logs/phase1_phase2_unit_mock_test.log](logs/phase1_phase2_unit_mock_test.log) (32개 테스트, 53개 단언문 통과, `EXIT_CODE=0`)
- 3단계 macOS 통합 시험: [logs/phase3_integration_test.log](logs/phase3_integration_test.log) (5개 통합 시나리오, 46개 단언문 통과, `EXIT_CODE=0`)