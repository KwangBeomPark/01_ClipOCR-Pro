# 사용자 설정 백업·검증·복원

앱의 표시 이름, 설치 식별자와 기존 단축키는 유지합니다. 설정 위치의 기준은 앱이 실제 사용하는 `UserSetting` 폴더입니다. 설치/포터블/소스 실행의 활성 위치는 아래 안내를 확인하세요.

## 백업 범위

기본 설치는 `%LOCALAPPDATA%/Programs/ClipOCR`. 실행 폴더의 `UserSetting/config.ini`에 캡처·OCR·번역·창·단축키·언어 설정을 저장합니다. 소스/포터블 실행에서는 실행 폴더를 `-AppRoot`로 명시하세요.

기본 백업은 선택한 앱 폴더의 **UserSetting 전체 파일**를 포함합니다. 연결 정보나 비밀번호가 설정 파일에 들어 있으면 백업에도 포함될 수 있으므로 이 ZIP을 공개 저장소·GitHub Releases에 올리지 마세요. Windows 사용자에게 연결된 암호화 값은 같은 PC/사용자로 복원해야 사용할 수 있습니다. 현재 사용 중인 앱과 관련 DB/자동화 작업을 먼저 종료하세요. 원본 업무 파일은 변경하지 않습니다. 소스 실행은 외부 AutoHotkey/Python 프로세스의 작업 폴더를 항상 식별할 수 없으므로 해당 앱을 직접 종료한 후 백업하세요. 종료 자동 검사는 선택한 앱 폴더 내부에서 실행되는 프로세스와 알려진 실행 파일을 대상으로 합니다.

`-SettingsOnly`는 이 앱에서 제외할 대용량 하위 폴더가 없으므로 기본 백업과 같은 범위을 제외합니다. 제외 범위는 ZIP의 `backup-manifest.json`에 기록되며, 이를 전체 자료 백업으로 취급하지 않습니다. 지정한 외부 저장소·원본 파일은 자동 탐색/복사하지 않습니다. 외부 예외: Capture output folder; External Tesseract runtime and tessdata.

## 실행 순서

이 도구는 소스 저장소의 Windows PowerShell 5.1 이상 관리 도구입니다. 설치된 앱 화면과 별개로 사용하며 Python이나 추가 라이브러리는 필요하지 않습니다. ZIP은 암호화되지 않습니다. 아래 백업 폴더를 먼저 만들고, 같은 ZIP 이름을 재사용하지 마세요.

```powershell
# 저장소 루트에서 실행. 다른 설치/포터블 위치면 -AppRoot를 지정합니다.
powershell -NoProfile -File scripts/Manage-UserData.ps1 -Action Backup -Archive "$env:USERPROFILE/Downloads/App01_ClipOCR-userdata.zip"
powershell -NoProfile -File scripts/Manage-UserData.ps1 -Action Verify -Archive "$env:USERPROFILE/Downloads/App01_ClipOCR-userdata.zip"
powershell -NoProfile -File scripts/Manage-UserData.ps1 -Action Restore -Archive "$env:USERPROFILE/Downloads/App01_ClipOCR-userdata.zip" -Destination "$env:USERPROFILE/Downloads/App01_ClipOCR-restored"
```

복원 대상은 **아직 존재하지 않는 새 폴더**여야 합니다. 앱 식별자·파일 목록·크기·SHA-256을 확인한 뒤 같은 부모 폴더의 스테이징에서 복원하고 새 대상 폴더로 이동합니다. 기존 설치와 설정을 덮어쓰거나 삭제하지 않습니다. 손상·중복·경로 탈출·링크·다른 앱 백업·크기 제한 위반은 거부합니다. 기본 합계 제한은 10 GiB이며 필요하면 `-MaxBytes`로 늘립니다. 쓰기/이동 실패 시 기존 자료를 유지하고 새 임시 사본을 남길 수 있습니다.

복원 내용을 확인한 다음 앱을 종료하고 기존 활성 `UserSetting`을 별도 이름으로 보관하세요. 새로 복원한 `UserSetting`을 활성 위치에 옮긴 후 앱에서 설정과 대표 작업을 확인합니다. 기존 보관본은 검수가 끝날 때까지 유지합니다. 이 전환은 자동으로 실행하지 않습니다. 포터블 위치가 쓰기 불가능해 다른 저장소를 사용하는 경우 그 활성 저장소에서 전환해야 합니다.

## 검수와 진단

`powershell -NoProfile -File scripts/test_user_data_backup.ps1`는 저장소의 무시된 `build/` 아래 사본으로 검사합니다. 실제 사용자 설정을 읽거나 바꾸지 않습니다. 관리자 권한이나 보안 정책 변경을 요구하지 않습니다.

진단 로그와 OCR 임시는 `%TEMP%/ClipOCR-Pro`에 있으며 기본 백업 대상 밖입니다.

설정 쓰기 실패를 표시했다면 변경값이 저장됐다고 가정하지 말고, 기존 파일을 보관한 채 쓰기 권한·잠금·공간을 확인한 다음 다시 저장하세요.
