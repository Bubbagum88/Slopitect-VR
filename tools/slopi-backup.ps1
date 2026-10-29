# Backs up one Slopitect project from the headset into a git repository on
# this PC, and (with -Push) pushes it to GitHub with this PC's own git login.
# The headset never holds a GitHub login. A project marked private
# (projects_config) is never backed up, and its assets/ folder (downloaded
# or game-ripped files) is never copied.
#
# Put it in the platform-tools folder, next to adb.exe. Then, for example:
#   .\slopi-backup.ps1 -Project castle
#   .\slopi-backup.ps1 -Project castle -Remote https://github.com/YOU/slopitect-castle.git -Push
# Make the GitHub repository yourself first, and make it private.
param(
    [Parameter(Mandatory = $true)][string]$Project,
    [string]$To = "D:\Slopitect-Projects",
    [string]$Remote = "",
    [switch]$Push
)
if ($Project -notmatch '^[A-Za-z0-9_-]{1,40}$') {
    Write-Error "A project name is 1 to 40 letters, digits, - or _ (projects_list shows them)."
    exit 1
}
$adb = Join-Path $PSScriptRoot "adb.exe"
if (-not (Test-Path $adb)) { $adb = "adb" }
$source = "/sdcard/Slopitect/projects/$Project"

# What the project says about itself; a private one stops here.
$info = & $adb shell cat "$source/project.json"
if ($LASTEXITCODE -ne 0 -or -not $info) {
    Write-Error "Couldn't read $source/project.json from the headset (is the project's name right, and the headset connected?)"
    exit 1
}
$info = ($info -join "`n") | ConvertFrom-Json
if ($info.private -eq $true) {
    Write-Error "Project ""$Project"" is marked private, so it isn't backed up (projects_config changes that)."
    exit 1
}

# A fresh copy off the headset, into a temporary folder first.
$stage = Join-Path $env:TEMP "slopitect-backup-$Project"
if (Test-Path $stage) { Remove-Item $stage -Recurse -Force }
New-Item -ItemType Directory -Path $stage | Out-Null
& $adb pull $source $stage
if ($LASTEXITCODE -ne 0) {
    Write-Error "adb pull of $source failed."
    exit 1
}
$pulled = Join-Path $stage $Project

$repo = Join-Path $To $Project
New-Item -ItemType Directory -Path $repo -Force | Out-Null
if (-not (Test-Path (Join-Path $repo ".git"))) {
    git -C $repo init -b main | Out-Null
}
# The repository becomes exactly what's on the headset (its .git stays).
Get-ChildItem $repo -Force | Where-Object { $_.Name -ne ".git" } | Remove-Item -Recurse -Force
Get-ChildItem $pulled -Force | Where-Object { $_.Name -notin @("assets", "views") } | Copy-Item -Destination $repo -Recurse -Force

# The live modules it uses, so the backup is the whole project.
if ($info.modules) {
    $modules = Join-Path $repo "modules"
    New-Item -ItemType Directory -Path $modules -Force | Out-Null
    foreach ($module in $info.modules) {
        if ($module -match '^[A-Za-z0-9_-]{1,40}$') {
            & $adb pull "/sdcard/Slopitect/modules/$module.gd" $modules | Out-Null
            if ($LASTEXITCODE -ne 0) { Write-Warning "Module $module.gd isn't on the headset; skipped." }
        }
    }
}
Set-Content -Path (Join-Path $repo ".gitignore") -Value "# Downloaded or game-ripped files stay on the headset`nassets/`nviews/`n*.partial/`n*.writing`n"
Remove-Item $stage -Recurse -Force

git -C $repo add -A
git -C $repo diff --cached --quiet
if ($LASTEXITCODE -eq 0) {
    Write-Host "Nothing changed since the last backup of ""$Project""."
} else {
    git -C $repo commit -q -m "Backup of $Project, $(Get-Date -Format 'yyyy-MM-dd HH:mm')"
    Write-Host "Backed up ""$Project"" into $repo."
}

if ($Remote) {
    $existing = git -C $repo remote 2>$null
    if ($existing -notcontains "origin") { git -C $repo remote add origin $Remote }
}
if ($Push) {
    git -C $repo push -u origin main
    if ($LASTEXITCODE -ne 0) {
        Write-Error "The push failed. Is the GitHub repository made (and private), and is -Remote right?"
        exit 1
    }
    Write-Host "Pushed."
}
