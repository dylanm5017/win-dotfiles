[CmdletBinding()]
param(
    # Validate only the committed config files (JSON/JSONC/XML/YAML/TOML/Lua) and PowerShell parse,
    # skipping the live-machine checks. Used by the git pre-commit hook and CI, where the host state
    # (installed tools, symlinks, registry) is neither present nor relevant.
    [switch]$ConfigOnly
)

if ($ConfigOnly) {
    . (Join-Path $PSScriptRoot 'profile.d\140-reliability.ps1')
    $repoRoot = Split-Path -Parent $PSScriptRoot

    $results = @(Test-WinDotfilesConfig -RepoRoot $repoRoot)

    $parsePaths = @(
        (Join-Path $repoRoot 'powershell')
        (Join-Path $repoRoot 'tools')
        (Join-Path $repoRoot 'install.ps1')
    ) | Where-Object { Test-Path -LiteralPath $_ }
    $parseErrors = Test-PowerShellScriptsParse -Path $parsePaths
    $results += New-WinDotfilesCheckResult 'PowerShell scripts parse' (-not $parseErrors) ($(if ($parseErrors) { "$(@($parseErrors).Count) parse error(s)" } else { 'OK' }))
}
else {
    . (Join-Path $PSScriptRoot 'profile.ps1')
    $results = Test-WinDotfiles -Quiet
}

$failed = @($results | Where-Object { -not $_.Passed })

$results |
Sort-Object Passed, Name |
Format-Table -AutoSize

if ($failed) {
    exit 1
}
