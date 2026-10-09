; Write only sibling temporary files; commit with an atomic Windows rename.
SettingsTempPath(path) {
    loop 20 {
        candidate := path ".pending." DllCall("GetCurrentProcessId") "." A_TickCount "." Random(100000, 999999)
        if !FileExist(candidate)
            return candidate
    }
    throw Error("Cannot reserve a temporary settings path.")
}

SettingsCommitTemp(tempPath, targetPath) {
    stream := FileOpen(tempPath, "rw")
    if !stream
        throw Error("Cannot reopen temporary settings for flushing.")
    try {
        if !DllCall("FlushFileBuffers", "ptr", stream.Handle)
            throw OSError()
    } finally {
        stream.Close()
    }
    if FileExist(targetPath) {
        ; Keep the existing ACL; no direct-write fallback on failure.
        if !DllCall("ReplaceFileW", "str", targetPath, "str", tempPath, "ptr", 0, "uint", 0, "ptr", 0, "ptr", 0)
            throw OSError()
    } else {
        ; A concurrently created destination wins rather than being overwritten.
        if !DllCall("MoveFileExW", "str", tempPath, "str", targetPath, "uint", 8)
            throw OSError()
    }
}

SettingsWriteIniValues(path, changes) {
    SplitPath(path, , &directory)
    if !DirExist(directory)
        DirCreate(directory)
    temp := SettingsTempPath(path)
    try {
        if FileExist(path)
            FileCopy(path, temp, false)
        else
            FileAppend("", temp, "UTF-16")
        for change in changes {
            if change.HasOwnProp("SectionText") {
                if change.SectionText != ""
                    IniWrite(change.SectionText, temp, change.Section)
                else
                    IniDelete(temp, change.Section)
            } else {
                IniWrite(String(change.Value), temp, change.Section, change.Key)
                if !(IniRead(temp, change.Section, change.Key, Chr(0x1F)) == String(change.Value))
                    throw Error("Temporary settings validation failed: " change.Key)
            }
        }
        SettingsCommitTemp(temp, path)
    } finally {
        if FileExist(temp)
            try FileDelete(temp)
    }
}

SettingsWriteText(path, content, encoding := "UTF-16") {
    SplitPath(path, , &directory)
    if !DirExist(directory)
        DirCreate(directory)
    temp := SettingsTempPath(path)
    try {
        FileAppend(content, temp, encoding)
        if !(FileRead(temp, encoding) == content)
            throw Error("Temporary settings content could not be verified.")
        SettingsCommitTemp(temp, path)
    } finally {
        if FileExist(temp)
            try FileDelete(temp)
    }
}
