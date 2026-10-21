<#
.SYNOPSIS
    Battlefield 3 启动器 —— 按正确顺序拉起，并在失败时自动降级/给出结论

.DESCRIPTION
    本机实测的故障模式：
      1. Steam 只运行 EA App 的安装器（EAX_LAUNCH_CLIENT=0）就断链，bf3.exe 没被启动；
      2. 直接跑 bf3.exe 会秒退（退出码 0），因为拿不到 EA 授权票据，而报错用的
         MessageDlg.exe 又缺失，所以完全静默。
    因此本脚本按「EA App 先认证 → Steam 拉 → 直接拉」的顺序试，并实时汇报结果。

.PARAMETER Mode
    auto   : 依次尝试 steam → direct（默认）
    steam  : 只走 Steam
    direct : 只直接启动 bf3.exe

.PARAMETER Timeout
    每一步观察多少秒（默认 Steam 45 秒 / direct 20 秒）

.EXAMPLE
    .\BF3-Play.ps1
    .\BF3-Play.ps1 -Mode direct
#>
[CmdletBinding()]
param(
    [ValidateSet('auto','steam','direct')]
    [string]$Mode = 'auto',
    [string]$GamePath = "",
    [int]$AppId = 1238820,
    [int]$SteamTimeout = 45,
    [int]$DirectTimeout = 20
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

function Get-EaState {
    $log = "$env:LOCALAPPDATA\Electronic Arts\EA Desktop\Logs\EADesktop.log"
    if (-not (Test-Path $log)) { return '无日志' }
    $m = Select-String -Path $log -Pattern 'DesktopFSM\[(\w+)\]' -ErrorAction SilentlyContinue | Select-Object -Last 1
    if ($m -and $m.Line -match 'DesktopFSM\[(\w+)\]') { return $Matches[1] }
    return '未知'
}
function Find-Steam {
    foreach ($c in @("C:\Program Files (x86)\Steam\steam.exe","C:\Program Files\Steam\steam.exe")) { if (Test-Path $c) { return $c } }
    return $null
}
function Find-EaApp {
    foreach ($c in @("$env:ProgramFiles\Electronic Arts\EA Desktop\EA Desktop\EADesktop.exe","${env:ProgramFiles(x86)}\Electronic Arts\EA Desktop\EA Desktop\EADesktop.exe")) { if (Test-Path $c) { return $c } }
    return $null
}
function Wait-ProcessAppear([string]$name, [int]$seconds) {
    for ($i = 1; $i -le [math]::Ceiling($seconds/2); $i++) {
        Start-Sleep -Seconds 2
        $p = Get-Process $name -ErrorAction SilentlyContinue
        if ($p) { return $p }
    }
    return $null
}
function Test-Launched([int]$seconds) {
    <# 监控 bf3.exe 是否出现并存活；返回 $true 表示成功跑起来 #>
    $seen = $false
    for ($i = 1; $i -le [math]::Ceiling($seconds/3); $i++) {
        Start-Sleep -Seconds 3
        $bf = Get-Process bf3 -ErrorAction SilentlyContinue
        if ($bf) {
            if (-not $seen) { Ok "bf3.exe 已启动 (PID $($bf.Id -join ','))"; $seen = $true }
            $bf | ForEach-Object { $_.Refresh() }
            $alive = Get-Process bf3 -ErrorAction SilentlyContinue
            if (-not $alive) { No "bf3.exe 启动后退出"; return $false }
        } elseif ($seen) {
            No "bf3.exe 已退出"
            return $false
        }
    }
    return (Get-Process bf3 -ErrorAction SilentlyContinue) -ne $null
}

# =====================================================================
Write-Host ''
Write-Host '  Battlefield 3 启动器' -ForegroundColor White
Write-Host "  模式: $Mode   游戏: $GamePath" -ForegroundColor DarkGray

$exe = Join-Path $GamePath 'bf3.exe'
if (-not (Test-Path $exe)) { No "找不到 bf3.exe: $exe"; exit 2 }

$steam = Find-Steam
$eaApp = Find-EaApp

# ---------- 预检 ----------
Write-Step '预检'
if (Get-Process bf3 -ErrorAction SilentlyContinue) {
    Ok 'bf3.exe 已经在运行，直接返回'
    exit 0
}
if (-not (Get-Process steam -ErrorAction SilentlyContinue)) {
    if ($steam) { Hint 'Steam 未运行，正在启动…'; Start-Process $steam; Start-Sleep -Seconds 12 } else { No '找不到 Steam' }
} else { Ok 'Steam 正在运行' }

if (-not (Get-Process EADesktop -ErrorAction SilentlyContinue)) {
    if ($eaApp) { Hint 'EA App 未运行，正在启动…'; Start-Process $eaApp }
}
$auth = $false
for ($i = 1; $i -le 20; $i++) {
    Start-Sleep -Seconds 3
    $st = Get-EaState
    if ($st -eq 'authenticated') { Ok "EA App 已认证（$($i*3) 秒）"; $auth = $true; break }
}
if (-not $auth) {
    No "EA App 未进入 authenticated（当前: $(Get-EaState)）"
    Hint '请手动打开 EA App 并登录一次，再重跑本脚本'
}

# ---------- 尝试 1: Steam ----------
if ($Mode -in @('auto','steam')) {
    Write-Step "尝试 1/2：通过 Steam 启动 (appid $AppId)"
    Start-Process "steam://rungameid/$AppId"
    Hint "已发送启动请求，观察 $SteamTimeout 秒…"
    $ok = Test-Launched $SteamTimeout
    if ($ok) {
        Write-Host ''
        Ok '启动成功（Steam 链）'
        if (Test-Path "$env:USERPROFILE\Documents\Battlefield 3") { Ok '游戏已创建用户配置目录' }
        exit 0
    }
    No 'Steam 链未能拉起 bf3.exe'
}

# ---------- 尝试 2: 直接启动 ----------
if ($Mode -in @('auto','direct')) {
    Write-Step '尝试 2/2：直接启动 bf3.exe'
    $p = Start-Process -FilePath $exe -WorkingDirectory (Split-Path $exe) -PassThru
    $ok = Test-Launched $DirectTimeout
    if ($ok) {
        Write-Host ''
        Ok '启动成功（直接启动）'
        exit 0
    }
    if ($p.HasExited) {
        No ("bf3.exe 已退出，退出码 0x{0:X8}" -f $p.ExitCode)
        Hint '退出码 0 且无窗口 = 拿不到 EA 授权票据后静默退出（本机已确认的故障）'
        Hint '报错组件 MessageDlg.exe 缺失，所以连错误框都弹不出来'
    }
}

# ---------- 都失败 ----------
Write-Host ''
Write-Host ('=' * 72) -ForegroundColor DarkYellow
Write-Host '  两条官方启动链都没成功' -ForegroundColor Yellow
Write-Host ('=' * 72) -ForegroundColor DarkYellow
Hint '1) 先跑 .\BF3-Doctor.ps1 -Fix -Deep 修复激活链，然后再试'
Hint '2) 在 Steam 里右键 BF3 → 属性 → 已安装文件 → 校验完整性（可补回缺失的 MessageDlg.exe）'
Hint '3) 在 EA App 里确认这个游戏出现在「我的库」中；不在就说明授权没同步，需要 EA 支持补授权'
Hint '4) 想马上能玩：运行 .\BF3-VU-Offline.ps1（Venice Unleashed 本地机器人服务器，不依赖 EA 服务器）'
Write-Host ''
exit 1
