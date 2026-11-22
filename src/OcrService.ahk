; Local OCR orchestration. Supports offline RapidOCR (PP-OCRv5), Windows.Media.Ocr, and optional portable Tesseract.

NormalizeOcrEngine(value) {
    normalized := StrLower(Trim(String(value)))
    return (normalized == "windows" || normalized == "tesseract" || normalized == "rapidocr") ? normalized : "auto"
}

GetBaseOcrLanguage(language) {
    parts := StrSplit(StrLower(Trim(String(language))), "-")
    return parts.Length > 0 ? parts[1] : ""
}

global DEFAULT_OCR_LANGUAGES := "ko-KR,en-US"
global ACTIVE_OCR_JOBS := Map()
global ACTIVE_OCR_TEMP_FILES := Map()

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
    return [{ label: "Auto (RapidOCR ko, Windows others)", value: "auto" },
        { label: "RapidOCR only (PP-OCRv5 local)", value: "rapidocr" },
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

NextOcrTempId() {
    static ocrRunSeq := 0
    ocrRunSeq++
    return DllCall("GetCurrentProcessId") "_" A_TickCount "_" ocrRunSeq
}

RegisterOcrTempFile(path) {
    global ACTIVE_OCR_TEMP_FILES
    if (path != "")
        ACTIVE_OCR_TEMP_FILES[path] := true
}

DeleteOcrTempFile(path) {
    global ACTIVE_OCR_TEMP_FILES
    if (path == "")
        return
    try FileDelete(path)
    if !FileExist(path) {
        try ACTIVE_OCR_TEMP_FILES.Delete(path)
    }
}

IsOcrCancelled(cancelState) {
    return IsObject(cancelState) && cancelState.HasProp("cancelled") && cancelState.cancelled
}

RunOcrProcessHidden(command, &exitCode := 0, timeoutMs := 30000, cancelState := 0) {
    global ACTIVE_OCR_JOBS
    static jobSeq := 0
    static CREATE_SUSPENDED_NO_WINDOW := 0x08000004
    static JOB_LIMIT_KILL_ON_CLOSE := 0x2000

    if IsOcrCancelled(cancelState)
        throw Error("OCR cancelled.")

    hJob := DllCall("CreateJobObjectW", "Ptr", 0, "Ptr", 0, "Ptr")
    if !hJob
        throw Error("Could not create OCR process job: " A_LastError)
    jobInfo := Buffer(A_PtrSize == 8 ? 144 : 112, 0)
    NumPut("UInt", JOB_LIMIT_KILL_ON_CLOSE, jobInfo, 16)
    if !DllCall("SetInformationJobObject", "Ptr", hJob, "Int", 9, "Ptr", jobInfo.Ptr, "UInt", jobInfo.Size, "Int") {
        lastErr := A_LastError
        DllCall("CloseHandle", "Ptr", hJob)
        throw Error("Could not configure OCR process job: " lastErr)
    }

    si := Buffer(A_PtrSize == 8 ? 104 : 68, 0)
    NumPut("UInt", si.Size, si, 0)
    pi := Buffer(A_PtrSize == 8 ? 24 : 16, 0)
    cmdBuf := Buffer((StrLen(command) + 1) * 2, 0)
    StrPut(command, cmdBuf, "UTF-16")
    hProc := 0
    hThread := 0
    jobKey := ""
    try {
        if !DllCall("CreateProcessW", "Ptr", 0, "Ptr", cmdBuf.Ptr, "Ptr", 0, "Ptr", 0, "Int", false,
            "UInt", CREATE_SUSPENDED_NO_WINDOW, "Ptr", 0, "Ptr", 0, "Ptr", si.Ptr, "Ptr", pi.Ptr, "Int")
            throw Error("Could not start OCR helper process: " A_LastError)
        hProc := NumGet(pi, 0, "Ptr")
        hThread := NumGet(pi, A_PtrSize, "Ptr")
        jobKey := "job_" (++jobSeq)
        ACTIVE_OCR_JOBS[jobKey] := { job: hJob, proc: hProc }

        if !DllCall("AssignProcessToJobObject", "Ptr", hJob, "Ptr", hProc, "Int") {
            lastErr := A_LastError
            try DllCall("TerminateProcess", "Ptr", hProc, "UInt", 1)
            throw Error("Could not assign OCR helper to job: " lastErr)
        }
        if (DllCall("ResumeThread", "Ptr", hThread, "UInt") == 0xFFFFFFFF) {
            lastErr := A_LastError
            try DllCall("TerminateJobObject", "Ptr", hJob, "UInt", 1)
            throw Error("Could not resume OCR helper process: " lastErr)
        }
        DllCall("CloseHandle", "Ptr", hThread)
        hThread := 0

        startTick := DllCall("GetTickCount64", "Int64")
        while ((waitState := DllCall("WaitForSingleObject", "Ptr", hProc, "UInt", 0, "UInt")) == 258) {
            if IsOcrCancelled(cancelState) {
                try DllCall("TerminateJobObject", "Ptr", hJob, "UInt", 1)
                try DllCall("WaitForSingleObject", "Ptr", hProc, "UInt", 2000)
                throw Error("OCR cancelled.")
            }
            if (timeoutMs > 0 && (DllCall("GetTickCount64", "Int64") - startTick) >= timeoutMs) {
                try DllCall("TerminateJobObject", "Ptr", hJob, "UInt", 1)
                try DllCall("WaitForSingleObject", "Ptr", hProc, "UInt", 2000)
                throw Error("OCR helper timed out.")
            }
            Sleep(15)
        }
        if (waitState != 0)
            throw Error("OCR helper wait failed: " waitState)

        code := 0
        if !DllCall("GetExitCodeProcess", "Ptr", hProc, "UInt*", &code)
            throw Error("Could not query OCR helper exit code: " A_LastError)
        exitCode := code
        return true
    } finally {
        if hThread
            try DllCall("CloseHandle", "Ptr", hThread)
        if (jobKey != "" && ACTIVE_OCR_JOBS.Has(jobKey))
            try ACTIVE_OCR_JOBS.Delete(jobKey)
        if hProc
            try DllCall("CloseHandle", "Ptr", hProc)
        if hJob
            try DllCall("CloseHandle", "Ptr", hJob)
    }
}

CleanupActiveOcrResources() {
    global ACTIVE_OCR_JOBS, ACTIVE_OCR_TEMP_FILES
    if IsSet(ACTIVE_OCR_JOBS) {
        for jobKey, entry in ACTIVE_OCR_JOBS.Clone() {
            try ACTIVE_OCR_JOBS.Delete(jobKey)
            if entry.job
                try DllCall("TerminateJobObject", "Ptr", entry.job, "UInt", 1)
            if entry.proc
                try DllCall("WaitForSingleObject", "Ptr", entry.proc, "UInt", 2000)
        }
    }
    if IsSet(ACTIVE_OCR_TEMP_FILES) {
        for filePath, _ in ACTIVE_OCR_TEMP_FILES.Clone()
            DeleteOcrTempFile(filePath)
    }
}

ResolveOcrInputPath(imageInput, rawImagePath := "", mode := "processed") {
    if (mode == true)
        mode := "raw"
    else if (mode == false)
        mode := "processed"
    if IsObject(imageInput) {
        if (mode == "raw")
            return imageInput.GetRawPath()
        if (mode == "tesseract")
            return imageInput.HasProp("GetTesseractPath") ? imageInput.GetTesseractPath() : imageInput.GetProcessedPath()
        return imageInput.GetProcessedPath()
    }
    return (mode == "raw" && rawImagePath != "") ? rawImagePath : String(imageInput)
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

FindPortableRapidOcr(languages := "", customCandidates := 0) {
    candidates := []
    if IsObject(customCandidates) {
        candidates := customCandidates
    } else {
        try {
            configuredDir := Trim(EnvGet("CLIPOCR_RAPIDOCR_DIR"))
            if (configuredDir != "")
                candidates.Push(configuredDir)
        }
        candidates.Push(A_ScriptDir "\ocr\rapidocr")
        if !A_IsCompiled
            candidates.Push(A_ScriptDir "\..\tools\rapidocr")
    }

    validInstallations := []
    for _, root in candidates {
        root := RTrim(Suite_ExpandEnvironment(root), "\/")
        if (root == "")
            continue
        pythonExe := ""
        for _, pyRel in ["\python\python.exe", "\.venv\Scripts\python.exe"] {
            candidatePy := root pyRel
            if FileExist(candidatePy) {
                pythonExe := candidatePy
                break
            }
        }
        modelsDir := root "\models"
        if (pythonExe != "" && DirExist(modelsDir)
            && FileExist(modelsDir "\ch_PP-OCRv5_det_mobile.onnx")
            && (FileExist(modelsDir "\korean_PP-OCRv5_rec_mobile.onnx")
                || FileExist(modelsDir "\latin_PP-OCRv5_rec_mobile.onnx"))) {
            validInstallations.Push({ python: pythonExe, modelsDir: modelsDir, root: root })
        }
    }

    if (validInstallations.Length == 0)
        return 0
    if (languages == "")
        return validInstallations[1]

    for _, language in StrSplit(ResolveOcrLanguages(languages), ",") {
        for _, inst in validInstallations {
            if HasRapidOcrModelForLanguages(inst.modelsDir, language)
                return inst
        }
    }
    return 0
}

HasRapidOcrModelForLanguages(modelsDir, languages) {
    static latinBases := ",en,pl,de,fr,es,it,pt,nl,cs,sk,hu,ro,tr,vi,id,ms,sv,da,no,nb,nn,fi,hr,sl,lt,lv,et,"
    if !FileExist(modelsDir "\ch_PP-OCRv5_det_mobile.onnx")
        return false
    hasKorean := FileExist(modelsDir "\korean_PP-OCRv5_rec_mobile.onnx") != ""
    hasLatin := FileExist(modelsDir "\latin_PP-OCRv5_rec_mobile.onnx") != ""
    for _, language in StrSplit(ResolveOcrLanguages(languages), ",") {
        baseLang := GetBaseOcrLanguage(language)
        if (baseLang == "ko" && hasKorean)
            return true
        if (baseLang != "" && InStr(latinBases, "," baseLang ",") && hasLatin)
            return true
    }
    return false
}

RunRapidOcr(imagePath, languages, rawImagePath := "", cancelState := 0) {
    global APP_TEMP_DIR
    if IsOcrCancelled(cancelState)
        return { ok: false, engine: "RapidOCR", language: "", text: "", error: "OCR cancelled.", cancelled: true }
    installation := FindPortableRapidOcr(languages)
    if !IsObject(installation) {
        if IsObject(FindPortableRapidOcr(""))
            return { ok: false, engine: "RapidOCR", language: "", text: "", error: "NO_LANGUAGE: RapidOCR model for requested language is not installed." }
        return { ok: false, engine: "RapidOCR", language: "", text: "", error: "Portable RapidOCR is not installed." }
    }
    helperPath := PrepareRapidOcrHelper()
    if (helperPath == "")
        return { ok: false, engine: "RapidOCR", language: "", text: "", error: "RapidOCR helper is unavailable." }

    outputPath := ""
    statusPath := ""
    try {
        if !DirExist(APP_TEMP_DIR)
            DirCreate(APP_TEMP_DIR)
        resolvedImagePath := ResolveOcrInputPath(imagePath, rawImagePath, "raw")
        id := NextOcrTempId()
        outputPath := APP_TEMP_DIR "\ocr_rapid_" id ".txt"
        statusPath := APP_TEMP_DIR "\ocr_rapid_" id ".status"
        RegisterOcrTempFile(outputPath)
        RegisterOcrTempFile(statusPath)
        command := QuoteOcrArgument(installation.python) " -I -X utf8 " QuoteOcrArgument(helperPath)
            . " --image " QuoteOcrArgument(resolvedImagePath)
            . " --lang " QuoteOcrArgument(languages)
            . " --models-dir " QuoteOcrArgument(installation.modelsDir)
            . " --output " QuoteOcrArgument(outputPath)
            . " --status " QuoteOcrArgument(statusPath)
        rapidExit := 0
        RunOcrProcessHidden(command, &rapidExit, 30000, cancelState)
        status := ReadOcrStatus(statusPath)
        if !status.ok
            return { ok: false, engine: "RapidOCR", language: "", text: "", error: status.code ": " status.message }
        text := FileExist(outputPath) ? NormalizeOcrText(FileRead(outputPath, "UTF-8")) : ""
        return { ok: true, engine: "RapidOCR", language: status.code, text: text, error: "" }
    } catch as e {
        if IsOcrCancelled(cancelState)
            return { ok: false, engine: "RapidOCR", language: "", text: "", error: "OCR cancelled.", cancelled: true }
        return { ok: false, engine: "RapidOCR", language: "", text: "", error: ShortErrorMessage(e.Message) }
    } finally {
        DeleteOcrTempFile(outputPath)
        DeleteOcrTempFile(statusPath)
    }
}

RunWindowsOcr(imagePath, languages, cancelState := 0) {
    global APP_TEMP_DIR
    if IsOcrCancelled(cancelState)
        return { ok: false, engine: "Windows OCR", language: "", text: "", error: "OCR cancelled.", cancelled: true }
    helperPath := PrepareWindowsOcrHelper()
    if (helperPath == "")
        return { ok: false, engine: "Windows OCR", language: "", text: "", error: "Windows OCR helper is unavailable." }

    outputPath := ""
    statusPath := ""
    try {
        if !DirExist(APP_TEMP_DIR)
            DirCreate(APP_TEMP_DIR)
        resolvedImagePath := ResolveOcrInputPath(imagePath, "", "processed")
        id := NextOcrTempId()
        outputPath := APP_TEMP_DIR "\ocr_windows_" id ".txt"
        statusPath := APP_TEMP_DIR "\ocr_windows_" id ".status"
        RegisterOcrTempFile(outputPath)
        RegisterOcrTempFile(statusPath)
        powershellPath := A_WinDir "\System32\WindowsPowerShell\v1.0\powershell.exe"
        command := QuoteOcrArgument(powershellPath)
            . " -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File " QuoteOcrArgument(helperPath)
            . " -ImagePath " QuoteOcrArgument(resolvedImagePath)
            . " -Languages " QuoteOcrArgument(languages)
            . " -OutputPath " QuoteOcrArgument(outputPath)
            . " -StatusPath " QuoteOcrArgument(statusPath)
        winExit := 0
        RunOcrProcessHidden(command, &winExit, 30000, cancelState)
        status := ReadOcrStatus(statusPath)
        if !status.ok
            return { ok: false, engine: "Windows OCR", language: "", text: "", error: status.code ": " status.message }
        text := FileExist(outputPath) ? NormalizeOcrText(FileRead(outputPath, "UTF-8")) : ""
        return { ok: true, engine: "Windows OCR", language: status.code, text: text, error: "" }
    } catch as e {
        if IsOcrCancelled(cancelState)
            return { ok: false, engine: "Windows OCR", language: "", text: "", error: "OCR cancelled.", cancelled: true }
        return { ok: false, engine: "Windows OCR", language: "", text: "", error: ShortErrorMessage(e.Message) }
    } finally {
        DeleteOcrTempFile(outputPath)
        DeleteOcrTempFile(statusPath)
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

RunTesseractOcr(imagePath, languages, cancelState := 0) {
    global APP_TEMP_DIR
    if IsOcrCancelled(cancelState)
        return { ok: false, engine: "Tesseract", language: "", text: "", error: "OCR cancelled.", cancelled: true }
    installation := FindPortableTesseract()
    if !IsObject(installation)
        return { ok: false, engine: "Tesseract", language: "", text: "", error: "Portable Tesseract is not installed." }

    resolvedLanguages := ResolveTesseractLanguages(languages, installation.tessdata)
    if (resolvedLanguages.value == "")
        return { ok: false, engine: "Tesseract", language: "", text: "", error: "Requested Tesseract language data is missing." }

    outputPath := ""
    try {
        if !DirExist(APP_TEMP_DIR)
            DirCreate(APP_TEMP_DIR)
        resolvedImagePath := ResolveOcrInputPath(imagePath, "", "tesseract")
        id := NextOcrTempId()
        outputBase := APP_TEMP_DIR "\ocr_tesseract_" id
        outputPath := outputBase ".txt"
        RegisterOcrTempFile(outputPath)
        command := QuoteOcrArgument(installation.executable) " " QuoteOcrArgument(resolvedImagePath) " " QuoteOcrArgument(outputBase)
            . " -l " resolvedLanguages.value " --tessdata-dir " QuoteOcrArgument(installation.tessdata) " --psm 6"
        exitCode := 0
        RunOcrProcessHidden(command, &exitCode, 30000, cancelState)
        if (exitCode != 0 || !FileExist(outputPath))
            return { ok: false, engine: "Tesseract", language: resolvedLanguages.value, text: "", error: "Tesseract exited with code " exitCode "." }
        text := NormalizeOcrText(FileRead(outputPath, "UTF-8"))
        warning := resolvedLanguages.missing.Length > 0 ? "Some requested language data was unavailable." : ""
        return { ok: true, engine: "Tesseract", language: resolvedLanguages.value, text: text, error: warning }
    } catch as e {
        if IsOcrCancelled(cancelState)
            return { ok: false, engine: "Tesseract", language: "", text: "", error: "OCR cancelled.", cancelled: true }
        return { ok: false, engine: "Tesseract", language: resolvedLanguages.value, text: "", error: ShortErrorMessage(e.Message) }
    } finally {
        DeleteOcrTempFile(outputPath)
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
    if (InStr(error, "Portable RapidOCR is not installed") && !InStr(error, "NO_LANGUAGE")
        && !InStr(error, "Portable Tesseract is not installed")) {
        return "⚠️ RapidOCR 런타임이 설치되지 않았습니다.`r`n"
            . "설정에서 Engine을 Auto 또는 Windows OCR only로 바꾸거나 RapidOCR 런타임을 설치하세요.`r`n"
            . "RapidOCR runtime is not installed. Switch Engine to Auto/Windows OCR or install RapidOCR."
    }
    if (InStr(error, "NO_LANGUAGE") || InStr(error, "Portable Tesseract is not installed")
        || InStr(error, "language data is missing")) {
        return "⚠️ 사용할 수 있는 로컬 OCR 언어가 없습니다.`r`n"
            . "Windows OCR 언어를 설치하거나 회사용 Full 패키지(kor+eng)를 사용하세요.`r`n"
            . "No matching OCR language is available. Install a Windows OCR language or use the Full package."
    }
    return "⚠️ 로컬 OCR 실패 / Local OCR failed: " error
}

RunLocalOcr(imagePath, engine, languages, rawImagePath := "", cancelState := 0) {
    engine := NormalizeOcrEngine(engine)
    languages := ResolveOcrLanguages(languages)
    errors := []

    IsCancelledStep(stepResult := 0) {
        return IsOcrCancelled(cancelState) || (IsObject(stepResult) && stepResult.HasProp("cancelled") && stepResult.cancelled)
    }
    MakeCancelledResult() {
        return { ok: false, engine: "Local OCR", language: "", text: "", error: "OCR cancelled.", noText: false, cancelled: true }
    }

    if IsCancelledStep()
        return MakeCancelledResult()

    if (engine == "rapidocr") {
        result := RunRapidOcr(imagePath, languages, rawImagePath, cancelState)
        if IsCancelledStep(result)
            return MakeCancelledResult()
        if (result.ok && result.text != "")
            return result
        return { ok: false, engine: result.engine, language: result.language, text: "",
            error: result.ok ? "No text was detected." : result.error, noText: result.ok }
    }
    if (engine == "windows") {
        result := RunWindowsOcr(imagePath, languages, cancelState)
        if IsCancelledStep(result)
            return MakeCancelledResult()
        if (result.ok && result.text != "")
            return result
        return { ok: false, engine: result.engine, language: result.language, text: "",
            error: result.ok ? "No text was detected." : result.error, noText: result.ok }
    }
    if (engine == "tesseract") {
        result := RunTesseractOcr(imagePath, languages, cancelState)
        if IsCancelledStep(result)
            return MakeCancelledResult()
        if (result.ok && result.text != "")
            return result
        return { ok: false, engine: result.engine, language: result.language, text: "",
            error: result.ok ? "No text was detected." : result.error, noText: result.ok }
    }

    languageList := StrSplit(languages, ",")
    primaryLanguage := languageList[1]
    primaryBase := GetBaseOcrLanguage(primaryLanguage)
    hadSuccessEmpty := false
    lastEmptyEngine := "Local OCR"
    lastEmptyLanguage := ""

    RecordEmptyOrError(stepResult, emptyMessage) {
        if stepResult.ok {
            hadSuccessEmpty := true
            lastEmptyEngine := stepResult.engine
            lastEmptyLanguage := stepResult.language
            errors.Push(emptyMessage)
        } else {
            errors.Push(stepResult.error)
        }
    }

    if (primaryBase == "ko") {
        result := RunRapidOcr(imagePath, primaryLanguage, rawImagePath, cancelState)
        if IsCancelledStep(result)
            return MakeCancelledResult()
        if (result.ok && result.text != "")
            return result
        RecordEmptyOrError(result, "RapidOCR detected no text.")

        result := RunWindowsOcr(imagePath, primaryLanguage, cancelState)
        if IsCancelledStep(result)
            return MakeCancelledResult()
        if (result.ok && result.text != "")
            return result
        RecordEmptyOrError(result, "Windows OCR detected no text.")

        result := RunTesseractOcr(imagePath, languages, cancelState)
        if IsCancelledStep(result)
            return MakeCancelledResult()
        if (result.ok && result.text != "")
            return result
        RecordEmptyOrError(result, "Tesseract detected no text.")
    } else {
        result := RunWindowsOcr(imagePath, primaryLanguage, cancelState)
        if IsCancelledStep(result)
            return MakeCancelledResult()
        if (result.ok && result.text != "")
            return result
        RecordEmptyOrError(result, "Windows OCR detected no text.")

        result := RunTesseractOcr(imagePath, languages, cancelState)
        if IsCancelledStep(result)
            return MakeCancelledResult()
        if (result.ok && result.text != "")
            return result
        RecordEmptyOrError(result, "Tesseract detected no text.")

        result := RunRapidOcr(imagePath, primaryLanguage, rawImagePath, cancelState)
        if IsCancelledStep(result)
            return MakeCancelledResult()
        if (result.ok && result.text != "")
            return result
        RecordEmptyOrError(result, "RapidOCR detected no text.")
    }

    if (languageList.Length > 1) {
        fallbackLanguages := ""
        loop languageList.Length - 1
            fallbackLanguages .= (A_Index == 1 ? "" : ",") languageList[A_Index + 1]
        result := RunWindowsOcr(imagePath, fallbackLanguages, cancelState)
        if IsCancelledStep(result)
            return MakeCancelledResult()
        if (result.ok && result.text != "")
            return result
        RecordEmptyOrError(result, "Windows fallback detected no text.")
    }

    return { ok: false, engine: hadSuccessEmpty ? lastEmptyEngine : "Local OCR",
        language: hadSuccessEmpty ? lastEmptyLanguage : "", text: "",
        error: JoinOcrErrors(errors), noText: hadSuccessEmpty }
}
