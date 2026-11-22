# Local OCR deployment

ClipOCR-Pro keeps text extraction local. The Light executable uses `Windows.Media.Ocr` (and can optionally use a locally provisioned offline RapidOCR PP-OCRv5 runtime for Korean); the optional Full ZIP places a company-approved portable Tesseract runtime beside the app.

## Runtime selection

- `Auto (RapidOCR ko, Windows others)`:
  - When the primary requested language is Korean (`ko`), try local offline RapidOCR PP-OCRv5 (on `1×` raw input), then `Windows.Media.Ocr` (`ko`), then portable Tesseract, then remaining fallback languages in `Windows.Media.Ocr`.
  - When the primary requested language is Polish (`pl`), English (`en`), or another non-Korean language, try `Windows.Media.Ocr` first (on `2×` + uniform-edge padded input), then portable Tesseract, then RapidOCR (if the corresponding model is installed), then remaining fallback languages.
- `RapidOCR only (PP-OCRv5 local)`: use only the local offline RapidOCR ONNX runtime and local models.
- `Windows OCR only`: use only OCR languages installed in Windows.
- `Portable Tesseract only`: use only the adjacent portable runtime.

In the local OCR result popup, you can also switch the `OCR` language selector (for example `한국어 (ko)` ↔ `Polski (pl)` ↔ `English (en)`) to re-run local extraction on the current capture without re-taking a screenshot.

Language tags use BCP 47, for example `ko-KR,en-US`; script subtags such as `zh-Hans-CN` or `sr-Cyrl` are accepted as well. Windows may expose a neutral tag such as `ko`; ClipOCR-Pro matches the base language. Tesseract receives the matching `tessdata` code (`ko` → `kor`, `en` → `eng`, `ja` → `jpn`, `zh-Hant` → `chi_tra`, and so on); unmapped three-letter codes are passed through unchanged. An invalid language list is rejected in the settings dialog rather than silently replaced with the default.

## Optional local RapidOCR PP-OCRv5 runtime (offline Korean boost)

To keep the public Light installer lightweight and free of external model downloads in `build.ps1`, RapidOCR models are not bundled into the public release installer. To enable local RapidOCR PP-OCRv5 alongside ClipOCR-Pro:

```text
ClipOCR-Pro.exe (or running from src\ClipOCR-Pro.ahk)
ocr\rapidocr\ (or tools\rapidocr\ when running uncompiled from src\, or %CLIPOCR_RAPIDOCR_DIR%)
  .venv\Scripts\python.exe (or python\python.exe)
  models\
    ch_PP-OCRv5_det_mobile.onnx
    korean_PP-OCRv5_rec_mobile.onnx
    latin_PP-OCRv5_rec_mobile.onnx   (optional)
```

For local development or approved internal setup, prepare `tools\rapidocr` explicitly with:

```powershell
.\scripts\Prepare-RapidOcrRuntime.ps1
```

At runtime `Invoke-RapidOcr.py` runs completely offline with explicit local ONNX paths (`Global.use_cls=False`, `Det.limit_type=max`, `Det.limit_side_len=1600`, `Det.box_thresh=0.3`) and never touches the network.

## English Windows without a Korean language pack

No Windows UI-language change is required. Deploy the Full ZIP with this structure:

```text
ClipOCR-Pro.exe
ocr\
  tesseract.exe
  tessdata\
    kor.traineddata
    eng.traineddata
  ...runtime DLLs and configuration supplied by the approved distribution...
```

The build does not fetch OCR binaries. Obtain and approve a portable Windows Tesseract distribution according to company software and security policy, then run:

```powershell
.\scripts\build.ps1 -TesseractDirectory C:\Approved\Tesseract
```

The build rejects a Full package unless `tesseract.exe`, Korean data, and English data are present and the runtime successfully reports both `kor` and `eng`. It copies the complete approved runtime so its required DLLs are preserved. The resulting `App01_ClipOCR-Pro_vX.Y.Z-Full.zip` and its diagnostic stage are retained under a unique `build/full-ocr-<GUID>/` directory before the local application EXE is removed from the installer-only output. It is separate from the public installer manifest and is not uploaded by publish.ps1. Record a private hash when distributing this approved internal package.

The Full ZIP is produced only by this explicit `build.ps1` invocation and is distributed internally by the administrator. `publish.ps1` uploads the previously signed installer and its two verification metadata files only and never bundles the approved runtime into a public GitHub release; neither `CLIPOCR_TESSERACT_DIR` nor `CLIPOCR_RAPIDOCR_DIR` is consulted by the build.

## Privacy boundary

Local OCR (Windows OCR, RapidOCR, and portable Tesseract) never calls the Google translation path, never makes network requests, and never asks for translation consent. Choosing Google image or selected-text translation remains an explicit separate action governed by the existing consent notice.
