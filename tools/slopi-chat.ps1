# Talk to the Slopitect agent on the headset from the PC, and watch what it
# does: its replies, its thinking, and every tool it runs, as they happen.
#
# Once per PowerShell window:   Set-ExecutionPolicy -Scope Process Bypass
# Once per headset connection:  .\adb forward tcp:7777 tcp:7777
# Then:                         .\slopi-chat.ps1
#
# Type a message and press Enter. While it works, Ctrl+C stops watching (the
# agent keeps going; /stop stops it). Other things you can type:
#   /stop     stop the agent
#   /reset    forget the conversation and start a new one
#   /status   the model, the tokens used, and what it's doing
#   /quit     leave (the agent and the app keep running)
param([int]$Port = 7777)

# Sends one command and returns its reply, or $null if the app didn't answer.
function Send-Command($request) {
    $client = [System.Net.Sockets.TcpClient]::new()
    try {
        $client.Connect("127.0.0.1", $Port)
        $stream = $client.GetStream()
        $stream.ReadTimeout = 30000
        $utf8 = [System.Text.UTF8Encoding]::new($false)
        $writer = [System.IO.StreamWriter]::new($stream, $utf8)
        $writer.NewLine = "`n"
        $writer.AutoFlush = $true
        $reader = [System.IO.StreamReader]::new($stream, $utf8)
        $writer.WriteLine(($request | ConvertTo-Json -Compress -Depth 10))
        return $reader.ReadLine() | ConvertFrom-Json
    } catch {
        Write-Host "No answer from the headset on localhost:$Port ($($_.Exception.Message))." -ForegroundColor Red
        Write-Host "Is the app open? Did you run .\adb forward tcp:$Port tcp:7777 ?" -ForegroundColor Red
        return $null
    } finally {
        $client.Close()
    }
}

# The agent keeps its last 40 events; returns the ones in $now that weren't
# in $before (old ones drop off the front as new ones are added).
function Get-NewEvents($before, $now) {
    for ($start = 0; $start -lt $before.Count; $start++) {
        $overlap = $before.Count - $start
        if ($overlap -gt $now.Count) { continue }
        $same = $true
        for ($i = 0; $i -lt $overlap; $i++) {
            if ($before[$start + $i] -ne $now[$i]) { $same = $false; break }
        }
        if ($same) { return @($now | Select-Object -Skip $overlap) }
    }
    return @($now)
}

function Show-Event($text) {
    if ($text.StartsWith("you: ")) { return }  # you typed it
    $color = "Gray"
    if ($text.StartsWith("agent: ")) { $color = "Green" }
    elseif ($text.StartsWith("thinking: ")) { $color = "DarkGray" }
    elseif ($text.StartsWith("tool ")) { $color = "Cyan" }
    elseif ($text.StartsWith("ERROR")) { $color = "Red" }
    Write-Host $text -ForegroundColor $color
}

function Show-Status($status) {
    $t = $status.tokens
    Write-Host ("{0} / {1}, key {2}. {3}" -f $status.provider, $status.model, ($(if ($status.key_set) { "set" } else { "NOT set" })), $status.status_line)
    Write-Host ("Tokens: this conversation {0}; this question {1}; since the app started {2}" -f $t.conversation, ($t.this_question | ConvertTo-Json -Compress), ($t.since_start | ConvertTo-Json -Compress))
}

$status = Send-Command @{ cmd = "agent_status" }
if ($null -eq $status) { exit 1 }
Show-Status $status
Write-Host "Type a message for the agent (/stop, /reset, /status, /quit)."

while ($true) {
    $line = Read-Host "you"
    if ([string]::IsNullOrWhiteSpace($line)) { continue }
    $word = $line.Trim()
    if ($word -eq "/quit") { exit 0 }
    if ($word -eq "/status") {
        $r = Send-Command @{ cmd = "agent_status" }
        if ($r) { Show-Status $r }
        continue
    }
    if ($word -eq "/stop" -or $word -eq "/reset") {
        $r = Send-Command @{ cmd = "agent_" + $word.Substring(1) }
        if ($r) { Write-Host ($r | ConvertTo-Json -Compress) }
        continue
    }

    $before = Send-Command @{ cmd = "agent_status" }
    if ($null -eq $before) { continue }
    $seen = @($before.events)
    $asked = Send-Command @{ cmd = "agent_ask"; prompt = $line }
    if ($null -eq $asked) { continue }
    if (-not $asked.ok) { Write-Host $asked.error -ForegroundColor Red; continue }

    # Watch until it's done, printing each new event once.
    while ($true) {
        Start-Sleep -Milliseconds 700
        $now = Send-Command @{ cmd = "agent_status" }
        if ($null -eq $now) { break }
        foreach ($text in (Get-NewEvents $seen @($now.events))) { Show-Event $text }
        $seen = @($now.events)
        if (-not $now.busy) {
            # Events are cut at 500 characters; the whole reply is kept apart.
            if ($now.last_reply.Length -gt 490) {
                Write-Host "--- whole reply ---" -ForegroundColor DarkGreen
                Write-Host $now.last_reply -ForegroundColor Green
            }
            Write-Host ("(done; this question used {0})" -f ($now.tokens.this_question | ConvertTo-Json -Compress)) -ForegroundColor DarkGray
            break
        }
    }
}
