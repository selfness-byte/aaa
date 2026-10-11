# 맥 작업정리 — 커밋 9be2ec6 재검토

- 작성일: 2026-10-11 (Asia/Seoul)
- 저장소: `selfness-byte/aaa`
- 검토 대상: `9be2ec6289a890c7157840e0ebc182716fd04402`
- 대조 기준: `14e2fca7bb4a238112210f230683029403da141c`의 R1~R4 검토 문서
- 판정: **R1·R3의 수정 코드 확인, R2의 제한 강화 확인. R4의 앱 준비 알림 귀속과 회귀시험 연결은 추가 보완 필요.**
- 변경 범위: 재검토 문서만 추가한다. 제품 소스·기존 문서·시험 로그·알림 설정은 변경하지 않는다.

## 1. 이번에 확인한 범위

GitHub 연결 도구로 main의 HEAD, 대상 커밋의 diff, 수정된 Darwin 수집 함수, 통합 시험의 대상 제한·번들 준비·실행 알림·정상/지연 종료 구간, 새 회귀시험 3개, 저장된 두 시험 로그를 확인했다. 기존 단위 러너 전체를 다시 실행하거나 macOS 통합 시험을 재실행하지 않았다. [S1–S6]

독립 실행은 Linux x86_64 / Swift 6.2.1에서 수행한 두 코드 조각의 합성 입력 검사에 한정된다. 대상 커밋의 `NotificationTracker` 클래스와 `formatChronologyTime` 본문을 가져와, 새 검토용 실행기에 배치했다. 메서드 본문은 변경하지 않았고 AppKit은 연결하지 않았다. 실제 PID 조회·더미 앱 실행·프로세스 종료는 수행하지 않았다.

| 증거 종류 | 확인한 결과 | 한계 |
| --- | --- | --- |
| 저장된 1~2단계 명칭의 로그 | 35개 시험, 61개 단언문 통과, 실패 0, EXIT_CODE=0 | 저장된 실행 보고. 1개 시험이 실제 Darwin 조회를 하므로 모두 순수/모의 시험은 아님 |
| 저장된 3단계 로그 | 5개 시험, 48개 단언문 통과, 실패 0, EXIT_CODE=0 | macOS에서 독립 재실행한 결과 아님 |
| 추출 로직 검토용 실행기 | 컴파일 종료 0, 검사 7개 중 6개 통과·1개 실패, 실행 종료 1 | 아래 R4 오판 반례가 의도한 기대값을 위반한 결과. 원래 35개 시험의 실패로 합산하지 않음 |
| 로그 산술 재계산 | CPU 146.03% 및 종료 관측 구간의 계산 일치 | 새로운 실기기 측정이나 대기 성능 결과 아님 |

소스 열람은 GitHub 연결 도구로 수행했다. 컨테이너의 별도 공개 원격 다운로드 시도는 DNS 오류로 실패했다. 이 제한을 우회해 사용자 로컬 프로젝트에 접근하지 않았다.

## 2. R1~R4별 판단

| 항목 | 확인한 변경 | 판정 |
| --- | --- | --- |
| R1: 관측 시각 UInt64 감산 | Optional 시각, 즉시 종료 확인 경로의 시각 기록, 출력 전 순서 검사 추가 | 문제였던 감산 경로는 수정 확인. 실제 함수 본문 추출 검사 4개도 통과 |
| R2: 더미·종료 알림 제한 | PID 불일치 시 false, 표준화한 전체 번들 경로 비교, 종료 알림의 앱 동등성 비교 추가 | 제한 강화 확인. 실제 어댑터를 호출하는 거절 경로 회귀시험은 부족 |
| R3: CPU 표본 신원 | CPU 조회 전후 BSD 시작 시각·좀비 상태·반환 크기 확인, 반환 표본에 커널 시작 시각 사용 | 수정 확인. 현재 추가된 실제 API 시험은 호출자의 오래된 시작 시각 거절을 검사하며, 수집 중 교체 등 모든 경로를 검증한 것은 아님 |
| R4: 번들·시작 준비 | 파일 준비의 try? 제거, 오류 전파·실행 권한 검사, 시작 알림 또는 isFinishedLaunching 대기 | 번들 오류 전파는 개선. 시작 알림의 대상 귀속 오류가 남아 완전 해결로 닫지 않음 |

출처: 수정 diff [S1], 통합 시험 [S2], Darwin 수집기 [S3].

### R1: 수정 확인과 회귀시험 범위의 구분

실제 `formatChronologyTime` 본문에 nil, 0, 요청보다 이른 시각, 요청 1초 뒤 시각을 입력한 검토용 실행에서 네 경우 모두 기대 결과를 얻었다. 다만 이는 함수 본문을 별도로 실행한 검사이며 AppKit에서 빠른 종료 이벤트를 실제 발생시킨 시험은 아니다.

저장소에 추가된 `testChronologyCalculationSafeUnderflow`는 실제 함수를 호출하지 않고, 테스트 내부의 새 `formatTime` 복사본을 호출한다. 실제 함수에 오류가 다시 생겨도 복사본이 그대로면 이 시험은 통과할 수 있다. 실제 호출 지점과 시험이 같은 구현을 사용하도록 연결해야 한다. [S2], [S4]

### R2: 개선됐지만 false 자체가 instanceMismatch를 보장하지는 않음

PID 불일치 때 종료 사실을 반환하지 않도록 바꾼 수정은 적절하다. 다만 false는 단지 '이미 종료됐다고 확인하지 않음'을 뜻하며, 최종 `.instanceMismatch` 상태는 뒤의 스냅숏 비교 조건에 의존한다. 어댑터 대상과 다른 실행을 요청하되 조회 스냅숏이 그 요청 실행과 일치하는 경우까지 모두 `.instanceMismatch`로 귀결된다고 일반화하지 않는다.

추가된 `testTargetMismatchDoesNotTriggerAlreadyTerminated`는 `MockAppTerminator`와 불일치 스냅숏을 사용한다. 수정된 `DummyAppTerminator.isAlreadyTerminated`나 경로 검사를 호출하지 않으므로, 실제 어댑터가 되돌아가는 회귀를 직접 잡는 시험이 아니다. 실제 어댑터가 사용하는 대상 검증 로직을 시험에 연결하고 거절 시 OS 종료 요청 0회임을 확인해야 한다. 실제 업무 앱을 시험 대상으로 쓸 필요는 없다. [S2], [S4]

종료 알림의 `termApp == app`는 앱 동등성 확인으로 기술한다. 기존 주석의 'reference equality'를 이유로 `===`로 바꾸지 않는다. Apple 문서도 앱 비교를 PID에만 의존하지 말고 `isEqual(_:)`을 사용하도록 안내한다. [A2]

### R3: 조회 검증과 시험 계층의 구분

커널 시작 시각을 CPU 조회 전후에 확인하고, 호출자가 특정 실행을 지정했는데 커널 값이 다르면 nil을 반환하는 변경을 확인했다. 시작 시각 0/0인 최초 조회는 커널에서 읽은 시작 시각을 표본에 넣는다. 이 변경은 '새 카운터에 옛 시작 시각을 복사'하던 경로를 보완한다. 별도 시스템 호출들을 원자적 연산으로 만든다는 의미는 아니다. [S3]

`testRejectStaleInstanceStartTimeOnCPUSample`은 실제 `DarwinStatusCollector`를 생성하고 실행 중인 자신을 `proc_pidinfo`로 조회한다. 따라서 커널 호출 없는 1~2단계에 해당하지 않는다. 이를 3단계로 옮기거나 실제 OS 시험을 명시적으로 분리해야 한다. 현재 수치 35/61은 로그에 존재하지만 전부 순수/모의 검증이라는 분류는 부정확하다. [S4], [S5]

## 3. R4의 남은 문제: 다른 실행의 조기 알림이 준비 완료로 남음

`NotificationTracker.filterPID`의 초기값은 0이다. `recordIfMatches`는 필터가 0일 때 들어온 이벤트를 수용해 `received=true`로 만든다. `setFilterPID`는 필터만 바꾸고, 이미 기록한 이벤트가 어느 PID에서 왔는지 검증하거나 재분류하지 않는다. 실제 `launchDummyApp`은 openApplication 완료를 기다린 후에 필터를 설정한다. [S2]

합성 입력으로 아래 순서를 재현했다. PID 100과 200은 설명·시험용 숫자이며 실제 프로세스 번호를 조회한 것이 아니다.

1. 필터 미설정 상태에서 PID 100의 시작 이벤트가 도착한다.
2. 반환된 실제 대상 앱의 PID가 200이라고 가정하고 `setFilterPID(200)`을 호출한다.
3. PID 200의 준비 완료 이벤트가 없고 `isFinishedLaunching=false`여도 `isReceived`는 true다.
4. 현재의 `isFinishedLaunching || isReceived` 판정은 준비 완료를 수용한다.

검토용 실행의 실제 출력:

```text
PASS R4_matching_event_before_filter actual=true
PASS R4_other_event_after_filter actual=false
FAIL R4_other_event_before_filter_must_not_mark_target_ready expected=false actual=true
R4_COMBINED_READINESS targetFinished=false trackerReceived=true accepted=true
PROBE_SUMMARY passed=6 failed=1
PROBE_EXIT_CODE=1
```

정상 경로에서는 같은 번들 식별자의 다른 실행이 끼어들지 않을 수 있다. 이번 저장된 macOS 로그에서 이 오판이 발생했다거나 다른 앱을 종료했다고 주장하지 않는다. 재현한 것은 '다른 실행의 조기 이벤트를 이후 대상의 준비 사실로 유지하는' 추적 로직의 오류다.

수정 방향: 대상 객체가 반환되기 전의 이벤트도 앱 객체/실행별로 저장하고, 반환된 대상과 대응되는 이벤트만 준비 근거로 사용한다. 필터 설정 시 무조건 모두 지우면 올바른 대상의 조기 이벤트도 잃을 수 있으므로, 올바른 조기 이벤트는 보존하고 무관한 이벤트만 제외해야 한다. Apple의 시작 알림은 userInfo에 해당 `NSRunningApplication`을 제공한다. [A1]

추가로 일부 출력의 `isFinishedLaunching=true`는 속성 값을 읽은 보간이 아니라 문자열 상수다. 실제 속성 값과 '시작 알림으로 준비를 확인했는지'를 구분해 기록해야 한다. `Test 2`에는 별도 true 단언문이 있지만 그 사실을 다른 시험의 하드코딩된 로그까지 확대하지 않는다. [S2]

수용 기준은 같은 실행의 알림이 먼저 오는 경우와 다른 실행의 알림이 먼저 오는 경우를 모두 실제 공유 추적 로직으로 시험하는 것이다. 서로 다른 실행의 이벤트로 준비 여부를 확정하지 않아야 한다.

## 4. 저장 로그의 CPU·시각 재계산

출처는 대상 커밋의 `logs/phase3_integration_test.log`이다. [S6]

- 사용자 틱 증가: 26,372,904 - 25,087,132 = 1,285,772
- 시스템 틱 증가: 12,214,995 - 11,625,256 = 589,739
- 합계 틱: 1,285,772 + 589,739 = 1,875,511
- 정수 CPU 나노초: floor(1,875,511 × 125 / 3) = 78,146,291ns
- 단조 경과시간: 345,552,220,868,791 - 345,552,167,355,250 = 53,513,541ns
- CPU 비율: 78,146,291 / 53,513,541 × 100 = 146.03087282151634%, 소수 둘째 자리 146.03%

계산값은 로그와 일치한다. 시험용 연산 부하 구간이며, 단일 코어 100% 기준 프로세스 CPU를 100%에서 자르지 않는 정의를 사용한다. 대기 CPU 1% 목표와 비교하지 않는다.

| 구간 | 나노초 차이 ÷ 1,000,000,000 | 초 |
| --- | --- | --- |
| 정상 요청 → 종료 속성 관측 | (345552961374041 - 345552870050583) / 1e9 | 0.091323458 |
| 정상 요청 → 알림 | (345552934237958 - 345552870050583) / 1e9 | 0.064187375 |
| 지연 요청 → 타임아웃 | (345553520042833 - 345553194203708) / 1e9 | 0.325839125 |
| 지연 요청 → 늦은 알림 | (345554511922125 - 345553194203708) / 1e9 | 1.317718417 |

통합 로그의 실행시간 2,823.274ms / 1,000 = 2.823274초다. 이는 제품의 지속 동작·메모리 누적 시험이 아니다. 로그의 전체 소요시간 감소를 제품 성능 향상으로 해석하지 않는다.

## 5. 다음 수정 범위

전체 설계 재작성이나 새 UI 개발보다, 아래 세 범위만 먼저 마무리한다.

1. R4 시작 이벤트 귀속 수정. 다른 PID 조기 알림 거절과 올바른 조기 알림 보존을 함께 시험한다.
2. R1·R2 회귀시험을 실제 사용 로직에 연결한다. 복사본/독립 모의 구현의 통과로 수정 함수의 회귀 방지를 대신하지 않는다.
3. 실제 Darwin 조회 시험을 3단계로 구분하고, 준비 상태 로그는 관측한 값/근거만 표시한다.

현재 문서는 R1·R3의 모든 OS 경쟁 조건 제거, R2의 모든 경로에 대한 원자적 신원 보장, 실제 업무 앱의 무손실 종료 또는 M1 성능 목표 달성을 인증하지 않는다. 국소 수정 이후 기존 시험과 영향받은 반례의 결과를 같은 커밋에 보존하면 된다. 웹훅 생성·예약 변경·실시간 알림 수신 설정은 이번 코드 재검토의 작업 범위에 포함하지 않았다.

## 출처

- [S1: 수정 커밋](https://github.com/selfness-byte/aaa/commit/9be2ec6289a890c7157840e0ebc182716fd04402)
- [S2: 통합 시험 러너](https://github.com/selfness-byte/aaa/blob/9be2ec6289a890c7157840e0ebc182716fd04402/Sources/MacTaskCleanerIntegrationTests/main.swift)
- [S3: DarwinStatusCollector](https://github.com/selfness-byte/aaa/blob/9be2ec6289a890c7157840e0ebc182716fd04402/Sources/MacTaskCleanerCore/DarwinStatusCollector.swift)
- [S4: 단위·모의 명칭의 시험 러너](https://github.com/selfness-byte/aaa/blob/9be2ec6289a890c7157840e0ebc182716fd04402/Sources/MacTaskCleanerTestsRunner/main.swift)
- [S5: 저장된 1~2단계 로그](https://github.com/selfness-byte/aaa/blob/9be2ec6289a890c7157840e0ebc182716fd04402/logs/phase1_phase2_unit_mock_test.log)
- [S6: 저장된 3단계 로그](https://github.com/selfness-byte/aaa/blob/9be2ec6289a890c7157840e0ebc182716fd04402/logs/phase3_integration_test.log)
- [S7: 이전 R1~R4 검토](https://github.com/selfness-byte/aaa/blob/14e2fca7bb4a238112210f230683029403da141c/docs/MAC_TASK_CLEANER_CODE_REVIEW_5746995_2026-10-11.md)
- [A1: Apple — didLaunchApplicationNotification](https://developer.apple.com/documentation/appkit/nsworkspace/didlaunchapplicationnotification)
- [A2: Apple — processIdentifier 및 앱 비교 안내](https://developer.apple.com/documentation/appkit/nsrunningapplication/processidentifier)
