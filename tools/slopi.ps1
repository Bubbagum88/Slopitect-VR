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
param(
    [Parameter(Mandatory = $true, ParameterSetName = "Command", Position = 0)][string]$Command,
    [Parameter(Mandatory = $true, ParameterSetName = "SetKey")][switch]$SetKey,
    [int]$Port = 7777
)

if ($SetKey) {
    # Typed in hidden, so it isn't on screen or saved in the command history.
    $secure = Read-Host "Paste the API key (it won't show)" -AsSecureString
    $key = [System.Net.NetworkCredential]::new("", $secure).Password
    if ([string]::IsNullOrWhiteSpace($key)) {
        Write-Error "No key given; nothing was sent."
        exit 1
    }
    $Command = @{ cmd = "agent_config"; api_key = $key.Trim() } | ConvertTo-Json -Compress
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
$reply
if (($reply | ConvertFrom-Json).ok -ne $true) { exit 1 }
