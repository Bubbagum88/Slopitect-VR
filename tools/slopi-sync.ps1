# Puts the PC's live modules on the headset and, with -Load, loads them.
#
# Only files that differ from the headset's copy (by SHA-256) are pushed, and
# each push is checked by reading the headset's SHA-256 back. With -Load,
# each changed module gets a code_load, which shows its code in the headset
# and waits for your Yes there (nothing here can answer it). Modules load in
# the order they need: controls and ui first.
#
# Once per PowerShell window:
#   Set-ExecutionPolicy -Scope Process Bypass
# Then, from this folder (Tools is the folder with adb.exe and the paired
# slopi.ps1; or set $env:SLOPI_TOOLS to it once):
#   .\slopi-sync.ps1 -Tools D:\quest1-root-project\tools\platform-tools
#   .\slopi-sync.ps1 -Tools D:\quest1-root-project\tools\platform-tools -Load
#   .\slopi-sync.ps1 move,grab -Load
#   .\slopi-sync.ps1 -Status
# After a headset restart the Wi-Fi adb port changes; give the new one:
#   .\slopi-sync.ps1 -Device 192.168.1.95:5555
param(
    [Parameter(Position = 0)][string[]]$Name,
    [switch]$Load,
    [switch]$Status,
    [string]$Device,
    [string]$Tools = $env:SLOPI_TOOLS,
    [string]$From,
    [int]$Port = 7777
)

$remoteDir = "/sdcard/Slopitect/modules"
# The order modules need each other in; any others load after, by name.
$order = @("controls", "ui", "tools", "landscape", "paths", "assets", "save", "move", "grab", "physics", "projects", "inspect")

# --- Finding adb and slopi.ps1 ----------------------------------------------------

if (-not $Tools) { $Tools = $PSScriptRoot }
$adb = Join-Path $Tools "adb.exe"
if (-not (Test-Path $adb)) {
    $found = Get-Command adb -ErrorAction SilentlyContinue
    if (-not $found) {
        Write-Error "No adb.exe in $Tools or on PATH. Give the platform-tools folder with -Tools."
        exit 1
    }
    $adb = $found.Source
}
# The slopi.ps1 next to the pairing key (slopi-key.txt), so commands are paired.
$slopi = Join-Path $Tools "slopi.ps1"
if (-not (Test-Path $slopi)) { $slopi = Join-Path $PSScriptRoot "slopi.ps1" }

# Windows PowerShell has no $PSScriptRoot in param defaults.
if (-not $From) { $From = Join-Path $PSScriptRoot "..\live-modules" }
$From = (Resolve-Path $From -ErrorAction SilentlyContinue).Path
if (-not $From) {
    Write-Error "No live-modules folder; give it with -From."
    exit 1
}

# --- Connecting -------------------------------------------------------------------

if ($Device) {
    $said = & $adb connect $Device
    Write-Host $said
}
$devices = @(& $adb devices | Select-Object -Skip 1 | Where-Object { $_ -match "\tdevice$" } | ForEach-Object { ($_ -split "\t")[0] })
if ($Device) { $devices = @($devices | Where-Object { $_ -eq $Device }) }
if ($devices.Count -eq 0) {
    Write-Error "No headset on adb. Over Wi-Fi: -Device with its IP and port (the port changes after every restart). Over USB: plug it in and allow the PC in the headset."
    exit 1
}
if ($devices.Count -gt 1) {
    Write-Error "More than one device on adb ($($devices -join ', ')); pick one with -Device."
    exit 1
}
$serial = $devices[0]
function Adb { & $adb -s $serial @args }
Write-Host "Headset: $serial"

# The command port, for code_list and code_load. Safe to repeat.
Adb forward "tcp:$Port" "tcp:7777" | Out-Null

function Send-Command([hashtable]$command) {
    # slopi.ps1 adds the pairing key; its errors come back as text.
    $json = $command | ConvertTo-Json -Compress
    $out = & $slopi -Port $Port $json 2>&1
    $text = ($out | ForEach-Object { "$_" }) -join "`n"
    try { return $text | ConvertFrom-Json } catch { return [pscustomobject]@{ ok = $false; error = $text } }
}

# --- What's where -----------------------------------------------------------------

function Get-RemoteHashes {
    $hashes = @{}
    $lines = Adb shell "cd $remoteDir 2>/dev/null && sha256sum *.gd 2>/dev/null"
    foreach ($line in $lines) {
        if ($line -match "^([0-9a-f]{64})\s+(\S+)\.gd$") { $hashes[$Matches[2]] = $Matches[1] }
    }
    return $hashes
}

$local = @{}
foreach ($file in Get-ChildItem (Join-Path $From "*.gd")) {
    $local[$file.BaseName] = $file
}
if ($Name) {
    foreach ($n in $Name) {
        if (-not $local.ContainsKey($n)) {
            Write-Error "No $n.gd in $From"
            exit 1
        }
    }
    $wanted = $Name
} else {
    $wanted = @($local.Keys)
}
$wanted = @($wanted | Sort-Object { $i = [array]::IndexOf($order, $_); if ($i -lt 0) { 1000 } else { $i } }, { $_ })

$remote = Get-RemoteHashes
$changed = @()
$rows = @()
foreach ($n in $wanted) {
    $file = $local[$n]
    $hash = (Get-FileHash $file.FullName -Algorithm SHA256).Hash.ToLower()
    $state = if (-not $remote.ContainsKey($n)) { "new" } elseif ($remote[$n] -ne $hash) { "changed" } else { "same" }
    if ($state -ne "same") { $changed += $n }
    # Windows line endings give a different SHA-256 than the repo's copy, so
    # a file you already said Yes to would ask again.
    $crlf = [System.IO.File]::ReadAllText($file.FullName).Contains("`r")
    $rows += [pscustomobject]@{ module = $n; pc_vs_headset = $state; crlf = $(if ($crlf) { "yes" } else { "" }) }
}

# An asleep headset stops the app, and the command port then hangs.
$awake = (Adb shell "dumpsys power | grep mWakefulness=") -match "Awake"
$list = if ($awake) { Send-Command @{ cmd = "code_list" } } else { [pscustomobject]@{ ok = $false; error = "the headset is asleep" } }
$app = @{}
if ($list.ok -eq $true) {
    foreach ($m in $list.modules) { $app[$m.name] = $m }
}
foreach ($row in $rows) {
    $m = $app[$row.module]
    $row | Add-Member loaded $(if ($m) { [bool]$m.loaded } else { "" })
    $row | Add-Member approved $(if ($m) { [bool]$m.approved } else { "" })
    $row | Add-Member error $(if ($m) { $m.error } else { "" })
}
if ($rows | Where-Object crlf) {
    Write-Warning "Some files have Windows line endings (crlf). In the repo, run: git config core.autocrlf false; then check them out again."
}

if ($Status) {
    $rows | Format-Table -AutoSize
    if ($list.ok -ne $true) { Write-Host "The app isn't answering (is Slopitect open and the headset awake?): $($list.error)" }
    exit 0
}

# --- Pushing ----------------------------------------------------------------------

if ($changed.Count -eq 0) {
    Write-Host "The headset already has every one of these modules as they are on the PC."
} else {
    Adb shell "mkdir -p $remoteDir" | Out-Null
    foreach ($n in $changed) {
        Adb push $local[$n].FullName "$remoteDir/$n.gd" 2>&1 | Out-Null
    }
    $after = Get-RemoteHashes
    foreach ($n in $changed) {
        $hash = (Get-FileHash $local[$n].FullName -Algorithm SHA256).Hash.ToLower()
        if ($after[$n] -ne $hash) {
            Write-Error "$n.gd on the headset doesn't match the PC's after the push; stopping."
            exit 1
        }
        Write-Host "Pushed $n.gd ($($hash.Substring(0, 12)))"
    }
}

# --- Loading ----------------------------------------------------------------------

if ($Load) {
    if ($list.ok -ne $true) {
        Write-Error "The app isn't answering, so nothing was loaded (is Slopitect open and the headset awake?): $($list.error)"
        exit 1
    }
    # Changed files, and ones the app has but isn't running.
    $toLoad = @($wanted | Where-Object { $changed -contains $_ -or ($app[$_] -and -not $app[$_].loaded) })
    foreach ($n in $toLoad) {
        $needsYes = -not ($app[$n] -and $app[$n].approved -and $changed -notcontains $n)
        Write-Host $(if ($needsYes) { "Loading ${n}: say Yes in the headset (the right stick scrolls the code)..." } else { "Loading $n (already has your Yes)..." })
        $reply = Send-Command @{ cmd = "code_load"; name = $n }
        if ($reply.ok -ne $true) {
            # slopi.ps1 stops waiting after 2 minutes, but the code sheet waits
            # 5; the app may still have loaded it, so ask.
            $again = Send-Command @{ cmd = "code_list" }
            $m = $again.modules | Where-Object name -eq $n
            if ($m -and $m.loaded -and $m.approved -and -not $m.changed_since_approved) { $reply = [pscustomobject]@{ ok = $true } }
        }
        if ($reply.ok -eq $true) {
            Write-Host "  loaded"
        } else {
            Write-Host "  not loaded: $($reply.error)"
            if ($order -contains $n -and $order.IndexOf($n) -le 1) {
                Write-Error "Stopping: $n is needed by the rest."
                exit 1
            }
        }
    }
} elseif ($changed.Count -gt 0) {
    Write-Host "Not loaded yet. Run again with -Load to load them (Yes in the headset for each changed one)."
}
