; Headless regression checks used by local builds and CI.

RunInternalHealthCheck() {
    errors := []
    try {
        RunHealthCheckSuite(errors)
    } catch as e {
        errors.Push("unhandled error: " DescribeThrown(e))
    }
    WriteHealthCheckLog(errors)
    return errors.Length == 0 ? 0 : 1
}

; Every check runs in isolation so one exception is recorded as a failure instead of aborting
; the rest of the suite.
RunHealthCheckSuite(errors) {
    Check(probe, message) {
        try {
            if !probe()
                errors.Push(message)
        } catch as e {
            errors.Push(message ": " ShortErrorMessage(e.Message))
        }
    }

    Check(() => CompareSemanticVersions("1.10.0", "1.9.9") == 1, "semantic version comparison")
    Check(() => ExtractSemanticVersion("Release v2.3.4") == "2.3.4", "semantic version extraction")
    Check(() => NormalizeJpegQuality(80) == 80 && NormalizeJpegQuality(85) == 90, "JPG quality normalization")
    Check(() => NormalizeSaveImageFormat("JPG") == "jpg" && NormalizeSaveImageFormat("gif") == "png",
        "save image format normalization")
    Check(() => GetImageSavePresetOptions().Length == 4 && GetImageSavePresetIndex("png", 90) == 1
        && GetImageSavePresetIndex("jpg", 80) == 3, "image save presets")
    Check(() => NormalizeSuiteBoolean("True", false) && !NormalizeSuiteBoolean("0", true)
        && NormalizeSuiteBoolean("invalid", true), "Suite boolean normalization")
    Check(() => !ResolveBooleanSetting(true, "0", true, "True", true)
        && !ResolveBooleanSetting(false, "", true, "False", true)
        && ResolveBooleanSetting(false, "", false, "", true), "local and Suite boolean precedence")
    Check(() => IsCaptureHotkeySupported("Win+Drag") && IsCaptureHotkeySupported("#LButton")
        && !IsCaptureHotkeySupported("Alt+F4") && NormalizeCaptureHotkey("Alt+F4") == "#LButton",
        "capture hotkey validation")
    Check(() => GetSettingSection("SaveImageFormat") == "Image"
        && GetSettingSection("TranslateLang") == "Translation"
        && GetSettingSection("OcrEngine") == "OCR"
        && GetSettingSection("MigratedFromRegistry") == "System"
        && GetSettingSection("SaveFolder") == "General", "SettingsManager section mapping")
    Check(() => IsTextTranslateHotkeySupported("#CapsLock") && IsTextTranslateHotkeySupported("^!CapsLock"),
        "translation hotkey validation")
    Check(() => IsValidTextTranslateFontSize(8) && IsValidTextTranslateFontSize(18)
        && !IsValidTextTranslateFontSize(19) && !IsValidTextTranslateFontSize("x")
        && NormalizeTextTranslateFontSize("x") == 10 && NormalizeTextTranslateFontSize(12) == 12,
        "translation font size bounds")
    Check(() => NormalizeOcrEngine("WINDOWS") == "windows" && NormalizeOcrEngine("unknown") == "auto",
        "OCR engine normalization")
    Check(() => NormalizeOcrLanguages("ko_kr;EN-us;ko-KR") == "ko-KR,en-US"
        && NormalizeOcrLanguages("zh-hans-cn, SR-cyrl") == "zh-Hans-CN,sr-Cyrl"
        && NormalizeOcrLanguages("invalid") == "" && ResolveOcrLanguages("invalid") == "ko-KR,en-US",
        "OCR language normalization")
    Check(() => GetTesseractLanguageCode("ko-KR") == "kor" && GetTesseractLanguageCode("en-US") == "eng"
        && GetTesseractLanguageCode("ja-JP") == "jpn" && GetTesseractLanguageCode("zh-Hant-TW") == "chi_tra"
        && GetTesseractLanguageCode("zh-CN") == "chi_sim" && GetTesseractLanguageCode("zh-Hans-HK") == "chi_sim"
        && GetTesseractLanguageCode("fa-IR") == "fas" && GetTesseractLanguageCode("nb-NO") == "nor"
        && GetTesseractLanguageCode("de") == "deu" && GetTesseractLanguageCode("kor") == "kor"
        && GetTesseractLanguageCode("xx") == "xx", "Tesseract language mapping")
    Check(() => NormalizeOcrText("a`r`nb`nc`r") == "a`r`nb`r`nc", "OCR text line endings")
    Check(() => InStr(GetOcrUserFailureMessage("NO_LANGUAGE"), "Full package") > 0,
        "OCR recovery guidance")
    Check(() => FileExist(PrepareWindowsOcrHelper()), "embedded Windows OCR helper")

    tessFixtureRoot := A_Temp "\clipocr_tessdata_" DllCall("GetCurrentProcessId")
    try {
        DirCreate(tessFixtureRoot)
        FileAppend("fixture", tessFixtureRoot "\kor.traineddata", "UTF-8-RAW")
        FileAppend("fixture", tessFixtureRoot "\eng.traineddata", "UTF-8-RAW")
        resolvedTessFixture := ResolveTesseractLanguages("ko-KR,en-US,pl-PL", tessFixtureRoot)
        Check(() => resolvedTessFixture.value == "kor+eng" && resolvedTessFixture.missing.Length == 1,
            "Tesseract language data resolution")
    } catch as e {
        errors.Push("Tesseract fixtures: " ShortErrorMessage(e.Message))
    } finally {
        try {
            if DirExist(tessFixtureRoot)
                DirDelete(tessFixtureRoot, true)
        }
    }

    saveFixtureRoot := A_Temp "\clipocr_settings_" DllCall("GetCurrentProcessId")
    localSaveFixture := saveFixtureRoot "\local"
    suiteSaveFixture := saveFixtureRoot "\suite"
    SaveFolderResolvesTo(localFound, localValue, suiteFound, suiteValue, folder, source) {
        resolution := ResolveSaveFolderSetting(localFound, localValue, suiteFound, suiteValue)
        return resolution.folder == folder && resolution.source == source
    }
    try {
        DirCreate(localSaveFixture)
        DirCreate(suiteSaveFixture)
        Check(() => SaveFolderResolvesTo(true, localSaveFixture, true, suiteSaveFixture, localSaveFixture, "local"),
            "explicit save folder precedence")
        Check(() => SaveFolderResolvesTo(false, "", true, suiteSaveFixture, suiteSaveFixture, "suite"),
            "Suite save folder fallback")
        Check(() => SaveFolderResolvesTo(true, "", true, suiteSaveFixture, "", "local"),
            "explicit Desktop save preference")
        Check(() => SaveFolderResolvesTo(false, "", false, "", "", "desktop"), "Desktop save fallback")
    } catch as e {
        errors.Push("save folder fixtures: " ShortErrorMessage(e.Message))
    } finally {
        try {
            if DirExist(saveFixtureRoot)
                DirDelete(saveFixtureRoot, true)
        }
    }

    fixtureHash := "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
    fixtureJson := '{"tag_name":"v9.8.7","name":"Release v9.8.7","html_url":"https://github.com/KwangBeomPark/01_ClipOCR-Pro/releases/tag/v9.8.7","assets":[{"name":"ClipOCR-Pro.v9.8.7.exe","size":1569280,"digest":"sha256:'
    fixtureJson .= fixtureHash
    fixtureJson .= '","browser_download_url":"https://github.com/KwangBeomPark/01_ClipOCR-Pro/releases/download/v9.8.7/ClipOCR-Pro.v9.8.7.exe"}]}'
    Check(() => (releaseInfo := ParseGithubLatestRelease(fixtureJson)) && IsObject(releaseInfo)
        && releaseInfo.version == "9.8.7" && releaseInfo.assetName == "ClipOCR-Pro.v9.8.7.exe"
        && releaseInfo.assetSize == 1569280 && releaseInfo.sha256 == fixtureHash, "GitHub release parsing")

    hashFixture := A_Temp "\clipocr_health_" DllCall("GetCurrentProcessId") ".txt"
    try {
        FileAppend("abc", hashFixture, "UTF-8-RAW")
        Check(() => GetFileSha256(hashFixture) == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
            "SHA-256 calculation")
    } catch as e {
        errors.Push("SHA-256 fixture: " ShortErrorMessage(e.Message))
    } finally {
        try {
            if FileExist(hashFixture)
                FileDelete(hashFixture)
        }
    }

    formatToken := 0
    formatBitmap := 0
    formatGraphics := 0
    pngFixture := A_Temp "\clipocr_health_" DllCall("GetCurrentProcessId") ".png"
    jpgFixture := A_Temp "\clipocr_health_" DllCall("GetCurrentProcessId") ".jpg"
    try {
        formatToken := Gdip_Startup()
        formatBitmap := Gdip_CreateBitmap(64, 64)
        formatGraphics := Gdip_GraphicsFromImage(formatBitmap)
        Gdip_GraphicsClear(formatGraphics, 0xFFF4F4F4)
        Check(() => SafeSaveBitmapToFile(formatBitmap, pngFixture, 100) && FileGetSize(pngFixture) > 0,
            "PNG lossless save")
        Check(() => SafeSaveBitmapToFile(formatBitmap, jpgFixture, 90) && FileGetSize(jpgFixture) > 0,
            "JPG quality save")
    } catch as e {
        errors.Push("image format fixture: " ShortErrorMessage(e.Message))
    } finally {
        if formatGraphics
            try Gdip_DeleteGraphics(formatGraphics)
        if formatBitmap
            try Gdip_DisposeImage(formatBitmap)
        if formatToken
            try Gdip_Shutdown(formatToken)
        try {
            if FileExist(pngFixture)
                FileDelete(pngFixture)
            if FileExist(jpgFixture)
                FileDelete(jpgFixture)
        }
    }
}

; Writes this run's verdict to %TEMP%\ClipOCR-Pro\health-check.log and echoes failures to stdout.
; The log is informational: failing to write it must never change the verdict.
WriteHealthCheckLog(errors) {
    healthDir := GetAppTempDir()
    healthLog := healthDir "\health-check.log"
    try {
        if !DirExist(healthDir)
            DirCreate(healthDir)
        if FileExist(healthLog)
            FileDelete(healthLog)
        if (errors.Length == 0)
            FileAppend("ClipOCR-Pro health check: PASS`r`n", healthLog, "UTF-8")
        for _, message in errors
            FileAppend("FAIL: " message "`r`n", healthLog, "UTF-8")
    }
    for _, message in errors
        try FileAppend("FAIL: " message "`n", "*")
}
