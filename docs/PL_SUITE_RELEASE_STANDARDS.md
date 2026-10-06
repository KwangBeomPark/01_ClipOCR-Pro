# PL Suite 표준 릴리즈 및 프로젝트 구조 기준안 (Packaging & Directory Standards)

본 문서는 PL Suite (App01 ~ App10) 전 프로젝트의 일관된 배포 관리, 디렉터리 청결성 유지, 무결성 검증을 위한 표준 기준안입니다.

---

## 1. 프로젝트 표준 디렉터리 구조

모든 PL Suite 프로젝트는 아래의 표준 디렉터리 구조를 준수합니다.

```text
<프로젝트 루트>/
├── assets/                 # 아이콘(.ico), 시연 GIF, 매뉴얼 이미지 등
├── docs/                   # 기술 문서, 설계서 및 본 표준 기준안
├── installer/              # Inno Setup 설치 설계도 (setup.iss 등)
├── release/                # [공식 배포] 최신 릴리즈 산출물 (설치파일, 포터블, 체크섬, 매니페스트)
├── scripts/                # 표준 빌드/서명/배포 자동화 스크립트 (build.ps1, publish.ps1 등)
├── src/                    # 애플리케이션 소스 코드
├── tools/                  # [로컬 전용] 개발 도구, 테스트 인증서, 임시 아티팩트 (Git 추적 제외)
├── dist/                   # [빌드 임시] 빌드 컴파일 단계의 중간 출력 폴더 (Git 추적 제외)
├── .gitignore              # Git 제외 규칙
├── AI_CODE_MAP.md          # 코드 맵 및 심볼 인덱스
├── LICENSE                 # 오픈소스 라이선스
├── README.ko.md / README.md# 프로젝트 설명서
└── myAGENT.md              # 에이전트 지침 및 규칙
```

### 디렉터리 관리 원칙
1. **루트 청결 유지 (Clean Root)**:
   - 프로젝트 루트에는 소스, 공식 문서, 라이선스, 배포 설정 외의 파일(테스트용 `.cer`, `.pfx`, 임시 스크립트, 로그 등)을 절대 방치하지 않습니다.
   - 로컬 작업 파일이나 테스트 인증서는 반드시 `tools/` 폴더로 격리합니다.
2. **`release/` vs `dist/` 분리**:
   - `release/`: 최종 검증 및 디지털 서명이 완료된 공식 배포판만 보관합니다.
   - `dist/`: 빌드 파이프라인이 임시로 컴파일하고 아티팩트를 스테이징하는 워킹 디렉터리입니다.
3. **`tools/` 격리 폴더**:
   - `.gitignore`에 등록하여 Git 추적 대상에서 제외하며, 개발자 개인 도구, 테스트 인증서(`tools/certs/`), 스크래치 데이터를 안전하게 보관합니다.

---

## 2. 배포 산출물(Artifacts) 표준 네이밍 규칙

PL Suite는 기업 표준 관리 번호(App01~App10)와 일반 공개 명칭 간의 호환성을 보장하기 위해 **듀얼 네이밍(Dual Naming)** 체계를 따릅니다.

### (1) 인스톨러 (Windows Installer - 필수 권장)
- **PL Suite 엔터프라이즈 명칭**: `App{NN}_{AppName}-Setup_v{version}.exe`
  - *예시*: `App01_ClipOCR-Setup_v1.6.1.exe` (현재 프로젝트)
  - *예시*: `App02_SwiftDeck-Setup_v1.4.0.exe`
  - *예시*: `App04_DataRefinery_Setup_v1.12.0.exe`
- **일반 공개 명칭**: `{AppName}-Setup.v{version}.exe`
  - *예시*: `ClipOCR-Setup.v1.6.1.exe`
  - *예시*: `SwiftDeck-Setup.v1.4.0.exe`

### (2) 포터블 바이너리 (Portable - 선택/보조)
- **PL Suite 엔터프라이즈 명칭**:
  - 실행 파일: `App{NN}_{AppName}_v{version}.exe`
  - 압축 파일: `App{NN}_{AppName}_v{version}.zip`
- **일반 공개 명칭**:
  - 실행 파일: `{AppName}.v{version}.exe`
  - 압축 파일: `{AppName}.v{version}.zip`

---

## 3. 릴리즈 폴더(`release/`) 구성 필수 세트

릴리즈 폴더에는 배포판의 무결성과 신뢰성을 증명하기 위해 아래 4종류의 아티팩트가 일관되게 포함되어야 합니다:

| 항목 | 파일명 형식 | 설명 |
| :--- | :--- | :--- |
| **1. 인스톨러** | `App{NN}_*-Setup_v*.exe`<br>`*-Setup.v*.exe` | Inno Setup 기반 Per-User 설치 파일 (디지털 서명 필수) |
| **2. 포터블 파일** | `App{NN}_*_v*.exe` / `.zip`<br>`*.v*.exe` / `.zip` | 무설치 단독 실행 파일 및 압축본 (디지털 서명 필수) |
| **3. 무결성 해시** | `SHA256SUMS.txt` | 릴리즈 내 모든 파일의 SHA-256 해시값 (UTF-8 No-BOM) |
| **4. 빌드 메타데이터** | `build-manifest.json` | 버전, Git 커밋, 빌드 일시, 서명 정보(발급자/인증서/타임스탬프) 기록 |

---

## 4. 인스톨러(.iss) 및 빌드 스크립트 작성 기준

1. **설계도(`installer/setup.iss`)**:
   - `Source` 경로는 컴파일러 매개변수(`/DMyAppExeSource=...`)를 통해 동적으로 주입받을 수 있도록 작성하여 `dist` 및 `release` 어디서나 빌드 가능해야 합니다.
   - 사용자 설정 디렉터리(`UserSetting`)는 언인스톨 시 보존(`uninsneveruninstall`)합니다.
2. **빌드 스크립트(`scripts/build.ps1`)**:
   - 컴파일 완료 후 반드시 코드 서명(Authenticode + RFC 3161 타임스탬프)을 수행합니다.
   - 생성된 모든 배포 파일(인스톨러, 포터블, 엔터프라이즈 에일리어스)을 아티팩트 목록(`$artifactPaths`)에 등록하여 체크섬과 매니페스트에 누락 없이 기록합니다.
