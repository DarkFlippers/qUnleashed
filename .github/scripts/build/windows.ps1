param(
    [string]$FlutterBin = $env:FLUTTER_BIN
)

$ErrorActionPreference = "Stop"

$RootDir = (Resolve-Path (Join-Path $PSScriptRoot "..\..\..")).Path
$AppName = "qunleashed"
# The asset version, which carries the channel suffix and build number on a dev
# build so its filenames differ from the release of the same cycle. Falls back
# to the numeric name, then to pubspec.
$VersionName = $env:QUNLEASHED_ASSET_VERSION
if ([string]::IsNullOrWhiteSpace($VersionName)) {
    $VersionName = $env:QUNLEASHED_VERSION_NAME
}
if ([string]::IsNullOrWhiteSpace($VersionName)) {
    $pubspecPath = Join-Path $RootDir "pubspec.yaml"
    $versionLine = Get-Content -Path $pubspecPath | Where-Object { $_ -match '^version:\s*([0-9A-Za-z._-]+)' } | Select-Object -First 1
    if ($versionLine -match '^version:\s*([0-9A-Za-z._-]+)') {
        $VersionName = ($Matches[1] -split '\+')[0]
    }
}
if ([string]::IsNullOrWhiteSpace($VersionName)) {
    throw "App version not found. Set QUNLEASHED_ASSET_VERSION or pubspec.yaml version."
}
$DistDir = Join-Path $RootDir "dist"
$OutFile = Join-Path $DistDir "$AppName`_$VersionName`_windows_x64.exe"
$RawZipFile = Join-Path $DistDir "$AppName`_$VersionName`_windows_x64_raw.zip"

if ([string]::IsNullOrWhiteSpace($FlutterBin)) {
    $flutterCommand = Get-Command flutter -ErrorAction SilentlyContinue
    if ($null -eq $flutterCommand) {
        throw "Flutter executable not found. Set FLUTTER_BIN=C:\path\to\flutter.bat."
    }
    $FlutterBin = $flutterCommand.Source
}

if (-not (Test-Path $FlutterBin)) {
    throw "Flutter executable not found: $FlutterBin"
}

New-Item -ItemType Directory -Force -Path $DistDir | Out-Null

Write-Host "Using Flutter: $FlutterBin"
Write-Host "Building Windows release..."

$buildArgs = @("build", "windows", "--release")
if (-not [string]::IsNullOrWhiteSpace($env:QUNLEASHED_FLUTTER_BUILD_ARGS)) {
    $buildArgs += $env:QUNLEASHED_FLUTTER_BUILD_ARGS -split "\s+"
}

Push-Location $RootDir
try {
    & $FlutterBin @buildArgs
    if ($LASTEXITCODE -ne 0) {
        throw "Flutter build failed with exit code $LASTEXITCODE."
    }
}
finally {
    Pop-Location
}

$buildCandidates = @(
    (Join-Path $RootDir "build\windows\x64\runner\Release"),
    (Join-Path $RootDir "build\windows\runner\Release")
)
$BuildDir = $buildCandidates | Where-Object { Test-Path (Join-Path $_ "$AppName.exe") } | Select-Object -First 1
if ([string]::IsNullOrWhiteSpace($BuildDir)) {
    throw "Expected app binary not found in: $($buildCandidates -join ', ')"
}

# The PDBs have to exist before there is any point excluding them, and this
# check is the important one of the two. #310 was not a bundle that shipped too
# much; it was a toolchain that produced nothing and a pipeline that reported
# success anyway. In that state the exclusion below excludes nothing, the leak
# assertion finds nothing, `sentry-cli` uploads the PEs and exits 0, and the
# Sentry step is `continue-on-error` regardless - so every gate is green and
# Windows traces are back to `guard_dispatch_icall$thunk$`. A guard that cannot
# fail is a rubber stamp; `check_ffi_exports.sh` argues the same about a regex
# that matches nothing.
#
# The runner AND our own FFI libraries, by name. The runner alone would be the
# weakest possible check: it lands here from the linker's default and would
# still be here with `CMAKE_PDB_OUTPUT_DIRECTORY` deleted, so a guard that
# names only it passes while every plugin PDB is missing. The three in
# `lib/modules/cpp` are the ones that went unoptimized and undebuggable when
# `/Zi` was appended before C was enabled, and they are most of what a desktop
# crash is.
$ExpectedPdbs = @("$AppName.pdb")
foreach ($lib in @("mfkey32", "hardnested", "faaccrack")) {
    $ExpectedPdbs += "${AppName}_$lib.pdb"
}
$MissingPdbs = $ExpectedPdbs | Where-Object { -not (Test-Path (Join-Path $BuildDir $_)) }
if ($MissingPdbs) {
    throw "No $($MissingPdbs -join ', ') in $BuildDir, so Sentry cannot symbolicate a Windows crash. Release must compile with /Zi and link with /DEBUG, and C must be enabled before the append - see the debug information block in windows/CMakeLists.txt. (#310)"
}
$PdbCount = @(Get-ChildItem -Path $BuildDir -Filter *.pdb -Force).Count
Write-Host "Debug files for Sentry: $PdbCount PDB(s) in the bundle."

# Preserve the standard Flutter Windows bundle before creating the optional
# self-extracting executable, minus the PDBs. `windows/CMakeLists.txt` collects
# every target's PDB into this directory so one upload covers the whole
# application; they are for Sentry, not for a download, and they outweigh the
# thing being shipped. The upload step runs after this script and reads the
# directory, not the archive, so excluding them here costs nothing.
#
# `-Exclude` has to go on `Get-ChildItem`: `Compress-Archive` has no exclusion
# of its own. Top-level entries are what the old `"*"` glob passed too, and
# directories still go in whole.
#
# `-Force` so a hidden or system file still goes in: the old `"$BuildDir\*"`
# glob was expanded by `Compress-Archive` itself and did not filter them, and a
# file silently absent from the shipped ZIP is the same class of fault as a
# file silently present in it.
$BundleEntries = Get-ChildItem -Path $BuildDir -Exclude "*.pdb" -Force
Compress-Archive -Path $BundleEntries -DestinationPath $RawZipFile -CompressionLevel Optimal -Force

# The exclusion above is the only thing standing between a debug file and a
# user, and the self-extracting EXE below is built from this same archive - so
# it is asserted rather than trusted. A PDB nested inside a subdirectory would
# slip past `-Exclude`, which only sees the top level.
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip = [System.IO.Compression.ZipFile]::OpenRead($RawZipFile)
try {
    # `@(...)` because member enumeration over a one-entry collection yields a
    # scalar, and `-like` on a scalar returns a bool - the throw below would
    # then say "True" instead of naming the file.
    $leaked = @($zip.Entries.FullName) -like "*.pdb"
}
finally {
    $zip.Dispose()
}
if ($leaked) {
    throw "Debug symbols leaked into $RawZipFile and would ship to users: $($leaked -join ', ')"
}

Write-Host "Built raw Windows archive:"
Write-Host $RawZipFile

$TempDir = Join-Path ([System.IO.Path]::GetTempPath()) "$AppName-build-$PID"
$PayloadZip = Join-Path $TempDir "payload.zip"
$StubSource = Join-Path $TempDir "SelfExtractingLauncher.cs"
$StubExe = Join-Path $TempDir "stub.exe"
$Marker = [System.Text.Encoding]::ASCII.GetBytes("`r`n__QUNLEASHED_PAYLOAD_BELOW__`r`n")

if (Test-Path $TempDir) {
    Remove-Item -Recurse -Force $TempDir
}
New-Item -ItemType Directory -Force -Path $TempDir | Out-Null

try {
    Copy-Item -Path $RawZipFile -Destination $PayloadZip -Force

    @'
using System;
using System.Diagnostics;
using System.IO;
using System.IO.Compression;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;

internal static class SelfExtractingLauncher
{
    private const string AppExe = "qunleashed.exe";
    private const string SentinelFile = ".qunleashed_payload_extracted";
    private static readonly byte[] Marker = Encoding.ASCII.GetBytes("\r\n__QUNLEASHED_PAYLOAD_BELOW__\r\n");

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern int MessageBox(IntPtr hWnd, string text, string caption, uint type);

    [STAThread]
    private static int Main(string[] args)
    {
        try
        {
            string selfPath = Assembly.GetExecutingAssembly().Location;
            string workDir = Path.Combine(Path.GetTempPath(), "qunleashed-self-" + GetFileHashPrefix(selfPath));
            string appPath = Path.Combine(workDir, AppExe);
            string sentinelPath = Path.Combine(workDir, SentinelFile);

            if (!File.Exists(appPath) || !File.Exists(sentinelPath))
            {
                if (Directory.Exists(workDir))
                {
                    Directory.Delete(workDir, true);
                }
                Directory.CreateDirectory(workDir);
                ExtractPayload(selfPath, workDir);
            }

            ProcessStartInfo startInfo = new ProcessStartInfo(appPath)
            {
                UseShellExecute = false,
                WorkingDirectory = workDir,
                Arguments = JoinArguments(args)
            };

            using (Process process = Process.Start(startInfo))
            {
                process.WaitForExit();
                return process.ExitCode;
            }
        }
        catch (Exception ex)
        {
            MessageBox(IntPtr.Zero, ex.ToString(), "qUnleashed launch failed", 0x00000010);
            Console.Error.WriteLine(ex.ToString());
            return 1;
        }
    }

    private static void ExtractPayload(string selfPath, string workDir)
    {
        byte[] bytes = File.ReadAllBytes(selfPath);
        int markerIndex = IndexOf(bytes, Marker);
        if (markerIndex < 0)
        {
            throw new InvalidDataException("Embedded payload marker not found.");
        }

        string payloadPath = Path.Combine(workDir, "payload.zip");
        using (FileStream output = File.Create(payloadPath))
        {
            output.Write(bytes, markerIndex + Marker.Length, bytes.Length - markerIndex - Marker.Length);
        }

        ZipFile.ExtractToDirectory(payloadPath, workDir);
        File.Delete(payloadPath);
        File.WriteAllText(Path.Combine(workDir, SentinelFile), DateTime.UtcNow.ToString("O"));
    }

    private static string JoinArguments(string[] args)
    {
        StringBuilder builder = new StringBuilder();
        for (int i = 0; i < args.Length; i++)
        {
            if (i > 0)
            {
                builder.Append(' ');
            }
            builder.Append(QuoteArgument(args[i]));
        }
        return builder.ToString();
    }

    private static string QuoteArgument(string arg)
    {
        if (arg.Length == 0)
        {
            return "\"\"";
        }

        bool needsQuotes = arg.IndexOfAny(new[] { ' ', '\t', '\n', '\v', '"' }) >= 0;
        if (!needsQuotes)
        {
            return arg;
        }

        StringBuilder builder = new StringBuilder();
        builder.Append('"');
        int backslashes = 0;
        foreach (char c in arg)
        {
            if (c == '\\')
            {
                backslashes++;
                continue;
            }
            if (c == '"')
            {
                builder.Append('\\', backslashes * 2 + 1);
                builder.Append('"');
                backslashes = 0;
                continue;
            }
            builder.Append('\\', backslashes);
            builder.Append(c);
            backslashes = 0;
        }
        builder.Append('\\', backslashes * 2);
        builder.Append('"');
        return builder.ToString();
    }

    private static int IndexOf(byte[] source, byte[] pattern)
    {
        for (int i = 0; i <= source.Length - pattern.Length; i++)
        {
            bool matched = true;
            for (int j = 0; j < pattern.Length; j++)
            {
                if (source[i + j] != pattern[j])
                {
                    matched = false;
                    break;
                }
            }
            if (matched)
            {
                return i;
            }
        }
        return -1;
    }

    private static string GetFileHashPrefix(string path)
    {
        using (SHA256 sha256 = SHA256.Create())
        using (FileStream stream = File.OpenRead(path))
        {
            byte[] hash = sha256.ComputeHash(stream);
            StringBuilder builder = new StringBuilder(16);
            for (int i = 0; i < 8; i++)
            {
                builder.Append(hash[i].ToString("x2"));
            }
            return builder.ToString();
        }
    }
}
'@ | Set-Content -Path $StubSource -Encoding ASCII

    $cscPath = "${env:SystemRoot}\Microsoft.NET\Framework64\v4.0.30319\csc.exe"
    if (-not (Test-Path $cscPath)) {
        $cscPath = "${env:SystemRoot}\Microsoft.NET\Framework\v4.0.30319\csc.exe"
    }
    if (-not (Test-Path $cscPath)) {
        throw "csc.exe not found. Cannot compile self-extracting stub."
    }
    & $cscPath /nologo /target:winexe /out:"$StubExe" /reference:"System.IO.Compression.dll" /reference:"System.IO.Compression.FileSystem.dll" "$StubSource"
    if ($LASTEXITCODE -ne 0) {
        throw "C# compilation failed with exit code $LASTEXITCODE."
    }

    $stubBytes = [System.IO.File]::ReadAllBytes($StubExe)
    $payloadBytes = [System.IO.File]::ReadAllBytes($PayloadZip)
    $stream = [System.IO.File]::Create($OutFile)
    try {
        $stream.Write($stubBytes, 0, $stubBytes.Length)
        $stream.Write($Marker, 0, $Marker.Length)
        $stream.Write($payloadBytes, 0, $payloadBytes.Length)
    }
    finally {
        $stream.Dispose()
    }
}
finally {
    Remove-Item -Recurse -Force $TempDir -ErrorAction SilentlyContinue
}

Write-Host "Built single-file executable:"
Write-Host $OutFile
