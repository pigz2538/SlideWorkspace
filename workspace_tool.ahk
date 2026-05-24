#Requires AutoHotkey v2.0
#SingleInstance Force
SetWorkingDir A_ScriptDir
KeyHistory 0
ListLines 0
SetWinDelay 5
SetControlDelay 5
DetectHiddenWindows false

; Self-elevate if --admin (or /admin) flag is present and we're not already admin.
; Required for managing windows of UAC-elevated processes (admin cmd, regedit, etc.)
; Use A_AhkPath explicitly — relying on .ahk file association via *RunAs fails
; silently when portable AHK isn't registered as the handler for .ahk files.
needsAdmin := false
for arg in A_Args {
    if (arg = "--admin" || arg = "/admin")
        needsAdmin := true
}
if (needsAdmin && !A_IsAdmin) {
    try {
        Run '*RunAs "' A_AhkPath '" "' A_ScriptFullPath '" --admin'
    } catch as e {
        MsgBox "Failed to elevate: " e.Message "`n`nTip: right-click run-as-admin.bat -> 'Run as administrator'."
    }
    ExitApp
}

;==============================================================
; WorkspaceTool v2.0 — AHK core daemon
;   - HTTP server on 127.0.0.1:<random> serves UI + JSON API
;   - Edge --app opens the manager UI as a chromeless window
;   - Dynamic hotkeys (incl. XButton1/2), workspaces, sticky windows,
;     focus mode, rules, tray badge, switch toast
;==============================================================

global APP_NAME     := "WorkspaceTool"
global APP_VERSION  := "2.0"
global F_SETTINGS   := A_ScriptDir "\settings.json"
global F_WORKSPACES := A_ScriptDir "\workspaces.json"
global F_RULES      := A_ScriptDir "\rules.json"
global F_DEBUG      := A_ScriptDir "\debug_script_out.txt"
global DEBUG_ENABLED := false
global D_UI         := A_ScriptDir "\ui"

global g_Settings       := Map()
global g_Workspaces     := []           ; Array of Map
global g_Rules          := Map()
global g_HwndCache      := Map()        ; workspace_id -> Array of hwnds
global g_ActiveWs       := ""           ; id of currently-active workspace
global g_History        := []           ; for undo
global g_BoundHotkeys   := Map()        ; ahkKey -> true (for tracking active bindings)
global g_FocusedHidden  := []           ; hwnds we minimized for focus mode (current session)
global g_LaunchGracePids := Map()       ; pid -> expiry tick for freshly launched apps
global g_LaunchGraceSpecs := Map()      ; exe -> {expires,before:Set(hwnd)}
global g_RestoreContext := 0
global g_RestorePersistPending := 0
global g_RestoreInProgress := false
global g_EdgePid        := 0
global g_HttpPort       := 0
global g_HttpSock       := 0
global g_HttpRunning    := false
global g_Routes         := Map()

;==============================================================
; JSON  (Map for objects, Array for arrays)
; Defined here (before any executable code) so #Warn UnreachableCode
; doesn't flag it as following a top-level return.
;==============================================================
class JSON {
    static parse(s) {
        ctx := {str: s, pos: 1, len: StrLen(s)}
        JSON._ws(ctx)
        return JSON._val(ctx)
    }
    static stringify(v, indent := "") {
        return JSON._enc(v, indent, "")
    }
    static _ws(ctx) {
        while (ctx.pos <= ctx.len) {
            c := SubStr(ctx.str, ctx.pos, 1)
            if (c = " " || c = "`t" || c = "`n" || c = "`r")
                ctx.pos++
            else
                break
        }
    }
    static _val(ctx) {
        JSON._ws(ctx)
        if (ctx.pos > ctx.len)
            throw Error("JSON: unexpected end")
        c := SubStr(ctx.str, ctx.pos, 1)
        if (c = "{")
            return JSON._obj(ctx)
        if (c = "[")
            return JSON._arr(ctx)
        if (c = '"')
            return JSON._str(ctx)
        if (c = "t" || c = "f")
            return JSON._bool(ctx)
        if (c = "n")
            return JSON._null(ctx)
        return JSON._num(ctx)
    }
    static _obj(ctx) {
        ctx.pos++
        m := Map()
        JSON._ws(ctx)
        if (SubStr(ctx.str, ctx.pos, 1) = "}") {
            ctx.pos++
            return m
        }
        Loop {
            JSON._ws(ctx)
            k := JSON._str(ctx)
            JSON._ws(ctx)
            if (SubStr(ctx.str, ctx.pos, 1) != ":")
                throw Error("JSON: expected ':' at " ctx.pos)
            ctx.pos++
            m[k] := JSON._val(ctx)
            JSON._ws(ctx)
            c := SubStr(ctx.str, ctx.pos, 1)
            if (c = ",") {
                ctx.pos++
                continue
            }
            if (c = "}") {
                ctx.pos++
                return m
            }
            throw Error("JSON: expected ',' or '}' at " ctx.pos)
        }
    }
    static _arr(ctx) {
        ctx.pos++
        a := []
        JSON._ws(ctx)
        if (SubStr(ctx.str, ctx.pos, 1) = "]") {
            ctx.pos++
            return a
        }
        Loop {
            a.Push(JSON._val(ctx))
            JSON._ws(ctx)
            c := SubStr(ctx.str, ctx.pos, 1)
            if (c = ",") {
                ctx.pos++
                continue
            }
            if (c = "]") {
                ctx.pos++
                return a
            }
            throw Error("JSON: expected ',' or ']' at " ctx.pos)
        }
    }
    static _str(ctx) {
        if (SubStr(ctx.str, ctx.pos, 1) != '"')
            throw Error("JSON: expected '`"' at " ctx.pos)
        ctx.pos++
        result := ""
        Loop {
            if (ctx.pos > ctx.len)
                throw Error("JSON: unterminated string")
            ; Fast-path: find next `"` or `\` via InStr (one OS-level scan),
            ; then SubStr the whole chunk in a single allocation. Avoids the
            ; O(n^2) char-by-char concat that was killing startup on big files.
            quotePos := InStr(ctx.str, '"', false, ctx.pos)
            bsPos := InStr(ctx.str, "\", false, ctx.pos)
            if !quotePos
                throw Error("JSON: unterminated string")
            next := (bsPos && bsPos < quotePos) ? bsPos : quotePos
            if (next > ctx.pos)
                result .= SubStr(ctx.str, ctx.pos, next - ctx.pos)
            ctx.pos := next
            c := SubStr(ctx.str, ctx.pos, 1)
            if (c = '"') {
                ctx.pos++
                return result
            }
            ; Backslash escape sequence
            ctx.pos++
            e := SubStr(ctx.str, ctx.pos, 1)
            if (e = '"' || e = "\" || e = "/") {
                result .= e
            } else if (e = "n") {
                result .= "`n"
            } else if (e = "t") {
                result .= "`t"
            } else if (e = "r") {
                result .= "`r"
            } else if (e = "b") {
                result .= Chr(8)
            } else if (e = "f") {
                result .= Chr(12)
            } else if (e = "u") {
                h := SubStr(ctx.str, ctx.pos + 1, 4)
                result .= Chr(Integer("0x" h))
                ctx.pos += 4
            }
            ctx.pos++
        }
    }
    static _num(ctx) {
        start := ctx.pos
        if (SubStr(ctx.str, ctx.pos, 1) = "-")
            ctx.pos++
        while (ctx.pos <= ctx.len) {
            c := SubStr(ctx.str, ctx.pos, 1)
            if (c = "")
                break
            if InStr("0123456789.eE+-", c)
                ctx.pos++
            else
                break
        }
        s := SubStr(ctx.str, start, ctx.pos - start)
        if InStr(s, ".") || InStr(s, "e") || InStr(s, "E")
            return Float(s)
        return Integer(s)
    }
    static _bool(ctx) {
        if (SubStr(ctx.str, ctx.pos, 4) = "true") {
            ctx.pos += 4
            return true
        }
        if (SubStr(ctx.str, ctx.pos, 5) = "false") {
            ctx.pos += 5
            return false
        }
        throw Error("JSON: bad literal at " ctx.pos)
    }
    static _null(ctx) {
        if (SubStr(ctx.str, ctx.pos, 4) = "null") {
            ctx.pos += 4
            return ""
        }
        throw Error("JSON: bad literal at " ctx.pos)
    }
    static _enc(v, indent, pad) {
        if (IsObject(v)) {
            if (v is Array)
                return JSON._encArr(v, indent, pad)
            if (v is Map)
                return JSON._encMap(v, indent, pad)
            return '""'
        }
        t := Type(v)
        if (t = "Integer" || t = "Float")
            return v . ""
        return '"' . JSON._esc(v . "") . '"'
    }
    static _encArr(arr, indent, pad) {
        if (arr.Length = 0)
            return "[]"
        nl := indent != "" ? "`n" : ""
        ip := pad . indent
        parts := []
        for v in arr
            parts.Push(ip . JSON._enc(v, indent, ip))
        sep := indent != "" ? ",`n" : ","
        out := "[" . nl . parts[1]
        Loop parts.Length - 1
            out .= sep . parts[A_Index + 1]
        return out . nl . pad . "]"
    }
    static _encMap(m, indent, pad) {
        keys := []
        for k, _ in m
            keys.Push(k)
        if (keys.Length = 0)
            return "{}"
        nl := indent != "" ? "`n" : ""
        ip := pad . indent
        kv := indent != "" ? ": " : ":"
        parts := []
        for k in keys
            parts.Push(ip . '"' . JSON._esc(k . "") . '"' . kv . JSON._enc(m[k], indent, ip))
        sep := indent != "" ? ",`n" : ","
        out := "{" . nl . parts[1]
        Loop parts.Length - 1
            out .= sep . parts[A_Index + 1]
        return out . nl . pad . "}"
    }
    static _esc(s) {
        s := s . ""
        s := StrReplace(s, "\", "\\")
        s := StrReplace(s, '"', '\"')
        s := StrReplace(s, "`b", "\b")
        s := StrReplace(s, "`f", "\f")
        s := StrReplace(s, "`n", "\n")
        s := StrReplace(s, "`r", "\r")
        s := StrReplace(s, "`t", "\t")
        return s
    }
}

;--------------------------------------------------------------
; INIT
;--------------------------------------------------------------
EnsureFiles()
SettingsLoad()
WorkspacesLoad()
RulesLoad()
DebugLog("===== session start =====")
RegisterRoutes()
HttpServerStart()
TraySetup()
HotkeysRebindAll()
OnExit(OnExitHandler)
TrayBadgeUpdate()
TrayTip(APP_NAME " v" APP_VERSION (A_IsAdmin ? " [admin]" : "") " ready. Manager: " g_Settings.Get("panelHotkey", "") " · http://127.0.0.1:" g_HttpPort, APP_NAME, 0x10)
return

OnExitHandler(*) {
    try HttpServerStop()
    try WorkspacesSave()
    try SettingsSave()
}

DebugLog(msg) {
    global F_DEBUG, DEBUG_ENABLED
    if !DEBUG_ENABLED
        return
    try FileAppend FormatTime(, "yyyy-MM-dd HH:mm:ss") " | " msg "`n", F_DEBUG, "UTF-8"
}

;==============================================================
; PERSISTENCE
;==============================================================
EnsureFiles() {
    if !DirExist(D_UI)
        DirCreate D_UI
    if !FileExist(F_SETTINGS)
        FileAppend JSON.stringify(DefaultSettings(), "  "), F_SETTINGS, "UTF-8"
    if !FileExist(F_WORKSPACES)
        FileAppend JSON.stringify(Map("version", 2, "workspaces", [], "active", ""), "  "), F_WORKSPACES, "UTF-8"
    if !FileExist(F_RULES)
        FileAppend JSON.stringify(DefaultRules(), "  "), F_RULES, "UTF-8"
}

DefaultSettings() {
    s := Map()
    s["version"] := 2
    s["managerHotkey"] := ""
    s["panelHotkey"] := "Ctrl+Alt+W"
    s["reloadHotkey"] := "Ctrl+Alt+R"
    s["undoHotkey"] := "Ctrl+Alt+Z"
    s["prevWorkspaceHotkey"] := "XButton1"
    s["nextWorkspaceHotkey"] := "XButton2"
    s["switchToast"] := 1
    s["trayBadge"] := 1
    s["focusMode"] := 0
    s["captureThumbnails"] := 1
    s["previewSize"] := "md"
    s["stickyEnabled"] := 0
    s["stickyPatterns"] := []
    return s
}

DefaultRules() {
    r := Map()
    r["version"] := 1
    r["blacklist"] := []
    r["perApp"] := Map()
    return r
}

SettingsLoad() {
    global g_Settings
    try {
        g_Settings := JSON.parse(FileRead(F_SETTINGS, "UTF-8"))
    } catch {
        g_Settings := DefaultSettings()
    }
    ; Fill any missing keys from defaults
    defaults := DefaultSettings()
    for k, v in defaults
        if !g_Settings.Has(k)
            g_Settings[k] := v
    ; Coerce boolean-ish settings (heal data written by older buggy encoder).
    boolFields := ["switchToast", "trayBadge", "focusMode", "captureThumbnails", "stickyEnabled"]
    for f in boolFields {
        if g_Settings.Has(f) {
            v := g_Settings[f]
            if (Type(v) != "Integer")
                g_Settings[f] := (v && v != "0" && v != "false") ? 1 : 0
        }
    }
    ; Migrate old virtual-desktop follow settings to sticky windows.
    if g_Settings.Has("followPatterns") && !g_Settings.Has("stickyPatterns") {
        g_Settings["stickyPatterns"] := g_Settings.Get("followPatterns", [])
        g_Settings["stickyEnabled"] := g_Settings.Get("followEnabled", 1) ? 1 : 0
    }
    if g_Settings.Has("followEnabled") && !g_Settings.Has("stickyEnabled") {
        g_Settings["stickyEnabled"] := g_Settings.Get("followEnabled", 0) ? 1 : 0
    }
    ; Clean up obsolete keys.
    try g_Settings.Delete("followEnabled")
    try g_Settings.Delete("followPatterns")
    try g_Settings.Delete("toggleFollowHotkey")
}

SettingsSave() {
    global g_Settings
    txt := JSON.stringify(g_Settings, "  ")
    try FileDelete F_SETTINGS
    FileAppend txt, F_SETTINGS, "UTF-8"
}

WorkspacesLoad() {
    global g_Workspaces, g_ActiveWs
    try {
        data := JSON.parse(FileRead(F_WORKSPACES, "UTF-8"))
        g_Workspaces := data.Get("workspaces", [])
        g_ActiveWs := data.Get("active", "")
        NormalizeWorkspaces()
    } catch {
        g_Workspaces := []
        g_ActiveWs := ""
    }
}

; Coerce window-info integer fields. Earlier JSON encoder had a bug where
; integer 0 was serialized as "" — heal that on load so downstream code
; (WinMove etc.) always sees real numbers.
; Also migrates base64 thumbnails (old format) to files under ./thumbs/
; so workspaces.json stays small.
NormalizeWorkspaces() {
    global g_Workspaces
    intFields := ["x", "y", "w", "h", "state", "monitor"]
    migrated := 0
    for ws in g_Workspaces {
        if !ws.Has("enabled") {
            ws["enabled"] := 1
            migrated++
        }
        if !ws.Has("windows") || !(ws["windows"] is Array)
            continue
        for win in ws["windows"] {
            if !(win is Map)
                continue
            ; Heal older VSCode snapshots that stored the whole title-derived
            ; prefix instead of the stable workspace/folder tail segment.
            if win.Has("exe") && win["exe"] = "Code.exe" && win.Has("title") {
                fixedFolder := ExtractVscodeFolderFromTitle(win["title"])
                if (fixedFolder != "" && (!win.Has("folder") || win["folder"] != fixedFolder)) {
                    win["folder"] := fixedFolder
                    migrated++
                }
                fixedUri := ResolveVscodeFolderUri(win["title"])
                if (fixedUri != "" && (!win.Has("vscodeUri") || win["vscodeUri"] != fixedUri)) {
                    win["vscodeUri"] := fixedUri
                    migrated++
                }
            }
            if win.Has("exe") && win["exe"] = "firefox.exe" {
                oldProfilePath := win.Has("firefoxProfilePath") ? win["firefoxProfilePath"] : ""
                FirefoxEnsureSessionData(&win)
                newProfilePath := win.Has("firefoxProfilePath") ? win["firefoxProfilePath"] : ""
                if (newProfilePath != oldProfilePath)
                    migrated++
            }
            for field in intFields {
                if !win.Has(field)
                    continue
                v := win[field]
                if (Type(v) = "Integer")
                    continue
                try {
                    win[field] := Integer(v . "")
                } catch {
                    win[field] := (field = "monitor") ? 1 : 0
                }
            }
            ; Migrate base64 thumb -> file. Old thumbs are long strings (>200 chars
            ; with base64 alphabet); new thumbs are short ids (~16 chars hex).
            if win.Has("thumb") && win["thumb"] != "" {
                tb := win["thumb"]
                if (StrLen(tb) > 100) {
                    thumbId := NewThumbId()
                    path := ThumbsDir() "\" thumbId ".jpg"
                    if Base64ToFile(tb, path) {
                        win["thumb"] := thumbId
                        migrated++
                    } else {
                        win["thumb"] := ""
                    }
                }
            }
        }
    }
    if (migrated > 0)
        WorkspacesSave()
}

WorkspacesSave() {
    global g_Workspaces, g_ActiveWs, g_RestorePersistPending
    g_RestorePersistPending := 0
    data := Map("version", 2, "workspaces", g_Workspaces, "active", g_ActiveWs)
    txt := JSON.stringify(data, "  ")
    try FileDelete F_WORKSPACES
    FileAppend txt, F_WORKSPACES, "UTF-8"
    try ThumbsGarbageCollect()
}

QueueRestorePersistence() {
    global g_RestorePersistPending
    g_RestorePersistPending := 1
    SetTimer FlushRestorePersistence, -1200
}

FlushRestorePersistence(*) {
    global g_RestorePersistPending
    if !g_RestorePersistPending
        return
    WorkspacesSave()
}

ThumbsReferencedSet() {
    global g_Workspaces
    set := Map()
    for ws in g_Workspaces {
        if !ws.Has("windows") || !(ws["windows"] is Array)
            continue
        for win in ws["windows"] {
            if !(win is Map)
                continue
            if win.Has("thumb") && win["thumb"] != ""
                set[win["thumb"]] := true
        }
    }
    return set
}

ThumbsGarbageCollect() {
    dir := ThumbsDir()
    refs := ThumbsReferencedSet()
    Loop Files, dir "\*.jpg", "F" {
        SplitPath A_LoopFileName, , , &ext, &nameNoExt
        if !refs.Has(nameNoExt)
            try FileDelete A_LoopFileFullPath
    }
}

ThumbDeleteById(thumbId) {
    if (thumbId = "")
        return
    try FileDelete(ThumbsDir() "\" thumbId ".jpg")
}

ThumbDeleteFromWindow(win) {
    if !(win is Map)
        return
    if win.Has("thumb") && win["thumb"] != ""
        ThumbDeleteById(win["thumb"])
}

ThumbDeleteFromWorkspace(ws) {
    if !ws || !ws.Has("windows") || !(ws["windows"] is Array)
        return
    for win in ws["windows"]
        ThumbDeleteFromWindow(win)
}

RulesLoad() {
    global g_Rules
    try {
        g_Rules := JSON.parse(FileRead(F_RULES, "UTF-8"))
    } catch {
        g_Rules := DefaultRules()
    }
    if !g_Rules.Has("blacklist")
        g_Rules["blacklist"] := []
    if !g_Rules.Has("perApp")
        g_Rules["perApp"] := Map()
}

RulesSave() {
    global g_Rules
    txt := JSON.stringify(g_Rules, "  ")
    try FileDelete F_RULES
    FileAppend txt, F_RULES, "UTF-8"
}

;==============================================================
; WORKSPACE HELPERS
;==============================================================
WorkspaceFind(id) {
    global g_Workspaces
    for ws in g_Workspaces
        if (ws["id"] = id)
            return ws
    return 0
}

WorkspaceIndex(id) {
    global g_Workspaces
    Loop g_Workspaces.Length
        if (g_Workspaces[A_Index]["id"] = id)
            return A_Index
    return 0
}

NewWorkspaceId() {
    return "ws_" Format("{:x}", A_TickCount) Format("{:x}", Random(0, 0xFFFF))
}

; Returns a unique name. If `desired` clashes with any existing workspace
; (other than the one identified by `ignoreId`), appends " (2)", " (3)", etc.
EnsureUniqueName(desired, ignoreId := "") {
    global g_Workspaces
    if (desired = "")
        desired := "Workspace"
    base := desired
    n := 2
    candidate := desired
    loop {
        clash := false
        for ws in g_Workspaces {
            if (ws["id"] = ignoreId)
                continue
            if (ws["name"] = candidate) {
                clash := true
                break
            }
        }
        if !clash
            return candidate
        candidate := base " (" n ")"
        n++
    }
}

NewWorkspace(name := "") {
    w := Map()
    w["id"] := NewWorkspaceId()
    w["name"] := EnsureUniqueName(name = "" ? "Workspace" : name)
    w["enabled"] := 1
    w["hotkey"] := ""
    w["saveHotkey"] := ""
    w["icon"] := "📋"
    w["color"] := "#4a9eff"
    w["windows"] := []
    return w
}

;==============================================================
; CAPTURE / RESTORE / FOCUS
;==============================================================
WorkspaceSnapshot(id) {
    global g_HwndCache
    ws := WorkspaceFind(id)
    if !ws
        return false
    list := []
    cache := []
    for hwnd in WinGetList() {
        if !WindowIsManageable(hwnd)
            continue
        if WindowMatchesBlacklist(hwnd)
            continue
        if WindowMatchesSticky(hwnd)
            continue
        ; Skip windows that are currently minimized — don't pollute the
        ; workspace with phantom entries the user can't see / doesn't want.
        try {
            if WinGetMinMax("ahk_id " hwnd) = -1
                continue
        }
        info := WindowCapture(hwnd)
        if info {
            list.Push(info)
            cache.Push(hwnd)
        }
    }
    ws["windows"] := list
    g_HwndCache[id] := cache
    WorkspacesSave()
    return true
}

WorkspaceRestore(id) {
    global g_HwndCache, g_ActiveWs, g_Settings, g_History, g_RestoreContext, g_LaunchGracePids, g_LaunchGraceSpecs, g_RestoreInProgress
    if g_RestoreInProgress {
        DebugLog("restore skipped reentry id='" id "'")
        return false
    }
    g_RestoreInProgress := true
    restoreStart := A_TickCount
    try {
        ws := WorkspaceFind(id)
        if !ws
            return false
        if (ws.Has("enabled") && !ws["enabled"]) {
            DebugLog("restore skipped disabled id='" id "'")
            return false
        }
        LaunchGracePruneExpired()
        ; Push to history for undo
        g_History.Push(g_ActiveWs)
        if g_History.Length > 10
            g_History.RemoveAt(1)

        list := ws["windows"]
        cache := g_HwndCache.Has(id) ? g_HwndCache[id] : []
        g_RestoreContext := BuildRestoreContext(list)
        DebugLog("restore ctx workspace='" ws["name"] "' windows=" list.Length " ms=" (A_TickCount - restoreStart))

        ; Build exclude set: hwnds owned by OTHER workspaces' caches (live ones
        ; only). Prevents stealing a window that belongs to another workspace
        ; just because fingerprint (class+exe) happens to match.
        excludeSet := BuildExcludeSet(id)

        moved := 0, launched := 0
        missing := []
        appliedHwnds := []
        appliedSet := Map()
        Loop list.Length {
            slotIdx := A_Index
            itemStart := A_TickCount
            info := list[slotIdx]
            DebugLog("restore item begin idx=" slotIdx " exe='" info.Get("exe", "") "' title='" info.Get("title", "") "'")
            info := ApplyPerAppRules(info)
            hint := slotIdx <= cache.Length ? cache[slotIdx] : 0
            DebugLog("restore item before resolve idx=" slotIdx " hint=" hint)
            target := WindowResolve(info, hint, excludeSet)
            DebugLog("restore item after resolve idx=" slotIdx " target=" target " resolveMs=" (A_TickCount - itemStart))
            if target {
                moveStart := A_TickCount
                if WindowReposition(target, info)
                    moved++
                DebugLog("restore item after move idx=" slotIdx " hwnd=" target " moveMs=" (A_TickCount - moveStart))
                try {
                    DebugLog("restore item cache-write begin idx=" slotIdx " cacheType=" Type(cache) " cacheLen=" cache.Length)
                    while (cache.Length < slotIdx)
                        cache.Push(0)
                    cache[slotIdx] := target
                    DebugLog("restore item cache-write done idx=" slotIdx " cacheLen=" cache.Length)
                    PushUniqueHwnd(appliedHwnds, appliedSet, target)
                    DebugLog("restore item push-unique done idx=" slotIdx)
                    ; Prevent the same hwnd from being assigned to multiple slots
                    excludeSet[target] := true
                    DebugLog("restore item exclude-set done idx=" slotIdx)
                } catch as e {
                    DebugLog("restore item post-move error idx=" slotIdx " line=" e.Line " msg='" e.Message "' what='" e.What "'")
                    return false
                }
            } else {
                missing.Push(Map("info", info, "idx", slotIdx))
            }
            if (info.Has("exe") && info["exe"] = "firefox.exe")
                DebugLog("restore item firefox idx=" slotIdx " matched=" (target ? 1 : 0) " ms=" (A_TickCount - itemStart) " title='" info["title"] "'")
        }
        DebugLog("restore before hwnd-cache save workspace='" ws["name"] "'")
        g_HwndCache[id] := cache
        DebugLog("restore after hwnd-cache save workspace='" ws["name"] "'")
        DebugLog("restore after loop workspace='" ws["name"] "' moved=" moved " missing=" missing.Length)

        ; Prompt to launch missing windows.
        if missing.Length > 0 && PromptLaunchMissing(missing) {
            pending := []
            for item in missing {
                info := item["info"]
                idx := item["idx"]
                DebugLog("launch missing exe=" info["exe"] " title='" info["title"] "' folder='" info["folder"] "' url='" info["url"] "'")
                pid := WindowLaunch(info, id)
                launched++
                hwnd := 0
                if pid {
                    for candidate in WinGetList("ahk_pid " pid) {
                        if !WindowIsManageable(candidate)
                            continue
                        if WindowMatchesBlacklist(candidate)
                            continue
                        if WindowMatchesSticky(candidate)
                            continue
                        hwnd := candidate
                        break
                    }
                }
                if !hwnd && info.Has("exe") && info["exe"] != ""
                    hwnd := FindNewWindowFromLaunchBaseline(info["exe"], excludeSet)
                if hwnd {
                    while (cache.Length < idx)
                        cache.Push(0)
                    cache[idx] := hwnd
                    PushUniqueHwnd(appliedHwnds, appliedSet, hwnd)
                    excludeSet[hwnd] := true
                }
                pending.Push(Map("info", info, "idx", idx, "pid", pid, "hwnd", hwnd))
            }
            if pending.Length > 0 {
                SetTimer(((p, wid) => (*) => PostLaunchPosition(wid, p))(pending, id), -2200)
                SetTimer(((p, wid) => (*) => PostLaunchPosition(wid, p))(pending, id), -9000)
            }
        }

    ; 对严格匹配应用（如 VSCode/浏览器），即使当前没有精确命中，
    ; 也先把同 exe 的现存窗口保留下来，避免 focus mode 把它们最小化。
    strictKeepAliveExes := Map()
    for item in missing {
        info := item["info"]
        if !info.Has("exe") || info["exe"] = ""
            continue
        if (info["exe"] != "Code.exe" && info["exe"] != "firefox.exe" && info["exe"] != "msedge.exe" && info["exe"] != "chrome.exe")
            continue
        strictKeepAliveExes[info["exe"]] := true
    }
    for exe, _ in strictKeepAliveExes {
        for hwnd in RestoreContextExeWindows(exe)
            PushUniqueHwnd(appliedHwnds, appliedSet, hwnd)
    }

    ; Sticky windows: always restore/show windows matching stickyPatterns,
    ; regardless of whether they belong to this workspace.
    if g_Settings.Get("stickyEnabled", 0) {
        patterns := g_Settings.Get("stickyPatterns", [])
        for pattern in patterns {
            for hwnd in WinGetList(pattern) {
                if !WindowIsManageable(hwnd)
                    continue
                if WindowMatchesBlacklist(hwnd)
                    continue
                try {
                    if WinGetMinMax("ahk_id " hwnd) = -1
                        WinRestore "ahk_id " hwnd
                    PushUniqueHwnd(appliedHwnds, appliedSet, hwnd)
                }
            }
        }
    }

        g_ActiveWs := id
        DebugLog("restore before persist workspace='" ws["name"] "'")
        QueueRestorePersistence()
        DebugLog("restore after persist queue workspace='" ws["name"] "'")
        TrayBadgeUpdate()
        DebugLog("restore after tray workspace='" ws["name"] "'")
        if g_Settings["switchToast"]
            ToastShow(ws["icon"] " " ws["name"])
        DebugLog("restore after toast workspace='" ws["name"] "'")
        if g_Settings["focusMode"] {
            DebugLog("restore before focus workspace='" ws["name"] "'")
            FocusModeApply(appliedHwnds)
            DebugLog("restore after focus workspace='" ws["name"] "'")
        }
        DebugLog("restore done workspace='" ws["name"] "' moved=" moved " missing=" missing.Length " launched=" launched " totalMs=" (A_TickCount - restoreStart))
        return true
    } finally {
        g_RestoreContext := 0
        g_RestoreInProgress := false
    }
}

BuildRestoreContext(list) {
    ctx := Map()
    ctx["exeWindows"] := Map()
    ctx["classExeWindows"] := Map()
    ctx["titleWindows"] := Map()
    ctx["explorerFolderWindows"] := Map()
    ctx["vscodeFolderWindows"] := Map()
    ctx["firefoxStates"] := []
    ctx["titleByHwnd"] := Map()
    needFirefox := false
    sessionFile := ""
    for info in list {
        if (info is Map) && info.Has("exe") && info["exe"] = "firefox.exe" {
            needFirefox := true
            if (sessionFile = "" && info.Has("firefoxSession") && info["firefoxSession"] != "")
                sessionFile := info["firefoxSession"]
            break
        }
    }
    for hwnd in WinGetList() {
        if !WindowIsManageable(hwnd)
            continue
        if WindowMatchesBlacklist(hwnd)
            continue
        if WindowMatchesSticky(hwnd)
            continue
        try title := WinGetTitle("ahk_id " hwnd)
        catch
            continue
        try exe := WinGetProcessName("ahk_id " hwnd)
        catch
            continue
        try cls := WinGetClass("ahk_id " hwnd)
        catch
            continue
        RestoreContextIndexPush(ctx["exeWindows"], exe, hwnd)
        RestoreContextIndexPush(ctx["classExeWindows"], RestoreContextKey(cls, exe), hwnd)
        RestoreContextIndexPush(ctx["titleWindows"], RestoreContextKey(cls, exe, title), hwnd)
        ctx["titleByHwnd"][hwnd] := title
        if (cls = "CabinetWClass" && exe = "explorer.exe") {
            folder := WindowExplorerPath(hwnd)
            if (folder != "")
                RestoreContextIndexPush(ctx["explorerFolderWindows"], folder, hwnd)
        }
        if (exe = "Code.exe") {
            folder := ExtractVscodeFolderFromTitle(title)
            if (folder != "")
                RestoreContextIndexPush(ctx["vscodeFolderWindows"], folder, hwnd)
        }
    }
    if needFirefox {
        if (sessionFile = "")
            sessionFile := FirefoxSessionFile()
        states := FirefoxExtractAllWindowStates(sessionFile)
        if (states is Array)
            ctx["firefoxStates"] := states
    }
    return ctx
}

RestoreContextKey(a, b := "", c := "") {
    return a Chr(31) b Chr(31) c
}

RestoreContextIndexPush(index, key, hwnd) {
    if (key = "")
        return
    if !index.Has(key)
        index[key] := []
    index[key].Push(hwnd)
}

RestoreContextGetIndex(ctx, indexName, key) {
    if (ctx && ctx.Has(indexName) && ctx[indexName].Has(key))
        return ctx[indexName][key]
    return []
}

RestoreContextGet(indexName, key) {
    global g_RestoreContext
    if (g_RestoreContext && g_RestoreContext.Has(indexName) && g_RestoreContext[indexName].Has(key))
        return g_RestoreContext[indexName][key]
    return []
}

RestoreContextTitle(hwnd) {
    global g_RestoreContext
    if (g_RestoreContext && g_RestoreContext.Has("titleByHwnd") && g_RestoreContext["titleByHwnd"].Has(hwnd))
        return g_RestoreContext["titleByHwnd"][hwnd]
    return WinGetTitle("ahk_id " hwnd)
}

RestoreContextExeWindows(exe) {
    global g_RestoreContext
    if (g_RestoreContext && g_RestoreContext.Has("exeWindows") && g_RestoreContext["exeWindows"].Has(exe))
        return g_RestoreContext["exeWindows"][exe]
    return WinGetList("ahk_exe " exe)
}

PushUniqueHwnd(list, set, hwnd) {
    if !hwnd || set.Has(hwnd)
        return false
    set[hwnd] := true
    list.Push(hwnd)
    return true
}

PostLaunchPosition(id, pending) {
    global g_HwndCache, g_LaunchGraceSpecs, g_ActiveWs
    ws := WorkspaceFind(id)
    if !ws
        return
    if (g_ActiveWs != id) {
        DebugLog("post-launch skipped inactive id='" id "' active='" g_ActiveWs "'")
        return
    }
    cache := g_HwndCache.Has(id) ? g_HwndCache[id] : []
    excludeSet := BuildExcludeSet(id)
    appliedHwnds := []
    appliedSet := Map()
    for hwnd in cache {
        if hwnd
            PushUniqueHwnd(appliedHwnds, appliedSet, hwnd)
    }
    for item in pending {
        info := item["info"]
        idx := item["idx"]
        hwnd := WindowFindByFingerprint(info, excludeSet)
        if !hwnd && info.Has("exe") && info["exe"] != ""
            hwnd := FindNewWindowFromLaunchBaseline(info["exe"], excludeSet)
        if !hwnd && item.Has("pid") && item["pid"] {
            for candidate in WinGetList("ahk_pid " item["pid"]) {
                if !WindowIsManageable(candidate)
                    continue
                if WindowMatchesBlacklist(candidate)
                    continue
                if WindowMatchesSticky(candidate)
                    continue
                hwnd := candidate
                break
            }
        }
        if hwnd {
            if (info.Has("exe") && info["exe"] = "firefox.exe" && (!item.Has("tabsPopulated") || !item["tabsPopulated"]))
                item["tabsPopulated"] := FirefoxPopulateExtraTabs(hwnd, info)
            WindowReposition(hwnd, info)
            while (cache.Length < idx)
                cache.Push(0)
            cache[idx] := hwnd
            PushUniqueHwnd(appliedHwnds, appliedSet, hwnd)
            excludeSet[hwnd] := true
        }
    }
    g_HwndCache[id] := cache

    ; Sticky windows in post-launch too so focus mode doesn't hide them.
    if g_Settings.Get("stickyEnabled", 0) {
        patterns := g_Settings.Get("stickyPatterns", [])
        for pattern in patterns {
            for hwnd in WinGetList(pattern) {
                if !WindowIsManageable(hwnd)
                    continue
                if WindowMatchesBlacklist(hwnd)
                    continue
                try {
                    if WinGetMinMax("ahk_id " hwnd) = -1
                        WinRestore "ahk_id " hwnd
                    PushUniqueHwnd(appliedHwnds, appliedSet, hwnd)
                }
            }
        }
    }

    if g_Settings["focusMode"]
        FocusModeApply(appliedHwnds)
}

; Build the "do not touch" set for restore operations: every live hwnd
; that's owned by some OTHER workspace's cache. Returns a Map of hwnd→true.
BuildExcludeSet(currentId) {
    global g_HwndCache
    set := Map()
    for otherId, otherCache in g_HwndCache {
        if (otherId = currentId)
            continue
        for h in otherCache {
            if !h
                continue
            try {
                if WinExist("ahk_id " h)
                    set[h] := true
            }
        }
    }
    return set
}

FocusModeApply(keepHwnds) {
    global g_FocusedHidden, g_LaunchGracePids, g_LaunchGraceSpecs
    selfPid := ProcessExist()
    LaunchGracePruneExpired()
    keep := Map()
    for h in keepHwnds
        keep[h] := true

    ; Un-hide only windows we previously hid that are now in keep set;
    ; leave the rest minimized (avoids the restore-then-minimize flicker).
    newHidden := []
    for h in g_FocusedHidden {
        try {
            if !WinExist("ahk_id " h)
                continue
            if keep.Has(h) {
                if WinGetMinMax("ahk_id " h) = -1
                    WinRestore "ahk_id " h
            } else {
                newHidden.Push(h)
            }
        }
    }
    g_FocusedHidden := newHidden

    ; Minimize windows that should be hidden AND aren't already minimized.
    for hwnd in WinGetList() {
        if keep.Has(hwnd)
            continue
        if !WindowIsManageable(hwnd)
            continue
        if WindowMatchesBlacklist(hwnd)
            continue
        if WindowMatchesSticky(hwnd)
            continue
        try {
            pid := WinGetPID("ahk_id " hwnd)
            if WinGetPID("ahk_id " hwnd) = selfPid
                continue
            if g_LaunchGracePids.Has(pid) && LaunchGraceOwnsActiveWorkspaceByPid(pid)
                continue
            exe := WinGetProcessName("ahk_id " hwnd)
            if LaunchGraceProtectsHwnd(exe, hwnd) && LaunchGraceOwnsActiveWorkspace(exe)
                continue
        }
        try {
            if WinGetMinMax("ahk_id " hwnd) != -1 {
                WinMinimize "ahk_id " hwnd
                g_FocusedHidden.Push(hwnd)
            }
        }
    }
}

UndoLastSwitch() {
    global g_History
    if g_History.Length = 0 {
        TrayTip("No previous workspace", APP_NAME, 0x10)
        return
    }
    prev := g_History.Pop()
    if (prev = "")
        return
    WorkspaceRestore(prev)
    ; Undo doesn't push to history
    g_History.Pop()
}

ApplyPerAppRules(info) {
    global g_Rules
    perApp := g_Rules.Get("perApp", Map())
    if !perApp.Has(info["exe"])
        return info
    rule := perApp[info["exe"]]
    if rule.Has("alwaysMaximize") && rule["alwaysMaximize"]
        info["state"] := 1
    if rule.Has("preferMonitor") && rule["preferMonitor"] > 0 {
        n := rule["preferMonitor"]
        if (n <= MonitorGetCount()) {
            MonitorGetWorkArea n, &l, &t, &r, &b
            ; Center the window on that monitor with current width/height
            info["x"] := l + 50
            info["y"] := t + 50
            info["monitor"] := n
        }
    }
    return info
}

;==============================================================
; WINDOW DETAIL EXTRACTION
;==============================================================
UriDecode(s) {
    if (s = "")
        return ""
    s := StrReplace(s, "+", "%20")
    out := ""
    i := 1
    while (i <= StrLen(s)) {
        ch := SubStr(s, i, 1)
        if (ch = "%" && i + 2 <= StrLen(s)) {
            hex := SubStr(s, i + 1, 2)
            try {
                out .= Chr(Integer("0x" hex))
                i += 3
                continue
            }
        }
        out .= ch
        i++
    }
    return out
}

VscodeUriBaseName(uri) {
    if (uri = "")
        return ""
    decoded := UriDecode(uri)
    decoded := RegExReplace(decoded, "^file:///", "")
    decoded := RegExReplace(decoded, "^vscode-remote://[^/]+", "")
    decoded := RegExReplace(decoded, "/+$", "")
    decoded := StrReplace(decoded, "/", "\")
    parts := StrSplit(decoded, "\")
    return parts.Length ? parts[parts.Length] : decoded
}

VscodeUriDisplayLabel(folderUri, remoteAuthority := "") {
    base := VscodeUriBaseName(folderUri)
    if (remoteAuthority != "") {
        if RegExMatch(remoteAuthority, "^ssh-remote\+(.+)$", &m)
            return base " [SSH: " m[1] "]"
        if InStr(remoteAuthority, "attached-container+")
            return (base != "" ? base : "Container") " [Container]"
        kind := remoteAuthority
        plus := InStr(kind, "+")
        if plus
            kind := SubStr(kind, 1, plus - 1)
        return (base != "" ? base : kind) " [" kind "]"
    }
    if (base = "")
        return ""
    return base
}

ParseVscodeLabel(label) {
    info := Map("base", label, "tag", "", "value", "")
    if RegExMatch(label, "^(.*) \[([^\]]+)\]$", &m) {
        info["base"] := Trim(m[1])
        tagText := Trim(m[2])
        info["tag"] := tagText
        colon := InStr(tagText, ":")
        if colon {
            info["tag"] := Trim(SubStr(tagText, 1, colon - 1))
            info["value"] := Trim(SubStr(tagText, colon + 1))
        }
    }
    return info
}

VscodeRemoteAuthorityMatches(remoteAuthority, labelInfo) {
    tag := StrLower(labelInfo["tag"])
    value := labelInfo["value"]
    if (tag = "")
        return true
    if (tag = "ssh")
        return RegExMatch(remoteAuthority, "^ssh-remote\+" RegExEscape(value) "$")
    if (tag = "container")
        return InStr(remoteAuthority, "attached-container+") > 0
    return InStr(StrLower(remoteAuthority), tag) > 0
}

FirefoxProfilesRoot() {
    return A_AppData "\Mozilla\Firefox\Profiles"
}

FirefoxSessionFile() {
    root := FirefoxProfilesRoot()
    if !DirExist(root)
        return ""
    newestPath := ""
    newestTime := ""
    Loop Files, root "\*", "D" {
        for rel in ["sessionstore-backups\recovery.jsonlz4", "sessionstore-backups\previous.jsonlz4", "sessionstore.jsonlz4"] {
            candidate := A_LoopFileFullPath "\" rel
            if !FileExist(candidate)
                continue
            t := FileGetTime(candidate, "M")
            if (newestTime = "" || t > newestTime) {
                newestTime := t
                newestPath := candidate
            }
        }
    }
    return newestPath
}

FirefoxProfileNameFromSessionFile(path) {
    root := FirefoxProfilesRoot()
    if (path = "" || root = "")
        return ""
    prefix := root "\"
    if InStr(path, prefix) != 1
        return ""
    rest := SubStr(path, StrLen(prefix) + 1)
    sep := InStr(rest, "\")
    return sep ? SubStr(rest, 1, sep - 1) : rest
}

FirefoxProfilePathFromSessionFile(path) {
    if (path = "")
        return ""
    SplitPath path, , &dir
    if (dir = "")
        return ""
    SplitPath dir, , &profileDir
    return profileDir
}

BufferEnsure(&buf, needSize, copySize := 0) {
    if (buf.Size >= needSize)
        return
    newSize := buf.Size > 0 ? buf.Size : 1024
    while (newSize < needSize)
        newSize *= 2
    newBuf := Buffer(newSize, 0)
    if (copySize > 0)
        DllCall("RtlMoveMemory", "ptr", newBuf.Ptr, "ptr", buf.Ptr, "uptr", copySize)
    buf := newBuf
}

FirefoxReadSessionRaw(sessionFile) {
    static cache := Map()
    static cacheTtlMs := 30000
    if (sessionFile = "" || !FileExist(sessionFile))
        return ""
    stamp := FileGetTime(sessionFile, "M")
    if cache.Has(sessionFile) {
        entry := cache[sessionFile]
        if (entry["stamp"] = stamp || (A_TickCount - entry["parsedAt"] <= cacheTtlMs))
            return entry["data"]
    }
    raw := FirefoxReadJsonLz4(sessionFile)
    if (raw = "")
        return ""
    cache[sessionFile] := Map("stamp", stamp, "data", raw, "parsedAt", A_TickCount)
    return raw
}

FirefoxReadJsonLz4(path) {
    try {
        f := FileOpen(path, "r")
        if !f
            return ""
        size := f.Length
        if (size <= 12)
            return ""
        buf := Buffer(size, 0)
        f.RawRead(buf, size)
        f.Close()
        if (NumGet(buf, 0, "UChar") != 109 || NumGet(buf, 1, "UChar") != 111 || NumGet(buf, 2, "UChar") != 122)
            return ""
        ; mozlz40 format = 8-byte magic + 4-byte uncompressed size + raw LZ4 block
        expectedSize := NumGet(buf, 8, "UInt")
        out := FirefoxLz4Decompress(buf, 12, size - 12, expectedSize)
        if !IsObject(out)
            return ""
        return StrGet(out.Ptr, out.Size, "UTF-8")
    }
    return ""
}

FirefoxLz4Decompress(srcBuf, srcOffset, srcLen, expectedSize := 0) {
    if (srcLen <= 0)
        return ""
    initialSize := expectedSize > 0 ? expectedSize : Max(srcLen * 6, 1048576)
    out := Buffer(initialSize, 0)
    srcPos := srcOffset
    srcEnd := srcOffset + srcLen
    outPos := 0
    while (srcPos < srcEnd) {
        token := NumGet(srcBuf, srcPos, "UChar")
        srcPos += 1
        litLen := token >> 4
        if (litLen = 15) {
            loop {
                if (srcPos >= srcEnd)
                    break
                ext := NumGet(srcBuf, srcPos, "UChar")
                srcPos += 1
                litLen += ext
                if (ext != 255)
                    break
            }
        }
        if (litLen > 0) {
            BufferEnsure(&out, outPos + litLen, outPos)
            DllCall("RtlMoveMemory", "ptr", out.Ptr + outPos, "ptr", srcBuf.Ptr + srcPos, "uptr", litLen)
            srcPos += litLen
            outPos += litLen
        }
        if (srcPos >= srcEnd)
            break
        offset := NumGet(srcBuf, srcPos, "UShort")
        srcPos += 2
        if (offset <= 0 || offset > outPos)
            return ""
        matchLen := token & 0x0F
        if (matchLen = 15) {
            loop {
                if (srcPos >= srcEnd)
                    break
                ext := NumGet(srcBuf, srcPos, "UChar")
                srcPos += 1
                matchLen += ext
                if (ext != 255)
                    break
            }
        }
        matchLen += 4
        BufferEnsure(&out, outPos + matchLen, outPos)
        srcMatch := outPos - offset
        Loop matchLen
            NumPut("UChar", NumGet(out, srcMatch + A_Index - 1, "UChar"), out, outPos + A_Index - 1)
        outPos += matchLen
    }
    final := Buffer(outPos, 0)
    if (outPos > 0)
        DllCall("RtlMoveMemory", "ptr", final.Ptr, "ptr", out.Ptr, "uptr", outPos)
    return final
}

FirefoxWindowTitleBase(title) {
    if (title = "")
        return ""
    title := RegExReplace(title, "\s+[—-]\s+Mozilla Firefox.*$", "")
    return Trim(title)
}

JsonUnescapeString(s) {
    out := StrReplace(s, '\/', '/')
    out := StrReplace(out, '\\', '\u005C')
    out := StrReplace(out, '\"', '"')
    out := StrReplace(out, '\b', Chr(8))
    out := StrReplace(out, '\f', Chr(12))
    out := StrReplace(out, '\n', '`n')
    out := StrReplace(out, '\r', '`r')
    out := StrReplace(out, '\t', '`t')
    while RegExMatch(out, '\\u([0-9A-Fa-f]{4})', &m)
        out := StrReplace(out, m[0], Chr(Integer('0x' m[1])))
    out := StrReplace(out, '\u005C', '\')
    return out
}

JsonExtractArrayContent(raw, key) {
    p := InStr(raw, '"' key '":[')
    if !p
        return ""
    start := p + StrLen(key) + 3
    return JsonExtractBracketBody(raw, start, '[', ']')
}

JsonExtractBracketBody(raw, startPos, openChar, closeChar) {
    depth := 0
    inStr := false
    esc := false
    bodyStart := 0
    len := StrLen(raw)
    Loop len - startPos + 1 {
        i := startPos + A_Index - 1
        ch := SubStr(raw, i, 1)
        if inStr {
            if esc {
                esc := false
            } else if (ch = '\\') {
                esc := true
            } else if (ch = '"') {
                inStr := false
            }
            continue
        }
        if (ch = '"') {
            inStr := true
            continue
        }
        if (ch = openChar) {
            depth += 1
            if (depth = 1)
                bodyStart := i + 1
            continue
        }
        if (ch = closeChar) {
            depth -= 1
            if (depth = 0)
                return SubStr(raw, bodyStart, i - bodyStart)
        }
    }
    return ""
}

JsonSplitTopLevelObjects(arrayContent) {
    items := []
    depth := 0
    inStr := false
    esc := false
    start := 0
    len := StrLen(arrayContent)
    Loop len {
        i := A_Index
        ch := SubStr(arrayContent, i, 1)
        if inStr {
            if esc {
                esc := false
            } else if (ch = '\\') {
                esc := true
            } else if (ch = '"') {
                inStr := false
            }
            continue
        }
        if (ch = '"') {
            inStr := true
            continue
        }
        if (ch = '{') {
            depth += 1
            if (depth = 1)
                start := i
            continue
        }
        if (ch = '}') {
            depth -= 1
            if (depth = 0 && start > 0)
                items.Push(SubStr(arrayContent, start, i - start + 1))
        }
    }
    return items
}

JsonFindAllStringValues(raw, key) {
    vals := []
    pos := 1
    pat := '"' key '":"((?:\\.|[^"\\])*)"'
    while pos := RegExMatch(raw, pat, &m, pos) {
        vals.Push(JsonUnescapeString(m[1]))
        pos += StrLen(m[0])
    }
    return vals
}

FirefoxWindowStateFromSession(win) {
    if (Type(win) != "String" || win = "")
        return ""
    tabs := []
    selected := 1
    if RegExMatch(win, '"selected":(\d+)', &mSel)
        selected := Integer(mSel[1])
    tabsContent := JsonExtractArrayContent(win, "tabs")
    if (tabsContent = "")
        return ""
    for tab in JsonSplitTopLevelObjects(tabsContent) {
        if (tab = "")
            continue
        idx := 1
        if RegExMatch(tab, '"index":(\d+)', &mIdx)
            idx := Integer(mIdx[1])
        urls := JsonFindAllStringValues(tab, "url")
        titles := JsonFindAllStringValues(tab, "title")
        if (urls.Length = 0)
            continue
        if (idx < 1 || idx > urls.Length)
            idx := urls.Length
        url := urls[idx]
        title := (idx <= titles.Length) ? titles[idx] : ""
        if (url = "")
            continue
        tabs.Push(Map("url", url, "title", title))
    }
    if (tabs.Length = 0)
        return ""
    if (selected < 1 || selected > tabs.Length)
        selected := 1
    active := tabs[selected]
    urlSet := Map()
    for tab in tabs {
        if (tab is Map) && tab.Has("url") && tab["url"] != ""
            urlSet[tab["url"]] := true
    }
    return Map("tabs", tabs, "activeUrl", active["url"], "activeTitle", active["title"], "urlSet", urlSet)
}

FirefoxScoreSessionWindow(state, wantedTitle) {
    if !(state is Map)
        return -1
    if (wantedTitle = "")
        return 0
    activeTitle := state.Has("activeTitle") ? state["activeTitle"] : ""
    if (activeTitle = wantedTitle)
        return 100
    if (activeTitle != "" && (InStr(activeTitle, wantedTitle) || InStr(wantedTitle, activeTitle)))
        return 80
    if state.Has("tabs") && (state["tabs"] is Array) {
        for tab in state["tabs"] {
            if !(tab is Map)
                continue
            title := tab.Has("title") ? tab["title"] : ""
            if (title = wantedTitle)
                return 60
            if (title != "" && (InStr(title, wantedTitle) || InStr(wantedTitle, title)))
                return 40
        }
    }
    return 0
}

FirefoxExtractWindowState(sessionFile, windowTitle := "") {
    states := FirefoxExtractAllWindowStates(sessionFile)
    if !(states is Array) || states.Length = 0
        return ""
    return FirefoxSelectBestWindowState(states, windowTitle)
}

FirefoxExtractAllWindowStates(sessionFile) {
    static cache := Map()
    startTick := A_TickCount
    if (sessionFile = "" || !FileExist(sessionFile))
        return ""
    stamp := FileGetTime(sessionFile, "M")
    if cache.Has(sessionFile) {
        entry := cache[sessionFile]
        if (entry["stamp"] = stamp) {
            DebugLog("firefox states cache-hit count=" entry["states"].Length " ms=" (A_TickCount - startTick))
            return entry["states"]
        }
    }
    raw := FirefoxReadSessionRaw(sessionFile)
    if (raw = "")
        return ""
    windowsContent := JsonExtractArrayContent(raw, "windows")
    if (windowsContent = "")
        return ""
    states := []
    for win in JsonSplitTopLevelObjects(windowsContent) {
        state := FirefoxWindowStateFromSession(win)
        if (state is Map)
            states.Push(state)
    }
    cache[sessionFile] := Map("stamp", stamp, "states", states)
    DebugLog("firefox states parsed count=" states.Length " ms=" (A_TickCount - startTick) " file='" sessionFile "'")
    return states
}

FirefoxSelectBestWindowState(states, windowTitle := "") {
    wanted := FirefoxWindowTitleBase(windowTitle)
    best := ""
    bestScore := -1
    for state in states {
        score := FirefoxScoreSessionWindow(state, wanted)
        if (score > bestScore) {
            best := state
            bestScore := score
        }
    }
    return best
}

FirefoxUrlsForLaunch(info) {
    urls := []
    seen := Map()
    if info.Has("firefoxTabs") && (info["firefoxTabs"] is Array) {
        activeUrl := info.Has("firefoxActiveUrl") ? info["firefoxActiveUrl"] : ""
        if (activeUrl != "" && !seen.Has(activeUrl)) {
            seen[activeUrl] := true
            urls.Push(activeUrl)
        }
        for tab in info["firefoxTabs"] {
            u := (tab is Map) ? (tab.Has("url") ? tab["url"] : "") : tab
            if (u = "" || seen.Has(u))
                continue
            seen[u] := true
            urls.Push(u)
        }
    } else {
        u := info.Has("url") ? info["url"] : ""
        if (u != "" && !seen.Has(u)) {
            seen[u] := true
            urls.Push(u)
        }
    }
    return urls
}

FirefoxTabsSupersetMatch(hwnd, info) {
    global g_RestoreContext
    matchStart := A_TickCount
    if !(info is Map)
        return false
    wanted := FirefoxUrlsForLaunch(info)
    if (wanted.Length = 0)
        return false
    states := []
    if (g_RestoreContext && g_RestoreContext.Has("firefoxStates") && (g_RestoreContext["firefoxStates"] is Array) && g_RestoreContext["firefoxStates"].Length > 0) {
        states := g_RestoreContext["firefoxStates"]
    } else {
        sessionFile := info.Has("firefoxSession") ? info["firefoxSession"] : ""
        if (sessionFile = "")
            sessionFile := FirefoxSessionFile()
        if (sessionFile = "")
            return false
        states := FirefoxExtractAllWindowStates(sessionFile)
    }
    if !(states is Array) || states.Length = 0
        return false
    liveTitle := RestoreContextTitle(hwnd)
    bestScore := -1
    checked := 0
    for state in states {
        if !(state is Map)
            continue
        checked += 1
        have := state.Has("urlSet") ? state["urlSet"] : Map()
        ok := true
        for u in wanted {
            if !have.Has(u) {
                ok := false
                break
            }
        }
        if !ok
            continue
        score := FirefoxScoreSessionWindow(state, FirefoxWindowTitleBase(liveTitle))
        if (info.Has("title") && info["title"] != "")
            score += FirefoxScoreSessionWindow(state, FirefoxWindowTitleBase(info["title"]))
        if (score > bestScore)
            bestScore := score
    }
    DebugLog("firefox match hwnd=" hwnd " wanted=" wanted.Length " states=" checked " matched=" (bestScore >= 0 ? 1 : 0) " ms=" (A_TickCount - matchStart) " liveTitle='" liveTitle "'")
    return bestScore >= 0
}

FirefoxTabUrls(tabs) {
    urls := []
    if !(tabs is Array)
        return urls
    for tab in tabs {
        if (tab is Map) {
            if tab.Has("url") && tab["url"] != ""
                urls.Push(tab["url"])
        } else if (tab != "") {
            urls.Push(tab)
        }
    }
    return urls
}

FirefoxEnsureSessionData(&info) {
    if !(info is Map)
        return
    sessionFile := info.Has("firefoxSession") ? info["firefoxSession"] : ""
    if (sessionFile = "")
        sessionFile := FirefoxSessionFile()
    if (sessionFile = "")
        return
    if !info.Has("firefoxSession") || info["firefoxSession"] = ""
        info["firefoxSession"] := sessionFile
    if (!info.Has("firefoxProfile") || info["firefoxProfile"] = "")
        info["firefoxProfile"] := FirefoxProfileNameFromSessionFile(sessionFile)
    if (!info.Has("firefoxProfilePath") || info["firefoxProfilePath"] = "")
        info["firefoxProfilePath"] := FirefoxProfilePathFromSessionFile(sessionFile)
    needTabs := (!info.Has("firefoxTabs") || !(info["firefoxTabs"] is Array) || info["firefoxTabs"].Length = 0)
    needActive := (!info.Has("firefoxActiveUrl") || info["firefoxActiveUrl"] = "")
    if !(needTabs || needActive || (info.Has("url") && info["url"] = ""))
        return
    stateInfo := FirefoxExtractWindowState(sessionFile, info.Has("title") ? info["title"] : "")
    if !(stateInfo is Map)
        return
    info["firefoxTabs"] := FirefoxTabUrls(stateInfo["tabs"])
    info["firefoxActiveUrl"] := stateInfo["activeUrl"]
    if (!info.Has("url") || info["url"] = "")
        info["url"] := stateInfo["activeUrl"]
}

RegExEscape(s) {
    return RegExReplace(s, "([\\.\^\$\|\(\)\[\]\{\}\*\+\?])", "\\$1")
}

ResolveVscodeFolderUri(title) {
    try {
        label := ExtractVscodeFolderFromTitle(title)
        return ResolveVscodeFolderUriByLabel(label)
    }
    return ""
}

ResolveVscodeFolderUriByLabel(label) {
    if (label = "")
        return ""
    try {
        labelInfo := ParseVscodeLabel(label)
        storagePath := A_AppData "\Code\User\globalStorage\storage.json"
        if !FileExist(storagePath) {
            DebugLog("resolve vscode uri label='" label "' storage missing")
            return ""
        }
        raw := FileRead(storagePath, "UTF-8")
        textHit := ResolveVscodeFolderUriFromText(raw, label)
        if (textHit != "") {
            DebugLog("resolve vscode uri label='" label "' text-hit='" textHit "'")
            return textHit
        }
        data := JSON.parse(raw)
        if !data.Has("backupWorkspaces") {
            DebugLog("resolve vscode uri label='" label "' no backupWorkspaces")
            return ""
        }
        bw := data["backupWorkspaces"]
        if bw.Has("folders") && (bw["folders"] is Array) {
            exact := ""
            fallback := ""
            remoteFallback := ""
            for item in bw["folders"] {
                try folderUri := item["folderUri"]
                catch
                    continue
                remoteAuthority := ""
                try remoteAuthority := item["remoteAuthority"]
                display := VscodeUriDisplayLabel(folderUri, remoteAuthority)
                base := VscodeUriBaseName(folderUri)
                if (display = label)
                    return folderUri
                if (base = labelInfo["base"])
                    exact := folderUri
                else if (fallback = "" && base != "" && InStr(labelInfo["base"], base))
                    fallback := folderUri
                if (remoteAuthority != "" && VscodeRemoteAuthorityMatches(remoteAuthority, labelInfo)) {
                    if (base != "" && labelInfo["base"] != "" && base = labelInfo["base"])
                        return folderUri
                    if (remoteFallback = "")
                        remoteFallback := folderUri
                }
            }
            if (exact != "")
                return exact
            if (remoteFallback != "")
                return remoteFallback
            if (fallback != "")
                return fallback
        }
        DebugLog("resolve vscode uri label='" label "' missed")
        return ""
    }
    catch as e {
        DebugLog("resolve vscode uri label='" label "' error=" e.Message)
    }
    return ""
}

ResolveVscodeFolderUriFromText(raw, label) {
    if (raw = "" || label = "")
        return ""
    foundAny := false
    Loop Parse, raw, "`n", "`r" {
        line := A_LoopField
        if !InStr(line, '"folderUri"')
            continue
        colon := InStr(line, ':')
        if !colon
            continue
        q1 := InStr(line, '"', false, colon + 1)
        if !q1
            continue
        q2 := InStr(line, '"', false, q1 + 1)
        if !q2
            continue
        folderUri := SubStr(line, q1 + 1, q2 - q1 - 1)
        folderUri := StrReplace(folderUri, '\\/', '/')
        base := VscodeUriBaseName(folderUri)
        foundAny := true
        if (base = label || InStr(folderUri, label))
            return folderUri
    }
    if !foundAny
        DebugLog("resolve vscode uri text-scan found no folderUri lines for label='" label "'")
    return ""
}

VscodeUriForLaunch(folderUri) {
    if (folderUri = "")
        return ""
    return folderUri
}

VscodeUriIsLocal(folderUri) {
    return RegExMatch(folderUri, "^file:///", &m) ? true : false
}

VscodeUriIsContainer(folderUri) {
    return InStr(folderUri, "vscode-remote://attached-container%2B") = 1
}

VscodeLocalPathFromUri(folderUri) {
    if !VscodeUriIsLocal(folderUri)
        return ""
    decoded := UriDecode(folderUri)
    path := RegExReplace(decoded, "^file:///", "")
    path := StrReplace(path, "/", "\")
    return path
}

FirefoxLaunchCommand(info) {
    FirefoxEnsureSessionData(&info)
    exePath := info.Has("path") && info["path"] != "" ? info["path"] : "firefox.exe"
    profilePath := info.Has("firefoxProfilePath") ? info["firefoxProfilePath"] : ""
    urls := FirefoxUrlsForLaunch(info)
    running := ProcessExist("firefox.exe")
    cmd := '"' exePath '"'
    if !running {
        cmd .= ' -new-instance'
        if (profilePath != "")
            cmd .= ' -profile "' profilePath '"'
    }
    if (urls.Length = 0)
        return running ? (cmd ' -new-window about:blank') : cmd
    cmd .= ' -new-window "' urls[1] '"'
    return cmd
}

FirefoxPopulateExtraTabs(hwnd, info) {
    urls := FirefoxUrlsForLaunch(info)
    if (urls.Length <= 1)
        return true
    exePath := info.Has("path") && info["path"] != "" ? info["path"] : "firefox.exe"
    try {
        if hwnd {
            WinActivate "ahk_id " hwnd
            WinWaitActive "ahk_id " hwnd, , 1
        }
    }
    Loop urls.Length - 1 {
        url := urls[A_Index + 1]
        try {
            Run '"' exePath '" -new-tab "' url '"'
            Sleep 120
        } catch as e {
            DebugLog("firefox extra-tab error url='" url "' msg='" e.Message "'")
            return false
        }
    }
    DebugLog("firefox extra-tabs hwnd=" hwnd " added=" (urls.Length - 1))
    return true
}

; 从 VSCode 窗口标题提取工作区/文件夹路径
; VSCode 标题格式: "文件夹名 - Visual Studio Code"
; 或者: "项目名 · Workspace [workspace.code-workspace] - Visual Studio Code"
; 或者多级: "文件路径/名 - 项目名 - ... - Visual Studio Code"
ExtractVscodeFolderFromTitle(title) {
    if !title || title = ""
        return ""
    ; 去掉后缀 " - Visual Studio Code" 或 " - Insiders"
    suffix := " - Visual Studio Code"
    pos := InStr(title, suffix)
    if !pos {
        suffix := " - Visual Studio Code Insiders"
        pos := InStr(title, suffix)
    }
    if !pos
        return ""
    name := SubStr(title, 1, pos - 1)
    ; 多级标题中取最后一段（通常是文件夹名）
    ; 例如 "GCMP Token 消耗统计 - 2026-05-23 - tools" -> "tools"
    ; 用 " - " 分隔，取最后一段
    sep := " - "
    lastSep := 0
    loop {
        p := InStr(name, sep, false, lastSep + 1)
        if !p
            break
        lastSep := p
    }
    if lastSep > 0
        name := SubStr(name, lastSep + StrLen(sep))
    return Trim(name)
}

PromptLaunchMissing(missing) {
    if missing.Length = 0
        return false
    msg := "以下窗口未找到，是否启动？`n`n"
    for item in missing {
        info := item["info"]
        label := info["title"]
        if (info.Has("folder") && info["folder"] != "")
            label .= " · " info["folder"]
        msg .= "• " label " (" info["exe"] ")`n"
    }
    return MsgBox(msg, "启动缺失窗口", "YesNo") = "Yes"
}

;==============================================================
; WINDOW OPERATIONS
;==============================================================
WindowCapture(hwnd) {
    global g_Settings
    try {
        if !WinExist("ahk_id " hwnd)
            return ""
        title := WinGetTitle("ahk_id " hwnd)
        cls := WinGetClass("ahk_id " hwnd)
        exe := WinGetProcessName("ahk_id " hwnd)
        path := ""
        try path := WinGetProcessPath("ahk_id " hwnd)
        WinGetPos &x, &y, &w, &h, "ahk_id " hwnd
        state := WinGetMinMax("ahk_id " hwnd)
        info := Map(
            "title", title, "class", cls, "exe", exe, "path", path,
            "x", x, "y", y, "w", w, "h", h,
            "state", state,
            "monitor", MonitorAtPoint(x + w//2, y + h//2),
            "folder", "", "url", "", "vscodeUri", "", "firefoxProfile", "", "firefoxProfilePath", "", "firefoxSession", "", "firefoxActiveUrl", "", "firefoxTabs", [], "thumb", "")
        if (cls = "CabinetWClass" && exe = "explorer.exe")
            info["folder"] := WindowExplorerPath(hwnd)
        ; VSCode: 从窗口标题提取文件夹名作为匹配标识
        if (exe = "Code.exe") {
            folderName := ExtractVscodeFolderFromTitle(title)
            if folderName
                info["folder"] := folderName
            info["vscodeUri"] := ResolveVscodeFolderUri(title)
            DebugLog("capture vscode hwnd=" hwnd " title='" title "' folder='" info["folder"] "' uri='" info["vscodeUri"] "'")
        }
        ; 浏览器 URL 记录（Edge/Firefox）
        if (exe = "msedge.exe" || exe = "firefox.exe" || exe = "chrome.exe") {
            try {
                url := WindowBrowserUrl(hwnd)
                if url
                    info["url"] := url
                if (exe = "firefox.exe") {
                    sessionFile := FirefoxSessionFile()
                    if (sessionFile != "") {
                        info["firefoxSession"] := sessionFile
                        info["firefoxProfile"] := FirefoxProfileNameFromSessionFile(sessionFile)
                        info["firefoxProfilePath"] := FirefoxProfilePathFromSessionFile(sessionFile)
                        FirefoxEnsureSessionData(&info)
                    }
                }
                DebugLog("capture browser hwnd=" hwnd " exe=" exe " title='" title "' url='" info["url"] "'")
            }
        }
        if (g_Settings.Get("captureThumbnails", 1) && state != -1)
            info["thumb"] := WindowCaptureThumb(hwnd, 1920, 1080)
        return info
    } catch {
        return ""
    }
}

WindowResolve(info, hint, excludeSet := 0) {
    startTick := A_TickCount
    if (info.Has("exe") && info["exe"] = "firefox.exe")
        DebugLog("resolve enter firefox hint=" hint " exclude=" (excludeSet ? excludeSet.Count : 0))
    if hint {
        try {
            if WinExist("ahk_id " hint) && !WindowMatchesSticky(hint) {
                if (info["exe"] = "Code.exe" || info["exe"] = "msedge.exe" || info["exe"] = "firefox.exe" || info["exe"] = "chrome.exe")
                    DebugLog("resolve hint-hit hwnd=" hint " exe=" info["exe"] " title='" info["title"] "'")
                return hint
            }
        }
    }
    if (info["exe"] = "Code.exe" || info["exe"] = "msedge.exe" || info["exe"] = "firefox.exe" || info["exe"] = "chrome.exe")
        DebugLog("resolve fingerprint exe=" info["exe"] " title='" info["title"] "' folder='" info["folder"] "' uri='" (info.Has("vscodeUri") ? info["vscodeUri"] : "") "' url='" info["url"] "'")
    hwnd := WindowFindByFingerprint(info, excludeSet)
    if (info.Has("exe") && info["exe"] = "firefox.exe")
        DebugLog("resolve fingerprint done hwnd=" hwnd " ms=" (A_TickCount - startTick))
    if !hwnd && info.Has("exe") && info["exe"] = "firefox.exe"
        hwnd := FindNewWindowFromLaunchBaseline("firefox.exe", excludeSet)
    if (info.Has("exe") && info["exe"] = "firefox.exe")
        DebugLog("resolve exit firefox hwnd=" hwnd " totalMs=" (A_TickCount - startTick))
    return hwnd
}

WindowFindByFingerprint(info, excludeSet := 0) {
    skipExcluded(hwnd) => excludeSet && excludeSet.Has(hwnd)
    safeHwnd(hwnd) => WindowIsManageable(hwnd) && !WindowMatchesSticky(hwnd)

    ; ============================================================
    ; 精确匹配（按优先级从高到低）
    ; ============================================================

    ; --- 资源管理器: 按文件夹路径精确匹配 ---
    if (info["exe"] = "explorer.exe" && info["folder"] != "") {
        candidates := RestoreContextGet("explorerFolderWindows", info["folder"])
        if (candidates.Length = 0) {
            for hwnd in WinGetList("ahk_class CabinetWClass") {
                if skipExcluded(hwnd)
                    continue
                if (WindowExplorerPath(hwnd) = info["folder"])
                    return hwnd
            }
        }
        for hwnd in candidates {
            if skipExcluded(hwnd)
                continue
            return hwnd
        }
    }

    ; --- VSCode: 按窗口标题提取的文件夹名匹配 ---
    ; 遍历所有 Code.exe 主窗口，提取标题中的文件夹名做比对
    if (info["exe"] = "Code.exe" && info["folder"] != "") {
        candidates := RestoreContextGet("vscodeFolderWindows", info["folder"])
        if (candidates.Length = 0)
            candidates := RestoreContextExeWindows("Code.exe")
        for hwnd in candidates {
            if skipExcluded(hwnd)
                continue
            if !safeHwnd(hwnd)
                continue
            ttl := RestoreContextTitle(hwnd)
            f := ExtractVscodeFolderFromTitle(ttl)
            if (f = "" || f != info["folder"])
                continue
            DebugLog("match vscode hwnd=" hwnd " folder='" info["folder"] "' title='" ttl "'")
            return hwnd
        }
        DebugLog("match vscode missed folder='" info["folder"] "'")
    }

    ; --- Firefox: 按标签页集合包含关系匹配 ---
    if (info["exe"] = "firefox.exe") {
        ffStart := A_TickCount
        candidateCount := 0
        for hwnd in RestoreContextExeWindows("firefox.exe") {
            candidateCount += 1
            if skipExcluded(hwnd)
                continue
            if !safeHwnd(hwnd)
                continue
            DebugLog("firefox candidate hwnd=" hwnd " idx=" candidateCount)
            if FirefoxTabsSupersetMatch(hwnd, info) {
                DebugLog("match firefox tabs hwnd=" hwnd " title='" WinGetTitle("ahk_id " hwnd) "'")
                return hwnd
            }
        }
        DebugLog("firefox candidates done count=" candidateCount " ms=" (A_TickCount - ffStart))
    }

    ; --- 浏览器: 按 URL 精确匹配 ---
    if (info["url"] != "" && info["exe"] != "firefox.exe") {
        for hwnd in RestoreContextExeWindows(info["exe"]) {
            if skipExcluded(hwnd)
                continue
            if !safeHwnd(hwnd)
                continue
            url := WindowBrowserUrl(hwnd)
            if (url != "" && url = info["url"]) {
                DebugLog("match browser hwnd=" hwnd " exe=" info["exe"] " url='" url "'")
                return hwnd
            }
        }
        DebugLog("match browser missed exe=" info["exe"] " wanted='" info["url"] "'")
    }

    ; ============================================================
    ; 模糊匹配（class + exe + 标题）
    ; ============================================================
    if (info["class"] != "" && info["exe"] != "") {
        q := "ahk_class " info["class"] " ahk_exe " info["exe"]
        filtered := RestoreContextGet("titleWindows", RestoreContextKey(info["class"], info["exe"], info["title"]))
        if (filtered.Length = 0) {
            for hwnd in WinGetList(q) {
                if !safeHwnd(hwnd)
                    continue
                try {
                    if (WinGetTitle("ahk_id " hwnd) = info["title"])
                        filtered.Push(hwnd)
                }
            }
        }
        ; 唯一标题匹配 → 直接返回（WeChat/QQ 等单例）
        if (filtered.Length = 1)
            return filtered[1]
        ; 多个同标题 → 排除其他工作区的
        if (filtered.Length > 1) {
            for hwnd in filtered {
                if skipExcluded(hwnd)
                    continue
                return hwnd
            }
        }

        ; VSCode / browser windows must NOT fall back to arbitrary same-exe
        ; windows. If there was no exact folder/title/URL match, treat them as
        ; missing so restore can offer launching a new window instead of
        ; hijacking an unrelated existing one.
        if (info["exe"] = "Code.exe" || info["exe"] = "msedge.exe" || info["exe"] = "firefox.exe" || info["exe"] = "chrome.exe") {
            DebugLog("no exact match for strict app exe=" info["exe"] " title='" info["title"] "' folder='" info["folder"] "' uri='" (info.Has("vscodeUri") ? info["vscodeUri"] : "") "' url='" info["url"] "'")
            return 0
        }

        ; class+exe 退而求其次（不做标题匹配，只排重）
        candidates := RestoreContextGet("classExeWindows", RestoreContextKey(info["class"], info["exe"]))
        if (candidates.Length = 0)
            candidates := WinGetList(q)
        for hwnd in candidates {
            if skipExcluded(hwnd)
                continue
            if !safeHwnd(hwnd)
                continue
            if (info["exe"] = "Code.exe" || info["exe"] = "msedge.exe" || info["exe"] = "firefox.exe" || info["exe"] = "chrome.exe")
                DebugLog("fallback class+exe hwnd=" hwnd " exe=" info["exe"] " title='" WinGetTitle("ahk_id " hwnd) "'")
            return hwnd
        }
    }

    ; --- 最后手段: 仅按 exe 匹配 ---
    if (info["exe"] != "") {
        if (info["exe"] = "Code.exe" || info["exe"] = "msedge.exe" || info["exe"] = "firefox.exe" || info["exe"] = "chrome.exe")
            return 0
        for hwnd in WinGetList("ahk_exe " info["exe"]) {
            if skipExcluded(hwnd)
                continue
            if !safeHwnd(hwnd)
                continue
            if (info["exe"] = "Code.exe" || info["exe"] = "msedge.exe" || info["exe"] = "firefox.exe" || info["exe"] = "chrome.exe")
                DebugLog("fallback exe hwnd=" hwnd " exe=" info["exe"] " title='" WinGetTitle("ahk_id " hwnd) "'")
            return hwnd
        }
    }
    return 0
}

WindowLaunch(info, workspaceId := "") {
    global g_LaunchGracePids, g_LaunchGraceSpecs
    MarkLaunchGrace(exe, pid := 0, before := 0, ownerWorkspaceId := "") {
        if !g_LaunchGraceSpecs.Has(exe)
            g_LaunchGraceSpecs[exe] := Map()
        spec := g_LaunchGraceSpecs[exe]
        spec["expires"] := A_TickCount + 15000
        spec["before"] := (before is Map) ? before : LaunchGraceBaseline(exe)
        spec["workspaceId"] := ownerWorkspaceId
        if pid {
            g_LaunchGracePids[pid] := Map("expires", A_TickCount + 15000, "workspaceId", ownerWorkspaceId)
        }
    }
    try {
        launchExe := info.Has("exe") ? info["exe"] : ""
        before := (launchExe != "") ? LaunchGraceBaseline(launchExe) : 0
        if (info["exe"] = "explorer.exe" && info["folder"] != "") {
            Run 'explorer.exe "' info["folder"] '"', , , &pid
            MarkLaunchGrace("explorer.exe", pid, before, workspaceId)
            return pid
        }
        if (info["exe"] = "Code.exe") {
            vscodeUri := info.Has("vscodeUri") ? info["vscodeUri"] : ""
            if (vscodeUri = "" && info.Has("title"))
                vscodeUri := ResolveVscodeFolderUri(info["title"])
            if (vscodeUri = "" && info.Has("folder") && info["folder"] != "")
                vscodeUri := ResolveVscodeFolderUriByLabel(info["folder"])
            if (vscodeUri != "")
                info["vscodeUri"] := vscodeUri
            DebugLog("launch vscode title='" info["title"] "' folder='" info["folder"] "' uri='" vscodeUri "'")
        }
        if (info["exe"] = "Code.exe" && info.Has("vscodeUri") && info["vscodeUri"] != "") {
            launchUri := VscodeUriForLaunch(info["vscodeUri"])
            if VscodeUriIsContainer(launchUri) {
                cmd := (info["path"] != "") ? ('"' info["path"] '" --new-window') : 'code --new-window'
            } else if VscodeUriIsLocal(launchUri) {
                localPath := VscodeLocalPathFromUri(launchUri)
                cmd := (info["path"] != "")
                    ? ('"' info["path"] '" --new-window "' localPath '"')
                    : ('code --new-window "' localPath '"')
            } else {
                cmd := (info["path"] != "")
                    ? ('"' info["path"] '" --new-window --folder-uri "' launchUri '"')
                    : ('code --new-window --folder-uri "' launchUri '"')
            }
            DebugLog("launch vscode cmd=" cmd)
            Run cmd, , , &pid
            MarkLaunchGrace("Code.exe", pid, before, workspaceId)
            return pid
        }
        if (info["exe"] = "firefox.exe") {
            cmd := FirefoxLaunchCommand(info)
            DebugLog("launch firefox cmd=" cmd)
            Run cmd, , , &pid
            MarkLaunchGrace("firefox.exe", pid, before, workspaceId)
            return pid
        }
        if (info["path"] != "")
            Run info["path"], , , &pid
        else
            Run info["exe"], , , &pid
        MarkLaunchGrace(info["exe"], pid, before, workspaceId)
        return pid
    } catch {
        return 0
    }
}

LaunchGraceBaseline(exe) {
    baseline := Map()
    for hwnd in WinGetList("ahk_exe " exe)
        baseline[hwnd] := true
    return baseline
}

LaunchGracePruneExpired() {
    global g_LaunchGracePids, g_LaunchGraceSpecs
    now := A_TickCount
    expired := []
    for pid, spec in g_LaunchGracePids {
        if !(spec is Map) || !spec.Has("expires") || spec["expires"] <= now
            expired.Push(pid)
    }
    for pid in expired
        g_LaunchGracePids.Delete(pid)
    expiredSpecs := []
    for exe, spec in g_LaunchGraceSpecs {
        if !(spec is Map) || !spec.Has("expires") || spec["expires"] <= now
            expiredSpecs.Push(exe)
    }
    for exe in expiredSpecs
        g_LaunchGraceSpecs.Delete(exe)
}

LaunchGraceOwnsActiveWorkspace(exe) {
    global g_LaunchGraceSpecs, g_ActiveWs
    if !g_LaunchGraceSpecs.Has(exe)
        return false
    spec := g_LaunchGraceSpecs[exe]
    return (spec is Map) && spec.Has("workspaceId") && spec["workspaceId"] = g_ActiveWs
}

LaunchGraceOwnsActiveWorkspaceByPid(pid) {
    global g_LaunchGracePids, g_ActiveWs
    if !g_LaunchGracePids.Has(pid)
        return false
    spec := g_LaunchGracePids[pid]
    return (spec is Map) && spec.Has("workspaceId") && spec["workspaceId"] = g_ActiveWs
}

LaunchGraceProtectsHwnd(exe, hwnd) {
    global g_LaunchGraceSpecs
    if !g_LaunchGraceSpecs.Has(exe)
        return false
    spec := g_LaunchGraceSpecs[exe]
    if !(spec is Map) || !spec.Has("before")
        return false
    before := spec["before"]
    return !(before is Map) || !before.Has(hwnd)
}

FindNewWindowFromLaunchBaseline(exe, excludeSet := 0) {
    global g_LaunchGraceSpecs
    if (exe = "" || !g_LaunchGraceSpecs.Has(exe))
        return 0
    spec := g_LaunchGraceSpecs[exe]
    if !(spec is Map) || !spec.Has("before")
        return 0
    before := spec["before"]
    for hwnd in WinGetList("ahk_exe " exe) {
        if excludeSet && excludeSet.Has(hwnd)
            continue
        if (before is Map) && before.Has(hwnd)
            continue
        if !WindowIsManageable(hwnd)
            continue
        if WindowMatchesBlacklist(hwnd)
            continue
        if WindowMatchesSticky(hwnd)
            continue
        return hwnd
    }
    return 0
}

WindowReposition(hwnd, info) {
    try {
        startTick := A_TickCount
        x := info["x"], y := info["y"], w := info["w"], h := info["h"]
        state := info["state"]
        if !PosOnAnyMonitor(x, y, w, h) {
            MonitorGetWorkArea 1, &l, &t, &r, &b
            x := l + 80, y := t + 80
            w := Min(w, r - l - 160)
            h := Min(h, b - t - 160)
        }
        curState := WinGetMinMax("ahk_id " hwnd)
        DebugLog("reposition enter hwnd=" hwnd " exe='" info.Get("exe", "") "' state=" state " curState=" curState)
        ; Already in target minimized state — no work, no flicker.
        if (state = -1 && curState = -1)
            return true
        ; If target is minimized but window is currently shown, set normal
        ; position first via SetWindowPos (no visible move), then minimize.
        if (state = -1) {
            try DllCall("user32\SetWindowPos",
                "ptr", hwnd, "ptr", 0,
                "int", x, "int", y, "int", w, "int", h,
                "uint", 0x0014 | 0x0010)  ; SWP_NOZORDER|SWP_NOACTIVATE|SWP_NOREDRAW
            WinMinimize "ahk_id " hwnd
            return true
        }
        ; For maximized windows, do not move to saved/safe rectangles.
        ; Windows preserves maximized state across minimize/restore; if not,
        ; a single WinMaximize is enough. Moving first is what caused the
        ; “maximized then shrinks to safe size” regression.
        if (state = 1) {
            if (curState = -1)
                WinRestore "ahk_id " hwnd
            if (WinGetMinMax("ahk_id " hwnd) != 1)
                WinMaximize "ahk_id " hwnd
            DebugLog("reposition maximize-only hwnd=" hwnd " totalMs=" (A_TickCount - startTick))
            return true
        }
        ; Restore first if currently min/max so WinMove can size correctly
        if (curState != 0)
            WinRestore "ahk_id " hwnd
        WinMove x, y, w, h, "ahk_id " hwnd
        DebugLog("reposition after move hwnd=" hwnd " ms=" (A_TickCount - startTick))
        DebugLog("reposition exit hwnd=" hwnd " totalMs=" (A_TickCount - startTick))
        return true
    } catch {
        DebugLog("reposition error hwnd=" hwnd)
        return false
    }
}

WindowIsManageable(hwnd) {
    global g_EdgePid
    try {
        if !DllCall("IsWindowVisible", "ptr", hwnd)
            return false
        title := WinGetTitle("ahk_id " hwnd)
        if (title = "")
            return false
        cls := WinGetClass("ahk_id " hwnd)
        static skip := Map(
            "Shell_TrayWnd", 1, "Shell_SecondaryTrayWnd", 1,
            "Progman", 1, "WorkerW", 1,
            "Windows.UI.Core.CoreWindow", 1,
            "MSCTFIME UI", 1, "Default IME", 1,
            "TaskListThumbnailWnd", 1)
        if skip.Has(cls)
            return false
        ; Exclude OUR OWN manager UI window (Edge --app launched by us).
        ; Primary check: PID. Backup check: known titles set by index.html.
        if (g_EdgePid != 0) {
            try {
                pid := WinGetPID("ahk_id " hwnd)
                if (pid = g_EdgePid)
                    return false
            }
        }
        try {
            exe := WinGetProcessName("ahk_id " hwnd)
            if (exe = "msedge.exe" && (title = "WorkspaceTool" || title = "工作区工具"))
                return false
        }
        cloaked := 0
        try DllCall("dwmapi\DwmGetWindowAttribute",
            "ptr", hwnd, "uint", 14, "int*", &cloaked, "uint", 4)
        if cloaked
            return false
        ex := WinGetExStyle("ahk_id " hwnd)
        if (ex & 0x80)
            return false
        return true
    } catch {
        return false
    }
}

WindowMatchesBlacklist(hwnd) {
    global g_Rules
    bl := g_Rules.Get("blacklist", [])
    if bl.Length = 0
        return false
    for pat in bl {
        if (pat = "")
            continue
        try {
            if WinExist(pat " ahk_id " hwnd)
                return true
        }
    }
    return false
}

WindowMatchesSticky(hwnd) {
    global g_Settings
    if !g_Settings.Get("stickyEnabled", 0)
        return false
    patterns := g_Settings.Get("stickyPatterns", [])
    if patterns.Length = 0
        return false
    for pat in patterns {
        if (pat = "")
            continue
        try {
            if WinExist(pat " ahk_id " hwnd)
                return true
        }
    }
    return false
}

WindowExplorerPath(hwnd) {
    try {
        for w in ComObject("Shell.Application").Windows {
            try {
                if (w.HWND = hwnd)
                    return w.Document.Folder.Self.Path
            }
        }
    }
    return ""
}

WindowBrowserUrl(hwnd) {
    ; 这版先禁用不稳定的 ACC 抓取逻辑，避免运行期直接崩掉。
    ; Firefox 的真实标签页恢复后续改为 session 文件方案实现。
    ; Chromium/Firefox 当前拿不到可靠 URL 时返回空字符串即可。
    DebugLog("browser-url skipped hwnd=" hwnd " title='" WinGetTitle("ahk_id " hwnd) "'")
    return ""
}

;-- Thumbnail capture (PrintWindow + GDI+ -> JPEG file on disk) ----
;   Returns a short id used as the filename: ./thumbs/<id>.jpg
;   workspaces.json stores only the id, not the binary, so JSON stays small.

ThumbsDir() {
    dir := A_ScriptDir "\thumbs"
    if !DirExist(dir)
        DirCreate dir
    return dir
}

NewThumbId() {
    return Format("{:x}", A_TickCount) "_" Format("{:08x}", Random(0, 0xFFFFFFFF))
}

WindowCaptureThumb(hwnd, maxW := 1920, maxH := 1080) {
    if !GdipEnsure()
        return ""
    rc := Buffer(16, 0)
    if !DllCall("GetClientRect", "ptr", hwnd, "ptr", rc)
        return ""
    srcW := NumGet(rc, 8, "int"), srcH := NumGet(rc, 12, "int")
    if (srcW < 10 || srcH < 10)
        return ""
    hdcScr := DllCall("GetDC", "ptr", 0, "ptr")
    hdcMem := DllCall("CreateCompatibleDC", "ptr", hdcScr, "ptr")
    hbm := DllCall("CreateCompatibleBitmap", "ptr", hdcScr, "int", srcW, "int", srcH, "ptr")
    DllCall("ReleaseDC", "ptr", 0, "ptr", hdcScr)
    oldBm := DllCall("SelectObject", "ptr", hdcMem, "ptr", hbm, "ptr")
    ok := DllCall("PrintWindow", "ptr", hwnd, "ptr", hdcMem, "uint", 2, "int")
    DllCall("SelectObject", "ptr", hdcMem, "ptr", oldBm, "ptr")
    DllCall("DeleteDC", "ptr", hdcMem)
    if !ok {
        DllCall("DeleteObject", "ptr", hbm)
        return ""
    }
    ratio := Min(maxW / srcW, maxH / srcH, 1.0)
    dstW := Round(srcW * ratio), dstH := Round(srcH * ratio)
    if (dstW < 10 || dstH < 10) {
        DllCall("DeleteObject", "ptr", hbm)
        return ""
    }
    bmpFull := 0
    DllCall("gdiplus\GdipCreateBitmapFromHBITMAP", "ptr", hbm, "ptr", 0, "ptr*", &bmpFull)
    DllCall("DeleteObject", "ptr", hbm)
    if !bmpFull
        return ""
    thumb := 0
    DllCall("gdiplus\GdipGetImageThumbnail", "ptr", bmpFull,
        "uint", dstW, "uint", dstH, "ptr*", &thumb, "ptr", 0, "ptr", 0)
    DllCall("gdiplus\GdipDisposeImage", "ptr", bmpFull)
    if !thumb
        return ""

    ; JPEG encoder + quality=85
    clsid := Buffer(16, 0)
    DllCall("ole32\CLSIDFromString", "wstr", "{557CF401-1A04-11D3-9A73-0000F81EF32E}", "ptr", clsid)
    ptrSize := A_PtrSize
    guidOffset := ptrSize
    numValuesOffset := guidOffset + 16
    typeOffset := numValuesOffset + 4
    valueOffset := typeOffset + 4
    totalSize := valueOffset + ptrSize
    encParams := Buffer(totalSize, 0)
    NumPut("uint", 1, encParams, 0)
    DllCall("ole32\CLSIDFromString",
        "wstr", "{1D5BE4B5-FA4A-452D-9CDD-5DB35105E7EB}",
        "ptr", encParams.Ptr + guidOffset)
    NumPut("uint", 1, encParams, numValuesOffset)
    NumPut("uint", 4, encParams, typeOffset)
    qualityBuf := Buffer(4, 0)
    NumPut("uint", 85, qualityBuf, 0)
    NumPut("ptr", qualityBuf.Ptr, encParams, valueOffset)

    thumbId := NewThumbId()
    path := ThumbsDir() "\" thumbId ".jpg"
    saveResult := DllCall("gdiplus\GdipSaveImageToFile",
        "ptr", thumb, "wstr", path, "ptr", clsid, "ptr", encParams, "uint")
    DllCall("gdiplus\GdipDisposeImage", "ptr", thumb)
    if (saveResult != 0)
        return ""
    return thumbId
}

Base64ToFile(b64, path) {
    flags := 0x1     ; CRYPT_STRING_BASE64
    binSize := 0
    if !DllCall("crypt32\CryptStringToBinaryW",
        "wstr", b64, "uint", 0, "uint", flags,
        "ptr", 0, "uint*", &binSize, "ptr", 0, "ptr", 0)
        return false
    binBuf := Buffer(binSize, 0)
    if !DllCall("crypt32\CryptStringToBinaryW",
        "wstr", b64, "uint", 0, "uint", flags,
        "ptr", binBuf, "uint*", &binSize, "ptr", 0, "ptr", 0)
        return false
    try {
        f := FileOpen(path, "w")
        if !f
            return false
        f.RawWrite(binBuf, binSize)
        f.Close()
        return true
    } catch {
        return false
    }
}

GdipEnsure() {
    static token := 0
    if token
        return token
    if !DllCall("LoadLibrary", "str", "gdiplus", "ptr")
        return 0
    si := Buffer(24, 0)
    NumPut("uint", 1, si, 0)
    t := 0
    if DllCall("gdiplus\GdiplusStartup", "ptr*", &t, "ptr", si, "ptr", 0) != 0
        return 0
    token := t
    return token
}

MonitorAtPoint(x, y) {
    Loop MonitorGetCount() {
        MonitorGet A_Index, &l, &t, &r, &b
        if (x >= l && x < r && y >= t && y < b)
            return A_Index
    }
    return 1
}

PosOnAnyMonitor(x, y, w, h) {
    cx := x + w//2, cy := y + h//2
    Loop MonitorGetCount() {
        MonitorGetWorkArea A_Index, &l, &t, &r, &b
        if (cx >= l && cx < r && cy >= t && cy < b)
            return true
    }
    return false
}

;==============================================================
; HOTKEYS — dynamic binding from settings + workspace data
;==============================================================
HotkeysRebindAll() {
    global g_BoundHotkeys
    ; Unbind everything we previously bound
    for ahkKey, _ in g_BoundHotkeys {
        try Hotkey ahkKey, "Off"
    }
    g_BoundHotkeys := Map()

    ; Global hotkeys from settings
    Bind(g_Settings.Get("managerHotkey", ""),       (*) => ActionOpenManager())
    Bind(g_Settings.Get("panelHotkey", ""),         (*) => ActionOpenManager())
    Bind(g_Settings.Get("reloadHotkey", ""),        (*) => ActionReloadAll())
    Bind(g_Settings.Get("undoHotkey", ""),          (*) => UndoLastSwitch())
    Bind(g_Settings.Get("prevWorkspaceHotkey", ""), (*) => ActionWorkspacePage(-1))
    Bind(g_Settings.Get("nextWorkspaceHotkey", ""), (*) => ActionWorkspacePage(1))

    ; Per-workspace hotkeys
    for ws in g_Workspaces {
        id := ws["id"]
        if ws.Has("hotkey") && ws["hotkey"] != ""
            Bind(ws["hotkey"], ((wid) => (*) => WorkspaceRestore(wid))(id))
        if ws.Has("saveHotkey") && ws["saveHotkey"] != ""
            Bind(ws["saveHotkey"], ((wid) => (*) => WorkspaceSnapshot(wid))(id))
    }
}

Bind(humanKey, fn) {
    global g_BoundHotkeys
    if (humanKey = "")
        return
    ahkKey := HotkeyToAhk(humanKey)
    if (ahkKey = "")
        return
    try {
        Hotkey ahkKey, fn, "On"
        g_BoundHotkeys[ahkKey] := true
    } catch as e {
        ; ignore conflicts
    }
}

; Parse "Ctrl+Alt+XButton2" -> "^!XButton2"
HotkeyToAhk(s) {
    if (s = "")
        return ""
    parts := StrSplit(s, "+")
    mods := ""
    key := ""
    for p in parts {
        p := Trim(p)
        if (p = "")
            continue
        lo := StrLower(p)
        if (lo = "ctrl") {
            mods .= "^"
        } else if (lo = "alt") {
            mods .= "!"
        } else if (lo = "shift") {
            mods .= "+"
        } else if (lo = "win" || lo = "meta") {
            mods .= "#"
        } else {
            key := p
        }
    }
    if (key = "")
        return ""
    if (mods = "" && (key = "XButton1" || key = "XButton2"))
        return "*" . key
    return mods . key
}

HotkeyToHuman(ahkKey) {
    if (ahkKey = "")
        return "(none)"
    out := []
    s := ahkKey
    while (s != "") {
        c := SubStr(s, 1, 1)
        if (c = "^") {
            out.Push("Ctrl")
            s := SubStr(s, 2)
        } else if (c = "!") {
            out.Push("Alt")
            s := SubStr(s, 2)
        } else if (c = "+") {
            out.Push("Shift")
            s := SubStr(s, 2)
        } else if (c = "#") {
            out.Push("Win")
            s := SubStr(s, 2)
        } else {
            out.Push(s)
            s := ""
        }
    }
    r := ""
    for i, p in out
        r .= (i > 1 ? "+" : "") . p
    return r
}

;==============================================================
; ACTIONS
;==============================================================
ActionOpenManager() {
    global g_EdgePid, g_HttpPort
    ; If we still have a live edge window, activate it
    if g_EdgePid {
        try {
            if WinExist("ahk_pid " g_EdgePid) {
                WinActivate "ahk_pid " g_EdgePid
                return
            }
        }
        g_EdgePid := 0
    }
    url := "http://127.0.0.1:" g_HttpPort "/"
    dataDir := A_ScriptDir "\.edge_profile"
    edgeExe := FindEdge()
    if !edgeExe {
        Run url
        return
    }
    cmd := '"' edgeExe '" --app=' url ' --user-data-dir="' dataDir '" --window-size=1200,720'
    try {
        Run cmd, , , &pid
        g_EdgePid := pid
    } catch {
        Run url
    }
}

FindEdge() {
    static cached := ""
    if cached != ""
        return cached
    paths := [
        "C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe",
        "C:\Program Files\Microsoft\Edge\Application\msedge.exe",
        A_ProgramFiles "\Microsoft\Edge\Application\msedge.exe"
    ]
    for p in paths
        if FileExist(p) {
            cached := p
            return p
        }
    return ""
}

ActionReloadAll() {
    SettingsLoad()
    WorkspacesLoad()
    RulesLoad()
    HotkeysRebindAll()
    TrayBadgeUpdate()
    TrayTip("Reloaded", APP_NAME, 0x10)
}

; Cycle through workspaces. delta = +1 (next) or -1 (prev). Wraps around.
ActionWorkspacePage(delta) {
    global g_Workspaces, g_ActiveWs
    n := g_Workspaces.Length
    if (n = 0)
        return
    enabledIdx := []
    for i, ws in g_Workspaces {
        if !ws.Has("enabled") || ws["enabled"]
            enabledIdx.Push(i)
    }
    if (enabledIdx.Length = 0)
        return
    curPos := 0
    if (g_ActiveWs != "") {
        for pos, idx in enabledIdx {
            if (g_Workspaces[idx]["id"] = g_ActiveWs) {
                curPos := pos
                break
            }
        }
    }
    if (curPos = 0)
        curPos := delta > 0 ? 0 : 1
    newPos := Mod(curPos - 1 + delta + enabledIdx.Length, enabledIdx.Length) + 1
    WorkspaceRestore(g_Workspaces[enabledIdx[newPos]]["id"])
}

;==============================================================
; TRAY + BADGE
;==============================================================
TraySetup() {
    A_IconTip := APP_NAME " v" APP_VERSION
    m := A_TrayMenu
    m.Delete()
    m.Add("Open Manager", (*) => ActionOpenManager())
    m.Add()
    m.Add("Reload", (*) => ActionReloadAll())
    m.Add()
    m.Add("Exit", (*) => ExitApp())
    m.Default := "Open Manager"
}

TrayBadgeUpdate() {
    global g_Settings, g_ActiveWs, APP_NAME, APP_VERSION
    adminTag := A_IsAdmin ? " [admin]" : ""
    if !g_Settings["trayBadge"] {
        A_IconTip := APP_NAME " v" APP_VERSION adminTag
        return
    }
    ws := g_ActiveWs != "" ? WorkspaceFind(g_ActiveWs) : 0
    if ws
        A_IconTip := APP_NAME adminTag " · " ws["icon"] " " ws["name"]
    else
        A_IconTip := APP_NAME adminTag " · (no active workspace)"
}

;==============================================================
; SWITCH TOAST
;==============================================================
ToastShow(text) {
    static gui := ""
    try {
        if gui {
            try {
                gui.Destroy()
            } catch {
            }
        }
        gui := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x80000 -DPIScale", "Toast")
        gui.BackColor := "1E1E1E"
        gui.MarginX := 24, gui.MarginY := 14
        gui.SetFont("s18 cWhite", "Segoe UI Variable")
        gui.AddText("Center", text)
        gui.Show("NoActivate Hide")
        WinSetTransparent 220, gui.Hwnd
        ; Position center of primary monitor
        MonitorGetWorkArea 1, &l, &t, &r, &b
        gui.GetPos(, , &gw, &gh)
        x := l + (r - l - gw) // 2
        y := t + (b - t) // 3
        gui.Show("x" x " y" y " NoActivate")
        SetTimer(((g) => (*) => (g.Destroy()))(gui), -800)
    } catch {
    }
}

;==============================================================
; HTTP SERVER (raw winsock, localhost-only, single-threaded poll)
;==============================================================
RegisterRoutes() {
    Route("GET", "/api/state",                        ApiState)
    Route("GET", "/api/workspaces",                   ApiWorkspacesList)
    Route("POST", "/api/workspaces",                  ApiWorkspaceCreate)
    Route("PUT", "/api/workspaces/:id",               ApiWorkspaceUpdate)
    Route("DELETE", "/api/workspaces/:id",            ApiWorkspaceDelete)
    Route("POST", "/api/workspaces/:id/snapshot",     ApiWorkspaceSnapshot)
    Route("POST", "/api/workspaces/:id/restore",      ApiWorkspaceRestore)
    Route("POST", "/api/workspaces/:id/move-window",  ApiMoveWindow)
    Route("POST", "/api/workspaces/:id/capture-window", ApiCaptureWindow)
    Route("DELETE", "/api/workspaces/:id/windows/:idx", ApiRemoveWindow)
    Route("PUT", "/api/workspaces/order",             ApiWorkspaceReorder)
    Route("GET", "/api/settings",                     ApiSettings)
    Route("PUT", "/api/settings",                     ApiSettingsUpdate)
    Route("GET", "/api/rules",                        ApiRules)
    Route("PUT", "/api/rules",                        ApiRulesUpdate)
    Route("GET", "/api/windows/live",                 ApiLiveWindows)
    Route("GET", "/api/export",                       ApiExport)
    Route("POST", "/api/import",                      ApiImport)
}

Route(method, path, fn) {
    global g_Routes
    g_Routes[method " " path] := fn
}

HttpServerStart() {
    global g_HttpSock, g_HttpPort, g_HttpRunning
    wsa := Buffer(408, 0)
    if DllCall("ws2_32\WSAStartup", "ushort", 0x202, "ptr", wsa) != 0
        throw Error("WSAStartup failed")
    g_HttpSock := DllCall("ws2_32\socket", "int", 2, "int", 1, "int", 6, "ptr")
    if (g_HttpSock = -1)
        throw Error("socket() failed")
    opt := Buffer(4, 0)
    NumPut("int", 1, opt, 0)
    DllCall("ws2_32\setsockopt", "ptr", g_HttpSock, "int", 0xFFFF, "int", 4, "ptr", opt, "int", 4)
    addr := Buffer(16, 0)
    NumPut("ushort", 2, addr, 0)
    NumPut("ushort", 0, addr, 2)
    NumPut("uint", 0x0100007F, addr, 4)
    if DllCall("ws2_32\bind", "ptr", g_HttpSock, "ptr", addr, "int", 16) != 0
        throw Error("bind() failed")
    alen := 16
    DllCall("ws2_32\getsockname", "ptr", g_HttpSock, "ptr", addr, "int*", &alen)
    hi := NumGet(addr, 2, "UChar")
    lo := NumGet(addr, 3, "UChar")
    g_HttpPort := (hi << 8) | lo
    mode := Buffer(4, 0)
    NumPut("uint", 1, mode, 0)
    DllCall("ws2_32\ioctlsocket", "ptr", g_HttpSock, "int", 0x8004667E, "ptr", mode)
    if DllCall("ws2_32\listen", "ptr", g_HttpSock, "int", 16) != 0
        throw Error("listen() failed")
    g_HttpRunning := true
    SetTimer(HttpAcceptLoop, 60)
}

HttpServerStop() {
    global g_HttpSock, g_HttpRunning
    g_HttpRunning := false
    SetTimer(HttpAcceptLoop, 0)
    if g_HttpSock {
        try DllCall("ws2_32\closesocket", "ptr", g_HttpSock)
        g_HttpSock := 0
    }
    try DllCall("ws2_32\WSACleanup")
}

HttpAcceptLoop(*) {
    global g_HttpSock, g_HttpRunning
    if !g_HttpRunning
        return
    Loop 8 {  ; drain up to 8 per tick
        addr := Buffer(16, 0)
        alen := 16
        client := DllCall("ws2_32\accept", "ptr", g_HttpSock, "ptr", addr, "int*", &alen, "ptr")
        if (client = -1)
            return
        try HttpServeOne(client)
        try DllCall("ws2_32\closesocket", "ptr", client)
    }
}

HttpServeOne(client) {
    ; Switch client to blocking with short recv timeout
    mode := Buffer(4, 0)
    NumPut("uint", 0, mode, 0)
    DllCall("ws2_32\ioctlsocket", "ptr", client, "int", 0x8004667E, "ptr", mode)
    tv := Buffer(4, 0)
    NumPut("int", 800, tv, 0)
    DllCall("ws2_32\setsockopt", "ptr", client, "int", 0xFFFF, "int", 0x1006, "ptr", tv, "int", 4)

    recvBuf := Buffer(8192, 0)
    request := ""
    headerEnd := 0
    contentLength := 0
    Loop {
        n := DllCall("ws2_32\recv", "ptr", client, "ptr", recvBuf, "int", 8192, "int", 0)
        if (n <= 0)
            break
        chunk := StrGet(recvBuf, n, "UTF-8")
        request .= chunk
        if !headerEnd {
            p := InStr(request, "`r`n`r`n")
            if p {
                headerEnd := p + 4  ; 1-based position of first body byte
                if RegExMatch(request, "i)Content-Length:\s*(\d+)", &m)
                    contentLength := Integer(m[1])
            }
        }
        if headerEnd {
            bodyHave := StrLen(request) - headerEnd + 1
            if (bodyHave >= contentLength)
                break
        }
        if (StrLen(request) > 2097152)
            break
    }
    if !headerEnd {
        HttpRespond(client, 400, "text/plain", "Bad Request")
        return
    }

    firstLine := SubStr(request, 1, InStr(request, "`r`n") - 1)
    parts := StrSplit(firstLine, " ")
    if (parts.Length < 2) {
        HttpRespond(client, 400, "text/plain", "Bad Request")
        return
    }
    method := parts[1]
    url := parts[2]
    qpos := InStr(url, "?")
    path := qpos ? SubStr(url, 1, qpos - 1) : url
    query := qpos ? SubStr(url, qpos + 1) : ""
    body := SubStr(request, headerEnd)

    response := HttpDispatch(method, path, query, body)
    binSize := response.HasOwnProp("binSize") ? response.binSize : -1
    HttpRespond(client, response.status, response.contentType, response.body, binSize)
}

HttpDispatch(method, path, query, body) {
    ; Static files
    if (method = "GET" && (path = "/" || path = "/index.html"))
        return HttpStatic(D_UI "\index.html", "text/html; charset=utf-8")
    if (method = "GET" && path = "/app.css")
        return HttpStatic(D_UI "\app.css", "text/css; charset=utf-8")
    if (method = "GET" && path = "/app.js")
        return HttpStatic(D_UI "\app.js", "application/javascript; charset=utf-8")
    if (method = "GET" && path = "/favicon.ico")
        return {status: 204, contentType: "image/x-icon", body: ""}
    ; Thumbnail files: GET /thumbs/<id>.jpg
    if (method = "GET" && SubStr(path, 1, 8) = "/thumbs/") {
        fname := SubStr(path, 9)
        if (fname = "" || InStr(fname, "..") || InStr(fname, "/") || InStr(fname, "\"))
            return {status: 400, contentType: "text/plain", body: "bad name"}
        return HttpStaticBinary(A_ScriptDir "\thumbs\" fname, "image/jpeg")
    }

    ; Exact route
    key := method " " path
    if g_Routes.Has(key) {
        try {
            r := g_Routes[key].Call(body, query, Map())
            return HttpToResponse(r)
        } catch as e {
            return {status: 500, contentType: "application/json", body: '{"error":"' StrReplace(e.Message, '"', '\"') '"}'}
        }
    }
    ; Pattern route
    for routeKey, fn in g_Routes {
        if (SubStr(routeKey, 1, StrLen(method) + 1) != method " ")
            continue
        pat := SubStr(routeKey, StrLen(method) + 2)
        if !InStr(pat, ":")
            continue
        params := HttpMatchPath(pat, path)
        if params {
            try {
                r := fn.Call(body, query, params)
                return HttpToResponse(r)
            } catch as e {
                return {status: 500, contentType: "application/json", body: '{"error":"' StrReplace(e.Message, '"', '\"') '"}'}
            }
        }
    }
    return {status: 404, contentType: "application/json", body: '{"error":"not found"}'}
}

HttpMatchPath(pat, path) {
    pp := StrSplit(pat, "/")
    sp := StrSplit(path, "/")
    if (pp.Length != sp.Length)
        return 0
    params := Map()
    Loop pp.Length {
        a := pp[A_Index], b := sp[A_Index]
        if (SubStr(a, 1, 1) = ":") {
            params[SubStr(a, 2)] := b
        } else if (a != b) {
            return 0
        }
    }
    return params
}

HttpStatic(path, contentType) {
    if !FileExist(path)
        return {status: 404, contentType: "text/plain", body: "Not found: " path}
    return {status: 200, contentType: contentType, body: FileRead(path, "UTF-8")}
}

HttpStaticBinary(path, contentType) {
    if !FileExist(path)
        return {status: 404, contentType: "text/plain", body: "Not found"}
    try {
        f := FileOpen(path, "r")
        if !f
            return {status: 404, contentType: "text/plain", body: "open failed"}
        size := f.Length
        buf := Buffer(size, 0)
        if (size > 0)
            f.RawRead(buf, size)
        f.Close()
        return {status: 200, contentType: contentType, body: buf, binSize: size}
    } catch {
        return {status: 500, contentType: "text/plain", body: "read failed"}
    }
}

HttpToResponse(r) {
    if IsObject(r) && Type(r) = "Object" && r.HasOwnProp("status")
        return r
    return {status: 200, contentType: "application/json", body: JSON.stringify(r)}
}

HttpRespond(client, status, contentType, body, binSize := -1) {
    static codes := Map(200, "OK", 201, "Created", 204, "No Content",
                        400, "Bad Request", 404, "Not Found", 500, "Internal Server Error")
    statusText := codes.Has(status) ? codes[status] : "OK"
    isBinary := IsObject(body) && Type(body) = "Buffer"
    if isBinary {
        bodyBytes := binSize >= 0 ? binSize : body.Size
    } else {
        bodyBytes := StrPut(body, "UTF-8") - 1
        if (bodyBytes < 0)
            bodyBytes := 0
    }
    headers := "HTTP/1.1 " status " " statusText "`r`n"
            .  "Content-Type: " contentType "`r`n"
            .  "Content-Length: " bodyBytes "`r`n"
            .  "Cache-Control: no-store`r`n"
            .  "Connection: close`r`n`r`n"
    SendUtf8(client, headers)
    if (bodyBytes <= 0)
        return
    if isBinary
        DllCall("ws2_32\send", "ptr", client, "ptr", body, "int", bodyBytes, "int", 0)
    else
        SendUtf8(client, body)
}

SendUtf8(sock, s) {
    nBytes := StrPut(s, "UTF-8")
    if (nBytes <= 1)
        return
    buf := Buffer(nBytes, 0)
    StrPut(s, buf, "UTF-8")
    DllCall("ws2_32\send", "ptr", sock, "ptr", buf, "int", nBytes - 1, "int", 0)
}

;==============================================================
; API HANDLERS
;==============================================================
ApiState(body, query, params) {
    global g_Workspaces, g_ActiveWs, g_Settings, g_HttpPort
    s := Map()
    s["version"] := APP_VERSION
    s["port"] := g_HttpPort
    s["active"] := g_ActiveWs
    s["settings"] := g_Settings
    s["rules"] := g_Rules
    s["workspaces"] := g_Workspaces
    s["monitorCount"] := MonitorGetCount()
    s["history"] := g_History.Length
    return s
}

ApiWorkspacesList(body, query, params) {
    return Map("workspaces", g_Workspaces, "active", g_ActiveWs)
}

ApiWorkspaceCreate(body, query, params) {
    global g_Workspaces
    payload := body != "" ? JSON.parse(body) : Map()
    ws := NewWorkspace(payload.Get("name", "Workspace"))
    if payload.Has("hotkey")
        ws["hotkey"] := payload["hotkey"]
    if payload.Has("saveHotkey")
        ws["saveHotkey"] := payload["saveHotkey"]
    if payload.Has("icon")
        ws["icon"] := payload["icon"]
    if payload.Has("color")
        ws["color"] := payload["color"]
    if payload.Has("snapshot") && payload["snapshot"] {
        list := []
        for hwnd in WinGetList() {
            if !WindowIsManageable(hwnd) || WindowMatchesBlacklist(hwnd) || WindowMatchesSticky(hwnd)
                continue
            try {
                if WinGetMinMax("ahk_id " hwnd) = -1
                    continue
            }
            info := WindowCapture(hwnd)
            if info
                list.Push(info)
        }
        ws["windows"] := list
    }
    g_Workspaces.Push(ws)
    WorkspacesSave()
    HotkeysRebindAll()
    return ws
}

ApiWorkspaceUpdate(body, query, params) {
    global g_Workspaces
    id := params["id"]
    idx := WorkspaceIndex(id)
    if !idx
        return {status: 404, contentType: "application/json", body: '{"error":"workspace not found"}'}
    payload := JSON.parse(body)
    ws := g_Workspaces[idx]
    for k, v in payload {
        if (k = "id")
            continue
        if (k = "name")
            v := EnsureUniqueName(v, id)
        ws[k] := v
    }
    WorkspacesSave()
    HotkeysRebindAll()
    TrayBadgeUpdate()
    return ws
}

ApiWorkspaceDelete(body, query, params) {
    global g_Workspaces, g_ActiveWs
    id := params["id"]
    idx := WorkspaceIndex(id)
    if !idx
        return {status: 404, contentType: "application/json", body: '{"error":"workspace not found"}'}
    ThumbDeleteFromWorkspace(g_Workspaces[idx])
    g_Workspaces.RemoveAt(idx)
    if (g_ActiveWs = id)
        g_ActiveWs := ""
    WorkspacesSave()
    HotkeysRebindAll()
    TrayBadgeUpdate()
    return Map("ok", true)
}

ApiWorkspaceSnapshot(body, query, params) {
    id := params["id"]
    if !WorkspaceSnapshot(id)
        return {status: 404, contentType: "application/json", body: '{"error":"workspace not found"}'}
    return WorkspaceFind(id)
}

ApiWorkspaceRestore(body, query, params) {
    id := params["id"]
    if !WorkspaceRestore(id)
        return {status: 404, contentType: "application/json", body: '{"error":"workspace not found"}'}
    return Map("ok", true, "active", g_ActiveWs)
}

ApiMoveWindow(body, query, params) {
    ; Move (or copy) a window entry from one workspace to another.
    ; body: {"from": "ws_id_src", "fromIdx": N, "copy": bool}
    global g_Workspaces
    try {
        targetId := params["id"]
        if (body = "")
            return {status: 400, contentType: "application/json", body: '{"error":"empty body"}'}
        payload := JSON.parse(body)
        fromId := payload.Has("from") ? payload["from"] . "" : ""
        rawIdx := payload.Has("fromIdx") ? payload["fromIdx"] : 0
        if !IsInteger(rawIdx)
            rawIdx := Integer(rawIdx . "")
        fromIdx := rawIdx + 0  ; ensure integer
        copyFlag := (payload.Has("copy") && payload["copy"]) ? 1 : 0
        src := WorkspaceFind(fromId)
        dst := WorkspaceFind(targetId)
        if !IsObject(src)
            return {status: 404, contentType: "application/json", body: '{"error":"src workspace not found: ' fromId '"}'}
        if !IsObject(dst)
            return {status: 404, contentType: "application/json", body: '{"error":"dst workspace not found: ' targetId '"}'}
        if !src.Has("windows") || !(src["windows"] is Array)
            return {status: 400, contentType: "application/json", body: '{"error":"src.windows missing or not Array"}'}
        if !dst.Has("windows") || !(dst["windows"] is Array)
            return {status: 400, contentType: "application/json", body: '{"error":"dst.windows missing or not Array"}'}
        srcList := src["windows"]
        if (fromIdx < 1 || fromIdx > srcList.Length)
            return {status: 400, contentType: "application/json", body: '{"error":"invalid fromIdx=' fromIdx ' (len=' srcList.Length ')"}'}
        info := srcList[fromIdx]
        dst["windows"].Push(info)
        if !copyFlag
            srcList.RemoveAt(fromIdx)
        WorkspacesSave()
        return Map("ok", true)
    } catch as e {
        line := 0
        try line := e.Line
        msg := StrReplace(e.Message, '"', "'")
        what := ""
        try what := e.What
        return {status: 500, contentType: "application/json", body: '{"error":"move-window @' line ' in ' what ': ' msg '"}'}
    }
}

ApiCaptureWindow(body, query, params) {
    ; Capture a specific window into this workspace. If body has "hwnd",
    ; capture that; otherwise capture the foreground window.
    global g_Workspaces
    id := params["id"]
    ws := WorkspaceFind(id)
    if !ws
        return {status: 404, contentType: "application/json", body: '{"error":"workspace not found"}'}
    targetHwnd := 0
    if (body != "") {
        try {
            payload := JSON.parse(body)
            if payload.Has("hwnd") && payload["hwnd"]
                targetHwnd := Integer(payload["hwnd"])
        }
    }
    if !targetHwnd
        targetHwnd := WinExist("A")
    if !targetHwnd
        return {status: 400, contentType: "application/json", body: '{"error":"no target window"}'}
    if WindowMatchesSticky(targetHwnd)
        return {status: 400, contentType: "application/json", body: '{"error":"sticky window cannot be captured"}'}
    info := WindowCapture(targetHwnd)
    if !info
        return {status: 400, contentType: "application/json", body: '{"error":"could not capture"}'}
    ws["windows"].Push(info)
    WorkspacesSave()
    return ws
}

ApiRemoveWindow(body, query, params) {
    global g_Workspaces
    id := params["id"]
    idx := Integer(params["idx"])
    ws := WorkspaceFind(id)
    if !ws
        return {status: 404, contentType: "application/json", body: '{"error":"workspace not found"}'}
    if (idx < 1 || idx > ws["windows"].Length)
        return {status: 400, contentType: "application/json", body: '{"error":"invalid idx"}'}
    ThumbDeleteFromWindow(ws["windows"][idx])
    ws["windows"].RemoveAt(idx)
    WorkspacesSave()
    return ws
}

ApiWorkspaceReorder(body, query, params) {
    global g_Workspaces
    payload := JSON.parse(body)
    order := payload.Get("order", [])
    newList := []
    for id in order {
        ws := WorkspaceFind(id)
        if ws
            newList.Push(ws)
    }
    if (newList.Length = g_Workspaces.Length) {
        g_Workspaces := newList
        WorkspacesSave()
    }
    return Map("ok", true)
}

ApiSettings(body, query, params) {
    return g_Settings
}

ApiSettingsUpdate(body, query, params) {
    payload := JSON.parse(body)
    for k, v in payload
        g_Settings[k] := v
    SettingsSave()
    HotkeysRebindAll()
    TrayBadgeUpdate()
    return g_Settings
}

ApiRules(body, query, params) {
    return g_Rules
}

ApiRulesUpdate(body, query, params) {
    payload := JSON.parse(body)
    for k, v in payload
        g_Rules[k] := v
    RulesSave()
    return g_Rules
}

ApiLiveWindows(body, query, params) {
    list := []
    for hwnd in WinGetList() {
        if !WindowIsManageable(hwnd) || WindowMatchesSticky(hwnd)
            continue
        try {
            list.Push(Map(
                "hwnd", hwnd,
                "title", WinGetTitle("ahk_id " hwnd),
                "class", WinGetClass("ahk_id " hwnd),
                "exe", WinGetProcessName("ahk_id " hwnd)
            ))
        }
    }
    return Map("windows", list)
}

ApiExport(body, query, params) {
    data := Map()
    data["exportedAt"] := FormatTime(, "yyyy-MM-dd HH:mm:ss")
    data["version"] := APP_VERSION
    data["settings"] := g_Settings
    data["workspaces"] := g_Workspaces
    data["rules"] := g_Rules
    return data
}

ApiImport(body, query, params) {
    global g_Settings, g_Workspaces, g_Rules, g_ActiveWs
    payload := JSON.parse(body)
    if payload.Has("settings")
        g_Settings := payload["settings"]
    if payload.Has("workspaces")
        g_Workspaces := payload["workspaces"]
    if payload.Has("rules")
        g_Rules := payload["rules"]
    g_ActiveWs := ""
    SettingsSave()
    WorkspacesSave()
    RulesSave()
    HotkeysRebindAll()
    TrayBadgeUpdate()
    return Map("ok", true)
}

;==============================================================
; (End of file — JSON class is defined near the top)
;==============================================================

