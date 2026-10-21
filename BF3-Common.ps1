<#
.SYNOPSIS
    BF3 工具箱公共函数：自动定位 Steam、游戏目录、EA App

.DESCRIPTION
    被其他脚本 dot-source 引用。目标是让工具在任意机器上都能自己找到路径，
    不依赖任何人肉写死的盘符。
#>

function Add-UniquePath {
    <# 大小写不敏感地去重（Windows 路径不区分大小写）#>
    param($List, [string]$Path)
    if (-not $Path) { return }
    foreach ($p in $List) { if ($p -ieq $Path) { return } }
    [void]$List.Add($Path)
}

function Get-SteamRoots {
    $roots = New-Object System.Collections.ArrayList
    foreach ($c in @(
        "${env:ProgramFiles(x86)}\Steam",
        "$env:ProgramFiles\Steam")) {
        if ($c -and (Test-Path (Join-Path $c 'steam.exe'))) { Add-UniquePath $roots $c }
    }
    $reg = (Get-ItemProperty 'HKCU:\SOFTWARE\Valve\Steam' -ErrorAction SilentlyContinue).SteamPath
    if ($reg) {
        $reg = $reg -replace '/', '\'
        if (Test-Path (Join-Path $reg 'steam.exe')) { Add-UniquePath $roots $reg }
    }
    return @($roots)
}

function Get-SteamLibraries {
    $libs = New-Object System.Collections.ArrayList
    foreach ($root in Get-SteamRoots) {
        Add-UniquePath $libs $root
        $vdf = Join-Path $root 'steamapps\libraryfolders.vdf'
        if (-not (Test-Path $vdf)) { $vdf = Join-Path $root 'steamapps\LibraryFolders.vdf' }
        if (Test-Path $vdf) {
            $txt = Get-Content $vdf -Raw -ErrorAction SilentlyContinue
            if ($txt) {
                # 新版格式: "path"  "D:\\SteamLibrary"   旧版格式: "1"  "D:\\SteamLibrary"
                foreach ($m in [regex]::Matches($txt, '"(?:path|[0-9]+)"\s+"([^"]+)"')) {
                    $p = $m.Groups[1].Value -replace '\\\\', '\'
                    if ($p -match '^[A-Za-z]:' -and (Test-Path $p)) { Add-UniquePath $libs $p }
                }
            }
        }
    }
    return @($libs)
}

function Find-BF3Install {
    <# 依次尝试：注册表 → Steam 库目录，返回含 bf3.exe 的目录或 $null #>
    foreach ($k in @(
        'HKLM:\SOFTWARE\WOW6432Node\EA Games\Battlefield 3',
        'HKLM:\SOFTWARE\EA Games\Battlefield 3')) {
        $d = (Get-ItemProperty $k -ErrorAction SilentlyContinue).'Install Dir'
        if ($d) {
            $d = $d.TrimEnd('\')
            if (Test-Path (Join-Path $d 'bf3.exe')) { return $d }
        }
    }
    foreach ($lib in Get-SteamLibraries) {
        foreach ($sub in @('steamapps\common\Battlefield 3', 'SteamApps\common\Battlefield 3')) {
            $p = Join-Path $lib $sub
            if (Test-Path (Join-Path $p 'bf3.exe')) { return $p }
        }
    }
    return $null
}

function Find-SteamExe {
    foreach ($root in Get-SteamRoots) {
        $exe = Join-Path $root 'steam.exe'
        if (Test-Path $exe) { return $exe }
    }
    return $null
}

function Find-EAApp {
    foreach ($c in @(
        "$env:ProgramFiles\Electronic Arts\EA Desktop\EA Desktop\EADesktop.exe",
        "${env:ProgramFiles(x86)}\Electronic Arts\EA Desktop\EA Desktop\EADesktop.exe",
        "$env:ProgramFiles\Origin\Origin.exe",
        "${env:ProgramFiles(x86)}\Origin\Origin.exe")) {
        if ($c -and (Test-Path $c)) { return $c }
    }
    return $null
}

function Get-EaState {
    <# 读 EA App 日志里的状态机当前状态（authenticated 才算可授权）#>
    $log = "$env:LOCALAPPDATA\Electronic Arts\EA Desktop\Logs\EADesktop.log"
    if (-not (Test-Path $log)) { return '无日志' }
    $m = Select-String -Path $log -Pattern 'DesktopFSM\[(\w+)\]' -ErrorAction SilentlyContinue | Select-Object -Last 1
    if ($m -and $m.Line -match 'DesktopFSM\[(\w+)\]') { return $Matches[1] }
    return '未知'
}

function Get-BF3AppManifest {
    param([int]$AppId = 1238820)
    foreach ($lib in Get-SteamLibraries) {
        $acf = Join-Path $lib "steamapps\appmanifest_$AppId.acf"
        if (Test-Path $acf) { return $acf }
    }
    return $null
}

function Resolve-BF3Path {
    <# 供脚本统一调用：优先用 -GamePath，其次自动探测；找不到就报错退出 #>
    param([string]$GamePath)
    if ($GamePath) {
        $GamePath = $GamePath.TrimEnd('\')
        if (Test-Path (Join-Path $GamePath 'bf3.exe')) { return $GamePath }
        Write-Host "  ! 指定的 -GamePath 下没找到 bf3.exe: $GamePath" -ForegroundColor Yellow
    }
    $found = Find-BF3Install
    if ($found) { return $found }
    return $null
}
