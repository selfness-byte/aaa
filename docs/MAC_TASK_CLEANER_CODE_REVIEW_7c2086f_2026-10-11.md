# 맥 작업정리 — 커밋 7c2086f 재검토

- 작성일: 2026-10-11 (Asia/Seoul)
- 저장소: `selfness-byte/aaa`
- 검토 대상: `7c2086f5a2de131367c9a29943afd0fc265d818c`
- 대조 기준: `b70d43e54dbfbe1e46f806e937b454ed05eefe79`의 재검토 지적
- 판정: **기존 다른 PID 조기 알림 오판은 수정 확인. R1/R2 회귀시험의 실제 경로 연결은 미완료이며, 통합시험의 단언문 0개 방어가 퇴행했다.**
- 변경 범위: 이 문서만 추가한다. 제품 코드, 기존 문서, 시험 로그, 알림 설정은 변경하지 않는다.

## 1. 커밋과 알림 수신의 구분

GitHub 연결 도구로 main과 해당 커밋을 조회하고 아래 소스·로그를 읽었다. 사용자 보고의 전체 SHA `7c2086fc50d898ba16fe6d1b64ff0cae84457e5b`와 원격에서 조회된 전체 SHA가 다르므로, 이 문서는 위의 원격 조회값에 고정한다. 짧은 접두사와 커밋 메시지만으로 전체 SHA가 같다고 취급하지 않는다. [S0]

이번 확인은 GitHub 직접 조회이며 웹훅을 수신해서 자동 시작된 확인이 아니다. Slack 메시지, Work 이벤트 작업의 실행 이력, 실제 웹훅 전달 응답은 확보하지 못했다. 커밋이 main에 있다는 사실만으로 실시간 알림 연결의 성공을 판정하지 않는다. GitHub 공식 안내상 웹훅 전달 내역에는 요청 본문·송신 시각·수신 서버의 응답을 확인할 수 있다. 이것과 최종 알림 채널의 수신 기록은 구분해야 한다. [S6]

## 2. 증거 범위

| 자료 | 결과 | 확인 수준 |
| --- | --- | --- |
| 저장된 1~2단계 로그 | 35개 시험, 66개 단언문 통과, 실패 0, EXIT_CODE=0 | 해당 커밋의 로그를 읽음. 전체 패키지 재실행 아님 |
| 저장된 3단계 로그 | 6개 시험, 50개 단언문 통과, 실패 0, EXIT_CODE=0 | 저장된 macOS 실행 기록. 독립 macOS 시험 아님 |
| 이번 분리 실행 | 포맷터 5개 + 알림 추적 5개 + 빈 시험 거절 확인 1개 = 11개 검사 | 10개 통과, 빈 시험 거절 검사 1개 실패. 검토 실행기 종료 코드 1 |

독립 실행 환경은 Linux 6.18.44 x86_64, Swift 6.2.1이다. `ObservationUtilities.swift`는 GitHub 도구 응답을 복사했고, Git blob SHA `460f041c021f65c9b85f738f67f5210972f5f51b`가 원격 값과 일치함을 계산으로 확인했다. 통합 러너의 `printPass`와 `runTest` 메서드 본문은 별도 검사 클래스에 그대로 배치하고 카운터 조회만 추가했다. AppKit, 실제 PID 조회, 더미 실행, 실제 프로세스 종료는 연결하지 않았다.

직접 공개 URL 다운로드는 DNS 오류로 실패했다. 이후 원격 조회는 GitHub 연결 도구를 사용했다. 사용자 로컬 프로젝트에는 접근하지 않았다. 저장된 35개 및 6개 시험의 통과 여부를 아래 검토용 실패와 섞어서 합산하지 않는다. [S1–S5]

## 3. 확인된 개선

### R4: 기존 다른 PID 조기 알림 반례는 해소

공용 NotificationTracker는 `[pid_t: UInt64]`에 이벤트를 보존하고 대상 PID로 조회한다. 통합 러너의 launchDummyApp도 반환된 앱의 PID를 사용한다. 다른 PID 100의 이벤트를 먼저 기록해도 PID 200이 준비 완료가 되지 않았으며, PID 200 자신의 조기 이벤트와 시각은 보존됐다. 미관측 PID와 reset 동작도 분리 실행에서 확인했다. [S1, S2]

이 결론은 종전에 재현한 서로 다른 PID 사이의 오판에 한정한다. PID를 재사용한 모든 상황과 실제 AppKit 이벤트 순서를 포괄적으로 증명했다는 뜻은 아니다.

### 시험 계층과 준비 상태 기록

실제 DarwinStatusCollector를 호출하는 시작 시각 검사 항목이 통합시험 Test 2로 이동했다. 준비 상태 로그도 실제 isFinishedLaunching 속성과 대상 시작 알림 수신 여부를 따로 출력한다. 이 변경은 해당 코드와 저장 로그에서 확인했다. [S2–S5]

## 4. 남은 수정 사항

### V1. 통합시험에서 단언문 0개 검사가 제거됨 — 퇴행 복구

통합 러너의 runTest는 블록 전후의 실패 수가 같으면 PASS를 출력한다. 이전 코드에 있던 실행 단언문 수 검사가 이번 변경에서 제거됐다. 1~2단계 러너에는 그 방어가 여전히 있으므로 두 러너를 구분해야 한다. [S0, S2, S3]

실제 메서드 본문으로 빈 블록을 실행한 결과:

```text
[PASS] empty_case_no_assertions
EXCERPT_ASSERTIONS_PASSED=0
EXCERPT_ASSERTIONS_FAILED=0
EXCERPT_ZERO_FAILURE_SUCCESS_CONDITION=true
AUDIT FAIL empty_integration_test_must_be_rejected
AUDIT_SUMMARY checks=11 passed=10 failed=1
RETURN_CODE=1
```

위 RETURN_CODE=1은 문제를 발견한 별도 검토 실행기의 반환값이다. 원래 통합 러너 전체를 실행한 반환값이 아니다. 이 반례는 현재 6개 시험이 단언문을 하나도 실행하지 않았다는 주장이 아니라, 이후 빈 시험이나 잘못된 조기 반환을 통과시킬 수 있는 방어 퇴행이다.

최소 수정: 통합 runTest에도 passed/failed 변화량을 계산하여 0개이면 실패로 기록하는 기존 규칙을 복구한다. 빈 블록 및 단언문 없는 조기 반환은 실패 수를 증가시켜야 하며, 러너 최종 종료 코드도 실패를 반영해야 한다. 별도 신규 기능은 필요 없다.

### V2. R1 공용 포맷터가 실제 통합 출력 경로에 연결되지 않음

단위 러너는 ChronologyFormatter.format을 호출하지만, 통합 러너는 여전히 자체 formatChronologyTime을 정의하고 정상·지연 종료 출력에서 그 메서드를 호출한다. 따라서 '두 러너가 동일 실제 포맷터를 공유한다'는 보고와 일치하지 않는다. [S1–S3]

공용 포맷터의 nil, 0, 요청보다 이른 시각, 같은 시각, 1초 뒤 시각 입력은 모두 통과했다. 기존 통합 함수도 시각 순서를 검사하므로, 과거 언더플로가 다시 발생했다고 주장하지 않는다. 남은 문제는 회귀시험이 실제 사용되는 함수를 보호하지 않는다는 점이다.

최소 수정: 통합 출력도 공용 계산·포맷 로직을 호출하게 하거나, 실제 경과시간 판정 부분을 공용화한다. 별도의 시각 원문 장식은 유지할 수 있다. 실제 사용 함수에 오류를 넣으면 해당 회귀시험이 실패하는지 확인한다.

### V3. R2 시험은 여전히 시험 안에서 만든 별도 구현을 검사

StrictConfinementTestTerminator는 테스트 블록 내부의 새 클래스다. AppKit 경로의 DummyAppTerminator와 공유되는 구현이 아니다. 더구나 allowedPID와 targetInstance.pid는 모두 1234이고, 모의 신원 조회 결과만 PID 9999다. 따라서 해당 시험에서 종료 어댑터의 PID 불일치 분기는 실행되지 않으며, 상태 머신의 신원 불일치 분기로 차단된다. [S2, S3]

추가된 호출 횟수 0 검사는 유효하지만, 의미는 이 모의 흐름에서 호출하지 않았다는 확인이다. 실제 어댑터의 PID·전체 경로 제한을 직접 검사한 결과로 확대하면 안 된다.

최소 수정: 실제 어댑터와 시험이 같은 격리 판정 로직을 사용하도록 연결하거나, 통합 계층에서 실제 어댑터의 거절 경로를 시험한다. 요청 PID와 허용 PID가 실제로 다른 입력 및 예상 경로 불일치 입력에서 OS 종료 전달부가 0회 호출돼야 한다. 실제 업무 앱을 대상으로 시험할 필요는 없다.

## 5. 다음 판정 기준

다음 수정 범위는 V1의 퇴행 복구와 V2/V3의 시험-실사용 경로 연결에 한정한다. R4의 이미 확인된 다른 PID 반례 수정과 시험 계층 이동까지 다시 설계하지 않는다. 정상 경로 성공 로그, 실제 함수의 오류 방어 시험, Slack/Work 알림 수신 성공을 각각 분리해서 기록한다.

실제 사용자 앱에 대한 종료 허용, 무손실 저장, 모든 프로세스 경쟁 조건 제거, 장시간 누적 없음, M1 대기 CPU·메모리 목표 달성, 웹훅 수신 성공은 이번 검토에서 인증하지 않는다.

## 출처

- [S0: 원격 커밋과 변경 내역](https://github.com/selfness-byte/aaa/commit/7c2086f5a2de131367c9a29943afd0fc265d818c)
- [S1: ObservationUtilities.swift](https://github.com/selfness-byte/aaa/blob/7c2086f5a2de131367c9a29943afd0fc265d818c/Sources/MacTaskCleanerCore/ObservationUtilities.swift)
- [S2: 통합시험 러너](https://github.com/selfness-byte/aaa/blob/7c2086f5a2de131367c9a29943afd0fc265d818c/Sources/MacTaskCleanerIntegrationTests/main.swift)
- [S3: 단위·모의시험 러너](https://github.com/selfness-byte/aaa/blob/7c2086f5a2de131367c9a29943afd0fc265d818c/Sources/MacTaskCleanerTestsRunner/main.swift)
- [S4: 1~2단계 저장 로그](https://github.com/selfness-byte/aaa/blob/7c2086f5a2de131367c9a29943afd0fc265d818c/logs/phase1_phase2_unit_mock_test.log)
- [S5: 3단계 저장 로그](https://github.com/selfness-byte/aaa/blob/7c2086f5a2de131367c9a29943afd0fc265d818c/logs/phase3_integration_test.log)
- [S6: GitHub 공식 웹훅 전달 내역 안내](https://docs.github.com/en/webhooks/testing-and-troubleshooting-webhooks/viewing-webhook-deliveries)
