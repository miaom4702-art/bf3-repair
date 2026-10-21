<#
.SYNOPSIS
    BF3 激活失败根治 —— 修复 EA 内容清单指向的旧路径（需要管理员/UAC）

.DESCRIPTION
    【本机实测确诊的根因】

    EA 用自己的 LocalContent 清单来判断"这个游戏装在哪、是否完整"：
        C:\ProgramData\Origin\LocalContent\Battlefield 3\DR224766400.dat
        C:\ProgramData\Origin\LocalContent\Battlefield 3\OFB-EAST*.dat
    这些清单里写的安装路径是：
        C:\Program Files (x86)\Origin Games\Battlefield 3\
    而这个目录根本不存在 —— 游戏实际装在：
        D:\SteamLibrary\steamapps\common\Battlefield 3

    于是 EA App 按清单去找，找不到文件 → 无法校验 → 拿不到 BF3 的授权票据
    （EA Services\License 下确实没有 70619.dlf / 71067.dlf，而 BF1 的 1026023.dlf 是有的），
    bf3.exe 请求激活失败后静默退出（退出码 0），而负责弹错误框的 MessageDlg.exe 又缺失，
    所以表现为"点了完全没反应"。

    【修复方式】

    不去改 EA 的二进制清单（风险高），而是**在清单指向的位置放一个目录联接（Junction）**，
    让它指向真实的游戏目录。这样 EA App 按老路径找的时候能顺利找到文件，校验即可通过。
    同时给注册表里 BF3 的两个内容记录（70619 / 71067）补上缺的 Install Dir。

        C:\Program Files (x86)\Origin Games\Battlefield 3
              └─(Junction)→ D:\SteamLibrary\steamapps\common\Battlefield 3

    完全可逆：加 -Undo 即删除联接与补写的注册表值，不动任何游戏文件。

.PARAMETER Undo
    撤销修复（删除 Junction 与补写的注册表值），游戏文件不受影响

.PARAMETER GamePath
    游戏真实安装目录

.PARAMETER NoElevate
    不自动提权（已用管理员身份运行本脚本时使用）

.EXAMPLE
    .\BF3-Repair-EA.ps1          # 自动弹 UAC 提权并修复
    .\BF3-Repair-EA.ps1 -Undo    # 撤销
#>
[CmdletBinding()]
param(
    [switch]$Undo,
    [string]$GamePath = "",
    [switch]$NoElevate
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'BF3-Common.ps1')

if (-not $GamePath) {
    $GamePath = Find-BF3Install
    if (-not $GamePath) {
        Write-Host '  ✖ 没有自动找到 Battlefield 3，请用 -GamePath "游戏目录" 指定' -ForegroundColor Red
        exit 2
    }
}
$LegacyParent = 'C:\Program Files (x86)\Origin Games'
$LegacyGame   = Join-Path $LegacyParent 'Battlefield 3'
$ContentIds   = @('70619','71067')
$GameName     = 'Battlefield 3'

function Say([string]$m, [string]$c = 'Gray') { Write-Host $m -ForegroundColor $c }
function Head([string]$t) {
    Write-Host ''
    Write-Host ('=' * 70) -ForegroundColor DarkCyan
    Write-Host "  $t" -ForegroundColor Cyan
    Write-Host ('=' * 70) -ForegroundColor DarkCyan
}

# ---------------------------------------------------------------- 提权
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($identity)
$isAdmin = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin -and -not $NoElevate) {
    Say ''
    Say '  需要管理员权限来修改 C:\Program Files (x86) 与 HKLM 注册表。' 'Yellow'
    Say '  正在请求提权（会弹出 UAC 窗口，请点"是"）…' 'Yellow'
    $argList = @('-NoProfile','-ExecutionPolicy','Bypass','-File',"`"$PSCommandPath`"",'-GamePath',"`"$GamePath`"")
    if ($Undo) { $argList += '-Undo' }
    try {
        Start-Process -FilePath 'powershell.exe' -ArgumentList $argList -Verb RunAs
    } catch {
        Say "  提权失败: $($_.Exception.Message)" 'Red'
        Say '  请右键本脚本 → 以管理员身份运行。' 'Yellow'
    }
    exit 0
}

if (-not $isAdmin -and $NoElevate) {
    Say ''
    Say '  ✖ 当前不是管理员，且指定了 -NoElevate。' 'Red'
    Say '    修复需要写入 C:\Program Files (x86) 与 HKLM 注册表。' 'Yellow'
    Say '    去掉 -NoElevate 让脚本自动提权，或右键「以管理员身份运行」。' 'Yellow'
    exit 2
}

Head ($(if ($Undo) { '撤销 BF3 激活路径修复' } else { '修复 BF3 激活路径（EA 内容清单指向错误）' }))
Say "  游戏真实目录: $GamePath"
Say "  清单期望目录: $LegacyGame"
Say "  管理员权限  : $isAdmin"
Say "  模式        : $(if ($Undo) { '撤销' } else { '修复' })"

if (-not $Undo -and -not (Test-Path (Join-Path $GamePath 'bf3.exe'))) {
    Say ''
    Say "  ✖ 找不到 $GamePath\bf3.exe，请用 -GamePath 指定正确的游戏目录。" 'Red'
    Read-Host '按回车退出'
    exit 1
}

# ---------------------------------------------------------------- 撤销
if ($Undo) {
    Head '撤销'
    if (Test-Path $LegacyGame) {
        $item = Get-Item $LegacyGame -Force
        if ($item.LinkType -eq 'Junction') {
            # 只删联接本身，不能碰目标内容
            [System.IO.Directory]::Delete($LegacyGame)
            Say "  ✔ 已删除目录联接 $LegacyGame（游戏文件未动）" 'Green'
        } else {
            Say "  ! $LegacyGame 已存在但不是联接，未做删除以免误删" 'Yellow'
        }
    } else { Say '  · 联接不存在，无需删除' }

    foreach ($id in $ContentIds) {
        $k = "HKLM:\SOFTWARE\WOW6432Node\Origin Games\$id"
        if (Test-Path $k) {
            Remove-ItemProperty -Path $k -Name 'Install Dir' -ErrorAction SilentlyContinue
            Say "  ✔ 已移除注册表 HKLM\...\Origin Games\$id\Install Dir" 'Green'
        }
    }
    Say ''
    Say '  撤销完成。' 'Green'
    Read-Host '按回车退出'
    exit 0
}

# ---------------------------------------------------------------- 1 建父目录
Head '1. 创建清单期望的父目录'
if (-not (Test-Path $LegacyParent)) {
    New-Item -ItemType Directory -Path $LegacyParent -Force | Out-Null
    Say "  ✔ 已创建 $LegacyParent" 'Green'
} else { Say "  · 已存在 $LegacyParent" }

# ---------------------------------------------------------------- 2 建 Junction
Head '2. 建立目录联接，让老路径指向真实安装位置'
if (Test-Path $LegacyGame) {
    $item = Get-Item $LegacyGame -Force
    if ($item.LinkType -eq 'Junction') {
        Say "  · 联接已存在 → $($item.Target)" 'Green'
    } else {
        Say "  ! $LegacyGame 已存在且不是联接，为避免破坏不覆盖。" 'Yellow'
        Say '    请先确认该目录内容，或先 -Undo 再处理。' 'Yellow'
    }
} else {
    New-Item -ItemType Junction -Path $LegacyGame -Target $GamePath | Out-Null
    Say "  ✔ 已创建联接: $LegacyGame  →  $GamePath" 'Green'
}

# ---------------------------------------------------------------- 3 验证联接
Head '3. 验证联接是否真的能读到游戏文件'
$probe = Join-Path $LegacyGame 'bf3.exe'
if (Test-Path $probe) {
    $size = [math]::Round((Get-Item $probe).Length/1MB, 1)
    Say "  ✔ $probe 可读（$size MB）" 'Green'
} else {
    Say "  ✖ 通过联接读不到 bf3.exe，修复未生效" 'Red'
}
foreach ($xp in @('Update\Xpack2','Update\Xpack4','Update\Xpack5','Data\cas_01.cas')) {
    $t = Join-Path $LegacyGame $xp
    if (Test-Path $t) { Say "  ✔ 清单项可读: $xp" 'Green' } else { Say "  ✖ 清单项缺失: $xp" 'Red' }
}

# ---------------------------------------------------------------- 4 注册表
Head '4. 补写 EA 内容记录的 Install Dir'
foreach ($id in $ContentIds) {
    $k = "HKLM:\SOFTWARE\WOW6432Node\Origin Games\$id"
    if (-not (Test-Path $k)) {
        New-Item -Path $k -Force | Out-Null
        Say "  · 新建 $k" 'Yellow'
    }
    Set-ItemProperty -Path $k -Name 'Install Dir' -Value ($GamePath.TrimEnd('\') + '\')
    if (-not (Get-ItemProperty -Path $k -ErrorAction SilentlyContinue).DisplayName) {
        Set-ItemProperty -Path $k -Name 'DisplayName' -Value 'Battlefield 3™'
    }
    Say "  ✔ HKLM\...\Origin Games\$id\Install Dir = $GamePath\" 'Green'
}
foreach ($k in @('HKLM:\SOFTWARE\WOW6432Node\EA Games\Battlefield 3','HKLM:\SOFTWARE\EA Games\Battlefield 3')) {
    if (Test-Path $k) {
        Set-ItemProperty -Path $k -Name 'Install Dir' -Value ($GamePath.TrimEnd('\') + '\')
        Say "  ✔ $k\Install Dir 已同步" 'Green'
    }
}

# ---------------------------------------------------------------- 5 重启 EA App
Head '5. 重启 EA App 让它重新校验'
$eaExe = $null
foreach ($c in @("$env:ProgramFiles\Electronic Arts\EA Desktop\EA Desktop\EADesktop.exe",
                 "${env:ProgramFiles(x86)}\Electronic Arts\EA Desktop\EA Desktop\EADesktop.exe")) {
    if (Test-Path $c) { $eaExe = $c; break }
}
Get-Process EADesktop,EABackgroundService -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 4
if ($eaExe) {
    Start-Process $eaExe
    Say '  · EA App 已重启，等待认证…'
    $log = "$env:LOCALAPPDATA\Electronic Arts\EA Desktop\Logs\EADesktop.log"
    for ($i=1; $i -le 20; $i++) {
        Start-Sleep -Seconds 3
        $st = Select-String -Path $log -Pattern 'DesktopFSM\[(\w+)\]' -ErrorAction SilentlyContinue | Select-Object -Last 1
        if ($st -and $st.Line -match 'DesktopFSM\[(\w+)\]' -and $Matches[1] -eq 'authenticated') {
            Say "  ✔ EA App 已认证（$($i*3) 秒）" 'Green'; break
        }
    }
} else { Say '  ! 未找到 EA App' 'Yellow' }

# ---------------------------------------------------------------- 完成
Head '修复完成'
Say ''
Say '  现在请：' 'White'
Say '    1) 等 EA App 完全进入主界面' 'White'
Say '    2) 运行 .\BF3-Play.ps1 启动游戏' 'White'
Say '    3) 若仍失败，在 Steam 里右键 BF3 → 属性 → 已安装文件 → 校验完整性' 'White'
Say ''
Say '  撤销修复: .\BF3-Repair-EA.ps1 -Undo' 'Gray'
Say '  联接只影响 EA 的查找路径，不复制、不移动、不删除任何游戏文件。' 'Gray'
Say ''
Read-Host '按回车退出'
