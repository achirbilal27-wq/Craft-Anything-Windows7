[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string[]] $BinaryPath
)

$ErrorActionPreference = "Stop"

$vswhere = Join-Path ${env:ProgramFiles(x86)} "Microsoft Visual Studio\Installer\vswhere.exe"
if (-not (Test-Path -LiteralPath $vswhere)) {
    throw "vswhere.exe was not found; Windows C++ build tools are required for PE import auditing."
}

$dumpbin = & $vswhere -latest -products "*" -find "VC\Tools\MSVC\**\bin\Hostx64\x64\dumpbin.exe" 2>$null | Select-Object -First 1
if (-not $dumpbin -or -not (Test-Path -LiteralPath $dumpbin)) {
    throw "dumpbin.exe was not found in the installed Visual Studio toolchain."
}

$forbidden = @(
    @{ Pattern = '(?i)\\bcombase\\.dll\\b'; Reason = "COMBASE.DLL is not present on Windows 7; COM imports must target OLE32.DLL" },
    @{ Pattern = '(?i)\bapi-ms-win-core-synch-l1-2-0\.dll\b'; Reason = "Windows 8 synchronization API-set DLL" },
    @{ Pattern = '(?i)\bbcryptprimitives\.dll\b'; Reason = "Windows 8 ProcessPrng provider DLL" },
    @{ Pattern = '(?i)\bWaitOnAddress\b'; Reason = "WaitOnAddress requires Windows 8" },
    @{ Pattern = '(?i)\bWakeByAddressSingle\b'; Reason = "WakeByAddressSingle requires Windows 8" },
    @{ Pattern = '(?i)\bWakeByAddressAll\b'; Reason = "WakeByAddressAll requires Windows 8" },
    @{ Pattern = '(?i)\bProcessPrng\b'; Reason = "ProcessPrng requires Windows 8" },
    @{ Pattern = '(?i)\bGetSystemTimePreciseAsFileTime\b'; Reason = "GetSystemTimePreciseAsFileTime is newer than Windows 7" }
)

$failed = $false
foreach ($path in $BinaryPath) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Expected executable was not produced: $path"
    }

    $imports = & $dumpbin /nologo /imports $path 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "dumpbin could not inspect imports for $path"
    }

    $violations = @()
    foreach ($rule in $forbidden) {
        $hits = @($imports | Select-String -Pattern $rule.Pattern)
        foreach ($hit in $hits) {
            $violations += "$($rule.Reason): $($hit.Line.Trim())"
        }
    }

    if ($violations.Count -gt 0) {
        $failed = $true
        Write-Host "::error file=$path::Windows 7 incompatible imports were found."
        foreach ($violation in $violations) { Write-Host "  $violation" }
    }
    else {
        Write-Host "Windows 7 import audit passed: $path"
    }
}

if ($failed) {
    throw "One or more executables still import APIs that are unavailable on Windows 7."
}
