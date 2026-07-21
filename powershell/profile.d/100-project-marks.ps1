function Set-ProjectMark {
    Set-Variable -Scope Global -Name proj -Value (Get-Location)
}

function Set-LocationToProjectMark {
    Set-Location $global:proj
}

if ($null -eq $global:proj) {
    Set-ProjectMark
}

Set-Alias mark Set-ProjectMark
Set-Alias goto Set-LocationToProjectMark
