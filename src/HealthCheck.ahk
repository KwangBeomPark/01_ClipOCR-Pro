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
    Check(() => NormalizeClipBorderColor("#e53935") == "E53935"
        && NormalizeClipBorderColor("invalid") == "000000"
        && NormalizeClipBorderWidth(3) == 3 && NormalizeClipBorderWidth(9) == 1,
        "clip border color and width normalization")
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
    fixtureJson := '{"tag_name":"v9.8.7","name":"Release v9.8.7","html_url":"https://github.com/KwangBeomPark/01_ClipOCR-Pro/releases/tag/v9.8.7","assets":[{"name":"App01_ClipOCR-Pro_Setup_v9.8.7.exe","size":1569280,"digest":"sha256:'
    fixtureJson .= fixtureHash
    fixtureJson .= '","browser_download_url":"https://github.com/KwangBeomPark/01_ClipOCR-Pro/releases/download/v9.8.7/App01_ClipOCR-Pro_Setup_v9.8.7.exe"}]}'
    Check(() => (releaseInfo := ParseGithubLatestRelease(fixtureJson)) && IsObject(releaseInfo)
        && releaseInfo.version == "9.8.7" && releaseInfo.assetName == "App01_ClipOCR-Pro_Setup_v9.8.7.exe"
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
    Check(() => CheckSettingsSetterFailure(), "settings setters keep runtime state after failed save")
    Check(() => CheckClipWinBorderGeometry(), "floating clip border geometry across resize and restore")
}

CheckSettingsSetterFailure() {
    global CONFIG_DIR, CONFIG_FILE, REG_PATH, SAVE_FOLDER, SAVE_FOLDER_SOURCE, AUTO_CLIPBOARD
    global OCR_ENGINE, OCR_LANGUAGES, CLIP_WIDTH, COPY_OUTLINE_ENABLED, JPG_QUALITY
    global WINDOW_BORDER_COLOR, WINDOW_BORDER_WIDTH
    global SAVE_IMAGE_FORMAT, TEXT_TRANSLATE_LANG, TEXT_TRANSLATE_FONT_SIZE
    oldDir := CONFIG_DIR
    oldFile := CONFIG_FILE
    CONFIG_DIR := A_Temp "\clipocr-settings-failure-" DllCall("GetCurrentProcessId") "-" A_TickCount
    CONFIG_FILE := CONFIG_DIR "\config.ini"
    locked := 0
    try {
        REG_PATH := "HKCU\Software\ClipOCR-Health-Fixture-NoUserSettings"
        SettingsWriteIniValues(CONFIG_FILE, [{Section: "General", Key: "Fixture", Value: "original"}])
        original := FileRead(CONFIG_FILE, "UTF-16")
        SAVE_FOLDER := "old"
        SAVE_FOLDER_SOURCE := "local"
        AUTO_CLIPBOARD := true
        OCR_ENGINE := "auto"
        OCR_LANGUAGES := "en-US"
        CLIP_WIDTH := 1200
        COPY_OUTLINE_ENABLED := false
        WINDOW_BORDER_COLOR := "000000"
        WINDOW_BORDER_WIDTH := 1
        JPG_QUALITY := 90
        SAVE_IMAGE_FORMAT := "png"
        TEXT_TRANSLATE_LANG := "ko"
        TEXT_TRANSLATE_FONT_SIZE := 10
        locked := FileOpen(CONFIG_FILE, "r-wd")
        if SetSaveFolder("new") || SAVE_FOLDER != "old"
            throw Error("Save folder changed after failed persistence")
        if SetAutoClipboard(false) || !AUTO_CLIPBOARD
            throw Error("Clipboard state changed after failed persistence")
        if SetOcrEngine("windows") || OCR_ENGINE != "auto"
            throw Error("OCR engine changed after failed persistence")
        if SetOcrLanguages("ko-KR") || OCR_LANGUAGES != "en-US"
            throw Error("OCR languages changed after failed persistence")
        if SetClipWidth(800) || CLIP_WIDTH != 1200
            throw Error("Clipboard width changed after failed persistence")
        if SetCopyOutline(true) || COPY_OUTLINE_ENABLED
            throw Error("Copy outline changed after failed persistence")
        if SetClipBorderColor("E53935") || WINDOW_BORDER_COLOR != "000000"
            throw Error("Clip border color changed after failed persistence")
        if SetClipBorderWidth(3) || WINDOW_BORDER_WIDTH != 1
            throw Error("Clip border width changed after failed persistence")
        if SetJpegQuality(70) || JPG_QUALITY != 90
            throw Error("JPEG quality changed after failed persistence")
        if SetSaveImageFormat("jpg") || SAVE_IMAGE_FORMAT != "png"
            throw Error("Image format changed after failed persistence")
        if SetTextTranslateLang("en") || TEXT_TRANSLATE_LANG != "ko"
            throw Error("Translation language changed after failed persistence")
        if SetTextTranslateFontSize(12) || TEXT_TRANSLATE_FONT_SIZE != 10
            throw Error("Translation font changed after failed persistence")
        return FileRead(CONFIG_FILE, "UTF-16") == original
    } finally {
        if locked
            locked.Close()
        CONFIG_DIR := oldDir
        CONFIG_FILE := oldFile
        ; Retain the unique fixture as inspection evidence.
    }
}

CheckClipWinBorderGeometry() {
    global WINDOW_BORDER_WIDTH, WINDOW_BORDER_COLOR, ClipWins, MINI_SIZE, MINI_OPACITY
    hasBorderW := IsSet(WINDOW_BORDER_WIDTH)
    hasBorderColor := IsSet(WINDOW_BORDER_COLOR)
    hasClipWins := IsSet(ClipWins)
    hasMiniSize := IsSet(MINI_SIZE)
    hasMiniOpacity := IsSet(MINI_OPACITY)
    oldBorderW := hasBorderW ? WINDOW_BORDER_WIDTH : 1
    oldBorderColor := hasBorderColor ? WINDOW_BORDER_COLOR : "000000"
    if !hasClipWins
        ClipWins := Map()
    if !hasMiniSize
        MINI_SIZE := 80
    if !hasMiniOpacity
        MINI_OPACITY := 128

    token := 0, bmp1 := 0, bmp2 := 0, hwnd1 := 0, hwnd2 := 0
    try {
        try DllCall("SetThreadDpiAwarenessContext", "ptr", -4, "ptr")
        token := Gdip_Startup()
        WINDOW_BORDER_WIDTH := 1
        WINDOW_BORDER_COLOR := "000000"
        bmp1 := Gdip_CreateBitmap(40, 30)
        bmp2 := Gdip_CreateBitmap(40, 30)
        hwnd1 := CreateClipWin(bmp1, 100, 120)
        bmp1 := 0 ; owned by ClipWins[hwnd1]
        hwnd2 := CreateClipWin(bmp2, 220, 140)
        bmp2 := 0 ; owned by ClipWins[hwnd2]

        MinimizeClipWin(hwnd2, ClipWins[hwnd2])
        if !ClipWins[hwnd2].IsMinimized
            return false

        WINDOW_BORDER_WIDTH := 5
        WINDOW_BORDER_COLOR := "E53935"
        UpdateAllClipWinBorders()

        ; Normal window keeps image top-left at (100, 120) -> window at (95, 115), size (50, 40)
        WinGetPos(&x1, &y1, &w1, &h1, "ahk_id " hwnd1)
        ClipWins[hwnd1].picCtrl.GetPos(&px1, &py1)
        ClipWins[hwnd1].closeBtn.GetPos(&cx1, &cy1)
        if (x1 + px1 != 100 || y1 + py1 != 120 || w1 != 50 || h1 != 40 || cx1 != 40 + 5 - 16 || cy1 != 5)
            return false

        ; Minimized window restored after border change keeps image top-left at (220, 140)
        SCW_RestoreAll()
        WinGetPos(&x2, &y2, &w2, &h2, "ahk_id " hwnd2)
        ClipWins[hwnd2].picCtrl.GetPos(&px2, &py2)
        if (x2 + px2 != 220 || y2 + py2 != 140 || w2 != 50 || h2 != 40)
            return false

        ; Switch back 5 -> 1 px while minimized via SCW_MinimizeAll / RestoreClipWin path
        SCW_MinimizeAll()
        WINDOW_BORDER_WIDTH := 1
        WINDOW_BORDER_COLOR := "000000"
        UpdateAllClipWinBorders()
        RestoreClipWin(hwnd1, ClipWins[hwnd1])
        RestoreClipWin(hwnd2, ClipWins[hwnd2])
        WinGetPos(&rx1, &ry1, &rw1, &rh1, "ahk_id " hwnd1)
        ClipWins[hwnd1].picCtrl.GetPos(&rpx1, &rpy1)
        ClipWins[hwnd1].closeBtn.GetPos(&rcx1, &rcy1)
        WinGetPos(&rx2, &ry2, &rw2, &rh2, "ahk_id " hwnd2)
        ClipWins[hwnd2].picCtrl.GetPos(&rpx2, &rpy2)
        ClipWins[hwnd2].closeBtn.GetPos(&rcx2, &rcy2)
        return (rx1 + rpx1 == 100 && ry1 + rpy1 == 120 && rw1 == 42 && rh1 == 32 && rcx1 == 25 && rcy1 == 1
            && rx2 + rpx2 == 220 && ry2 + rpy2 == 140 && rw2 == 42 && rh2 == 32 && rcx2 == 25 && rcy2 == 1)
    } finally {
        if (hwnd1 && ClipWins.Has(hwnd1))
            try CloseClipWin(ClipWins[hwnd1].gui)
        if (hwnd2 && ClipWins.Has(hwnd2))
            try CloseClipWin(ClipWins[hwnd2].gui)
        if bmp1
            try Gdip_DisposeImage(bmp1)
        if bmp2
            try Gdip_DisposeImage(bmp2)
        if token
            try Gdip_Shutdown(token)
        WINDOW_BORDER_WIDTH := oldBorderW
        WINDOW_BORDER_COLOR := oldBorderColor
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
