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
    Check(() => (items := GetTextTranslationPopupLangItems()) && items.Length > 1 && items[1] == "ORIGINAL",
        "translation popup language list starts with ORIGINAL")
    Check(() => TrimUnicodeWhitespace(Chr(0x00A0) Chr(0x3000) "  ") == ""
        && TrimUnicodeWhitespace(Chr(0x00A0) "ok" Chr(0x3000)) == "ok", "unicode whitespace trimming")
    Check(() => NormalizeOcrEngine("WINDOWS") == "windows"
        && NormalizeOcrEngine("RAPIDOCR") == "rapidocr"
        && NormalizeOcrEngine("unknown") == "auto",
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
    Check(() => InStr(GetOcrUserFailureMessage("Portable RapidOCR is not installed"), "Auto") > 0,
        "RapidOCR missing-runtime guidance")
    Check(() => FileExist(PrepareWindowsOcrHelper()), "embedded Windows OCR helper")
    Check(() => FileExist(PrepareRapidOcrHelper()), "embedded RapidOCR helper")

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
    Check(() => CheckOcrPopupLayout(), "OCR popup starts on ORIGINAL with non-overlapping layout")
    Check(() => CheckOcrPopupLangMapping(), "OCR popup language dropdown maps Tesseract and custom tags safely")
    Check(() => CheckOcrAsyncEdgeCases(), "OCR extraction gating and mid-flight popup closing stay leak-free")
    Check(() => CheckOcrLazyInputIsolation(), "OCR prepares engine-specific images lazily without blocking fallbacks")
    Check(() => CheckOcrInputPreprocessing(), "OCR input preprocessing scales small captures and pads uniform borders")
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

CheckOcrPopupLayout() {
    global OcrResultPopupHwnd, TRANSLATE_CONSENT, TEXT_TRANSLATE_MAX_CHARS, MANUAL_LANG, OCR_ENGINE, OCR_LANGUAGES
    if !IsSet(OcrResultPopupHwnd)
        OcrResultPopupHwnd := 0
    oldHwnd := OcrResultPopupHwnd
    oldConsent := IsSet(TRANSLATE_CONSENT) ? TRANSLATE_CONSENT : false
    oldMaxChars := IsSet(TEXT_TRANSLATE_MAX_CHARS) ? TEXT_TRANSLATE_MAX_CHARS : 5000
    oldManualLang := IsSet(MANUAL_LANG) ? MANUAL_LANG : "en"
    oldOcrEngine := IsSet(OCR_ENGINE) ? OCR_ENGINE : "auto"
    oldOcrLangs := IsSet(OCR_LANGUAGES) ? OCR_LANGUAGES : "ko-KR,en-US"
    TRANSLATE_CONSENT := true
    TEXT_TRANSLATE_MAX_CHARS := 5000
    MANUAL_LANG := "en"
    OCR_ENGINE := "auto"
    OCR_LANGUAGES := "ko-KR,en-US"
    try {
        try DllCall("SetThreadDpiAwarenessContext", "ptr", -4, "ptr")
        translateCalls := 0
        lastTranslatedSource := ""
        reOcrCalls := 0
        lastReOcrLang := ""
        MockTranslate(src, lang) {
            translateCalls++
            lastTranslatedSource := src
            return "mock:" lang ":" src
        }
        MockReOcr(langCode) {
            reOcrCalls++
            lastReOcrLang := langCode
            return { ok: true, engine: "Windows OCR", language: langCode, text: "Mock PL " langCode, error: "" }
        }
        ShowOcrResultPopup("Hello OCR test", "Windows OCR", "en-US", "", MockTranslate, 0, MockReOcr)
        if (!OcrResultPopupHwnd || !WinExist("ahk_id " OcrResultPopupHwnd))
            return false

        g := GuiFromHwnd(OcrResultPopupHwnd)
        if !IsObject(g)
            return false

        textCtrls := []
        ddlCtrls := []
        editCtrl := 0
        btnCtrls := []
        for ctrl in g {
            if (ctrl.Type == "Text")
                textCtrls.Push(ctrl)
            else if (ctrl.Type == "DDL")
                ddlCtrls.Push(ctrl)
            else if (ctrl.Type == "Edit")
                editCtrl := ctrl
            else if (ctrl.Type == "Button")
                btnCtrls.Push(ctrl)
        }
        if (textCtrls.Length < 3 || ddlCtrls.Length < 2 || !IsObject(editCtrl) || btnCtrls.Length < 2)
            return false

        ocrLabelCtrl := textCtrls[1]
        labelCtrl := textCtrls[2]
        detailsCtrl := textCtrls[3]
        ocrLangCtrl := ddlCtrls[1]
        langCtrl := ddlCtrls[2]
        copyCtrl := btnCtrls[1]
        closeCtrl := btnCtrls[2]
        if (ocrLangCtrl.Text != "English (en)" || langCtrl.Text != "ORIGINAL" || editCtrl.Value != "Hello OCR test")
            return false

        InBounds(ctrl, cw, ch) {
            ctrl.GetPos(&x, &y, &w, &h)
            return (x >= 0 && y >= 0 && x + w <= cw && y + h <= ch)
        }

        CheckBoundsAndOverlap() {
            g.GetClientPos(, , &cw, &ch)
            for _, c in [ocrLabelCtrl, ocrLangCtrl, labelCtrl, langCtrl, detailsCtrl, editCtrl, copyCtrl, closeCtrl] {
                if !InBounds(c, cw, ch)
                    return false
            }
            ocrLabelCtrl.GetPos(&olx, &oly, &olw, &olh)
            ocrLangCtrl.GetPos(&ocx, &ocy, &ocw, &och)
            labelCtrl.GetPos(&lx, &ly, &lw, &lh)
            langCtrl.GetPos(&cx, &cy, &cw2, &ch2)
            detailsCtrl.GetPos(&dx, &dy, &dw, &dh)
            editCtrl.GetPos(&ex, &ey, &ew, &eh)
            copyCtrl.GetPos(&bx, &by, &bw, &bh)
            closeCtrl.GetPos(&clx, &cly, &clw, &clh)
            return (olx + olw < ocx) && (ocx + ocw < lx) && (lx + lw < cx)
                && (oly + olh < dy) && (ocy + och < dy) && (ly + lh < dy) && (cy + ch2 < dy)
                && (dy + dh < ey) && (ey + eh < by) && (bx + bw < clx)
        }

        g.GetClientPos(, , &initW, &initH)
        if !CheckBoundsAndOverlap()
            return false

        g.Show("w520 h320")
        Sleep(30)
        g.GetClientPos(, , &minW, &minH)
        if (minW != 520 || minH != 320 || !CheckBoundsAndOverlap())
            return false

        ; Opening OCR language dropdown and navigating with Up + Esc must cancel back to English (en) with 0 re-OCR calls.
        SendMessage(0x014F, 1, 0, ocrLangCtrl.Hwnd)
        Sleep(20)
        if (SendMessage(0x0157, 0, 0, ocrLangCtrl.Hwnd) != 1)
            return false
        SendMessage(0x0100, 0x26, 0, ocrLangCtrl.Hwnd)
        Sleep(20)
        if (ocrLangCtrl.Value != 2)
            return false
        SendMessage(0x0100, 0x1B, 0, ocrLangCtrl.Hwnd)
        Sleep(30)
        if !(WinExist("ahk_id " OcrResultPopupHwnd)
            && SendMessage(0x0157, 0, 0, ocrLangCtrl.Hwnd) == 0
            && ocrLangCtrl.Text == "English (en)"
            && editCtrl.Value == "Hello OCR test"
            && reOcrCalls == 0
            && translateCalls == 0)
            return false

        ; Opening translation dropdown and navigating with Down + Esc must cancel back to ORIGINAL with 0 translations.
        SendMessage(0x014F, 1, 0, langCtrl.Hwnd)
        Sleep(20)
        if (SendMessage(0x0157, 0, 0, langCtrl.Hwnd) != 1)
            return false
        SendMessage(0x0100, 0x28, 0, langCtrl.Hwnd)
        Sleep(20)
        if (langCtrl.Value <= 1)
            return false
        SendMessage(0x0100, 0x1B, 0, langCtrl.Hwnd)
        Sleep(30)
        if !(WinExist("ahk_id " OcrResultPopupHwnd)
            && SendMessage(0x0157, 0, 0, langCtrl.Hwnd) == 0
            && langCtrl.Text == "ORIGINAL"
            && editCtrl.Value == "Hello OCR test"
            && translateCalls == 0)
            return false

        ; Full-text commit: open dropdown, Down to Korean (ko), Enter -> mock translation applied.
        SendMessage(0x014F, 1, 0, langCtrl.Hwnd)
        Sleep(20)
        SendMessage(0x0100, 0x28, 0, langCtrl.Hwnd)
        Sleep(20)
        SendMessage(0x0100, 0x0D, 0, langCtrl.Hwnd)
        Sleep(60)
        if !(translateCalls == 1 && lastTranslatedSource == "Hello OCR test" && editCtrl.Value == "mock:ko:Hello OCR test")
            return false

        ; Return to ORIGINAL, select "OCR" (indices 6..9), then switch to Korean (ko) -> selected-text translation applied.
        SendMessage(0x014F, 1, 0, langCtrl.Hwnd)
        Sleep(20)
        SendMessage(0x0100, 0x26, 0, langCtrl.Hwnd)
        Sleep(20)
        SendMessage(0x0100, 0x0D, 0, langCtrl.Hwnd)
        Sleep(40)
        if !(langCtrl.Text == "ORIGINAL" && editCtrl.Value == "Hello OCR test")
            return false

        SendMessage(0x00B1, 6, 9, editCtrl.Hwnd)
        Sleep(20)
        SendMessage(0x014F, 1, 0, langCtrl.Hwnd)
        Sleep(20)
        SendMessage(0x0100, 0x28, 0, langCtrl.Hwnd)
        Sleep(20)
        SendMessage(0x0100, 0x0D, 0, langCtrl.Hwnd)
        Sleep(60)
        if !(translateCalls == 2
            && lastTranslatedSource == "OCR"
            && editCtrl.Value == "mock:ko:OCR"
            && InStr(detailsCtrl.Value, "Selected text") > 0)
            return false

        ; Re-run local OCR on Polski (pl) without requiring translation consent; resets translation dropdown to ORIGINAL.
        TRANSLATE_CONSENT := false
        SendMessage(0x014F, 1, 0, ocrLangCtrl.Hwnd)
        Sleep(20)
        SendMessage(0x0100, 0x26, 0, ocrLangCtrl.Hwnd)
        Sleep(20)
        SendMessage(0x0100, 0x0D, 0, ocrLangCtrl.Hwnd)
        Sleep(60)
        return (reOcrCalls == 1
            && lastReOcrLang == "pl-PL"
            && ocrLangCtrl.Text == "Polski (pl)"
            && editCtrl.Value == "Mock PL pl-PL"
            && langCtrl.Text == "ORIGINAL"
            && translateCalls == 2
            && InStr(detailsCtrl.Value, "pl-PL") > 0
            && !InStr(detailsCtrl.Value, "Selected text"))
    } finally {
        if (OcrResultPopupHwnd && WinExist("ahk_id " OcrResultPopupHwnd))
            try WinClose("ahk_id " OcrResultPopupHwnd)
        OcrResultPopupHwnd := oldHwnd
        TRANSLATE_CONSENT := oldConsent
        TEXT_TRANSLATE_MAX_CHARS := oldMaxChars
        MANUAL_LANG := oldManualLang
        OCR_ENGINE := oldOcrEngine
        OCR_LANGUAGES := oldOcrLangs
    }
}

CheckOcrPopupLangMapping() {
    optsTess1 := GetOcrPopupLangOptions("pl-PL", "pol", "Tesseract")
    if (optsTess1.Length != 3 || GetOcrPopupLangIndex(optsTess1, "pol", "pl-PL", "Tesseract") != 2)
        return false

    optsTess2 := GetOcrPopupLangOptions("", "pol+eng", "Tesseract")
    if (optsTess2.Length != 3 || GetOcrPopupLangIndex(optsTess2, "pol+eng", "", "Tesseract") != 2)
        return false

    ; Missing kor in ko-KR,pl-PL,en-US yields pol+eng -> must select Polski (pl), not fallback Korean.
    optsTess3 := GetOcrPopupLangOptions("ko-KR,pl-PL,en-US", "pol+eng", "Tesseract")
    if (optsTess3.Length != 3 || GetOcrPopupLangIndex(optsTess3, "pol+eng", "ko-KR,pl-PL,en-US", "Tesseract") != 2)
        return false

    ; Distinct Chinese scripts sharing base language 'zh' must both be preserved and mapped accurately.
    optsZh := GetOcrPopupLangOptions("zh-Hans-CN,zh-Hant-TW", "chi_tra+chi_sim", "Tesseract")
    if (optsZh.Length != 5 || optsZh[4].code != "zh-Hans-CN" || optsZh[5].code != "zh-Hant-TW")
        return false
    if (GetOcrPopupLangIndex(optsZh, "chi_tra+chi_sim", "zh-Hans-CN,zh-Hant-TW", "Tesseract") != 5)
        return false

    optsCustom := GetOcrPopupLangOptions("ja-JP,en-US", "en-US", "Windows OCR")
    return (optsCustom.Length == 4
        && optsCustom[4].code == "ja-JP"
        && GetOcrPopupLangIndex(optsCustom, "en-US", "ja-JP,en-US", "Windows OCR") == 3)
}

CheckOcrAsyncEdgeCases() {
    global OcrResultPopupHwnd, OCR_EXTRACT_SEQ, OCR_ENGINE, OCR_LANGUAGES
    if !IsSet(OcrResultPopupHwnd)
        OcrResultPopupHwnd := 0
    if !IsSet(OCR_EXTRACT_SEQ)
        OCR_EXTRACT_SEQ := 0
    oldHwnd := OcrResultPopupHwnd
    oldSeq := OCR_EXTRACT_SEQ
    oldEngine := IsSet(OCR_ENGINE) ? OCR_ENGINE : "auto"
    oldLangs := IsSet(OCR_LANGUAGES) ? OCR_LANGUAGES : "ko-KR,en-US"
    OCR_ENGINE := "auto"
    OCR_LANGUAGES := "ko-KR,en-US"

    token := 0
    freshBmp := 0
    noLangBmp := 0
    tessMissingBmp := 0
    try {
        try DllCall("SetThreadDpiAwarenessContext", "ptr", -4, "ptr")
        token := Gdip_Startup()
        if !token
            return false

        OCR_EXTRACT_SEQ := 10
        staleBmp := Gdip_CreateBitmap(12, 12)
        freshBmp := Gdip_CreateBitmap(12, 12)
        noLangBmp := Gdip_CreateBitmap(12, 12)
        tessMissingBmp := Gdip_CreateBitmap(12, 12)
        if (!staleBmp || !freshBmp || !noLangBmp || !tessMissingBmp) {
            if staleBmp
                try Gdip_DisposeImage(staleBmp)
            return false
        }

        spyCalls := 0
        lastShownText := ""
        lastShownWarn := ""
        SpyShow(txt, eng, lang, warn, bmp, cfgLangs) {
            spyCalls++
            lastShownText := txt
            lastShownWarn := warn
            if (bmp == freshBmp)
                freshBmp := 0
            else if (bmp == noLangBmp)
                noLangBmp := 0
            else if (bmp == tessMissingBmp)
                tessMissingBmp := 0
            if bmp
                try Gdip_DisposeImage(bmp)
        }

        if ApplyClipOcrExtractionResult(9, { ok: true, engine: "RapidOCR", language: "ko", text: "stale", error: "" }, "ko-KR", staleBmp, SpyShow)
            return false
        if (spyCalls != 0)
            return false

        if !ApplyClipOcrExtractionResult(10, { ok: true, engine: "Windows OCR", language: "pl", text: "fresh", error: "" }, "pl-PL", freshBmp, SpyShow)
            return false
        if (spyCalls != 1 || lastShownText != "fresh")
            return false

        if !ApplyClipOcrExtractionResult(10, { ok: false, engine: "RapidOCR", language: "ko-KR", text: "", error: "NO_LANGUAGE: RapidOCR model for requested language is not installed.", noText: false }, "ko-KR,en-US", noLangBmp, SpyShow)
            return false
        if (spyCalls != 2 || lastShownText != "" || !InStr(lastShownWarn, "Selected OCR language unavailable"))
            return false

        if !ApplyClipOcrExtractionResult(10, { ok: false, engine: "Tesseract", language: "", text: "", error: "Requested Tesseract language data is missing.", noText: false }, "ko-KR,en-US", tessMissingBmp, SpyShow)
            return false
        if (spyCalls != 3 || lastShownText != "" || !InStr(lastShownWarn, "Selected OCR language unavailable"))
            return false

        liveBmp := Gdip_CreateBitmap(20, 10)
        if !liveBmp
            return false
        midFlightClosed := false
        midFlightCancelFlagged := false
        CloseMidFlightReOcr(langCode, cancelToken := 0) {
            if (OcrResultPopupHwnd && WinExist("ahk_id " OcrResultPopupHwnd)) {
                WinClose("ahk_id " OcrResultPopupHwnd)
                midFlightClosed := true
            }
            if (IsObject(cancelToken) && cancelToken.HasProp("cancelled") && cancelToken.cancelled)
                midFlightCancelFlagged := true
            return { ok: true, engine: "Windows OCR", language: langCode, text: "late", error: "" }
        }
        ShowOcrResultPopup("init", "RapidOCR", "ko", "", 0, liveBmp, CloseMidFlightReOcr, "ko-KR,en-US")
        popupId := OcrResultPopupHwnd
        if (!popupId || !WinExist("ahk_id " popupId))
            return false

        g := GuiFromHwnd(popupId)
        ocrLangCtrl := 0
        for ctrl in g {
            if (ctrl.Type == "DDL") {
                ocrLangCtrl := ctrl
                break
            }
        }
        if !IsObject(ocrLangCtrl)
            return false

        SendMessage(0x014F, 1, 0, ocrLangCtrl.Hwnd)
        Sleep(20)
        SendMessage(0x0100, 0x28, 0, ocrLangCtrl.Hwnd)
        Sleep(20)
        SendMessage(0x0100, 0x0D, 0, ocrLangCtrl.Hwnd)
        Sleep(80)
        return midFlightClosed && midFlightCancelFlagged && (!OcrResultPopupHwnd || !WinExist("ahk_id " popupId))
    } finally {
        if (OcrResultPopupHwnd && WinExist("ahk_id " OcrResultPopupHwnd))
            try WinClose("ahk_id " OcrResultPopupHwnd)
        if freshBmp
            try Gdip_DisposeImage(freshBmp)
        if noLangBmp
            try Gdip_DisposeImage(noLangBmp)
        if tessMissingBmp
            try Gdip_DisposeImage(tessMissingBmp)
        if token
            try Gdip_Shutdown(token)
        OcrResultPopupHwnd := oldHwnd
        OCR_EXTRACT_SEQ := oldSeq
        OCR_ENGINE := oldEngine
        OCR_LANGUAGES := oldLangs
    }
}

CheckOcrLazyInputIsolation() {
    global ACTIVE_OCR_JOBS
    rawCalls := 0
    procCalls := 0
    tiffCalls := 0
    FailRaw(*) {
        rawCalls++
        throw Error("raw prep failed")
    }
    FailProc(*) {
        procCalls++
        throw Error("proc prep failed")
    }
    MockTiff(*) {
        tiffCalls++
        return "C:\nonexistent\sample_multipage.tif"
    }
    provider := { GetRawPath: FailRaw, GetProcessedPath: FailProc, GetTesseractPath: MockTiff }

    preCancelled := { cancelled: true }
    cancelledRes := RunLocalOcr(provider, "auto", "ko-KR", "", preCancelled)
    if (cancelledRes.ok || !cancelledRes.HasProp("cancelled") || !cancelledRes.cancelled || rawCalls != 0 || procCalls != 0)
        return false

    if (ResolveOcrInputPath(provider, "", "tesseract") != "C:\nonexistent\sample_multipage.tif"
        || tiffCalls != 1 || rawCalls != 0 || procCalls != 0)
        return false

    winOnly := RunLocalOcr(provider, "windows", "ko-KR")
    if (winOnly.ok || rawCalls != 0 || procCalls != 1 || !InStr(winOnly.error, "proc prep failed"))
        return false

    rawCalls := 0
    procCalls := 0
    autoUnknown := RunLocalOcr(provider, "auto", "xx-XX")
    if (autoUnknown.ok || rawCalls != 0 || procCalls < 1 || !InStr(autoUnknown.error, "proc prep failed"))
        return false

    jobExit := 0
    RunOcrProcessHidden(A_ComSpec " /c exit 42", &jobExit)
    if (jobExit != 42 || ACTIVE_OCR_JOBS.Count != 0)
        return false

    timedOut := false
    try {
        RunOcrProcessHidden(A_WinDir "\System32\PING.EXE -n 6 127.0.0.1", &jobExit, 200)
    } catch as e {
        timedOut := InStr(e.Message, "timed out") > 0
    }
    if (!timedOut || ACTIVE_OCR_JOBS.Count != 0)
        return false

    asyncCancel := { cancelled: false }
    cancelledMidFlight := false
    SetTimer(() => (asyncCancel.cancelled := true), -100)
    try {
        RunOcrProcessHidden(A_WinDir "\System32\PING.EXE -n 6 127.0.0.1", &jobExit, 5000, asyncCancel)
    } catch as e {
        cancelledMidFlight := InStr(e.Message, "OCR cancelled") > 0
    }
    if (!cancelledMidFlight || ACTIVE_OCR_JOBS.Count != 0)
        return false

    tmpRoot := A_Temp "\clipocr_hc_rapid_" A_TickCount "_" DllCall("GetCurrentProcessId")
    try {
        dirLatin := tmpRoot "\latin"
        dirKo := tmpRoot "\korean"
        DirCreate(dirLatin "\python")
        DirCreate(dirLatin "\models")
        DirCreate(dirKo "\python")
        DirCreate(dirKo "\models")
        FileAppend("", dirLatin "\python\python.exe")
        FileAppend("", dirLatin "\models\ch_PP-OCRv5_det_mobile.onnx")
        FileAppend("", dirLatin "\models\latin_PP-OCRv5_rec_mobile.onnx")
        FileAppend("", dirKo "\python\python.exe")
        FileAppend("", dirKo "\models\ch_PP-OCRv5_det_mobile.onnx")
        FileAppend("", dirKo "\models\korean_PP-OCRv5_rec_mobile.onnx")

        koFirst := FindPortableRapidOcr("ko-KR,en-US", [dirLatin, dirKo])
        plFirst := FindPortableRapidOcr("pl-PL,ko-KR", [dirLatin, dirKo])
        if (!IsObject(koFirst) || koFirst.root != dirKo || !IsObject(plFirst) || plFirst.root != dirLatin)
            return false
    } finally {
        try DirDelete(tmpRoot, true)
    }
    return true
}

CheckOcrInputPreprocessing() {
    token := 0
    bitmaps := []
    graphicsList := []
    brushes := []
    TrackBmp(bmp) {
        if bmp
            bitmaps.Push(bmp)
        return bmp
    }
    TrackGfx(gfx) {
        if gfx
            graphicsList.Push(gfx)
        return gfx
    }
    TrackBrush(brush) {
        if brush
            brushes.Push(brush)
        return brush
    }
    try {
        token := Gdip_Startup()
        if !token
            return false

        bmp1 := TrackBmp(Gdip_CreateBitmap(200, 60))
        g1 := TrackGfx(Gdip_GraphicsFromImage(bmp1))
        if (!bmp1 || !g1)
            return false
        Gdip_SetCompositingMode(g1, 1)
        Gdip_GraphicsClear(g1, 0xFF1E1E1E)
        edge1 := 0
        if (!DetectOcrUniformEdgeColor(bmp1, &edge1) || edge1 != 0xFF1E1E1E)
            return false
        out1 := TrackBmp(CreateOcrInputBitmap(bmp1, 2600))
        if (!out1 || Gdip_GetImageWidth(out1) != 440 || Gdip_GetImageHeight(out1) != 160
            || Gdip_GetPixel(out1, 0, 0) != 0xFF1E1E1E || Gdip_GetPixel(out1, 220, 80) != 0xFF1E1E1E)
            return false
        raw1 := TrackBmp(CreateOcrRawBitmap(bmp1, 2600))
        if (!raw1 || raw1 == bmp1 || Gdip_GetImageWidth(raw1) != 200 || Gdip_GetImageHeight(raw1) != 60
            || Gdip_GetPixel(raw1, 0, 0) != 0xFF1E1E1E)
            return false

        bmp2 := TrackBmp(Gdip_CreateBitmap(200, 60))
        g2 := TrackGfx(Gdip_GraphicsFromImage(bmp2))
        bBlack := TrackBrush(Gdip_BrushCreateSolid(0xFF000000))
        bWhite := TrackBrush(Gdip_BrushCreateSolid(0xFFFFFFFF))
        if (!bmp2 || !g2 || !bBlack || !bWhite)
            return false
        Gdip_SetCompositingMode(g2, 1)
        Gdip_FillRectangle(g2, bBlack, 0, 0, 100, 60)
        Gdip_FillRectangle(g2, bWhite, 100, 0, 100, 60)
        edge2 := 0
        if DetectOcrUniformEdgeColor(bmp2, &edge2)
            return false
        out2 := TrackBmp(CreateOcrInputBitmap(bmp2, 2600))
        if (!out2 || Gdip_GetImageWidth(out2) != 400 || Gdip_GetImageHeight(out2) != 120
            || Gdip_GetPixel(out2, 0, 60) != 0xFF000000 || Gdip_GetPixel(out2, 399, 60) != 0xFFFFFFFF)
            return false
        r199 := (Gdip_GetPixel(out2, 199, 60) >> 16) & 0xFF
        r200 := (Gdip_GetPixel(out2, 200, 60) >> 16) & 0xFF
        if (r199 >= 100 || r200 <= 155 || Abs((r199 + r200) - 255) > 4)
            return false

        bmp3 := TrackBmp(Gdip_CreateBitmap(1000, 800))
        g3 := TrackGfx(Gdip_GraphicsFromImage(bmp3))
        if (!bmp3 || !g3)
            return false
        Gdip_SetCompositingMode(g3, 1)
        Gdip_GraphicsClear(g3, 0xFFFFFFFF)
        out3 := TrackBmp(CreateOcrInputBitmap(bmp3, 2600))
        if (!out3 || Gdip_GetImageWidth(out3) != 1040 || Gdip_GetImageHeight(out3) != 840)
            return false

        bmp4 := TrackBmp(Gdip_CreateBitmap(100, 50))
        g4 := TrackGfx(Gdip_GraphicsFromImage(bmp4))
        if (!bmp4 || !g4)
            return false
        Gdip_SetCompositingMode(g4, 1)
        Gdip_GraphicsClear(g4, 0xFFFFFFFF)
        out4 := TrackBmp(CreateOcrInputBitmap(bmp4, 210.5))
        if (!out4 || Gdip_GetImageWidth(out4) != 210 || Gdip_GetImageHeight(out4) != 110)
            return false

        bmp5 := TrackBmp(Gdip_CreateBitmap(300, 150))
        g5 := TrackGfx(Gdip_GraphicsFromImage(bmp5))
        if (!bmp5 || !g5)
            return false
        Gdip_SetCompositingMode(g5, 1)
        Gdip_GraphicsClear(g5, 0xFFFFFFFF)
        out5 := TrackBmp(CreateOcrInputBitmap(bmp5, 100))
        if (!out5 || Gdip_GetImageWidth(out5) != 100 || Gdip_GetImageHeight(out5) != 50)
            return false
        raw5 := TrackBmp(CreateOcrRawBitmap(bmp5, 100))
        if (!raw5 || Gdip_GetImageWidth(raw5) != 100 || Gdip_GetImageHeight(raw5) != 50)
            return false

        bmp6 := TrackBmp(Gdip_CreateBitmap(40, 20))
        g6 := TrackGfx(Gdip_GraphicsFromImage(bmp6))
        if (!bmp6 || !g6)
            return false
        Gdip_SetCompositingMode(g6, 1)
        Gdip_GraphicsClear(g6, 0x00000000)
        edge6 := 0
        if DetectOcrUniformEdgeColor(bmp6, &edge6)
            return false
        out6 := TrackBmp(CreateOcrInputBitmap(bmp6, 2600))
        if (!out6 || Gdip_GetImageWidth(out6) != 80 || Gdip_GetImageHeight(out6) != 40
            || Gdip_GetPixel(out6, 0, 0) != 0 || Gdip_GetPixel(out6, 40, 20) != 0)
            return false

        bmpSemi := TrackBmp(Gdip_CreateBitmap(100, 50))
        gSemi := TrackGfx(Gdip_GraphicsFromImage(bmpSemi))
        bSemi := TrackBrush(Gdip_BrushCreateSolid(0x80000000))
        if (!bmpSemi || !gSemi || !bSemi)
            return false
        Gdip_SetCompositingMode(gSemi, 1)
        Gdip_GraphicsClear(gSemi, 0xFFFFFFFF)
        Gdip_FillRectangle(gSemi, bSemi, 25, 10, 50, 30)
        outSemi := TrackBmp(CreateOcrInputBitmap(bmpSemi, 2600))
        if (!outSemi || Gdip_GetImageWidth(outSemi) != 240 || Gdip_GetImageHeight(outSemi) != 140
            || Gdip_GetPixel(outSemi, 0, 0) != 0xFFFFFFFF || Gdip_GetPixel(outSemi, 120, 70) != 0x80000000)
            return false

        bmp7 := TrackBmp(Gdip_CreateBitmap(1000, 800))
        g7 := TrackGfx(Gdip_GraphicsFromImage(bmp7))
        if (!bmp7 || !g7)
            return false
        Gdip_SetCompositingMode(g7, 1)
        Gdip_FillRectangle(g7, bBlack, 0, 0, 500, 800)
        Gdip_FillRectangle(g7, bWhite, 500, 0, 500, 800)
        Gdip_SetPixel(bmp7, 500, 400, 0x01ABCDEF)
        edge7 := 0
        if DetectOcrUniformEdgeColor(bmp7, &edge7)
            return false
        out7 := TrackBmp(CreateOcrInputBitmap(bmp7, 2600))
        return (out7 && out7 != bmp7 && Gdip_GetImageWidth(out7) == 1000 && Gdip_GetImageHeight(out7) == 800
            && Gdip_GetPixel(out7, 0, 0) == 0xFF000000 && Gdip_GetPixel(out7, 999, 799) == 0xFFFFFFFF
            && Gdip_GetPixel(out7, 500, 400) == 0x01ABCDEF)
    } finally {
        for _, brush in brushes
            try Gdip_DeleteBrush(brush)
        for _, gfx in graphicsList
            try Gdip_DeleteGraphics(gfx)
        for _, bmp in bitmaps
            try Gdip_DisposeImage(bmp)
        if token
            try Gdip_Shutdown(token)
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
