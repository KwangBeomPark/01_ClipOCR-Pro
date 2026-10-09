# 공통 정비 1단계 검수 기록

검수일: 2026-10-07. 범위: 01·02·04·05·06·07. LocalDataMart 통합 제외.
공통 기준은 [SUITE_STANDARDIZATION.md](SUITE_STANDARDIZATION.md)입니다. 이 기록은 소스·자동 검사 결과이며 배포 완료 기록이 아닙니다.

## 반영 사항

- 여섯 저장소에 같은 공통 기준선·호환성·설정·배포·설치 흐름·단계별 완료 기준을 기록하고 README에서 연결했습니다.
- 모든 저장소에 사용자 설정·환경 파일·개인 키 보호 규칙을 확인·보완했습니다. `.env.example`은 공유 가능하게 유지합니다.
- 02·06의 서명 도구 탐색은 개인 작업 경로·다른 저장소 의존성을 제거하고 명시 경로·환경변수·PATH·로컬 도구·Windows SDK를 사용합니다.
- 07 테스트의 내부 SMTP 도메인을 중립 예시로 교체했습니다.
- 07은 저장 키가 있을 때 SMTP 포트 25와 빈 서버 값도 보존합니다. 없는 키만 중앙 기본값을 적용합니다.
- 07은 고유 임시 파일에 기록·flush·닫기를 마친 뒤 교체합니다. 실패 시 원본 직접 쓰기를 하지 않고 오류를 전달합니다.
- 07 설정 변경·최근 파일·수신자 이력·최근 목록 삭제·종료 시 저장 실패 처리를 확인했습니다. 이미 발송된 메일을 이력 저장 실패 때문에 발송 실패로 표시하지 않습니다.
- 검수에서 02 서명 스크립트의 기존 `$ReleaseDir:` 문법 오류를 발견해 `${ReleaseDir}:`로 수정했습니다. 정적 검사에도 해당 서명 스크립트를 추가했습니다.

## 자동 검사 결과

| 검사 | 결과 |
| --- | --- |
| 07 전체 `pytest tests -q` | 120 passed, 36 subtests passed |
| 07 신규 회귀 검사 | 14개 테스트 추가: 저장 키 우선순위·실패 시 원본 보호·초기 저장 실패·일시 잠금·고유 임시 파일·GUI 실패 안내·발송 성공 보존·저장 실패 시 다중 창 적용 차단 |
| 01 정적 검사 | PASS |
| 02 정적 검사 (서명 스크립트 포함) | ALL PASSED |
| 02 서명 도구 탐색 단독 검사 | 5 assertions PASS. 서명·서비스 작업 실행 없음 |
| 06 서명 도구 탐색 단독 검사 | 5 assertions PASS. 서명·서비스 작업 실행 없음 |
| 여섯 저장소 제외 규칙 | 48 assertions PASS: 루트/하위 UserSetting, 환경 파일, 개인 키, 공유 예시 |
| Git 추적 파일 | UserSetting·환경 비밀 파일·개인 키 경로 및 알려진 내부 SMTP/개인 작업 경로 잔여 없음 |
| 공통 문서 | 여섯 사본의 SHA-256 동일 |
| 04 기존 수정 문서 | 작업 전후 SHA-256 동일, 기존 변경 보존 |
| 변경 공백·충돌 검사 | `git diff --check` PASS |

Git 추적 텍스트 검색은 알려진 참조와 경로 패턴에 대한 검사입니다. 모든 과거 Git 이력·이미지·기존 배포 ZIP까지 검사했다는 뜻은 아닙니다.
06의 이미 추적된 `tools/dummy_erp.py`, `tools/spike/*`는 기존 테스트 도구이며, `tools/` 제외 규칙이 있어도 추적이 계속됩니다. 이번에 새로 보호한 사용자 자료·개인 키와 구분해 유지했습니다.
Qt offscreen 검사에서 GPU 컨텍스트 대체 로그가 있었지만 테스트는 통과했습니다. 실제 Windows 화면 검증은 별도입니다.

## 설치·업그레이드 흐름 소스 점검

공식 Inno Setup 문서를 함께 확인했습니다.
[`CloseApplications`](https://jrsoftware.org/ishelp/topic_setup_closeapplications.htm)는 설치가 교체·삭제할 파일을 사용하는 앱을 Restart Manager로 감지합니다. 일반 설치는 종료 여부를 묻고, 무인 설치는 명령줄 옵션에 따라 종료·재시작 동작이 달라집니다.
[`AppMutex`](https://jrsoftware.org/ishelp/topic_setup_appmutex.htm)는 설치 시작 시 실행 여부를 확인하고 종료를 요구합니다.
[`UsePreviousAppDir`](https://jrsoftware.org/ishelp/topic_setup_usepreviousappdir.htm)의 기본값은 yes지만 같은 설치 식별자가 전제입니다.
[`InstallDelete`](https://jrsoftware.org/ishelp/topic_installdeletesection.htm)는 설치 첫 단계에 처리되므로 새 파일 검증 후의 구형 EXE 정리와 다릅니다.

| 앱 | 현재 종료 처리 | 구형 파일·경로 처리 | 판단 및 다음 작업 |
| --- | --- | --- | --- |
| 01 | `CloseApplications=yes`, `CloseApplicationsFilter=ClipOCR-Pro.exe` | 고정 EXE 교체. InstallDelete는 구형 바로가기만 정리. 이전 경로 재사용은 기본값 | 같은 경로·이름의 앱 교체는 의도돼 있으나 과거 포터블/별명 EXE 종료·삭제는 보장되지 않음 |
| 02 | `CloseApplications=yes`, `CloseApplicationsFilter=SwiftDeck.exe` | 고정 EXE 교체. InstallDelete는 구형 바로가기만 정리. 이전 경로 재사용은 기본값 | 구형 FolderHotKey 계열·App02 별명/포터블과 일반 설치를 구분해 종료·정리 범위를 확정 |
| 04 | `CloseApplications=yes`, 필터는 기본값 | `UsePreviousAppDir=no`로 표준 설치 위치 사용. 버전별 EXE의 명시적 제거 없음. 구형 바로가기만 정리 | 버전명이 다른 구형 EXE 종료·잔존·런처 선택을 필수 확인. 이전 설치 경로 정책은 기존 계약과 함께 검토 |
| 05 | `CloseApplications=yes`, 빌드가 현 이름·구형 3개 이름의 필터 주입 | `UsePreviousAppDir=yes`. InstallDelete에 구형 EXE 파일만 주입. 폴더 삭제 없음 | 가장 명시적이지만 구형 EXE 삭제가 설치 시작에 수행되므로 취소·실패 복구와 기존 설치 식별자 호환을 확인 |
| 06 | `CloseApplications=yes`, `CloseApplicationsFilter=Stepwise.exe` | 고정 EXE 교체. 구형 별명 EXE 정리 없음. 이전 경로 재사용은 기본값. 두 설치 정의 존재 | 실행 중 매크로·정상 종료 거부·포터블 중복 실행·AppId 원문과 기존 제거 키를 확인 |
| 07 | `AppMutex=EmlViewerMutex`와 `CloseApplications=yes`. 앱도 같은 mutex 생성 | `UsePreviousAppDir=no`. 설치 기본 EXE는 EmlViewer.exe, 다른 식별자 EXE의 제거 규칙 없음 | 직접 설치 시 먼저 수동 종료 요구가 나올 수 있음. 자동 종료 계약·다중 창·구형 실행 이름 잔존을 정비 |

근거:
- 01·02·04·06: 각 `installer/setup.iss`; 06은 `installer/stepwise.iss`도 동일 범위 확인.
- 05: `installer/setup.iss`, `scripts/build_all.py::installer_command`, `legacy_shortcut_entries`, `src/app_identity.py::APP_EXE_NAMES`.
- 07: `packaging/inno/eml_viewer.iss`, `src/eml_viewer/app.py::main`의 mutex 생성, `gui/main_window.py::_on_download_finished`의 설치 실행 뒤 종료 흐름.
- 06 AppId의 실제 .iss 원문은 `AppId={{C782B3E1-628D-4C10-9E1D-3A20B71E86E2}}`입니다. 기준표의 GUID는 식별용이며, 표기만 맞추려고 실제 설치 키를 변경하지 않습니다.

**결론:** 여섯 앱 모두 일률적으로 '구버전 자동 종료 → 구버전 완전 제거 → 신버전 설치'가 보장된 상태는 아닙니다.
고정 EXE 교체와 다른 이름/버전의 EXE 정리는 다르며, 먼저 전체 구버전을 제거하는 방식은 사용자 자료·실패 복구 측면에서 기준으로 삼지 않습니다.
이번에는 설치 소스를 변경하거나 실제 설치 파일을 실행하지 않았습니다.

## 다음 배포 단계의 필수 작업·검증

1. 현재 설치 AppId·기존 공개 버전의 실제 제거 키·설치 경로·실행 이름을 대조합니다.
2. 설치 전에 앱이 사용하는 정상 종료 경로와 실행 중 작업 보존을 확정합니다. 작업 중 자동화·변환·DB 쓰기의 강제 종료는 기본값으로 삼지 않습니다.
3. 04 버전별 EXE와 01·02·06·07 별명 EXE의 종료·안전한 정리 대상을 정의합니다. 사용자 폴더 전체를 지우지 않습니다.
4. 05 InstallDelete의 구형 EXE 삭제 시점과 실패·취소 후 복구 가능성을 확인합니다.
5. 07 AppMutex와 자동 종료 처리의 선후 관계를 조정하고, 다중 창과 설치 완료 후 새 EXE 실행을 확인합니다.
6. 일반 설치·무인 설치·정상 종료 거부·사용자 지정 경로·구형 포터블 실행·재설치·중단/실패·제거 후 설정 보존을 실제 Windows에서 검증합니다.
7. 릴리즈 설치 파일에 변경이 반영됐는지 확인하고, 소스 검사·실물 배포물 검사·실제 설치 결과를 구분해 기록합니다.

## 이번 작업에서 실행하지 않은 항목

실제 서명·인증서/PIN 접근·빌드·설치/제거·SMTP 발송·GitHub 게시·커밋/푸시는 수행하지 않았습니다.
실제 사용자 설정과 기존 공식 배포물은 변경하지 않았습니다.


## Gemini 3.8 CLI 검수 및 재검수

Antigravity CLI의 Gemini 3.8 Flash Medium에 현재 설정 서비스·GUI 변경·여섯 설치 설계를 직접 전달해 읽기 전용 검수를 수행했습니다.
파일/명령 권한 제한과 고사양 요청 시간 초과 이후, 자료를 직접 전달하고 도구 호출을 금지하는 방식으로 검수를 완료했습니다. 권한을 일괄 우회하거나 설치·서명 명령을 실행하지 않았습니다.

- SMTP 저장 키 우선순위와 원자적 저장 실패 시 원본 보호는 요구사항 충족으로 판정했습니다.
- 초기 결과의 다중 창 저장 실패 누락 주장은 실제 WindowManager가 저장을 먼저 하고 예외를 전파하는 소스와 관련 통과 테스트로 대조했습니다.
- Gemini 3.8 Flash Low 재검수는 해당 주장과 동일 UI 스레드 내 동시 저장 주장을 근거 부족으로 정정했습니다. 별도 프로세스의 읽기-수정-저장 경쟁은 기존 제한으로, 설정 표준화 단계의 후속 점검에 남깁니다.
- AppMutex/CloseApplications만으로 완전한 자동 종료를 보장한다는 표현을 기각하고 실제 설치 검증을 유지했습니다.
- 설치 폴더의 EXE 일괄 삭제·신버전 반영 전 구형 앱 제거 제안은 보존·실패 복구 기준과 충돌하므로 채택하지 않았습니다. 앱 소유가 확인된 구형 파일의 안전한 정리만 다음 단계에서 설계합니다.
- 최종 재검수: 현재 소스 리뷰 단계 통과 가능, 실제 업그레이드 동작은 미검증.
- 변경 Python 소스·테스트의 Ruff E4/E7/E9/F 검사 PASS. 기존 미사용 import 4개를 정리했습니다. 이후 전체 테스트를 다시 실행해 120 passed, 36 subtests passed를 확인했습니다.
- 코드 지도는 여섯 프로젝트에서 갱신했습니다. 04 외의 로컬 코드 지도 공개 추적 정책은 후속 공유 문서 단계에서 결정하며 이번에 강제로 추적하지 않았습니다.
