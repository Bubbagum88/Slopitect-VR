# Sends one command to Slopitect on the headset and prints the reply.
#
# Once per PowerShell window (Windows blocks downloaded scripts otherwise):
#   Set-ExecutionPolicy -Scope Process Bypass
# Once per headset connection, from the platform-tools folder:
#   .\adb forward tcp:7777 tcp:7777
# Then, for example:
#   .\slopi.ps1 '{"cmd":"spawn","shape":"sphere","position":[0,1.5,-1],"color":"red"}'
#   .\slopi.ps1 '{"cmd":"list"}'
# To give the agent your API key without it landing in PowerShell's history:
#   .\slopi.ps1 -SetKey
# Once per PC (the app only takes commands from programs you said Yes to):
#   .\slopi.ps1 -Pair
# then say Yes in the headset. The pairing key is kept in slopi-key.txt next
# to this script and sent with every command; keep it private.
param(
    [Parameter(Mandatory = $true, ParameterSetName = "Command", Position = 0)][string]$Command,
    [Parameter(Mandatory = $true, ParameterSetName = "SetKey")][switch]$SetKey,
    [Parameter(Mandatory = $true, ParameterSetName = "Pair")][switch]$Pair,
    [int]$Port = 7777
)

$keyFile = Join-Path $PSScriptRoot "slopi-key.txt"
if ($Pair) {
    $Command = @{ cmd = "pair"; name = $env:COMPUTERNAME } | ConvertTo-Json -Compress
    Write-Host "Say Yes in the headset (you have a minute)..."
} elseif (-not $SetKey -and (Test-Path $keyFile)) {
    # Puts "pair_key" first in the command's JSON object.
    $pairKey = (Get-Content $keyFile -Raw).Trim()
    $body = $Command.Trim()
    if (-not $body.StartsWith("{")) {
        Write-Error "A command is a JSON object, like '{""cmd"":""list""}'"
        exit 1
    }
    $rest = $body.Substring(1).TrimStart()
    $Command = '{"pair_key":"' + $pairKey + '"' + $(if ($rest.StartsWith("}")) { "" } else { "," }) + $rest
}

if ($SetKey) {
    # Typed in hidden, so it isn't on screen or saved in the command history.
    $secure = Read-Host "Paste the API key (it won't show)" -AsSecureString
    $key = [System.Net.NetworkCredential]::new("", $secure).Password.Trim()
    if ([string]::IsNullOrWhiteSpace($key)) {
        Write-Error "No key given; nothing was sent."
        exit 1
    }
    # Ctrl+V may not paste into this hidden prompt (in one test it typed a
    # single invisible character instead); right-click pastes.
    if ($key -match '[\x00-\x1F\x7F]' -or $key.Length -lt 20) {
        Write-Error "That isn't a whole key ($($key.Length) characters; Ctrl+V doesn't paste here, right-click does). Nothing was sent."
        exit 1
    }
    $Command = @{ cmd = "agent_config"; api_key = $key } | ConvertTo-Json -Compress
    if (Test-Path $keyFile) {
        $Command = @{ cmd = "agent_config"; api_key = $key; pair_key = (Get-Content $keyFile -Raw).Trim() } | ConvertTo-Json -Compress
    }
}

$client = [System.Net.Sockets.TcpClient]::new()
try {
    $client.Connect("127.0.0.1", $Port)
} catch {
    Write-Error "Nothing is listening on localhost:$Port. Run: .\adb forward tcp:$Port tcp:7777"
    exit 1
}

try {
    $stream = $client.GetStream()
    # Most replies come at once; one that needs your Yes in the headset
    # waits for it (up to a minute), or for a long copy to finish.
    $stream.ReadTimeout = 120000
    $writer = [System.IO.StreamWriter]::new($stream, [System.Text.UTF8Encoding]::new($false))
    $writer.NewLine = "`n"
    $writer.AutoFlush = $true
    $reader = [System.IO.StreamReader]::new($stream, [System.Text.UTF8Encoding]::new($false))

    $writer.WriteLine($Command)
    $reply = $reader.ReadLine()
} catch {
    Write-Error "No reply within 2 minutes: $($_.Exception.Message)"
    exit 1
} finally {
    $client.Close()
}

if ($null -eq $reply) {
    # adb accepts the connection even when the app isn't listening, then closes it.
    Write-Error "The connection closed without a reply. Is Slopitect open on the headset? (adb forward only works while it's running)"
    exit 1
}
$parsed = $reply | ConvertFrom-Json
if ($Pair -and $parsed.ok -eq $true) {
    # Saved, never printed.
    Set-Content -Path $keyFile -Value $parsed.pair_key -NoNewline
    Write-Host "Paired as ""$($parsed.paired)"". The key is in $keyFile (keep it private)."
    exit 0
}
$reply
if ($parsed.ok -ne $true) { exit 1 }
