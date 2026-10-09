# 6개 앱 공통 정비 기준

기준일: 2026-10-08. 범위: ClipOCR-Pro, SwiftDeck, Data Refinery, FileOps Hub, Stepwise, EML Viewer. LocalDataMart 제외.

**1~5단계의 소스·자동 검사·교차 검수는 완료했습니다. 6단계는 현재 공개 배포물 읽기 검수와 빌드/컴파일까지이며, 실제 새 서명·설치/업그레이드/제거·대표 화면·게시 검증은 남아 있습니다.** 여섯 저장소의 이 문서는 동일하게 유지합니다. 문서 작성/모의 검사로 실환경 성공을 주장하지 않습니다. 기존 PL_SUITE_RELEASE_STANDARDS와 충돌하면 아래의 보존·호환·단계 기준을 우선합니다.

## 기준선과 호환성

신규 설치의 기본 위치는 `%LOCALAPPDATA%/Programs/<설치 폴더>`입니다. 아래는 소스 버전/커밋이며 공개 릴리즈 상태와 구분합니다. 버전·제품 이름·실행 파일명·설치 폴더·AppId·단축키·파일 연결·외부 런처 탐색 이름을 스타일 목적으로 바꾸지 않습니다.

| 앱 | 소스 버전 / 기준 커밋 | 표시 이름 / 설치 폴더 | 실행 파일 | 활성 설정 |
| --- | --- | --- | --- | --- |
| 01 | 1.6.1 / 103b129db873 | ClipOCR-Pro / ClipOCR | ClipOCR-Pro.exe | 실행/소스 폴더의 UserSetting/config.ini |
| 02 | 1.4.1 / 466c53a45527 | SwiftDeck / SwiftDeck | SwiftDeck.exe | UserSetting의 config.ini 및 폴더·프롬프트·텍스트 확장·키 리매핑 INI·Backups |
| 04 | 2.0.1 / 71bcdda2edad | Data Refinery / Data Refinery | App04_DataRefinery_v<version>.exe 및 Launcher | UserSetting의 설정·로그·프리셋·최근 작업·datasets |
| 05 | 1.4.3 / a3dc860d5bd7 | FileOps Hub / FileOps | App05_FileOps.exe | UserSetting/settings.json·로그·이력, 기존 설치 경로 유지 |
| 06 | 0.3.0 / fdb941fd8842 | Stepwise / Stepwise | Stepwise.exe | UserSetting/settings.json·macros·results, 사용자 지정 및 쓰기 불가 fallback |
| 07 | 0.1.16 / 364b34438bba | EML Viewer / EML Viewer | EmlViewer.exe, App07_EmlViewer.exe 호환 | 인지되는 frozen EXE 옆 UserSetting, 그 외 기본 설치 위치의 UserSetting |

기존 레지스트리/Roaming 원본을 보존하고 새 저장 위치의 기존 값이 우선합니다. 02의 예전 Roaming/SwiftDeck·AHK_FolderHotKey와 구형 Backups도 지우지 않습니다. 05의 구형 설정 자동 이관 제외 계약을 유지합니다. 외부 DB·입력·출력·매크로 위치는 임의 이동하지 않습니다. 앱별 실제 경로 및 백업 범위는 [USER_DATA](USER_DATA.md)에 있습니다.

| 앱 | 유지한 설치 AppId | canonical 설치 설계 / 호환 진입점 |
| --- | --- | --- |
| 01 | {5C88B084-2578-4D4B-A63E-C246990C05DC} | installer/setup.iss |
| 02 | {131A33AA-3326-4372-8B18-562CCC01BA5E} | installer/setup.iss |
| 04 | {2E1A7E3F-8D78-4DB0-9B62-50B12CD4326F} | installer/setup.iss |
| 05 | {2A0D58B7-8D1D-44B1-9C3A-2B33F4F3DF11} | installer/setup.iss, src/app_identity.py |
| 06 | {C782B3E1-628D-4C10-9E1D-3A20B71E86E2} | installer/setup.iss, stepwise.iss는 include wrapper |
| 07 | {A9D9B7C3-04B8-4D2F-B28C-5B18C01C9CE1} | installer/setup.iss, packaging/inno/eml_viewer.iss는 wrapper |

## 공통 동작 기준과 적용

| 영역 | 적용 기준 |
| --- | --- |
| 공개 저장소 | 모든 깊이 UserSetting·로컬 환경 파일·개인 키 제외, 추적 fixture는 중립 값. 공개 docs/CODE_MAP.md 제공 |
| 도구 탐색 | 개발자 개인 경로·다른 저장소에 의존하지 않음. 명시 인자/환경변수 우선, PATH·로컬 도구·SDK 탐색. 잘못된 명시 경로는 실패 |
| 설정 형식·우선순위 | AHK INI / Python JSON 유지. 저장 키 존재로 사용자 지정 구분. 값이 기본값과 같거나 명시적으로 빈 값이어도 우선 |
| 저장 실패 | 고유 sibling 임시 파일·완전 기록·검증/flush·원자 교체. 직접 원본 쓰기 fallback 없음. 실패 전달, 저장 성공 후 런타임 반영 |
| 손상 보호 | 읽기 권한/잠금 실패를 손상으로 오인하지 않음. 손상 JSON은 무단 기본값 덮어쓰기 차단. 기존 복구 계약은 검증된 원본 사본 확보 후만 수행 |
| 이관·복원 | 원본 보존·새 값 우선·반복 보호. 07은 검증한 임시 복사본을 덮어쓰기 없이 반영. 02 rollback 실패는 복구 사본 유지·실패 안내 |
| 백업 | 기본 UserSetting 전체. 04 datasets·06 results 제외는 명시 SettingsOnly 및 manifest 기록. 외부 사용자 경로 별도 보관 |
| 백업 검증·복원 | 앱 종료/잠금·해시·목록·범위·중복·ZIP 경로·링크·크기 검증. 아직 없는 새 폴더로 복원. 기존 활성 자료 자동 덮어쓰기 없음 |
| 배포 순서 | 앱/Launcher 서명 → ZIP·설치 생성 → 설치 파일 단일 서명 → 별칭 복사 → 해시/서명/매니페스트 검증 → 공식 폴더 반영 |
| 두 설치 이름 | 한 검증 파일의 사본으로 제공, SHA-256 동일. 기존 게시본을 재서명/덮어쓰기하지 않고 다음 새 버전부터 적용 |
| 실패·재시도 | 미서명/실패 결과가 공식 파일을 바꾸지 않음. 게시 재시도는 검증된 누락 자산만 보충, 기존 다른 바이트 자산은 실패 |
| 저장소 역할 | installer는 패키징 입력, scripts는 작업, build/dist는 임시/격리, release는 공식 검증 결과 |
| 사용성 | 실제 설정/결과 위치·백업 범위·실패 안내를 정확히 표시. 04 업데이트/정보 명칭, 06 설정/결과 폴더 액션, 07 실제 설정 폴더 표시 |

07 SMTP 포트 25·명시 빈 서버는 유지하며 누락 키만 중앙 기본값을 사용합니다. 중앙 포트는 1–65535로 확인합니다. 02 일반 단축키는 config.ini만 저장하고 누락 키에만 구형 General을 참고합니다. 06 GUI·CLI 기본 결과 경로는 저장한 results_dir를 사용하며 명시 CLI 경로가 우선합니다.

01·02에는 공유 AtomicSettings.ahk, 04·05에는 앱별 원자 저장 helper를 적용했습니다. 단일 키 원자 저장은 모든 다중 설정 동작의 전체 트랜잭션이나 여러 프로세스의 동시 편집 병합을 보장하지 않습니다. 민감 값이 든 ZIP은 암호화되지 않으므로 개인 보관하며 같은 사용자/PC 암호화 제약을 따릅니다.

## 구조·문서 기준

05 canonical spec은 installer/App05_FileOps.spec이며 scripts/App05_FileOps.spec은 호환 wrapper입니다. 07 canonical은 installer/eml_viewer.spec 및 setup.iss이며 packaging의 이전 이름은 위임합니다. 06 stepwise.iss 중복 내용은 setup.iss include로 통합했습니다. 06 임시 빌드는 release에서 분리하고 release/build/signtool 레거시 탐색을 제거했습니다. 07 installer의 과거 배포물은 해시 검증 후 build/release-history에 보존했습니다.

04 docs/project-structure.md의 검수 전 사용자 메모 원문은 보존하고 이전 경로임을 표시한 뒤 현재 installer/build/dist/release 역할을 명시했습니다. AI_CODE_MAP.md의 기존 공유 여부는 유지하며, 개인 로컬 지도를 강제로 추적하지 않습니다. 여섯 앱 모두 공개 docs/CODE_MAP.md·README로 공통 작업 기준을 공유합니다.

01·02는 다음 버전 공식 세트 반영 때 기존 세트를 build/release-history에 보존하고 이동 실패 시 복원합니다. 06·07은 새 버전별 파일/장부를 추가하며 기존 공식 세트와 generic 장부를 유지합니다. 04·05는 기존 보호 절차를 유지합니다. 보호 폴더 권한을 임의로 바꾸지 않습니다.

## 설치·업그레이드 기준

1. 공식 서명·대상 버전·기존 설치 위치/식별자를 확인하고 사용자 자료를 백업합니다.
2. 실행 중 구버전에 정상 종료를 요청하거나 종료를 안내합니다. 자동화/미저장 작업을 고려하며 강제 종료를 기본값으로 삼지 않습니다.
3. 잠금·접근 거부가 남으면 새 EXE 복사 전 설치를 차단합니다. 07은 기존 AppMutex의 사용자 종료 안내/차단을 유지합니다.
4. 새 파일을 반영하고 성공·소유권·새/이전 해시 확인 후 04 버전별 EXE·05 호환 목록의 구형 EXE만 정리합니다. 고정 이름은 기존 위치에서 교체합니다.
5. UserSetting·DB·매크로·결과·외부 업무 자료 및 기존 폴더 전체를 먼저 지우지 않습니다. 새 바로가기/파일 연결과 실패·취소 후 기존 앱/자료를 확인합니다.

설치 옵션·잠금 회귀·Inno 컴파일은 실제 실행 중 업그레이드 성공과 다릅니다. [INSTALL_UPGRADE_ACCEPTANCE](INSTALL_UPGRADE_ACCEPTANCE.md)에 실제 Windows 합격 조건과 미실행 항목을 기록했습니다.

## 단계·판정

| 단계 | 작업 | 현재 판정 |
| --- | --- | --- |
| 1 | 기준선·공개 저장소 보호·SMTP 우선순위·설치 소스 점검 | 소스/자동 검사 완료 |
| 2 | 스테이징·서명 순서·별칭·게시 보호·설치 잠금/정리 | 소스/자동 회귀·격리 빌드 완료 |
| 3 | 설정 통합·저장 보호·전체 백업/새 폴더 복원 | 소스/실패 주입·복원 회귀 완료 |
| 4 | spec/설치 정의·호환 wrapper·공유 코드 지도 | 참조 검사·실제 canonical 05/07 빌드·06/07 설치 컴파일 완료 |
| 5 | 실제 위치/백업/실패/업데이트 명칭·대표 흐름 보호 | 구현/관련 회귀 완료, 실제 업무 화면 검수는 6단계 |
| 6 | 실제 설치/실행 중 업그레이드/제거/포터블/서명/게시 | 현재 공개 자산 읽기 검수 완료. 새 서명·실환경·게시 미완료 |

## 현재 배포 예외와 근거

공개 06 0.3.0 포터블 내부 EXE 및 07 0.1.16 설치/포터블 내부 EXE는 미서명입니다. 기존 02/06 두 설치 이름은 바이트가 다릅니다. 04 공개 장부와 로컬 장부/별칭 차이가 있고 05 공개 최신은 1.4.2(소스 1.4.3)입니다. 기존 파일을 덮어쓰지 않고 다음 새 버전으로 해소해야 합니다. 05 제한된 로컬 release ACL은 유지하면서 공개 설치/Launcher digest·서명 Valid를 별도 확인했습니다.

Windows Sandbox가 없는 현재 환경과 미서명 QA 정책 차단 때문에 실제 설치/제거는 완료로 표시하지 않습니다. 06 offscreen 회귀 통과는 실제 화면·DPI·포커스·단축키 검증과 구분합니다. SimplySign 로그인·PIN/OTP·개인 키는 사용자 열린 세션에서 처리합니다.

[종합 검수](STANDARDIZATION_FINAL_REVIEW.md), [2단계 기록](STANDARDIZATION_PHASE2_SUMMARY.md), [앱별 3~5단계 검수](STANDARDIZATION_PHASE3_5_REVIEW.md), [agy 활용](AGY_USAGE_REVIEW.md)을 참조하세요. 자동 검수와 실제 인증서 서명/설치/게시를 구분하며 기존 사용자 자료·미커밋 수정·서명물·태그를 보존합니다.
