param([string]$Dotnet = 'dotnet')
$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot
& $Dotnet build App/ScreenSpan.Windows.csproj -c Release --nologo
if ($LASTEXITCODE -ne 0) { throw 'Application build failed.' }
& $Dotnet run --project Tests/ScreenSpan.Tests.csproj -c Release
if ($LASTEXITCODE -ne 0) { throw 'Core checks failed.' }
$artifacts = Join-Path $PSScriptRoot 'artifacts'
New-Item -ItemType Directory -Force $artifacts | Out-Null
$exe = Join-Path $PSScriptRoot 'App/bin/Release/net48/ScreenSpan Wallpaper.exe'
$report = Join-Path $artifacts 'windows-checks.txt'
$process = Start-Process -FilePath $exe -ArgumentList @('--self-test', ('"' + $report + '"')) -Wait -PassThru
if ($process.ExitCode -ne 0) { throw "Windows rendering/project checks failed. See $report" }
Get-Content $report
& $Dotnet build Setup/ScreenSpan.Setup.csproj -c Release --nologo
if ($LASTEXITCODE -ne 0) { throw 'Installer build failed.' }
$setup = Join-Path $PSScriptRoot 'Setup/bin/Release/net48/ScreenSpan Wallpaper Setup.exe'
$testDirectory = Join-Path ([IO.Path]::GetTempPath()) ('ScreenSpan-Setup-Check-' + [Guid]::NewGuid())
try {
    $process = Start-Process -FilePath $setup -ArgumentList @('--self-test', ('"' + $testDirectory + '"')) -Wait -PassThru
    if ($process.ExitCode -ne 0) { throw "Installer standalone payload check failed. See $testDirectory" }
    Get-Content (Join-Path $testDirectory 'installer-checks.txt')
    Copy-Item (Join-Path $testDirectory 'installer-checks.txt') $artifacts
} finally {
    if (Test-Path $testDirectory) { Remove-Item -LiteralPath $testDirectory -Recurse -Force }
}
Copy-Item $exe (Join-Path $artifacts 'ScreenSpan-Wallpaper-Windows-1.0.5.exe') -Force
Copy-Item $setup (Join-Path $artifacts 'ScreenSpan-Wallpaper-Windows-Setup-1.0.5.exe') -Force
Compress-Archive -Path $exe, README.md, THIRD-PARTY-NOTICES.md -DestinationPath (Join-Path $artifacts 'ScreenSpan-Wallpaper-Windows-1.0.5-portable.zip') -Force
Get-ChildItem $artifacts -File | Where-Object Extension -in '.exe','.zip' | ForEach-Object {
    $hash = (Get-FileHash $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
    "$hash  $($_.Name)"
} | Set-Content (Join-Path $artifacts 'SHA256SUMS.txt')
Write-Host 'Built and checked Windows 1.0.5. Files are in artifacts.'
