<# 
.SYNOPSIS

 Decodes the .cfg file resulted from backing up the configuration of an Asus Router

.NOTES
 Author: Vlad Drumea (VladDBA)
 Website: https://vladdba.com/

 Based on this Bash script:
 https://github.com/billchaison/asus-router-decoder

.LINK
 https://github.com/VladDBA/Asus-Router-Config-Decoder

.EXAMPLE
 PS>.\Decode-AsusRouterConfig.ps1 '.\Settings_RT-AX86U Pro.CFG'

.EXAMPLE
 PS>.\PSBlitz.ps1 'C:\Users\SomeUser\Documents\Settings_RT-AX86U Pro.CFG'

#>
[cmdletbinding()]
param (
    [Parameter(Position = 0, Mandatory = $true)]
    [string]$File
)

if (-Not (Test-Path $File)) {
    Write-Host " Provide the ASUS router config file name." -Fore Red
    Exit
}
# Resolve file path in case of relative path
$File = Get-Item -Path $File | Select-Object -ExpandProperty FullName -ErrorAction Stop

$Size = (Get-Item $File).length

if ($Size -lt 10) {
    Write-Host " File size is too small."  -Fore Red
    Exit
}
try {
    $FileData = [System.IO.File]::ReadAllBytes($File) | ForEach-Object { "{0:x2}" -f $_ }
}
catch {
    Write-Host " Cannot read file." -Fore Red
    Write-Host " Try providing the full file path."
    Exit
}

if ($FileData.Count -ne $Size) {
    Write-Host " File read error."  -Fore Red
    Exit
}
elseif ($FileData[0] -ne "48" -or $FileData[1] -ne "44" -or $FileData[2] -ne "52" -or $FileData[3] -ne "32") {
    Write-Host " File header check failed."  -Fore Red
    Exit
}
else {

    $DataLength = "$($FileData[6])$($FileData[5])$($FileData[4])"
    $DataLength = [convert]::ToInt32($DataLength, 16)

    if ($DataLength -ne ($Size - 8)) {
        Write-Host " Data length check failed."
        Exit
    }
    else {
        Write-Host " Configuration file appears to be valid."
    }
}

$Rand = [convert]::ToInt32($FileData[7], 16)
$i = 8
$DecodedBytes = New-Object System.Collections.Generic.List[byte]

Write-Host " Decoding configuration file..."
while ($i -lt $Size) {
    $CurrentByte = [convert]::ToInt32($FileData[$i], 16)
    if ($CurrentByte -gt 252) {
        if ($i -gt 8 -and $FileData[$i - 1] -ne "00") {
            $DecodedBytes.Add(0x00)
        }
    }
    else {
        $B = 0xff + $Rand - $CurrentByte
        $DecodedBytes.Add([byte]$B)
    }
    $i++
}

# Convert decoded bytes to a string and replace the null character with a new line
$DecodedString = -join ($DecodedBytes | ForEach-Object { if ($_ -eq 0) { "`n" } else { [char]$_ } })

# Write the decoded string to the output file
$OutputFile = $File -ireplace '.cfg', '_Decoded.txt'
$DecodedString | Out-File -FilePath "$OutputFile" -Encoding ascii
Write-Host "->Decoded configuration file has been saved to:"
Write-Host "   $OutputFile" -Fore Green

# Retrieve admin username & password, and any configured SSID and password
Write-Host "->Attempting to identify:`n    HTTP (admin) username & password`n    SSIDs (Wi-Fi names)`n    WPA PSKs (Wi-Fi passwords)"
$FoundInfo = Select-String -Path $OutputFile -Pattern '_wpa_psk=.+|_ssid=.+|http_passwd=.+|http_username=.+'
# Cleanup output for PS versions older than 7
Write-Host $("=" * 60) -Fore Green
$FoundInfo -Replace ".+Decoded\.txt:[0-9]+:", ""
Write-Host $("=" * 60) -Fore Green