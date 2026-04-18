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
 PS>.\Decode-AsusRouterConfig.ps1 'C:\Users\SomeUser\Documents\Settings_RT-AX86U Pro.CFG'

.EXAMPLE
 PS>.\Decode-AsusRouterConfig.ps1 'C:\Users\SomeUser\Documents\Settings_RT-AX86U Pro.CFG' -SkipHeaderCheck

.EXAMPLE
 PS>.\Decode-AsusRouterConfig.ps1 '.\Settings_RT-AX86U Pro.CFG' -OutputDirectory 'C:\Decoded'

.EXAMPLE
 PS>.\Decode-AsusRouterConfig.ps1 '.\Settings_RT-AX86U Pro.CFG' -Force

.PARAMETER File
 The path to the ASUS router backup configuration file (.CFG).
 Accepts both relative and absolute paths.

.PARAMETER OutputDirectory
 Optional. The directory where decoded output files will be saved.
 If not specified, output files are saved in the same directory as the input file.
 The directory will be created if it does not exist.

.PARAMETER SkipHeaderCheck
 Optional. Skips validation of the "HDR2" magic bytes at the start of the file.
 Use this if the file header is non-standard but the file is otherwise valid.


#>

[cmdletbinding()]
param (
    [Parameter(Position=0, Mandatory)]
    [string]$File,
    [Parameter(Position=1)]
    [string]$OutputDirectory,
    [Parameter(Position=2)]
    [switch]$SkipHeaderCheck
)

if (-not (Test-Path $File)) {
    throw " Provide the ASUS router config file name."
}
# Resolve file path in case of relative path
$File = Get-Item -Path $File | Select-Object -ExpandProperty FullName -ErrorAction Stop

$Size = (Get-Item $File).length

if ($Size -lt 10) {
    throw " File size is too small."
}
try {
    # No per-byte conversion needed here
    [byte[]]$FileData = [System.IO.File]::ReadAllBytes($File)
} catch {
    throw " Cannot read file. Try providing the full file path."
}

# Magic bytes 0x48 0x44 0x52 0x32 = ASCII "HDR2"
if ((($FileData[0] -ne 0x48) -or ($FileData[1] -ne 0x44) -or ($FileData[2] -ne 0x52) -or ($FileData[3] -ne 0x32)) -and (-not $SkipHeaderCheck)) {
    throw "File header check failed."
} else {
    # Bytes 4-6 store the data length as a 3-byte little-endian integer (byte 4 = LSB, byte 6 = MSB)
    $DataLength = [int]$FileData[4] + ([int]$FileData[5] * 256) + ([int]$FileData[6] * 65536)

    if ($DataLength -ne ($Size - 8)) {
        Write-Host " Data length check failed."
        exit
    } else {
        Write-Verbose " Configuration file appears to be valid."
    }
}

# Determine output directory
if ($OutputDirectory) {
    if (-not (Test-Path $OutputDirectory)) {
        $splatNewDir = @{
            ItemType = "Directory"
            Path     = $OutputDirectory
            Force    = $true
        }
        New-Item @splatNewDir | Out-Null
    }
    $FilePath = (Get-Item -Path $OutputDirectory).FullName
} else {
    $FilePath = [System.IO.Path]::GetDirectoryName($File)
}

$Rand = $FileData[7]
$i = 8
$DecodedBytes = New-Object System.Collections.Generic.List[byte]

Write-Verbose " Decoding configuration file..."
while ($i -lt $Size) {
    $CurrentByte = $FileData[$i]
    if ($CurrentByte -gt 252) {
        if ($i -gt 8 -and $FileData[$i - 1] -ne 0x00) {
            $DecodedBytes.Add(0x00)
        }
    } else {
        # $B is always >= 3 (0xFF + 0 - 252); upper clamp handles Rand > CurrentByte overflow
        $B = 0xFF + $Rand - $CurrentByte
        if ($B -gt 255) {
            $B = 255
        }
        $DecodedBytes.Add([byte]$B)
    }
    $i++
}

# Convert decoded bytes to a string and replace the null character with a new line
$DecodedString = -join ($DecodedBytes | ForEach-Object { if ($_ -eq 0) { "`n" } else { [char]$_ } })

# Write the decoded string to the output file
$FileNameNoExt = [System.IO.Path]::GetFileNameWithoutExtension($File)
$DestName = $FileNameNoExt + "_Decoded.txt"
$OutputFile = Join-Path -Path $FilePath -ChildPath $DestName
$splatOutDecoded = @{
    FilePath = $OutputFile
    Encoding = "ascii"
    Force    = $Force.IsPresent
}
$DecodedString | Out-File @splatOutDecoded
Write-Host " ->Decoded configuration file has been saved to:"
Write-Host "   $OutputFile" -ForegroundColor Green
# Export dhcp_staticlist
$DHCPMatch = Select-String -Path $OutputFile -Pattern "dhcp_staticlist=.+"
if ($DHCPMatch) {
    Write-Host " Found DHCP client list"
    $DHCPInfo = $DHCPMatch.Line -replace "dhcp_staticlist=", ""
    $Header = "        MAC       |      IP       |   HostName "
    $DHCPInfo = $DHCPInfo -replace "<", "`n" -replace ">>", " | " -replace ">", " | "
    $DHCPInfo = "$Header$DHCPInfo"
    $DestName = $FileNameNoExt + "_DHCP.txt"
    $DHCPFile = Join-Path -Path $FilePath -ChildPath $DestName
    $splatOutDHCP = @{
        FilePath = $DHCPFile
        Encoding = "ascii"
    }
    $DHCPInfo | Out-File @splatOutDHCP
    Write-Host " ->DHCP client list has been saved to:"
    Write-Host "   $DHCPFile" -ForegroundColor Green
}
# Retrieve admin username & password, and any configured SSID and password
Write-Host " ->Attempting to identify:`n    HTTP (admin) username & password`n    PPPOE credentials`n    SSIDs (Wi-Fi names)`n    WPA PSKs (Wi-Fi passwords)"

$CredMatches = Select-String -Path $OutputFile -Pattern "_wpa_psk=.+|wl.*_ssid=.+|http_passwd=.+|http_username=.+|pppoe_passwd=.+|pppoe_username=.+"
$CredLines = $CredMatches | Select-Object -ExpandProperty Line
Write-Host $("=" * 60) -ForegroundColor Green
$CredLines
Write-Host $("=" * 60) -ForegroundColor Green
if ($CredLines) {
    $DestName = $FileNameNoExt + "_Credentials.txt"
    $CredFile = Join-Path -Path $FilePath -ChildPath $DestName
    $splatOutCred = @{
        FilePath = $CredFile
        Encoding = "ascii"
    }
    $CredLines | Out-File @splatOutCred
    Write-Host " ->Credentials have been saved to:"
    Write-Host "   $CredFile" -ForegroundColor Green
}