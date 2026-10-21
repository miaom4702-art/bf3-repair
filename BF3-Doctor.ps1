<#
.SYNOPSIS
    Battlefield 3 诊断与修复工具（Steam appid 1238820）

.DESCRIPTION
    只做只读诊断 + 安全的修复动作：进程重启、注册表纠正、缓存清理、服务修复。
    不改动 bf3.exe、不注入、不打补丁、不删除游戏文件与存档。

.PARAMETER Fix
    执行安全修复动作（会重启 Steam 与 EA App）

.PARAMETER Deep
    深度修复：额外清理 EA App / Origin 缓存，修复 PunkBuster 服务

.EXAMPLE
    .\BF3-Doctor.ps1
    .\BF3-Doctor.ps1 -Fix -Deep
#>
[CmdletBinding()]
param(
    [switch]$Fix,
    [switch]$Deep,
    [string]$GamePath = "",
    [int]$AppId = 1238820
)

$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot 'BF3-Common.ps1')

$GamePath = Resolve-BF3Path -GamePath $GamePath
if (-not $GamePath) {
    Write-Host ''
    Write-Host '  [问题] 没有自动找到 Battlefield 3 安装目录。' -ForegroundColor Red
    Write-Host '         请用 -GamePath 指定，例如：' -ForegroundColor Yellow
    Write-Host '         .\BF3-Doctor.ps1 -GamePath "D:\SteamLibrary\steamapps\common\Battlefield 3"' -ForegroundColor Yellow
    exit 2
}
$script:issues   = New-Object System.Collections.ArrayList
$script:fixed    = New-Object System.Collections.ArrayList
$script:notes    = New-Object System.Collections.ArrayList

function Write-Head([string]$t) {
    Write-Host ''
    Write-Host ('=' * 72) -ForegroundColor DarkCyan
    Write-Host "  $t" -ForegroundColor Cyan
    Write-Host ('=' * 72) -ForegroundColor DarkCyan
}
function Ok([string]$m)    { Write-Host "  [OK]   $m" -ForegroundColor Green }
function Bad([string]$m)   { Write-Host "  [问题] $m" -ForegroundColor Red;    [void]$script:issues.Add($m) }
function Warn([string]$m)  { Write-Host "  [注意] $m" -ForegroundColor Yellow; [void]$script:notes.Add($m) }
function Info([string]$m)  { Write-Host "  [信息] $m" -ForegroundColor Gray }

function Get-EaState {
    $log = "$env:LOCALAPPDATA\Electronic Arts\EA Desktop\Logs\EADesktop.log"
    if (-not (Test-Path $log)) { return '无日志' }
    $m = Select-String -Path $log -Pattern 'DesktopFSM\[(\w+)\]' -ErrorAction SilentlyContinue | Select-Object -Last 1
    if ($m -and $m.Line -match 'DesktopFSM\[(\w+)\]') { return $Matches[1] }
    return '未知'
}
function Get-SteamPath {
    foreach ($c in @("C:\Program Files (x86)\Steam\steam.exe", "C:\Program Files\Steam\steam.exe")) {
        if (Test-Path $c) { return $c }
    }
    $r = (Get-ItemProperty 'HKCU:\SOFTWARE\Valve\Steam' -ErrorAction SilentlyContinue).SteamExe
    if ($r -and (Test-Path $r)) { return $r }
    return $null
}
function Get-EaPath {
    foreach ($c in @(
        "$env:ProgramFiles\Electronic Arts\EA Desktop\EA Desktop\EADesktop.exe",
        "${env:ProgramFiles(x86)}\Electronic Arts\EA Desktop\EA Desktop\EADesktop.exe")) {
        if (Test-Path $c) { return $c }
    }
    return $null
}

# =====================================================================
Write-Head "Battlefield 3 诊断  (appid $AppId)"
Info "游戏目录: $GamePath"
Info "时间: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
Info "模式: $(if ($Fix) { if ($Deep) { '修复+深度清理' } else { '修复' } } else { '只诊断（不改动）' })"

# ---------------------------------------------------------------- 1 安装
Write-Head "1. 安装完整性"
$exe = Join-Path $GamePath 'bf3.exe'
if (-not (Test-Path $exe)) {
    Bad "找不到 bf3.exe，游戏未安装或路径错误: $exe"
} else {
    $vi = (Get-Item $exe).VersionInfo
    $sig = Get-AuthenticodeSignature $exe
    Ok "bf3.exe v$($vi.FileVersion)  签名=$($sig.Status)  ($($sig.SignerCertificate.Subject -replace '^CN=([^,]+).*','$1'))"

    $size = (Get-ChildItem $GamePath -Recurse -File -ErrorAction SilentlyContinue | Measure-Object -Sum Length).Sum
    $gb = [math]::Round($size/1GB, 2)
    if ($gb -lt 30) { Bad "安装体积仅 $gb GB，明显小于正常的 ~34.5 GB → 文件可能不完整" }
    else { Ok "安装体积 $gb GB" }

    foreach ($need in @('Data\cas_01.cas','Data\layout.toc','Data\Win32\Chunks0.sb','Update\Patch','Core\EACore.dll')) {
        if (Test-Path (Join-Path $GamePath $need)) { Ok "存在 $need" } else { Bad "缺失 $need" }
    }

    $mdl = Get-ChildItem $GamePath -Recurse -File -Filter 'MessageDlg.exe' -ErrorAction SilentlyContinue
    if ($mdl) { Ok "MessageDlg.exe 存在" }
    else { Bad "MessageDlg.exe 缺失（EACore_App.ini 的 AGENT_MESSAGE 指向它，缺失会导致激活错误静默无提示）" }
}

# ---------------------------------------------------------------- 2 Steam
Write-Head "2. Steam 记录"
$steam = Get-SteamPath
if (-not $steam) { Bad "找不到 Steam" } else { Ok "Steam: $steam" }

$acf = Get-BF3AppManifest -AppId $AppId
if (-not $acf) {
    Bad "找不到 appmanifest_$AppId.acf，Steam 未登记该游戏"
} else {
    $t = Get-Content $acf -Raw
    $flags = if ($t -match '"StateFlags"\s+"(\d+)"') { [int]$Matches[1] } else { -1 }
    $played = if ($t -match '"LastPlayed"\s+"(\d+)"') { [long]$Matches[1] } else { -1 }
    $depots = ([regex]::Matches($t, '"dlcappid"')).Count

    if ($flags -eq 4) { Ok "StateFlags=4（已完整安装）" } else { Bad "StateFlags=$flags（4 才是完整安装，建议 Steam 里校验文件）" }
    Ok "已装 DLC depot 数: $(if($depots){$depots}else{'0 个额外 DLC 记录'})"
    if ($played -eq 0) {
        Bad "LastPlayed=0 → Steam 从未成功启动过这个游戏（与'点了没反应'完全吻合）"
    } else {
        Ok "LastPlayed=$([DateTimeOffset]::FromUnixTimeSeconds($played).LocalDateTime.ToString('yyyy-MM-dd HH:mm'))"
    }
}

$rp = Join-Path (Split-Path $steam) 'logs\runprocess_log.txt'
if (Test-Path $rp) {
    $hits = Select-String -Path $rp -Pattern "$AppId" -ErrorAction SilentlyContinue
    if ($hits) {
        Info "最近启动链记录:"
        $hits | Select-Object -Last 3 | ForEach-Object { Write-Host "         $($_.Line.Trim())" -ForegroundColor DarkGray }
        if ($hits[-1].Line -match 'EAappInstaller\.exe') {
            Bad "Steam 只拉了 EA App 的安装器（EAX_LAUNCH_CLIENT=0），跑完就断链，bf3.exe 没被启动"
        }
    } else { Warn "runprocess_log 里没有本 app 的启动记录" }
}

# ---------------------------------------------------------------- 3 EA App
Write-Head "3. EA App"
$ea = Get-EaPath
if (-not $ea) {
    Bad "未安装 EA App / Origin"
} else {
    Ok "EA App: $ea"
    $proc = Get-Process EADesktop -ErrorAction SilentlyContinue
    if ($proc) { Ok "EADesktop 正在运行 (PID $($proc.Id -join ','))" }
    else { Bad "EA App 未运行（Steam 的接力需要它已经在跑）" }
    $st = Get-EaState
    if ($st -eq 'authenticated') { Ok "EA App 状态: authenticated" }
    else { Warn "EA App 状态: $st（需要 authenticated 才能授权）" }
}

$coreReg = Get-ItemProperty 'HKLM:\SOFTWARE\WOW6432Node\Electronic Arts\EA Core' -ErrorAction SilentlyContinue
if ($coreReg) { Ok "EA Core 已注册: $($coreReg.ClientPath)" } else { Warn "EA Core 注册表缺失" }

$eaData = "$env:LOCALAPPDATA\Electronic Arts\EA Desktop"
if (Test-Path $eaData) { Ok "EA App 用户数据目录存在" }

# ---- EA 内容清单与授权（本机故障的真正根因所在）----
Write-Head "3b. EA 内容清单与授权"
$ContentIds = @('70619','71067')   # BF3 在 EA 的两个内容 ID（1026023 是 BF1，勿混）
$anyContent = $false
foreach ($id in $ContentIds) {
    $k = "HKLM:\SOFTWARE\WOW6432Node\Origin Games\$id"
    if (Test-Path $k) {
        $anyContent = $true
        $p = Get-ItemProperty $k -ErrorAction SilentlyContinue
        $dir = $p.'Install Dir'
        if ($dir) {
            if (Test-Path $dir) { Ok "Origin Games\$id → $dir" }
            else { Bad "Origin Games\$id 的 Install Dir 指向不存在的路径: $dir" }
        } else { Bad "Origin Games\$id 缺少 Install Dir（EA 不知道游戏装在哪）" }
    }
}
if (-not $anyContent) { Warn "注册表里没有 BF3 的 Origin Games 内容记录（70619 / 71067）" }

# LocalContent 清单里写的路径 vs 真实路径
$lcDir = "$env:ProgramData\Origin\LocalContent\Battlefield 3"
$lcOldPath = 'C:\Program Files (x86)\Origin Games\Battlefield 3'
if (Test-Path $lcDir) {
    Ok "EA LocalContent 清单存在: $lcDir"
    $lcOldPath = $null
    foreach ($dat in Get-ChildItem $lcDir -File -Filter *.dat) {
        $bytes = [System.IO.File]::ReadAllBytes($dat.FullName)
        # 路径以 UTF-16LE 存放，起始偏移可能是奇数，两种对齐都试
        foreach ($off in @(0, 1)) {
            if ($off -ge $bytes.Length) { continue }
            $slice = if ($off -eq 0) { $bytes } else { $bytes[$off..($bytes.Length - 1)] }
            $txt = [System.Text.Encoding]::Unicode.GetString($slice)
            $m = [regex]::Match($txt, '[A-Za-z]:[\\/][^\u0000]{3,}?Battlefield 3')
            if ($m.Success) { $lcOldPath = $m.Value; break }
        }
        if ($lcOldPath) { break }
    }
    if ($lcOldPath) {
        Info "清单声明的安装路径: $lcOldPath"
        if (Test-Path $lcOldPath) { Ok "清单路径可访问" }
        else { Bad "清单路径不存在且不是联接 → EA 找不到游戏文件，校验/授权必然失败（这是激活失败的根因）" }
    } else { Warn "无法从清单里解析出安装路径" }
} else { Warn "找不到 EA LocalContent 中的 Battlefield 3 清单" }

# 授权文件
$licDir = "$env:ProgramData\Electronic Arts\EA Services\License"
if (Test-Path $licDir) {
    $lic = Get-ChildItem $licDir -File | Where-Object { $_.Name -match '70619|71067' }
    if ($lic) { Ok "BF3 授权文件存在: $(($lic | ForEach-Object { $_.Name }) -join ', ')" }
    else { Bad "EA Services\License 下没有 BF3 的授权文件（70619.dlf / 71067.dlf）→ 从未成功授权" }
} else { Warn "找不到 EA Services\License 目录" }

# ---- 残留启动器进程（本机实测：会导致新启动被锁死）----
Write-Head "3c. EA 启动器残留进程"
$staleNames = @('EASteamLauncher','EALaunchHelper','EASteamAuthHelper','EASteamProxy','EALocalHostSvc')
$stale = @()
foreach ($n in $staleNames) {
    $p = Get-Process $n -ErrorAction SilentlyContinue
    if ($p) { $stale += "$n(PID $($p.Id -join ','))" }
}
if ($stale.Count -eq 0) {
    Ok '没有残留的 EA 启动器进程'
} else {
    Warn "发现 $($stale.Count) 个启动器进程：$($stale -join ', ')"
    Info '这些实例会让新的启动请求报 "Another instance of EASteamLauncher is already running" 后静默退出'
    Info '修复：运行 .\BF3-Play.ps1（启动前会自动清理），或手动结束这些进程'
}

# ---------------------------------------------------------------- 4 注册表
Write-Head "4. 游戏注册表"
foreach ($k in @('HKLM:\SOFTWARE\WOW6432Node\EA Games\Battlefield 3','HKLM:\SOFTWARE\EA Games\Battlefield 3')) {
    if (Test-Path $k) {
        $d = (Get-ItemProperty $k -ErrorAction SilentlyContinue).'Install Dir'
        if ($d -and (Test-Path $d)) { Ok "$k → $d" }
        elseif ($d) { Bad "$k 指向不存在的路径: $d" }
        else { Bad "$k 缺少 Install Dir" }
    } else { Warn "缺少 $k（可尝试添加）" }
}

# ---------------------------------------------------------------- 5 运行库/网络
Write-Head "5. 运行库与网络"
$vc = Get-ChildItem 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall','HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall' -ErrorAction SilentlyContinue |
      ForEach-Object { (Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue).DisplayName } |
      Where-Object { $_ -match 'Visual C\+\+ 2010' }
if ($vc) { Ok "VC++ 2010 已安装 ($(($vc | Select-Object -Unique) -join ' / '))" }
else { Bad "缺少 VC++ 2010 运行库（bf3.exe 依赖，缺失会静默退出）" }

$pb = Get-Service PnkBstrA -ErrorAction SilentlyContinue
if ($pb) {
    if ($pb.Status -eq 'Running') { Ok "PunkBuster PnkBstrA 运行中" }
    else { Bad "PunkBuster PnkBstrA 状态: $($pb.Status)" }
} else { Bad "PunkBuster 服务未安装" }

foreach ($h in @('accounts.ea.com','activate.ea.com','battlelog.battlefield.com')) {
    $r = Test-NetConnection -ComputerName $h -Port 443 -WarningAction SilentlyContinue -InformationLevel Quiet
    if ($r) { Ok "网络可达 $h" } else { Bad "网络不可达 $h" }
}

$cfgDir = "$env:USERPROFILE\Documents\Battlefield 3"
if (Test-Path $cfgDir) { Ok "配置目录已存在: $cfgDir" }
else { Bad "配置目录不存在（$cfgDir）→ 游戏从未走完首次启动流程" }

# =====================================================================
if ($Fix) {
    Write-Head "开始修复"

    # --- 清理残留进程 ---
    Write-Host '  → 清理卡住的残留进程…' -ForegroundColor White
    foreach ($n in @('bf3','EACoreServer','activation','MessageDlg','PatchProgress')) {
        $p = Get-Process $n -ErrorAction SilentlyContinue
        if ($p) { $p | Stop-Process -Force -ErrorAction SilentlyContinue; Info "已结束 $n" }
    }

    # --- 纠正注册表 Install Dir ---
    if (Test-Path (Join-Path $GamePath 'bf3.exe')) {
        foreach ($k in @('HKLM:\SOFTWARE\WOW6432Node\EA Games\Battlefield 3','HKLM:\SOFTWARE\EA Games\Battlefield 3')) {
            try {
                if (-not (Test-Path $k)) { New-Item -Path $k -Force | Out-Null }
                Set-ItemProperty -Path $k -Name 'Install Dir' -Value ($GamePath.TrimEnd('\') + '\') -ErrorAction Stop
                Set-ItemProperty -Path $k -Name 'DisplayName' -Value 'Battlefield 3' -ErrorAction Stop
                [void]$script:fixed.Add("注册表 Install Dir 已校正: $k")
                Info "已校正 $k"
            } catch {
                Warn "无法写入 $k（需要管理员权限）: $($_.Exception.Message)"
            }
        }
    }

    # --- 重启 Steam（清掉"游戏正在运行"的卡死状态）---
    Write-Host '  → 重启 Steam（清除卡死的"正在运行"状态）…' -ForegroundColor White
    Stop-Process -Name steam,steamwebhelper -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 5
    if ($steam) {
        Start-Process $steam
        for ($i=1; $i -le 25; $i++) {
            Start-Sleep -Seconds 3
            $sp = Get-Process steam -ErrorAction SilentlyContinue
            if ($sp) { $sp | ForEach-Object { $_.Refresh() }; if ($sp | Where-Object { $_.MainWindowHandle -ne 0 }) { Info "Steam 已就绪（$($i*3)s）"; break } }
        }
    }

    # --- 启动 EA App 并等待认证 ---
    Write-Host '  → 启动 EA App 并等待认证…' -ForegroundColor White
    if (-not (Get-Process EADesktop -ErrorAction SilentlyContinue)) { if ($ea) { Start-Process $ea } }
    $auth = $false
    for ($i=1; $i -le 25; $i++) {
        Start-Sleep -Seconds 3
        $st = Get-EaState
        if ($st -eq 'authenticated') { $auth = $true; Info "EA App authenticated（$($i*3)s）"; break }
    }
    if ($auth) { [void]$script:fixed.Add('EA App 已完成认证') } else { Warn "EA App 在 75 秒内未进入 authenticated，请手动登录后重试" }

    # --- 深度清理 ---
    if ($Deep) {
        Write-Host '  → 深度修复：备份并清理 EA App 缓存…' -ForegroundColor White
        $bak = Join-Path $env:TEMP ("ea-cache-backup-" + (Get-Date -Format 'yyyyMMdd-HHmmss'))
        New-Item -ItemType Directory -Path $bak -Force | Out-Null
        foreach ($sub in @('CEF','UIC','IGOCache','OfflineCache')) {
            $src = Join-Path $eaData $sub
            if (Test-Path $src) {
                try {
                    Move-Item $src (Join-Path $bak $sub) -Force -ErrorAction Stop
                    Info "已移走 $sub → $bak"
                } catch { Warn "无法移走 ${sub} —— $($_.Exception.Message)" }
            }
        }
        [void]$script:fixed.Add("EA App 缓存已备份到 $bak")

        Write-Host '  → 修复 PunkBuster 服务…' -ForegroundColor White
        $pbsvc = Get-ChildItem $GamePath -Recurse -File -Filter 'pbsvc.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($pbsvc) {
            try {
                Start-Process -FilePath $pbsvc.FullName -ArgumentList '/i' -Wait -NoNewWindow -ErrorAction Stop
                Info "PunkBuster 安装器已执行"
                [void]$script:fixed.Add('PunkBuster 已重装')
            } catch { Warn "PunkBuster 重装失败: $($_.Exception.Message)" }
        } else { Warn "找不到 pbsvc.exe，跳过 PunkBuster 重装" }
    }
}

# =====================================================================
Write-Head "汇总"
if ($script:fixed.Count) {
    Write-Host '  已执行修复:' -ForegroundColor Green
    $script:fixed | ForEach-Object { Write-Host "    ✔ $_" -ForegroundColor Green }
    Write-Host ''
}
if ($script:issues.Count) {
    Write-Host "  发现 $($script:issues.Count) 个问题:" -ForegroundColor Red
    $script:issues | ForEach-Object { Write-Host "    ✖ $_" -ForegroundColor Red }
} else {
    Write-Host '  未发现问题' -ForegroundColor Green
}
if ($script:notes.Count) {
    Write-Host ''
    Write-Host '  备注:' -ForegroundColor Yellow
    $script:notes | ForEach-Object { Write-Host "    · $_" -ForegroundColor Yellow }
}

Write-Host ''
Write-Host '  下一步:' -ForegroundColor White
if (-not $Fix) {
    Write-Host '    · 根因是 EA 内容清单指向不存在的旧路径 → 运行 .\BF3-Repair-EA.ps1（会自动弹 UAC 提权）' -ForegroundColor White
    Write-Host '    · 想先自动修复一般性问题 → .\BF3-Doctor.ps1 -Fix -Deep' -ForegroundColor White
} else {
    Write-Host '    · 运行 .\BF3-Repair-EA.ps1 修复 EA 内容清单的路径错位（根因）' -ForegroundColor White
    Write-Host '    · 然后 .\BF3-Play.ps1 启动游戏' -ForegroundColor White
    Write-Host '    · 若仍秒退，用 .\BF3-VU-Offline.ps1 走离线机器人服务器' -ForegroundColor White
}
Write-Host ''
