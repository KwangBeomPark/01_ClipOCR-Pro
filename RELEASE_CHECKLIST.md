# ClipOCR-Pro 다음 릴리스 체크리스트

2026-10-09 릴리즈 준비 검수 기준입니다. 기존 변경을 보존하며 명명·선택 OCR 패키징·게시 보호를 최소 수정하고 자동 검사를 수행했습니다. 실제 KSP 서명·설치·게시·태그 변경은 실행하지 않았습니다.

## 현재 준비 상태

- [x] 설치 파일 이름은 `App01_ClipOCR-Pro_Setup_v1.6.2.exe` 하나입니다. 생성·검증·업데이트 선택·게시 목록을 맞췄습니다. AppId·기본 설치 폴더·앱 내부 EXE명은 유지합니다.
- [x] 새 소스 버전은 `1.6.2`입니다. 원격 v1.6.2 태그는 조회 시 없었습니다. 이는 태그 예약이나 게시 완료를 뜻하지 않습니다.
- [x] 선택형 Full OCR은 앱 EXE가 존재할 때 먼저 만들고, `build/full-ocr-<GUID>/`에 별도로 보존합니다. 공식 설치 파일 세트에 넣거나 공개 업로드하지 않습니다.
- [x] 게시 명령은 이미 서명한 `release/`를 검증해서 사용합니다. 다시 빌드·서명·폴더 반영하거나 자동 push하지 않습니다. GitHub 호스트/저장소와 origin을 고정·대조하고 draft 자산의 digest 검증 후 공개합니다.
- [ ] 리뷰한 소스를 clean `main` 커밋으로 확정하고 사용자 서명 명령을 실행합니다. 게시 전에 같은 커밋을 origin/main에 별도로 push해야 합니다.

## 사용자 할 일

- [ ] 기존 사용자 변경을 포함한 미커밋 소스를 검토하고, 새 버전·릴리스 노트·원본 변경 포함 여부를 검토한 뒤 clean `main` 커밋을 확정합니다.
- [ ] 실행 중인 앱과 AHK 소스를 종료합니다. 활성 `UserSetting` 전체를 백업하고 검증합니다. 실행 파일 옆 설정과 소스 실행 설정이 다를 수 있으므로 활성 위치를 먼저 확인합니다. 외부 캡처 파일·Tesseract/tessdata·TEMP 로그는 별도 범위입니다. [백업 안내](docs/USER_DATA.md).
- [ ] AutoHotkey v2, Ahk2Exe, Inno Setup, Microsoft SignTool을 준비합니다. SimplySign 로그인·인증서 선택·PIN/OTP는 사용자의 직접 실행 세션에서 처리합니다.
- [ ] 현재 커밋의 정적 검사·원자 저장·백업·릴리스 보호 검사와 실제 소스/컴파일 health를 다시 확인합니다. 이전 검수 기록은 [3~5단계 검수](docs/STANDARDIZATION_PHASE3_5_REVIEW.md), [종합 검수](docs/STANDARDIZATION_FINAL_REVIEW.md)에 있습니다. `SkipCompiledHealthCheck`·미서명 개발 산출물은 공식 게시 조건을 만족하지 않습니다.

```powershell
# 승인 커밋 확정 후, 사용자 직접 실행 관리자 Windows PowerShell에서 실행
.\scripts\release.ps1 -CertificateThumbprint '<선택한 공개 인증서 지문>' -SignToolPath '<Microsoft SignTool 전체 경로>'
```

- [ ] 위 명령은 고유 스테이징에서 빌드·서명·검증 후 로컬 공식 폴더로 반영합니다. `scripts/sign_release.ps1`은 같은 절차의 호환 진입점입니다. 기존 `release/` 파일을 먼저 지우거나 직접 다시 서명하지 않습니다.
- [ ] 설치 파일과 실제 설치된 앱의 유효 서명·게시자·타임스탬프, 실제 EXE health, 체크섬·장부의 버전/커밋/파일을 대조합니다. 설치 파일 한 개만 공개한다는 정책은 앱 내부 EXE의 서명을 생략한다는 뜻이 아닙니다.
- [ ] 격리 Windows에서 구버전 실행 중 정상 종료 요청, 종료 거부/잠금 시 설치 차단, 실패·취소, 설정 보존, 제거 후 설정 보존을 검수합니다. 캡처·주석·OCR·텍스트/이미지 번역, 번역 동의, 단축키 재등록·저장 실패 안내도 실제 화면에서 확인합니다. [실제 설치 검수](docs/INSTALL_UPGRADE_ACCEPTANCE.md).
- [ ] 기존 설치/포터블 버전의 앱 업데이트와 새 설치 파일 자산 선택을 실제로 확인합니다. 기존 앱 EXE명·AppId·설치 폴더·설정 키는 이름 통일 때문에 함께 바꾸지 않습니다. Office/VBA·공유 배포의 `App01*` 설치 패턴과 실제 배포된 값도 확인합니다.

```powershell
# 검증한 새 서명 세트의 게시만 실행합니다. 빌드/서명 명령과 별개입니다.
.\scripts\publish.ps1 -OutputDirectory release
```

- [ ] GitHub 새 태그의 커밋, stable/latest 상태, 설치 파일 한 개와 필요한 두 메타데이터의 SHA-256·크기를 확인합니다. 자동 확인 또는 승인 요구가 표시되면 실제 게시 결과를 확인하고 완료 처리합니다. 기존 태그·자산을 덮어쓰거나 삭제하지 않습니다.

## 사용자와 검토할 삭제 후보

아래는 2026-10-09 현재 크기이며 **삭제 승인이 아닙니다**. 모든 행은 Git 추적 파일 0개입니다. 폴더명 패턴에 맞는 것만 대조하며 `build/` 전체 삭제를 권하지 않습니다.

| 후보 | 크기·개수 | 현재 참조와 이유 | 지우기 전 조건·재생성 |
| --- | --- | --- | --- |
| `build/backup-test-*` 6개 | 합계 53,519 bytes, 119 files | `scripts/test_user_data_backup.ps1`이 매 실행 고유 fixture를 만듭니다. 실제 사용자 백업이 아니라 반복 검수 사본입니다. | 마지막 통과/실패 기록을 보관하고 fixture 안에 실제 자료가 없는지 확인한 뒤 승인받습니다. 같은 검사를 재실행해 재생성합니다. |
| `build/settings-tests-*` 3개 | 합계 162 bytes, 3 files | `tests/AtomicSettingsTests.ahk`의 고유 설정 fixture입니다. 운영 설정의 입력이 아닙니다. | 마지막 검수 근거 보존 후 승인받습니다. 해당 AHK 검사를 재실행해 생성합니다. |
| `build/phase2 verification d72385fce6dc431396d4bd179fdeed7d` | 10,549,706 bytes, 8 files | 이전 단계 설치/서명 보호 검수의 사본입니다. 현재 빌드 기본 입력으로 참조하지 않습니다. | 검수 장부와 로그를 별도로 보존하고 공식 배포 원본과 구분한 뒤 승인받습니다. 같은 소스·도구 버전으로 검수 fixture를 다시 만들 수 있으나 과거 서명 바이트 재현은 보장하지 않습니다. |
| `build/phase2-inno-2f40e5125107403483909485011788f4` | 2,143,368 bytes, 2 files | 이전 Inno fixture 산출물입니다. 현재 공식 설치 파일이 아닙니다. | 해당 컴파일 근거를 보존하고 승인받습니다. 새 고유 검수 폴더에서 재컴파일 가능합니다. |
| `build/standardization/portable-signature-21c2a7089dc241c19a927b043d117893` | 1,638,024 bytes, 1 file | 공식 ZIP 내부 EXE의 서명 검사용 추출 사본입니다. 앱/빌드 기본 입력이 아닙니다. | 원본 ZIP과 서명/해시 검수 JSON을 보존하고 승인받습니다. 같은 원본 ZIP에서 다시 추출합니다. |

`release/`, `build/release-history/`, `build/standardization`의 검수 JSON·Gemini 응답·소스/원격 비교 근거, `tools/certs/`, `UserSetting`, 레지스트리, 사용자 캡처·업무 자료는 이번 삭제 후보에서 제외합니다. 빈 검수 폴더도 내용 확인과 승인 후에만 정리합니다.

## 검수 근거와 남은 경계

현재 소스의 자동 검수와 실제 미서명 설치 파일 컴파일 결과는 [릴리즈 준비 검수](docs/RELEASE_PREPARATION_20261009.md)에 기록합니다. Gemini High의 내용 있는 새 설계 검토 61.67초와 실패한 CLI 출력 수집을 구분했습니다. 과거 통과 기록은 이 변경의 통과로 대체하지 않습니다.

서명·설치·게시 명령은 사용자가 직접 실행합니다. 새 KSP 서명 성공, 실행 중 실제 업그레이드·제거, 새 GitHub 게시 완료는 아직 확인되지 않았습니다.
