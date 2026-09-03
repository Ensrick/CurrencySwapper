[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })]
    [string] $SkyrimExe,

    [Parameter(Mandatory)]
    [ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })]
    [string] $AddressLibrary
)

$ErrorActionPreference = 'Stop'

$libraryBytes = [IO.File]::ReadAllBytes((Resolve-Path -LiteralPath $AddressLibrary))
if ($libraryBytes.Length -lt 96) {
    throw 'Address Library file is too short to contain a format-5 header.'
}

$format = [BitConverter]::ToInt32($libraryBytes, 0)
$versionParts = 0..3 | ForEach-Object {
    [BitConverter]::ToUInt32($libraryBytes, 4 + ($_ * 4))
}
$version = $versionParts -join '.'
$imageName = [Text.Encoding]::ASCII.GetString($libraryBytes, 20, 64).Trim([char] 0)
$pointerSize = [BitConverter]::ToInt32($libraryBytes, 84)
$offsetCount = [BitConverter]::ToInt32($libraryBytes, 92)

if ($format -ne 5 -or $version -ne '1.7.104.0' -or $imageName -ne 'SkyrimSE.exe' -or $pointerSize -ne 8) {
    throw "Unexpected Address Library header: format=$format version=$version image=$imageName pointerSize=$pointerSize"
}

$requiredLibrarySize = 96L + (4L * $offsetCount)
if ($offsetCount -le 0 -or $libraryBytes.Length -lt $requiredLibrarySize) {
    throw "Address Library is truncated: bytes=$($libraryBytes.Length) required=$requiredLibrarySize"
}

$executablePath = (Resolve-Path -LiteralPath $SkyrimExe).Path
$executableVersion = (Get-Item -LiteralPath $executablePath).VersionInfo.FileVersion
if ([version] $executableVersion -ne [version] '1.7.104.0') {
    throw "Unexpected Skyrim executable version: $executableVersion"
}

$executableBytes = [IO.File]::ReadAllBytes($executablePath)
$peOffset = [BitConverter]::ToInt32($executableBytes, 0x3C)
if ([Text.Encoding]::ASCII.GetString($executableBytes, $peOffset, 4) -ne "PE$([char] 0)$([char] 0)") {
    throw 'Skyrim executable does not have a valid PE signature.'
}

$sectionCount = [BitConverter]::ToUInt16($executableBytes, $peOffset + 6)
$optionalHeaderSize = [BitConverter]::ToUInt16($executableBytes, $peOffset + 20)
$sectionTableOffset = $peOffset + 24 + $optionalHeaderSize
$sections = for ($index = 0; $index -lt $sectionCount; $index++) {
    $sectionOffset = $sectionTableOffset + (40 * $index)
    [pscustomobject] @{
        Name = [Text.Encoding]::ASCII.GetString($executableBytes, $sectionOffset, 8).Trim([char] 0)
        VirtualSize = [uint64] [BitConverter]::ToUInt32($executableBytes, $sectionOffset + 8)
        VirtualAddress = [uint64] [BitConverter]::ToUInt32($executableBytes, $sectionOffset + 12)
        RawSize = [uint64] [BitConverter]::ToUInt32($executableBytes, $sectionOffset + 16)
        RawOffset = [uint64] [BitConverter]::ToUInt32($executableBytes, $sectionOffset + 20)
    }
}

function Get-LibraryOffset {
    param([Parameter(Mandatory)][int] $Id)

    if ($Id -lt 0 -or $Id -ge $offsetCount) {
        throw "Address Library ID $Id is outside the dense table (count=$offsetCount)."
    }

    [BitConverter]::ToUInt32($libraryBytes, 96 + (4 * $Id))
}

function Get-ExecutableByte {
    param([Parameter(Mandatory)][uint64] $Rva)

    $section = $sections | Where-Object {
        $Rva -ge $_.VirtualAddress -and
        $Rva -lt ($_.VirtualAddress + [Math]::Max($_.VirtualSize, $_.RawSize))
    } | Select-Object -First 1

    if (-not $section) {
        throw ('RVA 0x{0:X} is not contained in a PE section.' -f $Rva)
    }

    $fileOffset = $section.RawOffset + ($Rva - $section.VirtualAddress)
    if ($fileOffset -ge $executableBytes.Length) {
        throw ('RVA 0x{0:X} resolves beyond the executable.' -f $Rva)
    }

    [pscustomobject] @{
        Section = $section.Name
        FileOffset = $fileOffset
        Byte = $executableBytes[$fileOffset]
    }
}

$hookSites = @(
    @(50957, 0x069, 'Barter.GetPlayerGold'),
    @(50957, 0x139, 'Barter.GetVendorGold'),
    @(50951, 0x257, 'Barter.GetGoldFromSale'),
    @(50951, 0x121, 'Barter.GetGoldFromPurchase'),
    @(50952, 0x0B1, 'Barter.RawDeal'),
    @(50951, 0x1A7, 'Barter.RejectedDeal'),
    @(50957, 0x2F7, 'Barter.RecalcVendorGold'),
    @(50955, 0x021, 'Barter.ShowMenu'),
    @(40659, 0x12B, 'Crime.RemoveBounty'),
    @(21704, 0x03C, 'Crime.CanPay'),
    @(16127, 0x182, 'Notification.ItemAdded'),
    @(52666, 0x17E, 'Training.SetupMenu'),
    @(52667, 0x096, 'Training.GetPlayerGold'),
    @(52667, 0x087, 'Training.CalculateCost'),
    @(52668, 0x291, 'Training.CostText'),
    @(52667, 0x0C3, 'Training.RemoveGold'),
    @(52667, 0x1BB, 'Training.NotEnoughGold'),
    @(52668, 0x31B, 'Training.UpdateCurrency')
)

$results = foreach ($site in $hookSites) {
    $id = [int] $site[0]
    $delta = [int] $site[1]
    $baseRva = [uint64] (Get-LibraryOffset -Id $id)
    if ($baseRva -eq 0) {
        throw "Address Library ID $id has no offset."
    }

    $siteRva = $baseRva + $delta
    $resolved = Get-ExecutableByte -Rva $siteRva
    [pscustomobject] @{
        Hook = [string] $site[2]
        Id = $id
        SiteRva = '0x{0:X}' -f $siteRva
        Section = $resolved.Section
        Opcode = '0x{0:X2}' -f $resolved.Byte
        Pass = $resolved.Byte -eq 0xE8
    }
}

$results | Format-Table -AutoSize

$callableIds = 50957, 16059, 51636
foreach ($id in $callableIds) {
    if ((Get-LibraryOffset -Id $id) -eq 0) {
        throw "Required callable Address Library ID $id has no offset."
    }
}

$failed = @($results | Where-Object { -not $_.Pass })
if ($failed.Count -ne 0) {
    throw "$($failed.Count) hook site(s) do not begin with the expected E8 call opcode."
}

Write-Host "PASS: format-5 Address Library, runtime metadata, 18 guarded hook sites, and 3 callable IDs validated for Skyrim 1.7.104.0."
