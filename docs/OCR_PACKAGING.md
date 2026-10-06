# Local OCR deployment

ClipOCR-Pro keeps text extraction local. The Light executable uses `Windows.Media.Ocr`; the optional Full ZIP places a company-approved portable Tesseract runtime beside the app.

## Runtime selection

- `Auto`: try the first requested Windows OCR language, then portable Tesseract with every available requested language, then the remaining Windows OCR languages.
- `Windows OCR only`: use only OCR languages installed in Windows.
- `Portable Tesseract only`: use only the adjacent portable runtime.

Language tags use BCP 47, for example `ko-KR,en-US`; script subtags such as `zh-Hans-CN` or `sr-Cyrl` are accepted as well. Windows may expose a neutral tag such as `ko`; ClipOCR-Pro matches the base language. Tesseract receives the matching `tessdata` code (`ko` → `kor`, `en` → `eng`, `ja` → `jpn`, `zh-Hant` → `chi_tra`, and so on); unmapped three-letter codes are passed through unchanged. An invalid language list is rejected in the settings dialog rather than silently replaced with the default.

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

The build rejects a Full package unless `tesseract.exe`, Korean data, and English data are present and the runtime successfully reports both `kor` and `eng`. It copies the complete approved runtime so its required DLLs are preserved. The resulting `App01_ClipOCR-Pro_vX.Y.Z-Full.zip` is checksummed in `SHA256SUMS.txt` and listed in the build manifest together with the detected Tesseract version.

The Full ZIP is produced only by this explicit `build.ps1` invocation and is distributed internally by the administrator. `publish.ps1` uploads the Light artifacts only and never bundles the approved runtime into a public GitHub release; the app-side `CLIPOCR_TESSERACT_DIR` environment variable is not consulted by the build.

## Privacy boundary

Local OCR never calls the Google translation path and never asks for translation consent. Choosing Google image or selected-text translation remains an explicit separate action governed by the existing consent notice.
