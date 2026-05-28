# WorkspaceTool v2.3

![AutoHotkey](https://img.shields.io/badge/AutoHotkey-v2-green)
![Platform](https://img.shields.io/badge/platform-Windows-blue)
![License](https://img.shields.io/badge/license-MIT-blue)

> 轻量的 Windows 工作区管理工具 · AHK v2 核心 + HTML/CSS/JS 现代化 UI
> A lightweight Windows workspace manager · AHK v2 core + modern HTML UI

[**中文**](#中文文档) · [**English**](#english-documentation)

---

## 中文文档

### 简介

一键保存/恢复多窗口布局的轻量工具。后台只占 ~8MB 内存，管理面板用 Edge `--app` 模式打开（无边框），关掉就释放。

**核心特性**

- 一键保存/恢复工作区，含每个窗口的坐标、大小、显示器、最大化/最小化状态
- 自定义工作区名称、emoji 图标、独立呼出/保存快捷键
- **快捷键完全自由**：Ctrl/Alt/Shift/Win 任意组合
- **多种鼠标输入**：侧键 XButton1/2、中键、`修饰键+滚轮`（4 个以上侧键请用鼠标驱动映射到 F13–F24）
- **鼠标侧键翻页工作区**（默认 XButton1=上一个，XButton2=下一个，可自定义）
- 多工作区面板：所有工作区横向陈列，每个工作区的窗口列表都可见
- **拖拽窗口跨工作区移动**，按住 `Ctrl` 拖拽变复制
- **1920×1080 JPEG 缩略图**，hover 弹出预览（6 档尺寸可选 XS→XXL）
- **焦点模式**：切换工作区时最小化其他工作区的窗口（用 `SetWindowPlacement` 原子操作，无闪烁）
- 常驻窗口（在所有工作区都可见，快照/恢复时自动处理）
- **VSCode 恢复增强**：本地文件夹、SSH 工作区尽量按原目标恢复；Dev Container 在无法精确恢复时回退为新窗口
- **Firefox 会话恢复**：记录 profile、当前活动页和标签页列表，恢复时按标签页批量重开
- 黑名单 + 每应用规则（强制最大化 / 偏好显示器）
- 工作区命名自动加唯一后缀，不会重名
- 中文输入法友好（IME 组词时不会被自动刷新打断）
- 管理员模式可控制 admin cmd、regedit 等提权窗口
- JSON 导入导出，方便备份/迁移

### 安装

#### 推荐：Portable 方式

1. 下载 [AutoHotkey v2 portable zip](https://www.autohotkey.com/download/)
2. 解压后把 `AutoHotkey64.exe` (和 `AutoHotkey32.exe`) 放进本目录的 `autohotkey/` 子文件夹
3. 双击 `run.bat`

`run.bat` 会按下面顺序查找 AHK：

```
./autohotkey/AutoHotkey64.exe   ← 首选
./autohotkey/AutoHotkey32.exe
./AutoHotkey64.exe              ← 同目录后备
./AutoHotkey32.exe
系统 PATH 上的 AutoHotkey.exe   ← 最后兜底
```

#### 备选：系统安装

装 [AutoHotkey v2](https://www.autohotkey.com/) 后，直接双击 `workspace_tool.ahk` 即可。

#### 管理员模式（控制 admin cmd / regedit 等提权窗口）

Windows UAC 不允许普通进程操作提权进程的窗口。要让管理员 cmd、regedit、任务管理器等也能加入工作区/参与焦点模式，**双击 `run-as-admin.bat`**：

- 由 `bat` 自己通过 PowerShell 触发 UAC，弹一次提示点"是"
- 托盘 tooltip 和启动浮窗显示 `[admin]` 标识
- 普通和管理员模式只能选一个跑，切模式前先在托盘 Exit
- 想免每次 UAC：把 `run-as-admin.bat` 加进 Windows 任务计划程序，勾选"以最高权限运行"+ 登录时触发

#### 开机自启

把 `run.bat` 的快捷方式拖进 `shell:startup`（在 Win+R 里贴这个路径）。要管理员开机自启就用任务计划程序方案。

### 文件结构

```
tools/
├── workspace_tool.ahk    AHK 核心守护进程（HTTP server + 热键 + 窗口操作）
├── run.bat               普通用户启动器
├── run-as-admin.bat      管理员启动器（PowerShell 触发 UAC）
├── autohotkey/           Portable AHK runtime（用户自己放）
│   ├── AutoHotkey64.exe
│   └── AutoHotkey32.exe
├── ui/                   管理界面（HTTP server 直接 serve）
│   ├── index.html
│   ├── app.css
│   └── app.js
├── settings.json         快捷键、开关、常驻列表、预览尺寸（自动生成）
├── workspaces.json       工作区数据 + 缩略图 id + VSCode/Firefox 恢复元数据
├── rules.json            黑名单 + 每应用规则
├── .edge_profile/        Edge --app 的隔离 profile（自动生成）
├── .gitignore            Git 忽略规则（用户数据、缩略图、AHK 运行时）
└── README.md             本文件
```

### 快捷键（默认，可改）

| 快捷键 | 动作 |
|--------|------|
| `Ctrl+Alt+W` | 打开 / 唤起管理面板 |
| `Ctrl+Alt+R` | 重载配置 |
| `Ctrl+Alt+Z` | 撤销上一次工作区切换 |
| `XButton1`（鼠标后退键） | 上一个工作区 |
| `XButton2`（鼠标前进键） | 下一个工作区 |

每个工作区还可以**单独**绑定 Restore 和 Save 快捷键。点 hotkey chip → 按下你要的组合 → OK。

### 快捷键录制器支持的输入

| 输入方式 | 录制结果 | 说明 |
|---------|---------|------|
| 普通键盘 + 修饰键 | `Ctrl+Alt+W` 等 | Ctrl/Alt/Shift/Win 任意组合 |
| `F1–F24` | `F13` 等 | F13-F24 几乎无软件占用，最适合鼠标宏映射 |
| 鼠标中键 | `MButton` | 按下滚轮 |
| 鼠标侧键（后退） | `XButton1` | 4 键鼠标通常是这个 |
| 鼠标侧键（前进） | `XButton2` | 5 键鼠标才有 |
| 修饰键 + 滚轮 | `Ctrl+WheelUp` / `Ctrl+WheelDown` | 滚轮单独按必须配修饰键，否则会无意捕获 |
| 多于 5 键的鼠标 | 通过驱动映射到 F13–F24 | Windows 原生只识别 5 个鼠标键，多余的要走驱动 |

### 工作流

1. **建工作区**：右上 `+ Add workspace` 或顶栏 `+ Add`，输入名字（重名会自动加 `(2)` `(3)` 后缀）
2. **抓快照**：把窗口摆好位置 → 点工作区卡片上的 📸 按钮；所有可见窗口的位置、大小、显示器、状态、文件夹路径、缩略图，以及支持应用的恢复元数据都会存进去（管理面板自己的窗口会被排除）
3. **应用快照**：点卡片上的 ↻；存在的窗口用 `SetWindowPlacement` 原子归位（< 50ms，无闪烁），关掉的会先弹出确认，再按原应用类型恢复并重新定位（1-3s）
4. **跨工作区拖拽**：在卡片里拖窗口行到另一张卡片，松手 = 移动；按住 `Ctrl` 拖 = 复制
5. **鼠标侧键翻页**：按 XButton1/XButton2 循环切上一个/下一个工作区
6. **配快捷键**：点 hotkey chip → 按下任意组合 → OK

### 缩略图与预览

- 快照时通过 `PrintWindow` API（带 `PW_RENDERFULLCONTENT` 标志）抓窗口画面，缩到最多 **1920×1080**，编码为 **JPEG q85**，文件保存在 `thumbs/`，`workspaces.json` 里只存缩略图 id
- 列表里每行显示 60×38 的小缩略图
- **悬停预览**：浮窗 overlay 挂在 body 上，自动避开 viewport 边界裁剪
- **预览尺寸 6 档**（Settings → "悬停预览尺寸"）：

| 档位 | 尺寸 |
|------|------|
| XS | 240 × 150 |
| S | 400 × 250 |
| M（默认）| 560 × 350 |
| L | 800 × 500 |
| XL | 1100 × 690 |
| XXL | 1280 × 800 |

- 视口空间不够时按等比例自动缩小，不会溢出
- 缩略图是**静态**的，反映快照那一刻；想刷新就重新 📸
- 不要的话在 Settings 关掉"捕获窗口缩略图"

### 焦点模式

Settings 里开启后：切到工作区 N 时，**不属于 N 的窗口全部最小化**；切到别处时再恢复。

- 切换时**无闪烁**：用 `SetWindowPlacement` 原子设置位置 + 状态，不再"先 Restore 再 Minimize"那种闪一下
- 已经最小化的窗口不重复处理；已经在目标位置的也跳过

### 常驻窗口

Settings → "常驻窗口列表"，加入要常驻的窗口模式：

```
ahk_exe wechat.exe
ahk_exe QQ.exe
ahk_class TXGuiFoundation
```

开启后，匹配这些模式的窗口在所有工作区都保持可见，**不会被快照捕获进任何工作区**，切换工作区时也不会被最小化（不受焦点模式影响）。适合微信、QQ 等需要随时在线的通讯工具。

### 应用恢复说明

- **资源管理器**：按原文件夹路径恢复
- **VSCode**：
	- 本地文件夹优先按原目录恢复
	- SSH 工作区优先按原 `vscode-remote://` URI 恢复
	- Dev Container 若无法稳定回到原容器，会回退为打开新窗口
- **Firefox**：
	- 记录原 profile
	- 记录活动标签页和标签页列表
	- 恢复时按原 profile 批量重开标签页
- **常驻窗口**：不会进入工作区快照，也不会在焦点模式中被隐藏

### 安全性

- HTTP server 只绑定 `127.0.0.1`，外网/局域网打不进来
- 只有你自己的进程能访问（同账户即可，没有额外认证）
- 数据全是本地 JSON 明文，敏感内容别写在窗口标题里

### 性能

| 阶段 | 内存 |
|------|------|
| AHK 核心常驻 | 6–10 MB |
| 管理面板打开（Edge --app） | +80–150 MB |
| 管理面板关闭 | 回到 6–10 MB |

JSON 解析器对长 base64 字符串做了 InStr 优化，500KB 的 `workspaces.json` 启动加载 < 100ms。

### 故障排查

- **Edge 没开起管理面板** — 脚本会回退到默认浏览器。看 tray tooltip 上的 `http://127.0.0.1:<port>` URL，手动开也行
- **`run-as-admin.bat` 双击没反应** — `bat` 用 PowerShell 触发 UAC，如果 PowerShell 被禁用就只能右键"以管理员身份运行"。检查托盘启动浮窗有没有 `[admin]` 标识
- **自定义快捷键不响应** — 别的软件占用了那个组合（输入法、第三方工具）。换组合或用管理员模式覆盖系统级快捷键
- **窗口被恢复到奇怪位置** — 原显示器没插了。脚本会回退到主屏 work area；在当前显示器配置下重新 📸 刷新
- **缩略图全是黑的** — 少数硬件加速渲染但不支持 PrintWindow 的应用。无解，关掉 captureThumbnails 用字母 fallback
- **Firefox 弹出 profile 选择器** — 重新保存一次该工作区快照，让脚本记录当前 profile 的真实目录；旧快照可能只存了过时 profile 名称
- **Firefox 标签页没恢复完整** — 重新保存快照，确保 Firefox 的 `sessionstore-backups` 里已有最新会话数据
- **拖拽不工作** — 应该已修。如果还有问题，footer 状态栏会显示 `[drag] ERROR: ...` 详情
- **中文输入被打断** — 应该已修。自动刷新已经在输入框聚焦或 IME 组词时自动跳过
- **想重来一次** — 右键托盘 Exit，删 `settings.json` / `workspaces.json` / `rules.json` / `.edge_profile/`，下次启动重建默认

### 卸载

右键托盘 → Exit，然后删整个目录。无注册表项、无服务、无残留。

---

## English Documentation

### What it is

A lightweight tool that saves and restores multi-window layouts. Background daemon runs at ~8MB. The manager UI opens as a chromeless Edge `--app` window only when needed.

**Features**

- One-click save / restore of workspaces (positions, sizes, monitors, min/max state)
- Customize workspace name, emoji icon, and per-workspace hotkeys
- **Fully customizable hotkeys**: Ctrl/Alt/Shift/Win + anything
- **Rich mouse input support**: side buttons XButton1/2, middle button, `modifier+wheel` (for >5-button mice, remap via vendor driver to F13–F24)
- **Mouse side-button workspace paging** (default XButton1=prev, XButton2=next, fully customizable)
- Multi-workspace panel showing every workspace side-by-side with their window lists
- **Drag windows between workspaces**; hold `Ctrl` while dragging to copy
- **1920×1080 JPEG thumbnails** with 6 preview sizes (XS→XXL)
- **Focus mode**: minimize windows not in the active workspace (uses `SetWindowPlacement` for atomic state+position — no flicker)
- Sticky windows (always visible in all workspaces, skipped by snapshot)
- **Improved VSCode restore**: local folders and SSH workspaces try to reopen the original target; Dev Container falls back to a fresh window when exact restore is unreliable
- **Firefox session restore**: stores the profile, active tab, and tab list, then relaunches them in one shot
- Blacklist + per-app rules (force maximize / prefer monitor)
- Workspace names auto-suffix to avoid duplicates
- IME-friendly (auto-refresh pauses during IME composition / input focus)
- Admin mode for controlling UAC-elevated windows
- JSON import/export for backup and migration

### Install

#### Recommended: portable

1. Download the [AutoHotkey v2 portable zip](https://www.autohotkey.com/download/)
2. Extract `AutoHotkey64.exe` (and `AutoHotkey32.exe`) into the `autohotkey/` subfolder of this directory
3. Double-click `run.bat`

`run.bat` finds AutoHotkey in this priority order:

```
./autohotkey/AutoHotkey64.exe   ← preferred
./autohotkey/AutoHotkey32.exe
./AutoHotkey64.exe              ← fallback next to the script
./AutoHotkey32.exe
system PATH AutoHotkey.exe      ← last resort
```

#### Alternative: system install

Install [AutoHotkey v2](https://www.autohotkey.com/), then double-click `workspace_tool.ahk` directly.

#### Administrator mode (control admin cmd / regedit / other elevated windows)

Windows UAC blocks non-elevated processes from manipulating elevated windows. To let admin cmd, regedit, Task Manager, etc. participate in workspaces and focus mode, **double-click `run-as-admin.bat`**:

- The batch file uses PowerShell to trigger UAC — single prompt, click "Yes"
- Tray tooltip and startup toast show a `[admin]` tag so you can confirm
- Only one mode at a time; right-click tray → Exit before switching
- Skip the UAC prompt every launch: add `run-as-admin.bat` to Windows Task Scheduler, tick "Run with highest privileges", trigger on login

#### Auto-start at login

Drop a shortcut to `run.bat` into `shell:startup` (paste in the Windows Run dialog). For admin auto-start, use Task Scheduler.

### File layout

```
tools/
├── workspace_tool.ahk    Core daemon (HTTP server + hotkeys + window ops)
├── run.bat               Normal-user launcher
├── run-as-admin.bat      Admin launcher (PowerShell-triggered UAC)
├── autohotkey/           Portable AHK runtime (you provide)
│   ├── AutoHotkey64.exe
│   └── AutoHotkey32.exe
├── ui/                   Manager UI served by the HTTP server
│   ├── index.html
│   ├── app.css
│   └── app.js
├── settings.json         Hotkeys, toggles, sticky patterns, preview size (auto-created)
├── workspaces.json       Workspace data + thumbnail ids + restore metadata
├── rules.json            Blacklist + per-app rules
├── .edge_profile/        Isolated Edge profile for the --app UI
├── .gitignore            Git ignore rules (user data, thumbnails, AHK runtime)
└── README.md             This file
```

### Default hotkeys (all customizable)

| Hotkey | Action |
|--------|--------|
| `Ctrl+Alt+W` | Open / focus the manager panel |
| `Ctrl+Alt+R` | Reload config |
| `Ctrl+Alt+Z` | Undo last workspace switch |
| `XButton1` (mouse back) | Previous workspace |
| `XButton2` (mouse forward) | Next workspace |

Each workspace can also bind its **own** Restore and Save hotkeys via the chips on its card.

### Hotkey recorder inputs

| Input | Captured as | Notes |
|-------|------------|-------|
| Keyboard + modifiers | `Ctrl+Alt+W` etc. | Any combination of Ctrl/Alt/Shift/Win |
| `F1–F24` | `F13` etc. | F13–F24 are rarely used by other software — perfect for mouse-button remapping |
| Mouse middle | `MButton` | Wheel click |
| Mouse side (back) | `XButton1` | Usually present on 4-button mice |
| Mouse side (forward) | `XButton2` | Only on 5-button mice |
| Modifier + wheel | `Ctrl+WheelUp` / `Ctrl+WheelDown` | Wheel alone is rejected (would constantly capture scrolling) |
| Mice with >5 buttons | Remap via vendor driver → F13–F24 | Windows natively recognizes only 5 mouse buttons |

### Workflow

1. **Create a workspace** — top-right "+ Add workspace" or the trailing card, then name it (duplicates auto-suffix with `(2)`, `(3)`, etc.)
2. **Snapshot** — arrange windows, click 📸; positions, sizes, monitors, states, folder paths, thumbnails, and app-specific restore metadata are captured (the manager UI's own window is excluded)
3. **Restore** — click ↻; live windows return to their saved position, size, monitor, and min/max state, missing apps prompt before relaunch and are then restored according to app type within 1–3 s
4. **Move/copy windows** — drag a window row to another card to move; hold `Ctrl` to copy
5. **Mouse side-button paging** — press XButton1/XButton2 to cycle prev/next workspace
6. **Bind hotkeys** — click any hotkey chip → press the combination → OK

### Thumbnails & preview

- At snapshot time, the script uses `PrintWindow` (with `PW_RENDERFULLCONTENT` for Chromium / DirectComposition content), scales to max **1920×1080**, encodes as **JPEG q85**, saves the file under `thumbs/`, and stores only the thumbnail id in `workspaces.json`
- Window-list rows show a 60×38 thumb
- **Hover preview**: floating overlay attached to `<body>`, escapes any `overflow:hidden` ancestor, auto-clamped to viewport bounds (never clipped)
- **6 preview sizes** (Settings → "Hover preview size"):

| Tier | Size |
|------|------|
| XS | 240 × 150 |
| S | 400 × 250 |
| M (default) | 560 × 350 |
| L | 800 × 500 |
| XL | 1100 × 690 |
| XXL | 1280 × 800 |

- If the viewport is too small for the chosen size, the overlay shrinks proportionally
- Thumbnails are **static** — they show the contents at snapshot time. Re-snapshot to refresh
- Disable in Settings → "Capture window thumbnails" to save JSON space

### Focus mode

Toggle in Settings: when switching to workspace N, every window **not** in N gets minimized. Switching elsewhere restores them.

- **No flicker**: `SetWindowPlacement` atomically sets position + state, eliminating the "Restore → Move → Minimize" flash from previous versions
- Already-minimized windows are skipped; windows already in the target state aren't touched

### Sticky windows

Settings → "Sticky windows list". Add patterns like:

```
ahk_exe wechat.exe
ahk_exe QQ.exe
ahk_class TXGuiFoundation
```

When enabled, windows matching these patterns are always visible in all workspaces, **never captured into any workspace snapshot**, and are not minimized during workspace switches (not affected by focus mode). Perfect for communication apps like WeChat, QQ, etc.

### App restore notes

- **Explorer**: restores by the original folder path
- **VSCode**:
	- local folders restore by real local path
	- SSH workspaces restore by their original `vscode-remote://` URI when possible
	- Dev Container falls back to a fresh window when exact container restore is unreliable
- **Firefox**:
	- restores with the original profile directory
	- stores the active tab and tab list from Firefox sessionstore
	- relaunches the saved tab set in one new window

### Security

- The HTTP server binds to `127.0.0.1` only — never accessible from your network
- Only processes running as your own user account can connect (no extra authentication)
- All data is plaintext JSON on disk — treat the folder like any other config directory

### Performance

| Stage | Memory |
|-------|--------|
| AHK core idle | 6–10 MB |
| Manager panel open (Edge --app) | +80–150 MB |
| Manager closed | back to 6–10 MB |

JSON parser uses `InStr` chunking for long base64 strings — startup load of a 500KB `workspaces.json` takes < 100ms.

### Troubleshooting

- **Edge didn't open the manager** — Script falls back to your default browser. The startup tray notification shows the actual URL (`http://127.0.0.1:<port>`); open it manually if needed
- **`run-as-admin.bat` does nothing on double-click** — The bat triggers UAC via PowerShell; if PowerShell is locked down, right-click the bat → "Run as administrator". The startup toast should show `[admin]` once it works
- **Custom hotkey doesn't fire** — Another app may own the combination. Try a different combo, or run admin mode to override certain system hotkeys
- **Window restored to a weird place** — Original monitor probably disconnected. The script falls back to the primary monitor's work area; re-snapshot in your current monitor setup to refresh
- **Firefox shows the profile picker** — Re-snapshot that workspace so the tool can store the real profile directory instead of an old profile name
- **Firefox tabs didn't fully restore** — Re-snapshot after Firefox has updated `sessionstore-backups`; old snapshots may not yet have saved tab metadata
- **Thumbnails are black** — Some hardware-accelerated apps don't cooperate with PrintWindow. No fix; turn off captureThumbnails to use the letter fallback
- **Drag-drop doesn't work** — Should be fixed. If still broken, the footer status bar shows `[drag] ERROR: ...` with details
- **Chinese / IME input gets interrupted** — Fixed: auto-refresh is suspended during IME composition or while any input is focused
- **Start over** — Right-click tray → Exit, delete `settings.json` / `workspaces.json` / `rules.json` / `.edge_profile/`. Defaults are recreated on next launch

### Uninstall

Right-click tray → Exit, then delete the folder. No registry entries, no services, no residue.

---

## Version history

- **v2.4** — Snapshot now stores each window's real restore rectangle (`WINDOWPLACEMENT.rcNormalPosition`) so moved/maximized/minimized windows restore correctly · empty monitor ids now fall back safely instead of aborting the whole restore
- **v2.3** — VSCode local/SSH restore improvements · Firefox profile + tab session restore · thumbnail file GC and immediate delete · sticky-window cleanup · production cleanup of debug leftovers
- **v2.2** — Mouse side-button workspace paging (XButton1/2) · Admin mode (`run-as-admin.bat`) · 1920×1080 JPEG thumbnails (was 240×160 PNG) · 6-tier hover preview size selector · Atomic `SetWindowPlacement` switching (no flicker) · No-flash focus mode transitions · Workspace name uniqueness · IME-aware auto-refresh · Recorder accepts middle / side / modifier+wheel · Self-healing data on load · JSON parser InStr fast path for long strings · Detailed drag-drop error reporting in footer
- **v2.0** — Multi-workspace panel UI · Custom hotkeys (incl. mouse side buttons) · Drag-drop between workspaces (Ctrl=copy) · Window thumbnails · Focus mode · Tray badge · Switch toast · Per-app rules · Import/export · AHK core + HTTP server + Edge --app UI · Bilingual UI (中 / EN)
- **v1.0** — Pure-AHK Gui · 9 hardcoded hotkeys (Ctrl+Alt+1..9) · Single-monitor focus

---

## License

MIT License — 自由使用、修改和分发，但作者不对任何使用后果负责。
See [LICENSE](LICENSE) file for details.

## Acknowledgments

- Built with [AutoHotkey v2](https://www.autohotkey.com/)
- UI served via embedded HTTP server and rendered in Microsoft Edge `--app` mode
