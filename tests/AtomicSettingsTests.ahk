#Requires AutoHotkey v2.0
#Warn All, Off
#Include ..\src\SettingsManager.ahk
OnError(Failure)
global CONFIG_DIR := A_ScriptDir "\..\build\settings-tests-" DllCall("GetCurrentProcessId") "-" A_TickCount
global CONFIG_FILE := CONFIG_DIR "\config.ini"
global REG_PATH := "HKCU\Software\ClipOCR-Tests-NoUserSettings\" DllCall("GetCurrentProcessId")

Check(SafeWriteLocalSetting("ko", "Language"), "First save succeeds")
original := FileRead(CONFIG_FILE, "UTF-16")
locked := FileOpen(CONFIG_FILE, "r-wd")
Check(!SafeWriteLocalSetting("en", "Language"), "Locked save returns false")
locked.Close()
Check(FileRead(CONFIG_FILE, "UTF-16") == original, "Failed save preserves original")
Check(SafeWriteLocalSetting("한글", "Language"), "Unicode replacement succeeds")
value := ""
Check(TryReadLocalSetting("Language", &value) && value == "한글", "Read verifies saved Unicode")
loop files, CONFIG_FILE ".pending.*" {
    throw Error("Pending settings file leaked after failure")
}
FileAppend("ok AtomicSettings (6 atomic save/failure checks)`n", "*")
ExitApp(0)

Check(condition, label) {
    if !condition
        throw Error(label)
}
Failure(err, mode) {
    FileAppend("FAIL " err.Message " @ " err.File ":" err.Line "`n", "*")
    ExitApp(1)
}
