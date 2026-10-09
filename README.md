*Read this in other languages: [English](README.md), [한국어](README.ko.md)*

# 📸 ClipOCR-Pro: Office Screen Capture, OCR & Translation Tool
A portable screen capture, OCR, selected-text translation, and image workflow tool for practical office work, built with AutoHotkey v2.

<p align="center">
  <img src="./assets/demo.gif" width="900" alt="ClipOCR-Pro Demo">
</p>

---

## What ClipOCR-Pro Does

**ClipOCR-Pro** helps office professionals capture screen areas, keep reference images floating on top, annotate captured images, translate selected text, and streamline document review workflows.

It is designed especially for finance, accounting, sales administration, credit control, and back-office teams that frequently compare ERP data, Excel files, emails, scanned documents, screenshots, and supporting evidence.

> **Capture Faster · Review Documents Clearly · Translate Selected Text · Reduce Repetitive Screen Work**

---

## Core Features

- **📸 Screen Area Capture**: Capture any selected area with a hotkey and keep it as a floating always-on-top reference window.
- **🖍️ Quick Annotation**: Mark captured images with red boxes, highlights, arrows, numbered pins, text notes, and mosaic masking for sensitive information.
- **🌐 Selected Text Translation**: Translate selected text using the configured translation workflow.
- **🖼️ Image Translation Workflow**: Send captured images to Google Image Translation when needed for email attachments, scanned documents, and overseas evidence.
- **🔤 Local OCR**: Extract text from a floating capture without uploading the image. Auto mode uses Windows OCR first and an approved portable Tesseract runtime when available.
- **📐 Image Resize & Copy**: Resize captured images to a configured width from 400 to 1600 px before pasting them into documents, emails, or reports.
- **📧 Outlook Web Mail Estimate**: Estimate the attachment-free message size in MB from copied body data plus conservative subject, header, and encoding allowances.
- **🖥️ Multi-Monitor Support**: Use capture and floating windows across multi-monitor office environments.

---

## 🚀 Download & Quick Start

**ClipOCR-Pro** is a **portable application**. It runs by double-clicking the executable and does not require a complex installation process.

### 📥 For General Users (One-Click Portable Download)

1. Go to the **[Releases](https://github.com/KwangBeomPark/01_ClipOCR-Pro/releases)** tab on the right side of the GitHub repository.
2. Download the current release installer. From v1.6.2 its single name is **`App01_ClipOCR-Pro_Setup_vX.Y.Z.exe`**; previous releases retain their original asset names. The optional administrator-provided Full OCR ZIP stays a separate local/internal package.
3. Unzip the file if needed, then double-click **`ClipOCR-Pro.exe`**.
4. An icon will appear in the Windows system tray, and ClipOCR-Pro is ready to use.

If no release file is available yet, please build or run the source using AutoHotkey v2.

### 🛠️ For Power Users & Developers (Custom Build)

1. Install [AutoHotkey v2](https://www.autohotkey.com/) with Ahk2Exe.
2. Clone this repository and customize the source as needed.
3. Run `./scripts/build.ps1`. It performs source and compiled health checks, then writes the installer, SHA-256 list, and build manifest to `dist/`. It never commits, pushes, tags, or publishes. On a PC where Windows Smart App Control is turned on, a freshly built executable cannot run its compiled health check unless it is signed by a trusted CA (a self-signed test certificate does not help); the script checks before compiling whether the configured certificate chains to a trusted CA and stops early otherwise. For local development builds pass `-SkipCompiledHealthCheck` (recorded in the manifest, and `publish.ps1` refuses such builds); release builds signed with the release certificate run the check normally. Local output is restricted to build/, dist/ and out/; build.ps1 cannot write official release files.
4. Maintainers first prepare the signed local set through `./scripts/release.ps1` from a reviewed clean `main`. Push that reviewed source commit separately, then run `./scripts/publish.ps1` to verify and upload the existing signed set. Publication never rebuilds, re-signs, commits, or pushes; a draft is verified before it becomes public. See [release checklist](RELEASE_CHECKLIST.md).
5. If `./scripts/static-check.ps1` reports files that are not LF-normalized (older clones made with `core.autocrlf=true`), run `./scripts/normalize-eol.ps1`: it renormalizes committed CRLF files for you to commit and rewrites CRLF checkouts from the index, skipping any file with unstaged edits.

`./scripts/build.ps1 -TesseractDirectory C:\Approved\Tesseract` additionally creates the Full ZIP after verifying `tesseract.exe`, `tessdata\kor.traineddata`, and `tessdata\eng.traineddata`. The repository and Light build never bundle or download an unofficial OCR binary. See [OCR packaging](docs/OCR_PACKAGING.md).

Release signing selects the code-signing certificate from the Windows certificate store by SHA-1 thumbprint (`CLIPOCR_SIGN_CERT_THUMBPRINT`). That is how card- or cloud-backed certificates such as Certum's Open Source Code Signing (card reader or SimplySign Desktop) are exposed: the private key never leaves the token. An RFC 3161 timestamp server is required (`CLIPOCR_TIMESTAMP_SERVER`, for Certum `http://time.certum.pl`) so signatures stay valid after the certificate expires. `signtool.exe` from the Windows SDK is used when available (`CLIPOCR_SIGNTOOL_PATH` overrides discovery) and produces an RFC 3161 timestamp; without it the build falls back to `Set-AuthenticodeSignature`, which can only apply a legacy Authenticode timestamp — the manifest records which one was used (`timestampType`), so install the Windows SDK signing tools for release builds; `publish.ps1` refuses official releases whose timestamp is not RFC 3161; the former waiver is rejected. A PFX file (`CLIPOCR_SIGN_CERT_PATH` + `CLIPOCR_SIGN_CERT_PASSWORD`) is accepted only as a development fallback for self-signed test certificates. The build resolves the certificate, timestamp server, and signing tool before compiling; a card or cloud token that is not connected fails at the signing step with instructions for reconnecting it. `publish.ps1` additionally requires the signer to be issued by the release CA (pattern `CN=Certum Code Signing*`, override with `CLIPOCR_RELEASE_SIGNER_ISSUER`) and rejects self-issued certificates; official publication requires a valid timestamped signature; unsigned waivers are rejected. Signed releases are built and verified in a unique stage before promotion; the previous official directory is retained in build/release-history.

---

## 💼 Practical Business Use Cases

- **Settlement and supporting document review**: Capture key areas from invoices, ERP screens, Excel sheets, and evidence files so approvers can verify details quickly.
- **Overseas email and document translation**: Translate selected text or use image translation for foreign-language attachments and scanned documents.
- **Multi-source comparison**: Keep ERP, Excel, emails, screenshots, and supporting documents visible at the same time for reconciliation or review.
- **Report preparation**: Keep reference images floating on top while drafting reports, emails, or internal explanations.
- **Meetings and training**: Capture a part of a manual, annotate it, minimize/restore it, and explain the process clearly.
- **Email attachment optimization**: Resize captured images before pasting them into emails or documents to reduce file size and improve readability.

---

## 📖 User Guide

<p align="center">
  <img src="./assets/manual1.png" width="900" alt="ClipOCR-Pro Manual Infographic">
</p>

✔ **Capture Window**: Capture a selected screen area and keep it as an always-on-top floating image.  
✔ **Annotation**: Add red boxes, highlights, arrows, numbered pins, text notes, and mosaic masking to captured images.  
✔ **Translation**: Translate selected text or use image translation workflows when working with foreign-language documents.  
✔ **Copy / Save / Resize**: Copy, save, resize, or reuse captured images based on app settings.  
✔ **Window Management**: Minimize, restore, align, resize, or close floating capture windows using shortcuts.

> Selected text translation and image translation use Google Translate services, so review sensitive company or personal information before sending it.

---

## ⌨️ Main Shortcuts

| Shortcut | Function |
|---------|----------|
| `Win + Drag` | Capture a screen area and keep it floating on top; automatic clipboard copy follows the General setting |
| `Win + CapsLock` | Translate selected text using the configured Google Translate workflow (always active; a hotkey chosen in Preferences is added alongside it, not substituted) |
| `Ctrl + Win + 0` inside an Outlook web mail body | Show a conservative attachment-free body and subject/header estimate in MB |
| Right-click on floating window | Open image translation, annotation, copy/save, and window management menu |
| Right-click → `Extract Text (Local OCR)` | Extract text locally and open a copyable result window; no translation consent or external upload is involved |
| Double-click on floating window | Minimize or restore the floating image |
| `Ctrl + C` on floating window | Copy the floating image |
| `Ctrl + 0` on floating window | Save Original Size as the default and immediately copy the current image at its original dimensions |
| `Ctrl + 1` through `Ctrl + 7` on floating window | Set width from 400 to 1600 px and immediately copy the current image |
| `Ctrl + S` on floating window | Save a JPG or PNG to the configured folder using the current width, format, quality, and outline settings |
| Right-click → `Image Quality & Size` | Choose PNG or a JPG 90/80/70 preset and remember the last selection across restarts |
| `Shift + Drag`, `Ctrl + Drag`, `Alt + Drag`, `Ctrl + Z` on floating window | Red box, yellow highlight, green highlight, undo |
| Right-click menu → Arrow / Number Pin / Mosaic | Draw a directional arrow, stamp auto-incrementing numbered pins, or pixelate an area to mask sensitive information |
| `Ctrl + ↑`, `Ctrl + ↓`, `Ctrl + ←`, `Ctrl + Esc` on floating window | Minimize, restore original size, align left, close all |

---

## ⚙️ Settings Storage

ClipOCR-Pro stores per-user configuration data in the Windows Registry.

```text
HKCU\Software\ScreenClipTool
```

Current settings include clipboard image size, automatic clipboard copy, file-save preset, image outline, save folder, translation options, local OCR engine/languages, UI language, and the one-time translation consent flag. Auto OCR defaults to `ko-KR,en-US`: it tries an installed matching Windows OCR language first, then portable Tesseract, then another requested Windows language. App-local settings always take precedence over managed Suite defaults.

When an administrator enables the optional `PL_Suite\ClipOCR` integration, ClipOCR-Pro can read managed defaults for capture behavior and the explicit `Ctrl + S` save folder. Existing values under the app-owned path above always win, and the Suite registry is never written by the app. Translation consent remains app-local. Managed folders are never used to save captures automatically.

Opening the About tab checks the latest GitHub release. `Download & Update` is enabled only when a newer version exists. After confirmation, the compiled app downloads the official EXE to a staging folder, verifies its GitHub-provided size and SHA-256 digest plus its embedded version, replaces the current app, and restarts. Save or copy any open capture windows first. Source runs and releases without a verifiable EXE fall back to the release page. Unhandled runtime errors are appended to `%TEMP%\ClipOCR-Pro\error.log` (rolled over at 256 KB; message, source location and call stack only) so they can be attached to a support request.

Every push and pull request also runs repository policy checks and the Windows build workflow with checksum-pinned official AutoHotkey and Ahk2Exe tools. CI publishes test artifacts only; it has no release permission.

Recommended portable deployment structure:

```text
Light: ClipOCR-Pro.exe

Full:
ClipOCR-Pro.exe
ocr\tesseract.exe
ocr\tessdata\kor.traineddata
ocr\tessdata\eng.traineddata
```

If a team needs shared defaults, deploy the separate `PL_Suite` registry contract according to company policy. Do not copy personal consent or runtime data into the managed defaults.

---

## 🔐 Security & Privacy

- ClipOCR-Pro runs locally on Windows.
- Local OCR input and output stay on the PC. Windows OCR requires a matching installed Windows language; the Full package provides the approved `kor+eng` portable fallback for locked-down English Windows PCs.
- Local capture, annotation, copy, save, and resize actions are handled on the user's PC.
- Outlook web mail estimates are calculated only from the local clipboard and do not send message content externally. Actual sent size may differ.
- When translation features are used, selected text or images may be processed through external translation services such as Google Translate, depending on the configured workflow.
- Before the first translation, a one-time consent notice is shown so users can confirm that no sensitive data is being sent to an external service.
- In the default configuration, the app downloads no external images at runtime: the GitHub icon is a bundled asset, and the sponsor button auto-download is off by default — helpful on restricted corporate networks.
- The Mosaic annotation tool can pixelate account numbers, names, or other sensitive areas before a capture is shared.
- Avoid translating or storing passwords, API keys, personal credentials, confidential financial data, or highly sensitive documents through external services.
- Review exported Registry settings before distributing them to colleagues, especially if they contain workflow-specific values.

---

## 👨‍💼 Project Background

I am **not a professional developer, but a finance practitioner working with real business operations.**

I started this project to reduce repetitive office tasks such as screen capture, selected text translation, document organization, and information sharing. What began as a small automation script gradually evolved into a practical productivity tool for real office workflows.

ClipOCR-Pro reflects a hands-on approach: identify repetitive work, automate the practical pain points, and make the result simple enough for non-developers to use.

---

## 💻 Environment & License

- **Environment**: Windows 10 / 11, AutoHotkey v2 runtime, or compiled standalone executable
- **macOS**: Not supported
- **License**: MIT License. Includes GDI+ wrapper by Tariq Porter (tic).

---

## ☕ Support This Project

If this tool has helped reduce repetitive work or improved your productivity, your support is a great motivation for creating more practical office automation tools.

<p align="center">
  <a href="https://www.buymeacoffee.com/KBPark_Bob">
    <img
      src="https://cdn.buymeacoffee.com/buttons/v2/default-yellow.png"
      width="220"
      alt="Buy Me A Coffee">
  </a>
</p>


Shared installation, settings, release goals, and current exceptions are documented in [Suite standardization](docs/SUITE_STANDARDIZATION.md).

Release pipeline and remaining Windows checks: [Phase 2 review](docs/STANDARDIZATION_PHASE2_REVIEW.md).

설정 위치·전체 백업·새 폴더 복원: [사용자 자료](docs/USER_DATA.md), [관리 도구](scripts/Manage-UserData.ps1). 공개 구조·대표 흐름: [CODE_MAP](docs/CODE_MAP.md).
