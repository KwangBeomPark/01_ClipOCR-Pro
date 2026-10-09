# ClipOCR-Pro 공개 코드 지도

이 문서는 공개 저장소에서 공유하는 구조·대표 흐름입니다. 개인 작업 환경을 담은 로컬 `AI_CODE_MAP.md`는 별도로 유지합니다.

| 역할 | 위치와 대표 흐름 |
|---|---|
| 시작·캡처·주석 | `src/ClipOCR-Pro.ahk`: 설정 이관 → 단축키 등록 → 영역 캡처 → 주석·복사·저장 |
| OCR | `src/OcrService.ahk`: OCR 엔진·언어 선택 → 캡처 이미지 인식 → 결과 표시 |
| 설정·우선순위 | `src/SettingsManager.ahk`: config.ini의 저장값 우선 → 누락된 레지스트리 값 1회 복사 |
| 안전한 저장 | `src/AtomicSettings.ahk`: 같은 폴더의 임시 파일 검증 → FlushFileBuffers → 원자적 교체, 실패하면 원본 유지 |
| 공통 설정 | `src/SuiteRegistry.ahk`: 앱 설정이 없는 경우 공통 기본값 확인 |
| 자체 검증 | `src/HealthCheck.ahk`, `tests/AtomicSettingsTests.ahk`, `scripts/static-check.ps1` |
| 빌드·배포 | `scripts/build.ps1`, `publish.ps1`, `ReleaseSafety.ps1`; `installer/setup.iss` |

활성 설정은 실행 파일 또는 소스 진입점 옆 `UserSetting/config.ini`입니다. 기본 설치는 `%LOCALAPPDATA%/Programs/ClipOCR`입니다. 기존 레지스트리는 삭제하지 않습니다. `SafeWriteLocalSetting`과 호환용 `SafeRegWriteString`은 저장 실패 시 false를 반환하고 원본 파일을 보존합니다. 초기 이관 실패는 예외로 전달합니다.

오류 로그·OCR 임시는 `%TEMP%/ClipOCR-Pro`에 있으며, 사용자 지정 캡처 폴더와 외부 Tesseract/tessdata는 UserSetting 백업 밖에 있습니다. 자세한 범위와 복원은 [사용자 자료 안내](USER_DATA.md), [관리 도구](../scripts/Manage-UserData.ps1)를 참고하세요. 캡처·OCR·번역 기능과 기존 단축키·앱 식별자는 유지합니다.

배포 보호와 실제 설치 검수 경계는 [2단계 검수](STANDARDIZATION_PHASE2_REVIEW.md), 설정 저장 검수는 [3~5단계 검수](STANDARDIZATION_PHASE3_5_REVIEW.md)에 기록합니다.

2026-10-09 릴리즈 준비: App01 설치 파일 단일 이름, 선택 Full OCR 별도 로컬 패키지, 빌드/서명과 게시 분리. [준비 검수](RELEASE_PREPARATION_20261009.md), [사용자 체크리스트](../RELEASE_CHECKLIST.md).
