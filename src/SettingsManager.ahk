; SettingsManager.ahk - Per-User file-based configuration manager.
; Standardized configuration layout for PL Suite applications (App01 ~ App10).
;
; Standard Layout:
; %LOCALAPPDATA%\Programs\<AppFolder>\UserSetting\config.ini

#Include AtomicSettings.ahk

global CONFIG_DIR := A_ScriptDir "\UserSetting"
global CONFIG_FILE := CONFIG_DIR "\config.ini"

GetSettingSection(key) {
    switch key {
        case "SaveImageFormat", "JpegQuality":
            return "Image"
        case "TranslateLang", "TranslateHotkey", "TextTranslateFontSize", "ImageTranslateLangs", "TranslateConsent":
            return "Translation"
        case "OcrEngine", "OcrLanguages":
            return "OCR"
        case "MigratedFromRegistry":
            return "System"
        default:
            return "General"
    }
}

EnsureSettingsMigration() {
    global CONFIG_DIR, CONFIG_FILE, REG_PATH
    if IniRead(CONFIG_FILE, "System", "MigratedFromRegistry", "0") == "1"
        return false
    hasRegistry := false
    try {
        loop reg, REG_PATH, "V" {
            hasRegistry := true
            break
        }
    }
    if !hasRegistry
        return false
    changes := []
    loop reg, REG_PATH, "V" {
        if A_LoopRegName == ""
            continue
        section := GetSettingSection(A_LoopRegName)
        if IniRead(CONFIG_FILE, section, A_LoopRegName, Chr(0x1F)) != Chr(0x1F)
            continue
        changes.Push({Section: section, Key: A_LoopRegName, Value: String(RegRead(REG_PATH, A_LoopRegName))})
    }
    changes.Push({Section: "System", Key: "MigratedFromRegistry", Value: "1"})
    SettingsWriteIniValues(CONFIG_FILE, changes)
    return true
}
TryReadLocalSetting(key, &value) {
    global CONFIG_FILE, REG_PATH
    static NOT_FOUND := Chr(0x1F)

    ; 1. Try reading from UserSetting\config.ini first
    try {
        if FileExist(CONFIG_FILE) {
            section := GetSettingSection(key)
            val := IniRead(CONFIG_FILE, section, key, NOT_FOUND)
            if (val != NOT_FOUND) {
                value := val
                return true
            }
        }
    } catch {
        ; Fall through to legacy registry fallback
    }

    ; 2. Legacy registry fallback if not found in INI
    try {
        val := RegRead(REG_PATH, key)
        value := String(val)
        return true
    } catch {
        value := ""
        return false
    }
}

SafeWriteLocalSetting(value, key) {
    global CONFIG_DIR, CONFIG_FILE
    try {
        if !DirExist(CONFIG_DIR)
            DirCreate(CONFIG_DIR)
        section := GetSettingSection(key)
        SettingsWriteIniValues(CONFIG_FILE, [{Section: section, Key: key, Value: String(value)}])
        return true
    } catch {
        return false
    }
}

; Backward-compatibility wrapper for existing SafeRegWriteString calls
SafeRegWriteString(value, regPath, valueName) {
    return SafeWriteLocalSetting(value, valueName)
}
