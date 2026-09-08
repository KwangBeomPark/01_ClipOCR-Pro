; Local OCR orchestration. Windows.Media.Ocr is preferred; portable Tesseract is optional.

NormalizeOcrEngine(value) {
    normalized := StrLower(Trim(String(value)))
    return (normalized == "windows" || normalized == "tesseract") ? normalized : "auto"
}

global DEFAULT_OCR_LANGUAGES := "ko-KR,en-US"

; Accepts BCP 47 tags with script and region subtags (ko, en-US, zh-Hans-CN, sr-Cyrl), returns them
; canonically cased and de-duplicated. Returns "" when no entry is valid so callers can distinguish
; invalid input from the default instead of silently substituting it.
NormalizeOcrLanguages(value) {
    normalized := []
    seen := Map()
    for _, rawCode in StrSplit(StrReplace(String(value), ";", ","), ",") {
        code := Trim(StrReplace(rawCode, "_", "-"))
        if !RegExMatch(code, "i)^[a-z]{2,3}(?:-[a-z0-9]{2,8})*$")
            continue
        canonical := ""
        for index, part in StrSplit(code, "-") {
            if (index == 1)
                canonical := StrLower(part)
            else if (StrLen(part) == 4 && RegExMatch(part, "i)^[a-z]+$"))
                canonical .= "-" StrUpper(SubStr(part, 1, 1)) StrLower(SubStr(part, 2))
            else if (StrLen(part) == 2 || RegExMatch(part, "^\d{3}$"))
                canonical .= "-" StrUpper(part)
            else
                canonical .= "-" StrLower(part)
        }
        key := StrLower(canonical)
        if !seen.Has(key) {
            seen[key] := true
            normalized.Push(canonical)
        }
    }
    result := ""
    for index, code in normalized
        result .= (index == 1 ? "" : ",") code
    return result
}

ResolveOcrLanguages(value) {
    global DEFAULT_OCR_LANGUAGES
    normalized := NormalizeOcrLanguages(value)
    return normalized != "" ? normalized : DEFAULT_OCR_LANGUAGES
}

; Both engines return CRLF-separated lines so the result popup and clipboard see the same shape.
NormalizeOcrText(text) {
    text := StrReplace(String(text), "`r`n", "`n")
    text := StrReplace(text, "`r", "`n")
    text := StrReplace(text, "`n", "`r`n")
    return Trim(text, "`r`n `t")
}

GetOcrEngineOptions() {
    return [{ label: "Auto (Windows, then portable fallback)", value: "auto" },
        { label: "Windows OCR only", value: "windows" },
        { label: "Portable Tesseract only", value: "tesseract" }]
}

GetOcrEngineLabels() {
    labels := []
    for _, option in GetOcrEngineOptions()
        labels.Push(option.label)
    return labels
}

GetOcrEngineIndex(value) {
    value := NormalizeOcrEngine(value)
    for index, option in GetOcrEngineOptions() {
        if (option.value == value)
            return index
    }
    return 1
}

GetOcrEngineByLabel(label) {
    for _, option in GetOcrEngineOptions() {
        if (option.label == label)
            return option.value
    }
    return "auto"
}

QuoteOcrArgument(value) {
    value := String(value)
    if InStr(value, '"')
        throw Error("OCR path contains an unsupported quote character.")
    return '"' value '"'
}

ReadOcrStatus(statusPath) {
    if !FileExist(statusPath)
        return { ok: false, code: "NO_STATUS", message: "OCR helper returned no status." }
    status := Trim(FileRead(statusPath, "UTF-8"))
    parts := StrSplit(status, "|", , 3)
    if (parts.Length < 2)
        return { ok: false, code: "BAD_STATUS", message: status }
    message := parts.Length >= 3 ? parts[3] : ""
    return { ok: parts[1] == "OK", code: parts[2], message: message }
}

RunWindowsOcr(imagePath, languages) {
    global APP_TEMP_DIR
    if !DirExist(APP_TEMP_DIR)
        DirCreate(APP_TEMP_DIR)
    helperPath := PrepareWindowsOcrHelper()
    if (helperPath == "")
        return { ok: false, engine: "Windows OCR", language: "", text: "", error: "Windows OCR helper is unavailable." }

    id := DllCall("GetCurrentProcessId") "_" A_TickCount
    outputPath := APP_TEMP_DIR "\ocr_windows_" id ".txt"
    statusPath := APP_TEMP_DIR "\ocr_windows_" id ".status"
    powershellPath := A_WinDir "\System32\WindowsPowerShell\v1.0\powershell.exe"
    command := QuoteOcrArgument(powershellPath)
        . " -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File " QuoteOcrArgument(helperPath)
        . " -ImagePath " QuoteOcrArgument(imagePath)
        . " -Languages " QuoteOcrArgument(languages)
        . " -OutputPath " QuoteOcrArgument(outputPath)
        . " -StatusPath " QuoteOcrArgument(statusPath)
    try {
        RunWait(command, , "Hide")
        status := ReadOcrStatus(statusPath)
        if !status.ok
            return { ok: false, engine: "Windows OCR", language: "", text: "", error: status.code ": " status.message }
        text := FileExist(outputPath) ? NormalizeOcrText(FileRead(outputPath, "UTF-8")) : ""
        return { ok: true, engine: "Windows OCR", language: status.code, text: text, error: "" }
    } catch as e {
        return { ok: false, engine: "Windows OCR", language: "", text: "", error: ShortErrorMessage(e.Message) }
    } finally {
        try FileDelete(outputPath)
        try FileDelete(statusPath)
    }
}

FindPortableTesseract() {
    candidates := []
    try {
        configuredDir := Trim(EnvGet("CLIPOCR_TESSERACT_DIR"))
        if (configuredDir != "")
            candidates.Push(configuredDir)
    }
    candidates.Push(A_ScriptDir "\ocr")
    if !A_IsCompiled
        candidates.Push(A_ScriptDir "\..\tools\tesseract")
    candidates.Push("C:\Program Files\Tesseract-OCR")

    for _, root in candidates {
        root := RTrim(Suite_ExpandEnvironment(root), "\/")
        executable := root "\tesseract.exe"
        tessdata := root "\tessdata"
        if (FileExist(executable) && DirExist(tessdata))
            return { executable: executable, tessdata: tessdata }
    }
    return 0
}

; Maps a BCP 47 tag to the tessdata file name. Windows supplies the ISO 639-2/T code for any
; two-letter language it knows (GetLocaleInfoEx), which is what tessdata uses; the map holds only
; the exceptions (Norwegian data is "nor"), Chinese is split by script rather than language, and
; anything else (three-letter codes) passes through unchanged.
GetTesseractLanguageCode(language) {
    static tessdataExceptions := Map("nb", "nor", "nn", "nor", "no", "nor")
    parts := StrSplit(StrLower(Trim(String(language))), "-")
    baseLanguage := parts[1]
    if (baseLanguage == "zh") {
        ; An explicit script subtag wins over the region (zh-Hans-HK is Simplified).
        script := ""
        traditionalRegion := false
        for index, part in parts {
            if (index == 1)
                continue
            if (part == "hans" || part == "hant")
                script := part
            else if (part == "tw" || part == "hk" || part == "mo")
                traditionalRegion := true
        }
        if (script == "hans")
            return "chi_sim"
        return (script == "hant" || traditionalRegion) ? "chi_tra" : "chi_sim"
    }
    if tessdataExceptions.Has(baseLanguage)
        return tessdataExceptions[baseLanguage]
    if (StrLen(baseLanguage) == 2) {
        ; Windows knows the ISO 639-2 code for every two-letter language it supports (fa -> fas).
        iso3 := GetIso639LanguageCode(baseLanguage)
        if (iso3 != "")
            return iso3
    }
    return baseLanguage
}

GetIso639LanguageCode(baseLanguage) {
    static LOCALE_SISO639LANGNAME2 := 0x67
    nameBuffer := Buffer(9 * 2, 0)
    length := DllCall("GetLocaleInfoEx", "WStr", baseLanguage, "UInt", LOCALE_SISO639LANGNAME2, "Ptr", nameBuffer, "Int", 9, "Int")
    code := length > 1 ? StrLower(StrGet(nameBuffer, "UTF-16")) : ""
    ; Windows echoes names it does not recognize (or reports "zzz"); only a real three-letter code counts.
    return (StrLen(code) == 3 && code != "zzz") ? code : ""
}

ResolveTesseractLanguages(languages, tessdataPath) {
    codes := []
    missing := []
    seen := Map()
    for _, language in StrSplit(ResolveOcrLanguages(languages), ",") {
        code := GetTesseractLanguageCode(language)
        if seen.Has(code)
            continue
        seen[code] := true
        if FileExist(tessdataPath "\" code ".traineddata")
            codes.Push(code)
        else
            missing.Push(code)
    }
    joined := ""
    for index, code in codes
        joined .= (index == 1 ? "" : "+") code
    return { value: joined, missing: missing }
}

RunTesseractOcr(imagePath, languages) {
    global APP_TEMP_DIR
    if !DirExist(APP_TEMP_DIR)
        DirCreate(APP_TEMP_DIR)
    installation := FindPortableTesseract()
    if !IsObject(installation)
        return { ok: false, engine: "Tesseract", language: "", text: "", error: "Portable Tesseract is not installed." }

    resolvedLanguages := ResolveTesseractLanguages(languages, installation.tessdata)
    if (resolvedLanguages.value == "")
        return { ok: false, engine: "Tesseract", language: "", text: "", error: "Requested Tesseract language data is missing." }

    id := DllCall("GetCurrentProcessId") "_" A_TickCount
    outputBase := APP_TEMP_DIR "\ocr_tesseract_" id
    outputPath := outputBase ".txt"
    command := QuoteOcrArgument(installation.executable) " " QuoteOcrArgument(imagePath) " " QuoteOcrArgument(outputBase)
        . " -l " resolvedLanguages.value " --tessdata-dir " QuoteOcrArgument(installation.tessdata) " --psm 6"
    try {
        exitCode := RunWait(command, , "Hide")
        if (exitCode != 0 || !FileExist(outputPath))
            return { ok: false, engine: "Tesseract", language: resolvedLanguages.value, text: "", error: "Tesseract exited with code " exitCode "." }
        text := NormalizeOcrText(FileRead(outputPath, "UTF-8"))
        warning := resolvedLanguages.missing.Length > 0 ? "Some requested language data was unavailable." : ""
        return { ok: true, engine: "Tesseract", language: resolvedLanguages.value, text: text, error: warning }
    } catch as e {
        return { ok: false, engine: "Tesseract", language: resolvedLanguages.value, text: "", error: ShortErrorMessage(e.Message) }
    } finally {
        try FileDelete(outputPath)
    }
}

JoinOcrErrors(errors) {
    text := ""
    for _, message in errors {
        if (message != "")
            text .= (text == "" ? "" : " | ") message
    }
    return text
}

GetOcrUserFailureMessage(error) {
    error := ShortErrorMessage(error, 180)
    if (InStr(error, "NO_LANGUAGE") || InStr(error, "Portable Tesseract is not installed")
        || InStr(error, "language data is missing")) {
        return "⚠️ 사용할 수 있는 로컬 OCR 언어가 없습니다.`r`n"
            . "Windows OCR 언어를 설치하거나 회사용 Full 패키지(kor+eng)를 사용하세요.`r`n"
            . "No matching OCR language is available. Install a Windows OCR language or use the Full package."
    }
    return "⚠️ 로컬 OCR 실패 / Local OCR failed: " error
}

RunLocalOcr(imagePath, engine, languages) {
    engine := NormalizeOcrEngine(engine)
    languages := ResolveOcrLanguages(languages)
    errors := []

    if (engine == "windows") {
        result := RunWindowsOcr(imagePath, languages)
        if (result.ok && result.text != "")
            return result
        return { ok: false, engine: result.engine, language: result.language, text: "",
            error: result.ok ? "No text was detected." : result.error }
    }
    if (engine == "tesseract") {
        result := RunTesseractOcr(imagePath, languages)
        if (result.ok && result.text != "")
            return result
        return { ok: false, engine: result.engine, language: result.language, text: "",
            error: result.ok ? "No text was detected." : result.error }
    }

    languageList := StrSplit(languages, ",")
    primaryLanguage := languageList[1]
    result := RunWindowsOcr(imagePath, primaryLanguage)
    if (result.ok && result.text != "")
        return result
    errors.Push(result.ok ? "Windows OCR detected no text." : result.error)

    result := RunTesseractOcr(imagePath, languages)
    if (result.ok && result.text != "")
        return result
    errors.Push(result.ok ? "Tesseract detected no text." : result.error)

    if (languageList.Length > 1) {
        fallbackLanguages := ""
        loop languageList.Length - 1
            fallbackLanguages .= (A_Index == 1 ? "" : ",") languageList[A_Index + 1]
        result := RunWindowsOcr(imagePath, fallbackLanguages)
        if (result.ok && result.text != "")
            return result
        errors.Push(result.ok ? "Windows fallback detected no text." : result.error)
    }

    return { ok: false, engine: "Local OCR", language: "", text: "", error: JoinOcrErrors(errors) }
}
