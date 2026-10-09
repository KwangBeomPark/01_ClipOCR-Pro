# ClipOCR-Pro 3~5단계 검수

2026-10-08. 기존 배포 보호 변경을 유지하고 설정 저장 실패 계약·공개 지도·백업 안내를 정비했습니다. 앱 이름·설치 식별자·단축키·버전은 유지합니다.

## 변경된 동작

활성 저장 위치는 실행 파일/소스 진입점 옆 `UserSetting/config.ini`입니다. 새 값이 우선하며 기존 레지스트리의 누락된 키만 1회 복사합니다. 이관 전체를 한 번에 반영하고 실패 시 원본을 보존하며 시작 단계에서 안내합니다.

`src/AtomicSettings.ahk`는 검증한 형제 임시 파일을 flush 후 원자 교체합니다. 직접 쓰기 fallback은 없습니다. SafeWriteLocalSetting/SafeRegWriteString은 기존 bool 계약대로 실패를 전달합니다. 캡처·클립보드·OCR·이미지·번역 설정 setter는 저장 성공 후 런타임 값을 바꿉니다. 번역 단축키 저장 실패는 이전 등록을 다시 적용합니다. 번역 동의·설명서 언어 저장 실패도 사용자에게 알립니다.

공개 구조는 [CODE_MAP](CODE_MAP.md), 전체 UserSetting 백업·새 폴더 복원은 [USER_DATA](USER_DATA.md)와 [관리 도구](../scripts/Manage-UserData.ps1)를 사용합니다. 사용자 지정 캡처 출력 폴더, 외부 Tesseract/tessdata와 TEMP 로그·OCR 임시는 전체 설정 백업 범위 밖에 있습니다.

## 실행한 검증

- 실제 AutoHotkey v2 AtomicSettingsTests: 최초 저장·잠금 실패 false·원본 보존·Unicode 교체/읽기·임시 파일 잔여 확인, 6개 검사 통과.
- 실제 main source health: 고유 설정 fixture에서 실제 setter 10개의 잠금 저장 실패·런타임 상태 유지와 원본 파일 보존을 추가 확인했고 전체 health PASS.
- 실제 main `/Validate`, 정적 검사, Windows PowerShell 5.1 공통 백업 안전성 32개 검사 통과. 빌드 게이트에 원자 저장·백업 검사를 연결했습니다.
- SwiftDeck과 원자 저장 helper의 SHA-256이 동일합니다. 공개 CODE_MAP/README 및 로컬 지도에 설정·백업·대표 흐름을 연결했습니다.

## Gemini와 교차 검수

SwiftDeck과 공유하는 원자 저장 설계에 Antigravity CLI `gemini-3.8-flash-high`, effort high의 내용 있는 응답(54.89초)을 사용했습니다. 완료 증거는 SwiftDeck의 `build/standardization/agy/settings-design-ed52337ff42e4a09bd4ac50c9fac14cf.json`입니다. Buffer 객체 비교 등 잘못된 예시는 제외하고 Codex가 실제 AHK로 검증했습니다. 추가 90초 코드 검수 요청은 빈 응답·0토큰이므로 완료로 인정하지 않았습니다.

04·05 담당이 설정 저장·마지막 setter·health fixture 분리까지 독립 읽기 검수했고 새 P1 회귀를 발견하지 않았습니다. 공통 백업에서 버전·이름 변경 EXE 종료 감지 누락을 발견해 총괄이 보완했고 새 회귀 검사로 확인했습니다.

## 남은 실제 동작 게이트

실제 설정 UI 저장·언어 변경·번역 동의 안내, 번역 단축키 재등록 실패/복원, OCR·캡처·주석·번역 작업과 실행 중 설치 업그레이드는 Windows 사용자 세션에서 확인해야 합니다. 단일 키 저장 실패 보호는 다중 설정 적용 전체의 트랜잭션이나 다중 프로세스 동시 편집 병합을 의미하지 않습니다. 외부 AHK 소스 실행은 직접 종료한 뒤 백업합니다.

실제 사용자 설정 이관·앱 UI 실행·설치·서명·게시·공식 배포 파일 변경은 수행하지 않았습니다.
