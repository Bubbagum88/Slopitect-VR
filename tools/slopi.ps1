# Sends one command to Slopitect on the headset and prints the reply.
#
# Once per PowerShell window (Windows blocks downloaded scripts otherwise):
#   Set-ExecutionPolicy -Scope Process Bypass
# Once per headset connection, from the platform-tools folder:
#   .\adb forward tcp:7777 tcp:7777
# Then, for example:
#   .\slopi.ps1 '{"cmd":"spawn","shape":"sphere","position":[0,1.5,-1],"color":"red"}'
#   .\slopi.ps1 '{"cmd":"list"}'
param(
    [Parameter(Mandatory = $true)][string]$Command,
    [int]$Port = 7777
)

$client = [System.Net.Sockets.TcpClient]::new()
try {
    $client.Connect("127.0.0.1", $Port)
} catch {
    Write-Error "Nothing is listening on localhost:$Port. Run: .\adb forward tcp:$Port tcp:7777"
    exit 1
}

try {
    $stream = $client.GetStream()
    $stream.ReadTimeout = 5000
    $writer = [System.IO.StreamWriter]::new($stream, [System.Text.UTF8Encoding]::new($false))
    $writer.NewLine = "`n"
    $writer.AutoFlush = $true
    $reader = [System.IO.StreamReader]::new($stream, [System.Text.UTF8Encoding]::new($false))

    $writer.WriteLine($Command)
    $reply = $reader.ReadLine()
} catch {
    Write-Error "No reply within 5 seconds: $($_.Exception.Message)"
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
