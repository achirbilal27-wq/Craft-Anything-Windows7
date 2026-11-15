[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string[]] $BinaryPath
)

$ErrorActionPreference = "Stop"
$allowedComExports = @("CoTaskMemFree", "CoCreateFreeThreadedMarshaler")

function Read-AsciiZ([byte[]] $Bytes, [int] $Offset) {
    $end = $Offset
    while ($end -lt $Bytes.Length -and $Bytes[$end] -ne 0) { $end++ }
    if ($end -ge $Bytes.Length) { throw "Unterminated PE string at file offset $Offset" }
    return [System.Text.Encoding]::ASCII.GetString($Bytes, $Offset, $end - $Offset)
}

function Convert-RvaToOffset([uint32] $Rva, [byte[]] $Bytes, [int] $SectionTable, [int] $SectionCount) {
    for ($i = 0; $i -lt $SectionCount; $i++) {
        $s = $SectionTable + ($i * 40)
        $virtualSize = [BitConverter]::ToUInt32($Bytes, $s + 8)
        $virtualAddress = [BitConverter]::ToUInt32($Bytes, $s + 12)
        $rawSize = [BitConverter]::ToUInt32($Bytes, $s + 16)
        $rawPointer = [BitConverter]::ToUInt32($Bytes, $s + 20)
        $span = [Math]::Max([double]$virtualSize, [double]$rawSize)
        if ($Rva -ge $virtualAddress -and [double]($Rva - $virtualAddress) -lt $span) {
            $delta = [uint64]($Rva - $virtualAddress)
            if ($delta -ge $rawSize) { throw ("RVA 0x{0:X} points into an unbacked section" -f $Rva) }
            $offset = [uint64]$rawPointer + $delta
            if ($offset -ge $Bytes.Length) { throw "RVA maps outside the file." }
            return [int]$offset
        }
    }
    if ($Rva -lt 0x1000 -and $Rva -lt $Bytes.Length) { return [int]$Rva }
    throw ("Could not map PE RVA 0x{0:X} to file data." -f $Rva)
}

foreach ($path in $BinaryPath) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Missing executable: $path" }
    $bytes = [System.IO.File]::ReadAllBytes((Resolve-Path -LiteralPath $path).Path)
    if ($bytes.Length -lt 256 -or [BitConverter]::ToUInt16($bytes, 0) -ne 0x5A4D) { throw "Not a valid PE executable: $path" }

    $pe = [BitConverter]::ToInt32($bytes, 0x3C)
    if ($pe -lt 0 -or $pe + 24 -ge $bytes.Length -or [BitConverter]::ToUInt32($bytes, $pe) -ne 0x00004550) { throw "Invalid PE signature: $path" }
    $sectionCount = [BitConverter]::ToUInt16($bytes, $pe + 6)
    $optionalSize = [BitConverter]::ToUInt16($bytes, $pe + 20)
    $optional = $pe + 24
    if ([BitConverter]::ToUInt16($bytes, $optional) -ne 0x20B) { throw "Expected PE32+ x64 executable: $path" }
    if ($optionalSize -lt 128) { throw "PE optional header is too small: $path" }

    $sectionTable = $optional + $optionalSize
    $importRva = [BitConverter]::ToUInt32($bytes, $optional + 120)
    if ($importRva -eq 0) { throw "No PE import directory found: $path" }
    $importOffset = Convert-RvaToOffset $importRva $bytes $sectionTable $sectionCount
    $patched = 0

    for ($d = 0; $d -lt 4096; $d++) {
        $descriptor = $importOffset + ($d * 20)
        if ($descriptor + 20 -gt $bytes.Length) { throw "Import directory exceeds file bounds: $path" }
        $originalThunk = [BitConverter]::ToUInt32($bytes, $descriptor)
        $nameRva = [BitConverter]::ToUInt32($bytes, $descriptor + 12)
        $firstThunk = [BitConverter]::ToUInt32($bytes, $descriptor + 16)
        if ($originalThunk -eq 0 -and $nameRva -eq 0 -and $firstThunk -eq 0) { break }

        $nameOffset = Convert-RvaToOffset $nameRva $bytes $sectionTable $sectionCount
        $dllName = Read-AsciiZ $bytes $nameOffset
        if ($dllName -ieq "combase.dll") {
            $thunkRva = if ($originalThunk -ne 0) { $originalThunk } else { $firstThunk }
            $thunkOffset = Convert-RvaToOffset $thunkRva $bytes $sectionTable $sectionCount
            $found = @()
            for ($t = 0; $t -lt 4096; $t++) {
                $entryOffset = $thunkOffset + ($t * 8)
                if ($entryOffset + 8 -gt $bytes.Length) { throw "Import thunk exceeds file bounds: $path" }
                $entry = [BitConverter]::ToUInt64($bytes, $entryOffset)
                if ($entry -eq 0) { break }
                if (($entry -shr 63) -ne 0) { throw "Ordinal import from combase.dll is not approved for redirection: $path" }
                $ibn = Convert-RvaToOffset ([uint32]$entry) $bytes $sectionTable $sectionCount
                $symbol = Read-AsciiZ $bytes ($ibn + 2)
                if ($symbol -notin $allowedComExports) { throw "Unexpected combase.dll import '$symbol' in $path; refusing to redirect." }
                $found += $symbol
            }
            if ($found.Count -eq 0) { throw "combase.dll descriptor had no named imports: $path" }

            $replacement = [System.Text.Encoding]::ASCII.GetBytes("ole32.dll")
            $oldLength = ([System.Text.Encoding]::ASCII.GetBytes($dllName)).Length
            if ($replacement.Length -gt $oldLength) { throw "Replacement DLL name does not fit in the existing PE string." }
            [Array]::Clear($bytes, $nameOffset, $oldLength + 1)
            [Array]::Copy($replacement, 0, $bytes, $nameOffset, $replacement.Length)
            $patched++
            Write-Host ("Redirected {0} import(s) in {1}: {2}" -f $found.Count, $path, ($found -join ", "))
        }
    }

    if ($patched -eq 0) { throw "Expected combase.dll import was not found; refusing an unverified build: $path" }
    [System.IO.File]::WriteAllBytes((Resolve-Path -LiteralPath $path).Path, $bytes)
    Write-Host "Patched PE import table: $path"
}
