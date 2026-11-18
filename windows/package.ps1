$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$build = Join-Path $root 'build'
$publish = Join-Path $build 'windows-x64'
$archive = Join-Path $build 'Agent-Office-Windows-x64.zip'
$oldPackages = $env:NUGET_PACKAGES
$env:NUGET_PACKAGES = Join-Path $build 'nuget'
try {
    dotnet publish (Join-Path $PSScriptRoot 'AgentOffice.csproj') -c Release -r win-x64 --self-contained true -o $publish
    if ($LASTEXITCODE -ne 0 -or !(Test-Path (Join-Path $publish 'AgentOffice.exe'))) {
        throw 'Windows publish failed'
    }
    $frameworks = (Get-Content (Join-Path $publish 'AgentOffice.runtimeconfig.json') -Raw | ConvertFrom-Json).runtimeOptions.includedFrameworks
    foreach ($framework in $frameworks) {
        $name = $framework.name.ToLowerInvariant()
        $pack = Join-Path $env:NUGET_PACKAGES "$name.runtime.win-x64/$($framework.version)"
        foreach ($notice in @(Get-ChildItem $pack -File | Where-Object { $_.Name -match '^(LICENSE|THIRD-PARTY-NOTICES)(\.|$)' })) {
            Copy-Item $notice.FullName (Join-Path $publish "licenses/$name-$($notice.Name).txt")
        }
    }
    Compress-Archive -Path "$publish/*" -DestinationPath $archive -Force
    Write-Host $archive
} finally {
    $env:NUGET_PACKAGES = $oldPackages
}
