function Set-Mark-Proj {
    Set-Variable -Scope Global -Name proj -Value (Get-Location)
}

function Invoke-Set-Mark-Proj {
    Set-Location $global:proj
}

if ($null -eq $global:proj) {
    Set-Mark-Proj
}

Set-Alias mark Set-Mark-Proj
Set-Alias goto Invoke-Set-Mark-Proj
