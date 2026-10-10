# Release Audit: 01_ClipOCR-Pro

검수일: 2026-10-10. 검수 대상은 아래 HEAD 위의 현재 작업 변경입니다.

- 기준 Git HEAD: `0f5b603f51fe3eefec79f6eeddb1f2f4647aa0cc`
- 상태: 소스 수정 및 모의 검증 완료. 변경된 소스의 새 서명·설치·게시 검증은 미완료.
- 이번 교차 검수에서는 실제 서명, 설치, GitHub 업로드·공개, push 또는 태그 생성을 실행하지 않았습니다.

## Release contract

직접 업로드할 파일은 아래 세 파일입니다. GitHub의 자동 Source code ZIP/TAR는 이 목록에 포함하지 않습니다.

1. `App01_ClipOCR-Pro_Setup_v<version>.exe`
2. `build-manifest.json`
3. `SHA256SUMS.txt`

한 파일의 별칭 설치 파일이나 포터블 ZIP은 새 공식 업로드 목록에 넣지 않습니다. 기존 공개 자산은 변경하지 않습니다.

## Findings and corrections

- Gemini 작업 변경을 보존한 뒤 독립 검수에서 발견한 재개·공개 경로를 보완했습니다.
- 태그 없는 Draft의 target_commitish가 HEAD 전체 SHA와 일치하지 않으면 재개를 거부합니다. WhatIf일 때 임시 릴리즈 설명 파일을 생성하지 않습니다.
- 세 파일의 원격 이름 집합, 중복 이름, uploaded 상태, SHA-256 digest, 크기를 비교하며 누락된 파일만 업로드합니다. 추가·충돌 파일을 덮어쓰지 않습니다.
- Draft 검증 후 공개하고, 공개 후 상태 및 자산을 다시 확인합니다. prerelease Draft는 공개 전에 거부합니다.
- 기존 공개 릴리즈는 재개·교체하지 않습니다. 태그를 다른 커밋으로 이동하지 않습니다.
- 태그가 없는 기존 Draft가 main 같은 분기 이름을 대상으로 한다면 재개를 중단합니다. 원본 Draft를 보존하고 전체 SHA 또는 이미 존재하는 불변 태그의 커밋을 사람이 검토해야 합니다.

## Verification actually executed

Windows PowerShell 5.1에서 다음을 실행했고 모두 Exit Code 0을 확인했습니다.

| 검증 | 명령의 파일 | 결과 |
| --- | --- | --- |
| 기존 릴리즈 안전성 | `tests/Test-ReleaseSafety.ps1` | 53 checks passed |
| 실제 게시 스크립트 모의 실행 | `tests/Test-PublishOrchestration.ps1` | 22 scenarios, 45 checks passed |

새 모의 검증은 생산 publish.ps1을 수정 없이 별도 테스트 저장소에 복사하여 실행합니다. 생산 Get-SuiteMissingAssets도 사용합니다. git/gh 실행과 로컬 서명·출처 확인 경계는 모의 처리하므로 실제 인증서 및 GitHub 서비스의 동작을 증명하지 않습니다.

확인한 상황: 정상 신규 공개, Draft만 생성, 완료·누락 Draft 재개, 신규/재개 WhatIf에서 원격 변경 0회, 기존 공개 버전 거부, 잘못된 태그 SHA/분기 대상 Draft 거부, 추가·중복·pending·크기·digest 충돌 거부, 부분 생성 실패 후 Draft 보존, 업로드 실패 시 공개 안 함, 공개 후 digest 충돌 검출. 공개 후 검증 실패는 오류로 보고하며 이미 공개된 파일을 삭제하거나 교체하지 않습니다.

## Changed files

- `scripts/publish.ps1`: Draft 재개 및 공개 보호 보완.
- `scripts/ReleaseSafety.ps1`: 기존 작업의 원격 자산 집합·상태·해시 검증 보강 유지.
- `tests/Test-PublishOrchestration.ps1`: 게시 경로 모의 회귀 검증 추가.
- `RELEASE_AUDIT.md`: 실제 검증 범위와 남은 절차 정정.

## Remaining gates

1. 기존 게시 버전을 유지하고, 다음 버전의 소스 변경을 검토·커밋·동기화합니다. 게시 스크립트가 소스를 자동 커밋하거나 push하지 않습니다.
2. 그 최종 커밋에서 빌드·테스트하고 사용자 서명 세션으로 앱·설치 파일·필요한 제거 프로그램을 서명합니다. 현재 이전 버전 서명 파일을 새 소스의 서명 완료 증거로 사용하지 않습니다.
3. 실행 중인 구버전 종료, 구버전 설치 위의 업그레이드, 사용자 설정 보존, 제거 동작을 실제 Windows 환경에서 확인합니다.
4. 검증한 새 버전 세 파일의 Draft를 확인한 뒤 공개하고 실제 다운로드 해시·서명을 검증합니다. 이전 릴리즈 파일·버전·태그는 보존합니다.