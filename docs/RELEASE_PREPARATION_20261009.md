# ClipOCR-Pro 1.6.2 릴리즈 준비 검수

2026-10-09. 소스 준비와 자동 검수를 마쳤으며 실제 새 KSP 서명·앱 설치·게시·태그 생성은 하지 않았습니다. 이전 사용자 변경과 공식 파일을 보존했습니다.

## 변경과 효과

- 공식 설치 파일은 `App01_ClipOCR-Pro_Setup_v1.6.2.exe` 한 개와 검증용 `SHA256SUMS.txt`, `build-manifest.json`입니다. Inno 출력·빌드·자산 장부·업데이트 선택·게시 목록이 같은 이름을 사용합니다. AppId·기본 설치 폴더·내부 앱 EXE명은 유지합니다.
- 기존 v1.6.1 태그가 있으므로 최소 패치 후보를 1.6.2로 올렸습니다. 원격 태그 조회 당시 v1.6.2는 없었습니다. 다시 서명 직전 확인해야 하며 이 조회가 버전을 예약하지 않습니다.
- 선택형 Full OCR은 삭제되기 전 검증한 앱 EXE로 만들어 `build/full-ocr-<GUID>/`에 진단 stage와 함께 보존합니다. 공식 설치 파일 세트와 분리하고 공개 게시에서 제외합니다. 선택 기능을 제거하지 않았습니다.
- 게시가 빌드/서명을 반복하던 경로를 제거했습니다. `release.ps1`이 서명 세트를 준비하고 `publish.ps1`은 같은 파일의 서명·장부·커밋을 검증해서 게시합니다. 자동 commit/push나 기존 자산 교체는 없습니다.
- 게시자는 GitHub 호스트/저장소와 Git origin을 고정·대조하고 승인 커밋이 origin/main과 같아야 진행합니다. draft의 크기/해시를 확인한 뒤 공개하고 공개 상태를 다시 읽습니다. 실패한 draft는 보존합니다.

## 검증

| 검사 | 결과 |
| --- | --- |
| Windows PowerShell 5.1 릴리즈 보호 | 52개 통과; 서명 객체는 fixture이며 실제 KSP를 사용하지 않음 |
| 선택형 Full OCR 패키징 | 7개 통과; ZIP 내부 앱 해시·OCR 자료·원본 보존·공식 세트 분리 확인 |
| 공통 사용자 백업 | 32개 통과; 고유 합성 fixture만 사용 |
| 실제 AHK 원자 저장 | 6개 통과 |
| 실제 소스 health | exit 0 및 격리 TMP의 `ClipOCR-Pro health check: PASS`; setter 실패 보호 포함 |
| 정적 검사·diff 공백 검사 | 통과 |
| 새 이름 실제 미서명 설치 파일 컴파일 | 고유 `build/standardization/installer-ready-2ede5ef1d47e43699f23a355d07fa8b6/`에서 생성. 공식 release에 반영하지 않음 |

자동 검수의 환경 문제도 남겼습니다. Codex 런타임의 PowerShell 7 모듈 경로를 상속한 첫 격리 Windows PowerShell 실행은 Get-FileHash를 찾지 못했습니다. 검사 프로세스에만 Windows PowerShell 모듈 경로를 명시한 뒤 재실행해 통과했으며 컴퓨터 전역 환경은 변경하지 않았습니다. 미서명 preview는 `SkipCompiledHealthCheck`를 명시했으므로 **공식 게시 근거로 사용할 수 없습니다**. 사용자 서명 release 명령은 소스와 실제 서명 EXE health를 모두 실행합니다.

## Gemini와 검수 경계

02와 공유한 짧은 Antigravity 요청에서 `gemini-3.8-flash-high`, effort high의 내용 있는 완료 응답을 61.67초에 받았습니다. Map 대소문자·컴파일 모드·정책 차단·인증서 교체 검수에 사용했습니다. CLI 시간 단위 오류 1회와 stdout 인코딩 수집 실패 1회는 완료로 계산하지 않았습니다. 원문은 02의 git 제외 `build/standardization/agy/release-parser-review-cd48945a3df14f4aa15613d459d1d834.json`입니다. 이 응답은 실제 서명·게시 성공을 증명하지 않습니다.

## 사용자 실행 순서

[루트 체크리스트](../RELEASE_CHECKLIST.md)에 실제 옵션과 명령을 정리했습니다. 승인 clean main → 사용자 관리자 서명 세션에서 release → 실제 새 파일/내부 EXE 서명과 health·실행 중 업그레이드·설정 보존·제거 검사 → 같은 승인 커밋 별도 push → publish 순서입니다. 이 검수에서 새 서명·실제 앱 UI/OCR·실행 중 업그레이드·제거·새 게시를 완료로 표시하지 않습니다.
