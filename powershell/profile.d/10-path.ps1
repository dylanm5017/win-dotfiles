$UserBinPath = Join-Path $HOME 'bin'
$PreferredPathEntries = @($UserBinPath, $ToolsRoot, $env:NPM_CONFIG_PREFIX) | Where-Object { $_ } | Select-Object -Unique
$PathSeparator = [IO.Path]::PathSeparator
$CurrentPathParts = @($env:Path -split [regex]::Escape([string]$PathSeparator) | Where-Object { $_ })

if ($IsCodexShell) {
    $codexArg0Root = [IO.Path]::GetFullPath((Join-Path $HOME '.codex\tmp\arg0'))
    $CurrentPathParts = @(
        $CurrentPathParts | Where-Object {
            try {
                -not [IO.Path]::GetFullPath($_).StartsWith($codexArg0Root, [StringComparison]::OrdinalIgnoreCase)
            }
            catch {
                $true
            }
        }
    )
    $env:Path = ($CurrentPathParts -join $PathSeparator)
}

$MissingPathEntries = @($PreferredPathEntries | Where-Object { $CurrentPathParts -notcontains $_ })
if ($MissingPathEntries) {
    $env:Path = (($MissingPathEntries + @($env:Path)) -join $PathSeparator)
}

function Sync-WinDotfilesUserPath {
    [CmdletBinding(SupportsShouldProcess)]
    param()

    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    $UserPathParts = @($UserPath -split [regex]::Escape([string]$PathSeparator) | Where-Object { $_ -and ($PreferredPathEntries -notcontains $_) })
    $updatedUserPath = (($PreferredPathEntries + $UserPathParts) -join $PathSeparator)

    try {
        if ($PSCmdlet.ShouldProcess('User Path', "Put win-dotfiles entries first: $($PreferredPathEntries -join ', ')")) {
            [Environment]::SetEnvironmentVariable('Path', $updatedUserPath, 'User')
            Write-Host 'Updated User Path with win-dotfiles tool entries.' -ForegroundColor Green
        }
    }
    catch {
        Write-Warning "User Path update failed: $($_.Exception.Message)"
    }
}
