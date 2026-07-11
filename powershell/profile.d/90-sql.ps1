function Start-SqlSvc {
    param([Parameter(Mandatory)][string] $Svc)

    if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()
        ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw 'Please run PowerShell as Administrator.'
    }

    Start-Service -Name $Svc -ErrorAction Stop
    Write-Host "Started $Svc" -ForegroundColor Green
}

function Stop-SqlSvc {
    param([Parameter(Mandatory)][string] $Svc)

    if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()
        ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw 'Please run PowerShell as Administrator.'
    }

    Stop-Service -Name $Svc -Force -ErrorAction Stop
    Write-Host "Stopped $Svc" -ForegroundColor Yellow
}

function Start-DefaultSql { Start-SqlSvc -Svc 'MSSQLSERVER' }
function Stop-DefaultSql { Stop-SqlSvc -Svc 'MSSQLSERVER' }
function Start-SqlAgent { Start-SqlSvc -Svc 'SQLSERVERAGENT' }
function Stop-SqlAgent { Stop-SqlSvc -Svc 'SQLSERVERAGENT' }
function Start-SqlBrowser { Start-SqlSvc -Svc 'SQLBrowser' }
function Stop-SqlBrowser { Stop-SqlSvc -Svc 'SQLBrowser' }

Set-Alias startsql Start-DefaultSql
Set-Alias stopsql Stop-DefaultSql
Set-Alias startagent Start-SqlAgent
Set-Alias stopagent Stop-SqlAgent
Set-Alias startbrowser Start-SqlBrowser
Set-Alias stopbrowser Stop-SqlBrowser

function Get-SqlServices {
    Get-Service -Name 'MSSQL*' -ErrorAction SilentlyContinue |
    Select-Object Name, DisplayName, Status
}

Set-Alias getSQL Get-SqlServices
