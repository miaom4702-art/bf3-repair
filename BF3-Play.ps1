<#
.SYNOPSIS
    Battlefield 3 启动器 —— 按正确顺序拉起，并自动清理会锁死启动的残留进程

.DESCRIPTION
    本机实测的故障模式（按发现顺序）：
      1. Steam 只运行 EA App 的安装器（EAX_LAUNCH_CLIENT=0）就断链；
      2. 【关键】残留的 EASteamLauncher / EALaunchHelper 实例会锁死新启动：
             WARN  Another instance of EASteamLauncher is already running. Retrying. Attempt=[1..5]
             ERROR Another instance of EASteamLauncher is still running after retries. Exiting.
         带真实启动参数的那个实例因此直接退出，用户看到的就是"点了没反应"；
      3. EA 的启动终点是 BF3WebHelper.exe → 打开 Battlelog 网页
         （https://battlelog.battlefield.com/bf3/），再由 Battlelog 通过 origin:// 拉起 bf3.exe。

    所以本脚本在启动前会先清掉那些残留实例，再重启 EA Desktop，然后按
    Steam → 直接 的顺序尝试，并把"Battlelog 页面已打开"也算作启动成功。

.PARAMETER Mode
    auto   : 依次尝试 steam → direct（默认）
    steam  : 只走 Steam
    direct : 只直接启动 bf3.exe（一般无效，仅用于诊断）

.PARAMETER NoClean
    不清理残留的 EA 启动器进程（默认会清理）

.PARAMETER KeepEA
    不重启 EA Desktop（默认在清理后会重启它以确保状态干净）

.EXAMPLE
    .\BF3-Play.ps1
    .\BF3-Play.ps1 -Mode steam -NoClean
#>
[CmdletBinding()]
param(
    [ValidateSet('auto','steam','direct')]
    [string]$Mode = 'auto',
    [string]$GamePath = "",
    [int]$AppId = 1238820,
    [int]$SteamTimeout = 60,
    [int]$DirectTimeout = 20,
    [switch]$NoClean,
    [switch]$KeepEA
)

$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot 'BF3-Common.ps1')

$GamePath = Resolve-BF3Path -GamePath $GamePath
if (-not $GamePath) {
    Write-Host '  ✖ 没有自动找到 Battlefield 3，请用 -GamePath "游戏目录" 指定' -ForegroundColor Red
    exit 2
}

function Write-Step([string]$t) {
    Write-Host ''
    Write-Host "▶ $t" -ForegroundColor Cyan
}
function Ok([string]$m)   { Write-Host "  ✔ $m" -ForegroundColor Green }
function No([string]$m)   { Write-Host "  ✖ $m" -ForegroundColor Red }
function Hint([string]$m) { Write-Host "  · $m" -ForegroundColor Gray }
function Info2([string]$m){ Write-Host "  $m" -ForegroundColor Gray }

function Get-BattlelogTabCount {
    <#
      统计所有浏览器里 Battlelog 相关的 tab 数量。
      注意：EA 的 web launch 是在**已有窗口里新开一个 tab**，窗口数量不变，
      所以必须数 tab，不能数窗口 —— 这个坑实测踩过（会误报启动失败）。
    #>
    try {
        Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes -ErrorAction SilentlyContinue
        $root = [System.Windows.Automation.AutomationElement]::RootElement
        $n = 0
        foreach ($bn in @('msedge','chrome','firefox')) {
            $procs = Get-Process $bn -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 }
            foreach ($p in $procs) {
                $cond = New-Object System.Windows.Automation.PropertyCondition(
                    [System.Windows.Automation.AutomationElement]::ProcessIdProperty, $p.Id)
                $win = $root.FindFirst([System.Windows.Automation.TreeScope]::Children, $cond)
                if (-not $win) { continue }
                $tabCond = New-Object System.Windows.Automation.PropertyCondition(
                    [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
                    [System.Windows.Automation.ControlType]::TabItem)
                foreach ($t in $win.FindAll([System.Windows.Automation.TreeScope]::Descendants, $tabCond)) {
                    $name = $t.Current.Name
                    if ($name -like '*Battlelog*' -or $name -like '*Battlefield 3*') { $n++ }
                }
            }
        }
        return $n
    } catch {
        return -1   # UI Automation 不可用时返回 -1，调用方据此降级判断
    }
}

function Clear-EALaunchers {
    <# 清掉会锁死启动的残留实例（本机实测的关键修复）#>
    $names = @('EASteamLauncher','EALaunchHelper','EASteamAuthHelper','EASteamProxy',
               'IGOProxy32','IGOProxy64','EACoreServer','activation','MessageDlg','PatchProgress')
    $killed = @()
    foreach ($n in $names) {
        $p = Get-Process $n -ErrorAction SilentlyContinue
        if ($p) {
            $p | Stop-Process -Force -ErrorAction SilentlyContinue
            $killed += "$n($($p.Id -join ','))"
        }
    }
    return $killed
}

function Test-Launched([int]$seconds, [int]$baselineTabs = -1) {
    <#
      判断成功的标准（任一满足）：
        1. bf3.exe 进程出现；
        2. Battlelog 的 tab 数比启动前增加（EA 的 web launch 成功）；
        3. 拿不到 tab 数时，退化为"出现新的 Battlelog 窗口"。
    #>
    $sawGame = $false
    $sawWebLaunch = $false
    for ($i = 1; $i -le [math]::Ceiling($seconds/3); $i++) {
        Start-Sleep -Seconds 3
        if (Get-Process bf3 -ErrorAction SilentlyContinue) { $sawGame = $true }
        if (-not $sawWebLaunch -and $baselineTabs -ge 0) {
            $now = Get-BattlelogTabCount
            if ($now -gt $baselineTabs) {
                $sawWebLaunch = $true
                Ok "Battlelog 页面已打开（tab 数 $baselineTabs → $now）"
            }
        }
        if ($sawGame -and ($sawWebLaunch -or $baselineTabs -lt 0)) { break }
    }
    return [pscustomobject]@{ Game = $sawGame; Battlelog = $sawWebLaunch }
}

# =====================================================================
Write-Host ''
Write-Host '  Battlefield 3 启动器' -ForegroundColor White
Write-Host "  模式: $Mode   游戏: $GamePath" -ForegroundColor DarkGray

$exe = Join-Path $GamePath 'bf3.exe'
if (-not (Test-Path $exe)) { No "找不到 bf3.exe: $exe"; exit 2 }

# ---------- 预检 ----------
Write-Step '预检'
if (Get-Process bf3 -ErrorAction SilentlyContinue) {
    Ok 'bf3.exe 已经在运行'
    exit 0
}
$steam = Find-SteamExe
if (-not (Get-Process steam -ErrorAction SilentlyContinue)) {
    if ($steam) { Hint 'Steam 未运行，正在启动…'; Start-Process $steam; Start-Sleep -Seconds 12 }
    else { No '找不到 Steam' }
} else { Ok 'Steam 正在运行' }

# ---------- 清理残留 EA 启动器（关键步骤）----------
if (-not $NoClean) {
    Write-Step '清理残留的 EA 启动器进程'
    $killed = Clear-EALaunchers
    if ($killed.Count -gt 0) {
        Ok "已清理 $($killed.Count) 个残留进程：$($killed -join ', ')"
        Hint '残留实例会让新启动报 "Another instance of EASteamLauncher is already running" 然后静默退出'
    } else {
        Ok '没有残留实例'
    }
    Start-Sleep -Seconds 2
}

# ---------- 确保 EA Desktop 在跑且已认证 ----------
$eaExe = Find-EAApp
if (-not $KeepEA -and -not (Get-Process EADesktop -ErrorAction SilentlyContinue)) {
    if ($eaExe) { Hint 'EA Desktop 未运行，正在启动…'; Start-Process $eaExe }
}
$auth = $false
for ($i = 1; $i -le 20; $i++) {
    Start-Sleep -Seconds 3
    if ((Get-EaState) -eq 'authenticated') { Ok "EA App 已认证（$($i*3) 秒）"; $auth = $true; break }
}
if (-not $auth) {
    No "EA App 未进入 authenticated（当前: $(Get-EaState)）"
    Hint '请手动打开 EA App 并登录一次，再重跑本脚本'
}

# ---------- 记录启动前的 Battlelog tab 数（用于判断本次是否真的打开了网页）----------
$baselineTabs = Get-BattlelogTabCount
if ($baselineTabs -ge 0) {
    Info2 "启动前 Battlelog tab 数: $baselineTabs"
    if ($baselineTabs -gt 3) {
        Hint "Battlelog 已经开了 $baselineTabs 个 tab，建议关掉多余的再看结果"
    }
}

# ---------- 尝试 1: Steam ----------
$result = $null
if ($Mode -in @('auto','steam')) {
    Write-Step "尝试 1/2：通过 Steam 启动 (appid $AppId)"
    Start-Process "steam://rungameid/$AppId"
    Hint "已发送启动请求，观察 $SteamTimeout 秒…"
    $result = Test-Launched $SteamTimeout $baselineTabs
    if ($result.Game -or $result.Battlelog) {
        Write-Host ''
        Ok '启动成功（Steam 链）'
        if ($result.Battlelog) { Hint '在新打开的 Battlelog 页面登录后，即可进入战役或多人' }
        exit 0
    }
    No 'Steam 链未能拉起游戏，也未打开新的 Battlelog 页面'
}

# ---------- 尝试 2: 直接启动 ----------
if ($Mode -in @('auto','direct')) {
    Write-Step '尝试 2/2：直接启动 bf3.exe'
    $p = Start-Process -FilePath $exe -WorkingDirectory (Split-Path $exe) -PassThru
    $result = Test-Launched $DirectTimeout $baselineTabs
    if ($result.Game -or $result.Battlelog) {
        Write-Host ''
        Ok '启动成功'
        exit 0
    }
    if ($p.HasExited) {
        No ("bf3.exe 已退出，退出码 0x{0:X8}" -f $p.ExitCode)
        Hint 'bf3.exe 本身只是 Battlelog 的启动器，直接运行通常会立即退出，属正常'
    }
}

# ---------- 都失败 ----------
Write-Host ''
Write-Host ('=' * 72) -ForegroundColor DarkYellow
Write-Host '  两条官方启动链都没成功' -ForegroundColor Yellow
Write-Host ('=' * 72) -ForegroundColor DarkYellow
Hint '1) 再跑一次本脚本（清理后第一次有时会被 EA 的后台初始化占住）'
Hint '2) 在 Steam 里右键 BF3 → 属性 → 已安装文件 → 校验完整性'
Hint '3) 在 EA App 里确认游戏出现在「我的库」中'
Hint '4) 直接打开 https://battlelog.battlefield.com/bf3/ 登录后从网页进入'
Hint '5) 想稳定离线玩：.\BF3-VU-Offline.ps1（Venice Unleashed 本地机器人服务器）'
Write-Host ''
exit 1
