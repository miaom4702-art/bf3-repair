<#
.SYNOPSIS
    Battlefield 3 离线机器人玩法（Venice Unleashed）—— 不依赖 EA / Battlelog 服务器

.DESCRIPTION
    本机官方启动链已确认断裂（Steam 只跑 EA App 安装器就断链；bf3.exe 静默退出码 0）。
    本脚本走另一条合法路线：Venice Unleashed（VU）—— BF3 社区自有启动器与主服务器，
    用你自己的正版游戏文件运行，可以开一个本地服务器 + AI 机器人，一个人也能打。

    VU 本体需要你手动下载安装（不代下）：
        https://veniceunleashed.net/  →  Downloads  →  Client/Server 安装到 BF3 目录

.PARAMETER Check
    检查环境：游戏文件、VU 是否已安装、端口、模组目录

.PARAMETER Prepare
    生成离线机器人服务器配置（Server\Admin 下的 MapList / ModList / Startup + 启动脚本）

.PARAMETER Launch
    按已生成的配置启动本地服务器与客户端

.PARAMETER Bots
    机器人数量（默认 16）

.PARAMETER Port
    本地服务器端口（默认 25200）

.EXAMPLE
    .\BF3-VU-Offline.ps1 -Check
    .\BF3-VU-Offline.ps1 -Prepare -Bots 24
    .\BF3-VU-Offline.ps1 -Launch
#>
[CmdletBinding()]
param(
    [switch]$Check,
    [switch]$Prepare,
    [switch]$Launch,
    [int]$Bots = 16,
    [int]$Port = 25200,
    [string]$ServerName = "Local Bots",
    [string]$GamePath = ""
)

$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot 'BF3-Common.ps1')

$GamePath = Resolve-BF3Path -GamePath $GamePath
if (-not $GamePath) {
    Write-Host ''
    Write-Host '  ✖ 没有自动找到 Battlefield 3 安装目录。' -ForegroundColor Red
    Write-Host '    请用 -GamePath "你的游戏目录" 指定。' -ForegroundColor Yellow
    Write-Host ''
    exit 2
}

function Write-Head([string]$t) {
    Write-Host ''
    Write-Host ('=' * 72) -ForegroundColor DarkCyan
    Write-Host "  $t" -ForegroundColor Cyan
    Write-Host ('=' * 72) -ForegroundColor DarkCyan
}
function Ok([string]$m)   { Write-Host "  ✔ $m" -ForegroundColor Green }
function No([string]$m)   { Write-Host "  ✖ $m" -ForegroundColor Red }
function Hint([string]$m) { Write-Host "  · $m" -ForegroundColor Gray }
function Warn([string]$m) { Write-Host "  ! $m" -ForegroundColor Yellow }

if (-not ($Check -or $Prepare -or $Launch)) {
    Write-Host ''
    Write-Host '  请指定一个动作：' -ForegroundColor White
    Hint '.\BF3-VU-Offline.ps1 -Check     检查环境'
    Hint '.\BF3-VU-Offline.ps1 -Prepare   生成离线机器人服务器配置'
    Hint '.\BF3-VU-Offline.ps1 -Launch    启动'
    Write-Host ''
    exit 0
}

$vuExe     = Join-Path $GamePath 'vu.exe'
$serverDir = Join-Path $GamePath 'Server'
$adminDir  = Join-Path $serverDir 'Admin'
$modsDir   = Join-Path $serverDir 'Mods'

# =====================================================================
if ($Check) {
    Write-Head 'VU 离线玩法环境检查'

    if (-not (Test-Path (Join-Path $GamePath 'bf3.exe'))) {
        No "找不到游戏目录: $GamePath"
    } else {
        Ok "游戏目录存在: $GamePath"
        $gb = [math]::Round((Get-ChildItem $GamePath -Recurse -File -ErrorAction SilentlyContinue | Measure-Object -Sum Length).Sum/1GB, 2)
        Ok "游戏文件体积 $gb GB（VU 需要完整正版文件）"
    }

    if (Test-Path $vuExe) {
        $v = (Get-Item $vuExe).VersionInfo.FileVersion
        Ok "VU 已安装: vu.exe $(if($v){"v$v"})"
    } else {
        No 'VU 未安装（找不到 vu.exe）'
        Hint '下载: https://veniceunleashed.net/  →  Downloads  →  安装到上面这个游戏目录'
        Hint '安装完成后重新运行本脚本 -Check'
    }

    if (Test-Path $serverDir) { Ok "服务器目录存在: Server\" } else { Warn 'Server\ 目录还没生成（-Prepare 会创建）' }

    $funBots = Get-ChildItem $GamePath -Recurse -Directory -Filter '*fun-bots*' -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($funBots) { Ok "找到机器人模组: $($funBots.FullName)" }
    else {
        Warn '未找到 fun-bots 机器人模组（可选，用于 AI 对战）'
        Hint '下载: https://github.com/Joe91/fun-bots  →  解压到 Server\Mods\fun-bots\'
    }

    $inUse = Test-NetConnection -ComputerName 127.0.0.1 -Port $Port -WarningAction SilentlyContinue -InformationLevel Quiet
    if ($inUse) { No "端口 $Port 已被占用（换个 -Port，或关掉已开的服务器）" } else { Ok "端口 $Port 空闲" }

    Write-Host ''
    Hint '准备好后:  .\BF3-VU-Offline.ps1 -Prepare -Bots 16   然后   -Launch'
    Write-Host ''
    exit 0
}

# =====================================================================
if ($Prepare) {
    Write-Head "生成离线机器人服务器配置（$Bots 个机器人，端口 $Port）"

    if (-not (Test-Path (Join-Path $GamePath 'bf3.exe'))) {
        No "找不到游戏目录: $GamePath"; exit 2
    }
    foreach ($d in @($serverDir, $adminDir, $modsDir)) {
        if (-not (Test-Path $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null; Ok "创建 $d" }
    }

    # --- MapList.txt：单人玩用紧凑地图轮换 ---
    $maps = @(
        'MP_001 ConquestLarge0 1',
        'MP_003 ConquestLarge0 1',
        'MP_007 ConquestLarge0 1',
        'MP_011 ConquestLarge0 1',
        'MP_012 ConquestLarge0 1',
        'MP_013 ConquestLarge0 1',
        'MP_017 ConquestLarge0 1',
        'MP_018 ConquestLarge0 1'
    )
    Set-Content -Path (Join-Path $adminDir 'MapList.txt') -Value $maps -Encoding UTF8
    Ok "MapList.txt：$($maps.Count) 张征服大地图"

    # --- ModList.txt：机器人模组（装了才会生效） ---
    Set-Content -Path (Join-Path $adminDir 'ModList.txt') -Value @('fun-bots') -Encoding UTF8
    Ok 'ModList.txt：已登记 fun-bots'

    # --- Startup.txt：服务器启动参数 ---
    $startup = @(
        "vu.Server.Name `"$ServerName`"",
        'vu.Server.Description "Local bot match"',
        'vu.Server.Password ""',
        'vu.Server.GamePort 25200',
        'vu.Server.RemoteAdminPort 47200',
        'vu.Server.MaxPlayers 32',
        'vu.Server.Ranked false',
        'vu.Server.PunkBuster false',
        'vu.Server.UseGlobalRanking false'
    )
    Set-Content -Path (Join-Path $adminDir 'Startup.txt') -Value $startup -Encoding UTF8
    Ok 'Startup.txt：服务器名/端口/人数/关闭 PunkBuster 与全局排行'

    # --- fun-bots 配置 ---
    $fbDir = Join-Path $modsDir 'fun-bots'
    $fbMod = Join-Path $fbDir 'mod.json'
    if (-not (Test-Path $fbDir)) { New-Item -ItemType Directory -Path $fbDir -Force | Out-Null }
    $modJson = @{
        Name        = 'fun-bots'
        Version     = '3.0.0'
        Author      = 'De_Joe-91'
        Description = 'AI bots for Venice Unleashed'
    } | ConvertTo-Json -Depth 3
    Set-Content -Path $fbMod -Value $modJson -Encoding UTF8
    Ok "fun-bots 模组占位配置：$fbMod"

    $botCfg = @{
        BotCount      = $Bots
        BotDifficulty = 'normal'
        BotNames      = @('Bot_Alpha','Bot_Bravo','Bot_Charlie','Bot_Delta')
        TeamBalance   = $true
    } | ConvertTo-Json -Depth 3
    Set-Content -Path (Join-Path $fbDir 'bots.json') -Value $botCfg -Encoding UTF8
    Ok "机器人数量 $Bots → $(Join-Path $fbDir 'bots.json')"

    # --- 一键启动批处理 ---
    $bat = Join-Path $GamePath 'Start-Local-Bot-Server.bat'
    $batLines = @(
        '@echo off',
        'chcp 65001 >nul',
        'title BF3 Local Bot Server',
        "cd /d `"$GamePath`"",
        'echo Starting VU server ...',
        'start "" "vu.exe" -server -serverInstancePath "Server"',
        'timeout /t 6 >nul',
        'echo Starting VU client (connect to 127.0.0.1:25200) ...',
        'start "" "vu.exe" -gameMode "ConquestLarge0" -level "MP_001" -server "127.0.0.1:25200"',
        'echo.',
        'echo If the client does not auto-connect, open the VU server browser and pick "Local Bots".',
        'pause'
    )
    Set-Content -Path $bat -Value $batLines -Encoding OEM
    Ok "启动脚本：$bat"

    Write-Head '配置完成'
    Hint '清单一：确认已安装 VU（vu.exe 在游戏目录）'
    Hint '清单二：可选安装 fun-bots 到 Server\Mods\fun-bots\（否则没有 AI 机器人，只能自己一个人跑图）'
    Hint '清单三：双击 Start-Local-Bot-Server.bat，或在服务器浏览器里连 127.0.0.1:25200'
    Write-Host ''
    exit 0
}

# =====================================================================
if ($Launch) {
    Write-Head '启动 VU 本地机器人服务器'

    if (-not (Test-Path $vuExe)) {
        No '找不到 vu.exe —— VU 还没安装'
        Hint '下载: https://veniceunleashed.net/  →  Downloads  →  安装到'
        Hint "      $GamePath"
        Write-Host ''
        exit 2
    }
    if (-not (Test-Path (Join-Path $adminDir 'Startup.txt'))) {
        Warn '还没有服务器配置，先执行一次 -Prepare'
        Write-Host ''
        exit 2
    }

    $inUse = Test-NetConnection -ComputerName 127.0.0.1 -Port $Port -WarningAction SilentlyContinue -InformationLevel Quiet
    if ($inUse) { No "端口 $Port 已占用，先关掉旧服务器"; exit 2 }

    Ok "启动服务器: vu.exe -server -serverInstancePath `"Server`""
    Start-Process -FilePath $vuExe -ArgumentList @('-server','-serverInstancePath','Server') -WorkingDirectory $GamePath
    Start-Sleep -Seconds 6

    Ok "启动客户端并连接 127.0.0.1:$Port"
    Start-Process -FilePath $vuExe -ArgumentList @('-gameMode','ConquestLarge0','-level','MP_001','-server',"127.0.0.1:$Port") -WorkingDirectory $GamePath

    Write-Host ''
    Hint '如果客户端没自动进服：打开 VU 的服务器浏览器，选 "Local Bots" 或手动连 127.0.0.1:25200'
    Hint '停止服务器：任务管理器结束 vu.exe，或关掉那个"BF3 Local Bot Server"窗口'
    Write-Host ''
    exit 0
}
