# 맥 작업정리 v1 — 핵심 설계 및 구현 완료 요약 보고서

- 작성일: 2026-10-11 (Asia/Seoul)
- 대상 저장소: `selfness-byte/aaa`
- 대상 환경: Apple Silicon M1 (RAM 8GB) macOS

---

## 1. 핵심 설계 원칙

1. **관측 중심의 보수적 안전성**:
   - 백그라운드 임의 프로세스 자동 종료, RAM 강제 퍼지(Purge), 캐시 일괄 삭제 일체 배제.
   - 창 유무나 비활성 시간을 근거로 사용 종료를 임의 추정하지 않음.
2. **Fail-Safe 차단 (Default Deny)**:
   - 시스템 필수 프로세스(Finder, WindowServer, Dock), 개발 도구(Antigravity IDE, Terminal, VS Code, Xcode), root(`UID==0`) 프로세스는 종료 원천 차단 (`🔒 보호됨`).
   - 프로세스 신원(`pbi_start_tvsec`, `pbi_start_tvusec`), UID, 바이너리 경로 불일치 시 차단.
3. **표준 정상 종료(`terminate()`) 경로 전용**:
   - 사용자가 명시적으로 선택한 일반 `.regular` 앱에 대해서만 표준 `NSRunningApplication.terminate()` 호출.
   - `sudo`, `kill`, `killall`, `pkill`, `forceTerminate()` 등의 강제 수단 전면 배제.

---

## 2. 계층별 구현 및 검증 결과

| 계층 | 주요 구현 내용 | 검증 결과 |
| :--- | :--- | :--- |
| **Phase 1: 자원 관측 & 계산 코어** | • Darwin 커널 통계 수집 (`DarwinStatusCollector`)<br>• 128비트 전폭 정수 기반 나노초 환산 및 CPU 계산<br>• 오버플로 및 단조 시계 역전 방어 | 단위 시험 14개 통과 |
| **Phase 2: 상태 머신 & 안전 가드** | • Actor 기반 `TerminationStateMachine`<br>• 엄격한 신원 검증 및 중복 차단<br>• 타임아웃 레이스 및 재실행 격리 | 모의 시험 18개 통과<br>*(Phase 1+2 합계 73개 단언문 100% 통과)* |
| **Phase 3: AppKit 통합 테스트** | • `DummyTestTarget.app` 번들 실제 실행 및 관측<br>• AppKit 정상 종료 및 지연 종료 라이프사이클<br>• 나노초 단위 이벤트 시간축(Chronology) 추적 | 통합 시험 6개, 55개 단언문 100% 통과 |
| **코드 리뷰 반영 (7c2086f)** | • V1: 통합 러너 단언문 0개 거절 방어 복구<br>• V2: `ChronologyFormatter` 공용 로직 완전 일치<br>• V3: 공용 `TargetConfinementGuard` 직접 검증 | 회귀 검증 완료 |
| **Phase 4: 네이티브 앱 (UI)** | • 메뉴 막대 상주 앱 (`NSStatusItem`, `MacTaskCleanerApp`)<br>• 실시간 물리 RAM·스왑·메모리 압박 대시보드<br>• 앱별 실시간 메모리 검색 및 안전 종료 요청 창 | **실행 완료**<br>실측 **17.5 MB RSS**, **CPU 0.0%** |
| **이벤트 & 알림 파이프라인** | • GitHub main 푸시 → Webhook → 실시간 알림 연동 | HTTP 200 OK 실시간 수신 검증 완료 |

---

## 3. 실행 및 패키징

```bash
# 릴리스 앱 번들 빌드 및 패키징
./scripts/build_app.sh

# 앱 실행 (메뉴 막대 상주)
open .build/out/Products/Release/MacTaskCleaner.app
```
