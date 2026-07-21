if (Test-ShouldUseDefaultWorkspaceLocation) {
    Set-LocationIfExists $WorkspaceRoot
}

function ws {
    Set-LocationIfExists $WorkspaceRoot
}

function projects {
    Set-LocationIfExists $ProjectsRoot
}

function devroot {
    Set-LocationIfExists $DevRoot
}

function tools {
    Set-LocationIfExists $ToolsRoot
}

function cache {
    Set-LocationIfExists $CacheRoot
}

function inbox {
    Set-LocationIfExists (Join-Path $WorkspaceRoot 'Inbox')
}

function winfiles {
    Set-LocationIfExists $WinDotfilesRoot
}

function Get-ProjectRegistryPath {
    # Prefer a gitignored local override so private group names stay out of the repo.
    $localPath = Join-Path $WinDotfilesRoot 'powershell\projects.local.json'
    if (Test-Path -LiteralPath $localPath) {
        return $localPath
    }

    Join-Path $WinDotfilesRoot 'powershell\projects.json'
}

$script:WinDotfilesProjectRegistryCache = $null
$script:WinDotfilesProjectRegistryCachePath = $null
$script:WinDotfilesProjectRegistryCacheLastWriteTimeUtc = $null

function Get-ProjectRegistry {
    $registryPath = Get-ProjectRegistryPath
    $registryItem = Get-Item -LiteralPath $registryPath -ErrorAction SilentlyContinue
    if (-not $registryItem) {
        Write-Warning "Project registry not found: $registryPath"
        return $null
    }

    if ($script:WinDotfilesProjectRegistryCache -and
        $script:WinDotfilesProjectRegistryCachePath -eq $registryPath -and
        $script:WinDotfilesProjectRegistryCacheLastWriteTimeUtc -eq $registryItem.LastWriteTimeUtc) {
        return $script:WinDotfilesProjectRegistryCache
    }

    try {
        $registry = Get-Content -LiteralPath $registryPath -Raw | ConvertFrom-Json
        $script:WinDotfilesProjectRegistryCache = $registry
        $script:WinDotfilesProjectRegistryCachePath = $registryPath
        $script:WinDotfilesProjectRegistryCacheLastWriteTimeUtc = $registryItem.LastWriteTimeUtc
        $registry
    }
    catch {
        Write-Warning "Project registry could not be read: $($_.Exception.Message)"
        $null
    }
}

function Clear-ProjectRegistryCache {
    $script:WinDotfilesProjectRegistryCache = $null
    $script:WinDotfilesProjectRegistryCachePath = $null
    $script:WinDotfilesProjectRegistryCacheLastWriteTimeUtc = $null
}

function Resolve-ProjectPath {
    param([Parameter(Mandatory)][string]$Path)

    if ([IO.Path]::IsPathRooted($Path)) {
        return $Path
    }

    Join-Path $ProjectsRoot $Path
}

function Get-ProjectGroups {
    $registry = Get-ProjectRegistry
    if (-not $registry -or -not $registry.groups) {
        return @()
    }

    @($registry.groups | Where-Object { $_.name -and $_.path } | ForEach-Object {
        [PSCustomObject]@{
            Name    = [string]$_.name
            Command = [string]$_.command
            Path    = Resolve-ProjectPath ([string]$_.path)
        }
    })
}

function Get-ProjectGroup {
    param([Parameter(Mandatory)][string]$Name)

    Get-ProjectGroups | Where-Object { $_.Name -ieq $Name -or $_.Command -ieq $Name } | Select-Object -First 1
}

function Get-ProjectGroupDirectories {
    Get-ChildItem -LiteralPath $ProjectsRoot -Directory -ErrorAction SilentlyContinue |
    Sort-Object Name
}

function ConvertTo-ProjectCommandName {
    param([Parameter(Mandatory)][string]$Name)

    $commandName = ($Name.ToLowerInvariant() -replace '[^a-z0-9_-]', '')
    if ([string]::IsNullOrWhiteSpace($commandName)) {
        throw "Could not derive a command name from project name: $Name"
    }

    $commandName
}

function ConvertTo-ProjectRegistryPath {
    param([Parameter(Mandatory)][string]$Path)

    $resolvedPath = Resolve-ProjectPath $Path
    $resolvedProjectsRoot = [IO.Path]::GetFullPath($ProjectsRoot).TrimEnd('\')
    $resolvedFullPath = [IO.Path]::GetFullPath($resolvedPath)
    $isUnderProjectsRoot = $resolvedFullPath.Equals($resolvedProjectsRoot, [StringComparison]::OrdinalIgnoreCase) -or
    $resolvedFullPath.StartsWith("$resolvedProjectsRoot\", [StringComparison]::OrdinalIgnoreCase)

    if ([IO.Path]::IsPathRooted($Path) -and $isUnderProjectsRoot) {
        return [IO.Path]::GetRelativePath($ProjectsRoot, $resolvedPath)
    }

    $Path
}

function Set-ProjectGroupShortcut {
    param(
        [Parameter(Mandatory)][string]$Command,
        [Parameter(Mandatory)][string]$Name
    )

    Set-Item -Path "function:\global:$Command" -Value ([scriptblock]::Create("param([switch]`$Code) Open-ProjectGroup '$Name' -Code:`$Code"))
}

function Get-ProjectNameFromGitUrl {
    param([Parameter(Mandatory)][string]$GitUrl)

    $repoName = ($GitUrl.TrimEnd('/') -split '[:/]')[-1]
    if ($repoName.EndsWith('.git', [StringComparison]::OrdinalIgnoreCase)) {
        $repoName = $repoName.Substring(0, $repoName.Length - 4)
    }

    if ([string]::IsNullOrWhiteSpace($repoName)) {
        throw "Could not derive a project name from Git URL: $GitUrl"
    }

    $repoName
}

function Select-ProjectGroupDirectory {
    param([string]$Group)

    if ($Group) {
        $groupPath = Resolve-ProjectPath $Group
        if (Test-Path -LiteralPath $groupPath -PathType Container) {
            return $groupPath
        }

        $matchedGroup = Get-ProjectGroup $Group
        if ($matchedGroup -and (Test-Path -LiteralPath $matchedGroup.Path -PathType Container)) {
            return $matchedGroup.Path
        }

        throw "Project group directory does not exist: $groupPath"
    }

    $groupDirectories = @(Get-ProjectGroupDirectories)
    if (-not $groupDirectories) {
        throw "No project group directories were found under $ProjectsRoot"
    }

    if (Test-Command fzf -Application) {
        $fzfArgs = New-FzfArgs -Prompt 'group> ' -Label 'groups' -Preview (Get-FzfDirectoryPreviewCommand)
        $selected = $groupDirectories |
        ForEach-Object FullName |
        fzf @fzfArgs

        if ($selected) {
            return $selected
        }

        return $null
    }

    $groupDirectories | Select-Object Name, FullName | Format-Table -AutoSize | Out-Host
    $selectedName = Read-Host 'Project group'
    if ([string]::IsNullOrWhiteSpace($selectedName)) {
        return $null
    }

    Select-ProjectGroupDirectory -Group $selectedName
}

function Get-ProjectSearchRoots {
    $registryRoots = Get-ProjectGroups | ForEach-Object Path
    @(
        $ProjectsRoot
        $registryRoots
        (Join-Path $HOME 'Work')
        (Join-Path $HOME 'source')
    ) | Where-Object { $_ -and (Test-Path -LiteralPath $_ -PathType Container) } | Select-Object -Unique
}

function Test-ProjectDirectoryExcluded {
    param([Parameter(Mandatory)][string]$Path)

    $excludedNames = @(
        '.git', '.angular', '.firebase', '.firebase-local', '.firebase-local-config',
        '.cache', '.next', '.nx', '.turbo', '.vercel', '.yarn', '__pycache__',
        'bin', 'build', 'coverage', 'dist', 'node_modules', 'obj', 'target', 'tmp'
    )

    $segments = [IO.Path]::GetFullPath($Path).TrimEnd('\') -split '[\\/]'
    foreach ($segment in $segments) {
        if ($excludedNames -contains $segment.ToLowerInvariant()) {
            return $true
        }
    }

    $false
}

function Test-ProjectRootDirectory {
    param([Parameter(Mandatory)][string]$Path)

    if (Test-ProjectDirectoryExcluded $Path) {
        return $false
    }

    $markerFiles = @(
        '.git', 'package.json', 'pnpm-workspace.yaml', 'nx.json', 'angular.json',
        'firebase.json', 'pyproject.toml', 'requirements.txt', 'Cargo.toml',
        'go.mod', 'composer.json', 'pom.xml', 'Dockerfile'
    )

    foreach ($markerFile in $markerFiles) {
        if (Test-Path -LiteralPath (Join-Path $Path $markerFile)) {
            return $true
        }
    }

    foreach ($projectFilePattern in '*.sln', '*.csproj', '*.fsproj', '*.vbproj') {
        if (Get-ChildItem -LiteralPath $Path -File -Filter $projectFilePattern -ErrorAction SilentlyContinue | Select-Object -First 1) {
            return $true
        }
    }

    $false
}

function Get-ProjectRootDirectories {
    $candidatePaths = [ordered]@{}
    $configuredGroupPaths = @(Get-ProjectGroups | ForEach-Object Path | Where-Object { $_ })
    $personalRoots = @(
        (Join-Path $HOME 'Work')
        (Join-Path $HOME 'source')
    )

    function Add-ProjectCandidatePath {
        param([string]$Path)

        if (-not $Path -or -not (Test-Path -LiteralPath $Path -PathType Container)) {
            return
        }

        $fullPath = [IO.Path]::GetFullPath($Path).TrimEnd('\')
        if (-not $candidatePaths.Contains($fullPath)) {
            $candidatePaths[$fullPath] = $true
        }
    }

    foreach ($path in @(Get-ChildItem -LiteralPath $ProjectsRoot -Directory -ErrorAction SilentlyContinue | ForEach-Object FullName)) {
        Add-ProjectCandidatePath $path
    }

    foreach ($groupPath in $configuredGroupPaths) {
        Add-ProjectCandidatePath $groupPath
        foreach ($path in @(Get-ChildItem -LiteralPath $groupPath -Directory -ErrorAction SilentlyContinue | ForEach-Object FullName)) {
            Add-ProjectCandidatePath $path
        }
    }

    foreach ($root in $personalRoots) {
        if (-not (Test-Path -LiteralPath $root -PathType Container)) {
            continue
        }

        foreach ($path in @(Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue | ForEach-Object FullName)) {
            Add-ProjectCandidatePath $path
            foreach ($childPath in @(Get-ChildItem -LiteralPath $path -Directory -ErrorAction SilentlyContinue | ForEach-Object FullName)) {
                Add-ProjectCandidatePath $childPath
            }
        }
    }

    $projectDirectories = @($candidatePaths.Keys |
        Where-Object { -not (Test-ProjectDirectoryExcluded $_) -and (Test-ProjectRootDirectory $_) } |
        ForEach-Object { Get-Item -LiteralPath $_ -ErrorAction SilentlyContinue } |
        Where-Object { $_ } |
        Sort-Object FullName -Unique)

    $selectedPaths = [System.Collections.Generic.List[string]]::new()
    foreach ($directory in $projectDirectories) {
        $fullPath = [IO.Path]::GetFullPath($directory.FullName).TrimEnd('\')
        $isNestedUnderSelectedProject = $false

        foreach ($selectedPath in $selectedPaths) {
            if ($fullPath.StartsWith("$selectedPath\", [StringComparison]::OrdinalIgnoreCase)) {
                $isNestedUnderSelectedProject = $true
                break
            }
        }

        if (-not $isNestedUnderSelectedProject) {
            $selectedPaths.Add($fullPath)
            $directory
        }
    }
}

$script:WinDotfilesProjectDirectoryCache = $null
$script:WinDotfilesProjectDirectoryCacheTime = [datetime]::MinValue
$WinDotfilesProjectDirectoryMemoryCacheTtl = [TimeSpan]::FromMinutes(5)
$WinDotfilesProjectDirectoryFileCacheTtl = [TimeSpan]::FromHours(12)

function Get-KnownProjectDirectoryCachePath {
    Join-Path (Get-WinDotfilesStateRoot) 'project-directories.json'
}

function ConvertTo-KnownProjectDirectoryItems {
    param([string[]]$Path)

    @($Path | Where-Object { $_ } | ForEach-Object {
            Get-Item -LiteralPath $_ -ErrorAction SilentlyContinue
        } | Where-Object { $_ } | Sort-Object FullName -Unique)
}

function Test-KnownProjectDirectoryFileCacheFresh {
    param([Parameter(Mandatory)]$Cache)

    if (-not $Cache.CreatedAt -or -not $Cache.Paths) {
        return $false
    }

    try {
        $createdAtUtc = ([datetime]$Cache.CreatedAt).ToUniversalTime()
    }
    catch {
        return $false
    }

    if (((Get-Date).ToUniversalTime() - $createdAtUtc) -gt $WinDotfilesProjectDirectoryFileCacheTtl) {
        return $false
    }

    $registryItem = Get-Item -LiteralPath (Get-ProjectRegistryPath) -ErrorAction SilentlyContinue
    if ($registryItem -and $registryItem.LastWriteTimeUtc -gt $createdAtUtc) {
        return $false
    }

    foreach ($root in @(Get-ProjectSearchRoots)) {
        $rootItem = Get-Item -LiteralPath $root -ErrorAction SilentlyContinue
        if ($rootItem -and $rootItem.LastWriteTimeUtc -gt $createdAtUtc) {
            return $false
        }
    }

    $true
}

function Read-KnownProjectDirectoryFileCache {
    param([switch]$AllowStale)

    $cachePath = Get-KnownProjectDirectoryCachePath
    if (-not (Test-Path -LiteralPath $cachePath -PathType Leaf)) {
        return $null
    }

    try {
        $cache = Get-Content -LiteralPath $cachePath -Raw | ConvertFrom-Json
        if ($AllowStale -or (Test-KnownProjectDirectoryFileCacheFresh -Cache $cache)) {
            return $cache
        }
    }
    catch {
        return $null
    }

    $null
}

function Write-KnownProjectDirectoryFileCache {
    param([Parameter(Mandatory)][object[]]$Directories)

    $cachePath = Get-KnownProjectDirectoryCachePath
    $payload = [PSCustomObject]@{
        CreatedAt = (Get-Date).ToUniversalTime().ToString('o')
        Roots     = @((Get-ProjectSearchRoots) | Sort-Object -Unique)
        Paths     = @($Directories | ForEach-Object FullName | Sort-Object -Unique)
    }

    try {
        $payload | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $cachePath -Encoding utf8 -ErrorAction Stop
    }
    catch {
        # Cache writes are best-effort so sandboxed or locked-down shells still load cleanly.
    }
}

function Get-KnownProjectDirectoryCacheState {
    $cachePath = Get-KnownProjectDirectoryCachePath
    $cache = Read-KnownProjectDirectoryFileCache -AllowStale
    $createdAt = $null

    if ($cache -and $cache.CreatedAt) {
        try {
            $createdAt = ([datetime]$cache.CreatedAt).ToLocalTime()
        }
        catch {
            $createdAt = $null
        }
    }

    [PSCustomObject]@{
        CachePath  = $cachePath
        Exists     = [bool]$cache
        Fresh      = [bool]($cache -and (Test-KnownProjectDirectoryFileCacheFresh -Cache $cache))
        CreatedAt  = $createdAt
        AgeMinutes = if ($createdAt) { [math]::Round(((Get-Date) - $createdAt).TotalMinutes, 1) } else { $null }
        PathCount  = if ($cache -and $cache.Paths) { @($cache.Paths).Count } else { 0 }
    }
}

function Get-KnownProjectDirectories {
    param([switch]$Refresh)

    $cacheAge = (Get-Date) - $script:WinDotfilesProjectDirectoryCacheTime
    if (-not $Refresh -and $script:WinDotfilesProjectDirectoryCache -and $cacheAge -lt $WinDotfilesProjectDirectoryMemoryCacheTtl) {
        return ConvertTo-KnownProjectDirectoryItems -Path $script:WinDotfilesProjectDirectoryCache
    }

    if (-not $Refresh) {
        $fileCache = Read-KnownProjectDirectoryFileCache
        if ($fileCache -and $fileCache.Paths) {
            $directories = @(ConvertTo-KnownProjectDirectoryItems -Path @($fileCache.Paths))
            if ($directories) {
                $script:WinDotfilesProjectDirectoryCache = @($directories | ForEach-Object FullName)
                $script:WinDotfilesProjectDirectoryCacheTime = Get-Date
                return $directories
            }
        }
    }

    $directories = @(Get-ProjectRootDirectories | Sort-Object FullName -Unique)
    $script:WinDotfilesProjectDirectoryCache = @($directories | ForEach-Object FullName)
    $script:WinDotfilesProjectDirectoryCacheTime = Get-Date
    Write-KnownProjectDirectoryFileCache -Directories $directories

    $directories
}

function Clear-KnownProjectDirectoryCache {
    param([switch]$MemoryOnly)

    $script:WinDotfilesProjectDirectoryCache = $null
    $script:WinDotfilesProjectDirectoryCacheTime = [datetime]::MinValue

    if (-not $MemoryOnly) {
        Remove-Item -LiteralPath (Get-KnownProjectDirectoryCachePath) -Force -ErrorAction SilentlyContinue
    }
}

function Update-KnownProjectDirectoryCache {
    [CmdletBinding()]
    param(
        [switch]$Refresh,
        [switch]$Clear,
        [switch]$Raw
    )

    if ($Clear) {
        Clear-KnownProjectDirectoryCache
    }

    $directories = @(Get-KnownProjectDirectories -Refresh:$Refresh)
    $state = Get-KnownProjectDirectoryCacheState
    $result = [PSCustomObject]@{
        Projects   = $directories.Count
        Fresh      = $state.Fresh
        AgeMinutes = $state.AgeMinutes
        CachePath  = $state.CachePath
    }

    if ($Raw) {
        return $result
    }

    $result | Format-List
}

function Open-ProjectPath {
    param(
        [Parameter(Mandatory)][string]$Path,
        [switch]$OpenCode
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        Write-Warning "Directory does not exist: $Path"
        return
    }

    Set-Location -LiteralPath $Path
    if ($OpenCode) {
        if (Test-Command code -Application) {
            code .
        }
        else {
            Write-Warning 'VS Code command `code` is not installed or not on PATH.'
        }
    }
}

function Open-ProjectGroup {
    param(
        [Parameter(Mandatory)][string]$Name,
        [switch]$Code
    )

    $group = Get-ProjectGroup $Name
    if (-not $group) {
        Write-Warning "Project group is not configured: $Name"
        return
    }

    if (-not (Test-Path -LiteralPath $group.Path -PathType Container)) {
        Write-Warning "Directory does not exist: $($group.Path)"
        return
    }

    if (-not (Test-Command fzf -Application)) {
        Open-ProjectPath -Path $group.Path -OpenCode:$Code
        return
    }

    $fzfArgs = New-FzfArgs -Prompt "$($group.Name)> " -Label $group.Name -Preview (Get-FzfDirectoryPreviewCommand)
    $selected = Get-ChildItem -LiteralPath $group.Path -Directory -ErrorAction SilentlyContinue |
    Sort-Object Name |
    ForEach-Object FullName |
    fzf @fzfArgs

    if (-not $selected) {
        return
    }

    Open-ProjectPath -Path $selected -OpenCode:$Code
}

function Invoke-ProjectPicker {
    $searchRoots = Get-ProjectSearchRoots
    if (-not $searchRoots) {
        Write-Warning 'No project search roots were found.'
        return
    }

    if (-not (Test-Command fzf -Application)) {
        Write-Warning 'fzf is not installed or not on PATH.'
        return
    }

    $fzfArgs = New-FzfArgs -Prompt 'project> ' -Label 'projects' -Preview (Get-FzfDirectoryPreviewCommand)
    $selected = Get-KnownProjectDirectories |
    ForEach-Object FullName |
    fzf @fzfArgs

    if ($selected) {
        Open-ProjectPath -Path $selected
    }
}

function Open-Project {
    param(
        [string]$Name,
        [switch]$Code
    )

    if ([string]::IsNullOrWhiteSpace($Name)) {
        Invoke-ProjectPicker
        return
    }

    $group = Get-ProjectGroup $Name
    if ($group) {
        Open-ProjectGroup $group.Name -Code:$Code
        return
    }

    $matches = @(Get-KnownProjectDirectories | Where-Object { $_.Name -ieq $Name })
    if ($matches.Count -eq 1) {
        Open-ProjectPath -Path $matches[0].FullName -OpenCode:$Code
        return
    }

    if ($matches.Count -gt 1) {
        if (Test-Command fzf -Application) {
            $fzfArgs = New-FzfArgs -Prompt "$Name> " -Label 'matches' -Preview (Get-FzfDirectoryPreviewCommand)
            $selected = $matches | ForEach-Object FullName | fzf @fzfArgs
            if ($selected) {
                Open-ProjectPath -Path $selected -OpenCode:$Code
            }
        }
        else {
            Write-Warning "Multiple project matches found for '$Name'. Install fzf or use a more specific path."
        }
        return
    }

    Write-Warning "Project was not found: $Name"
}

function project {
    param(
        [string]$Name,
        [switch]$Code
    )

    Open-Project $Name -Code:$Code
}

function Add-ProjectGroup {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Name,

        [Parameter(Position = 1)]
        [string]$Path = $Name,

        [Parameter(Position = 2)]
        [string]$Command,

        [switch]$Force
    )

    $registryPath = Get-ProjectRegistryPath
    $registry = Get-ProjectRegistry
    if (-not $registry) {
        $registry = [PSCustomObject]@{ groups = @() }
    }

    if (-not $registry.PSObject.Properties['groups']) {
        $registry | Add-Member -MemberType NoteProperty -Name groups -Value @()
    }

    $registryGroups = @($registry.groups)
    $resolvedCommand = if ($Command) { $Command } else { ConvertTo-ProjectCommandName $Name }
    $registryProjectPath = ConvertTo-ProjectRegistryPath $Path
    $existing = @($registryGroups | Where-Object { $_.name -ieq $Name -or $_.command -ieq $resolvedCommand })
    $conflict = $existing | Where-Object { $_.name -ine $Name -or $_.command -ine $resolvedCommand } | Select-Object -First 1

    if ($conflict -and -not $Force) {
        throw "Project group already exists or command is already used: $($conflict.name). Use -Force to replace it."
    }

    $projectPath = Resolve-ProjectPath $registryProjectPath
    if (-not (Test-Path -LiteralPath $projectPath -PathType Container)) {
        if ($PSCmdlet.ShouldProcess($projectPath, 'Create project group directory')) {
            New-Item -ItemType Directory -Path $projectPath -Force | Out-Null
        }
    }

    $newGroup = [PSCustomObject]@{
        name    = $Name
        command = $resolvedCommand
        path    = $registryProjectPath
    }

    $updatedGroups = @($registryGroups | Where-Object {
        $_.name -ine $Name -and $_.command -ine $resolvedCommand
    }) + $newGroup

    $registry.groups = @($updatedGroups | Sort-Object name)
    $json = $registry | ConvertTo-Json -Depth 8

    if ($PSCmdlet.ShouldProcess($registryPath, "Add or update project group '$Name'")) {
        Set-Content -LiteralPath $registryPath -Value $json -Encoding utf8
        Clear-ProjectRegistryCache
        Clear-KnownProjectDirectoryCache -MemoryOnly
        Set-ProjectGroupShortcut -Command $resolvedCommand -Name $Name
        Write-Host "Added project group '$Name' as '$resolvedCommand' -> $registryProjectPath" -ForegroundColor Green
    }
}

function Add-Project {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [string]$Group,

        [ValidateSet('clone', 'empty')]
        [string]$Mode,

        [string]$Name,

        [string]$GitUrl,

        [switch]$Force
    )

    $groupPath = Select-ProjectGroupDirectory -Group $Group
    if (-not $groupPath) {
        return
    }

    if (-not $Mode) {
        $Mode = Read-Host 'Create mode (clone/empty)'
    }

    switch ($Mode.ToLowerInvariant()) {
        'clone' {
            if (-not $GitUrl) {
                $GitUrl = Read-Host 'Git URL'
            }

            if ([string]::IsNullOrWhiteSpace($GitUrl)) {
                throw 'Git URL is required.'
            }

            $projectName = if ($Name) { $Name } else { Get-ProjectNameFromGitUrl $GitUrl }
            $projectPath = Join-Path $groupPath $projectName

            if ((Test-Path -LiteralPath $projectPath) -and -not $Force) {
                throw "Project path already exists: $projectPath. Use -Force to continue."
            }

            if ($PSCmdlet.ShouldProcess($projectPath, "Clone $GitUrl")) {
                git clone $GitUrl $projectPath
                if ($LASTEXITCODE -ne 0) {
                    throw "git clone failed with exit code $LASTEXITCODE"
                }

                Set-Location -LiteralPath $projectPath
            }
        }

        'empty' {
            if (-not $Name) {
                $Name = Read-Host 'Project name'
            }

            if ([string]::IsNullOrWhiteSpace($Name)) {
                throw 'Project name is required.'
            }

            $projectPath = Join-Path $groupPath $Name
            if ((Test-Path -LiteralPath $projectPath) -and -not $Force) {
                throw "Project path already exists: $projectPath. Use -Force to continue."
            }

            if ($PSCmdlet.ShouldProcess($projectPath, 'Create empty project directory')) {
                New-Item -ItemType Directory -Path $projectPath -Force | Out-Null
                Set-Location -LiteralPath $projectPath
            }
        }

        default {
            throw "Unsupported create mode: $Mode"
        }
    }
}

Set-Alias -Name proj -Value project -Force
Set-Alias -Name p -Value project -Force
Set-Alias -Name addproj -Value Add-ProjectGroup -Force
Set-Alias -Name apg -Value Add-ProjectGroup -Force
Set-Alias -Name ap -Value Add-Project -Force
Set-Alias -Name projcache -Value Update-KnownProjectDirectoryCache -Force

foreach ($projectGroup in Get-ProjectGroups) {
    if ($projectGroup.Command) {
        Set-ProjectGroupShortcut -Command $projectGroup.Command -Name $projectGroup.Name
    }
}

if (Get-Command zoxide -CommandType Application -ErrorAction SilentlyContinue) {
    $global:__WinDotfilesZoxidePath = (Get-Command zoxide -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1).Source

    function global:__zoxide_bin {
        $encoding = [Console]::OutputEncoding
        try {
            [Console]::OutputEncoding = [System.Text.Utf8Encoding]::new()
            & $global:__WinDotfilesZoxidePath @args
        }
        finally {
            [Console]::OutputEncoding = $encoding
        }
    }

    function global:__zoxide_pwd {
        $cwd = Get-Location
        if ($cwd.Provider.Name -eq 'FileSystem') {
            $cwd.ProviderPath
        }
    }

    function global:__zoxide_cd {
        param(
            [Parameter(Mandatory)][string]$Directory,
            [Parameter(Mandatory)][bool]$Literal
        )

        if ($Literal) {
            Set-Location -LiteralPath $Directory -ErrorAction Stop
            return
        }

        Set-Location -Path $Directory -ErrorAction Stop
    }

    $global:__zoxide_oldpwd = __zoxide_pwd

    function global:__zoxide_hook {
        $currentPath = __zoxide_pwd
        if ($currentPath -and $currentPath -ne $global:__zoxide_oldpwd) {
            __zoxide_bin add '--' $currentPath *> $null
            $global:__zoxide_oldpwd = $currentPath
        }
    }

    if ($global:__zoxide_hooked -ne 1) {
        $global:__zoxide_hooked = 1
        $global:__zoxide_prompt_old = $function:prompt

        function global:prompt {
            if ($null -ne $global:__zoxide_prompt_old) {
                & $global:__zoxide_prompt_old
            }

            $null = __zoxide_hook
        }
    }

    function global:__zoxide_z {
        if ($args.Length -eq 0) {
            __zoxide_cd ~ $true
            return
        }

        if ($args.Length -eq 1 -and ($args[0] -eq '-' -or $args[0] -eq '+')) {
            __zoxide_cd $args[0] $false
            return
        }

        if ($args.Length -eq 1 -and (Test-Path -PathType Container -LiteralPath $args[0])) {
            __zoxide_cd $args[0] $true
            return
        }

        if ($args.Length -eq 1 -and (Test-Path -PathType Container -Path $args[0])) {
            __zoxide_cd $args[0] $false
            return
        }

        $currentPath = __zoxide_pwd
        $result = if ($currentPath) {
            __zoxide_bin query --exclude $currentPath '--' @args
        }
        else {
            __zoxide_bin query '--' @args
        }

        if ($LASTEXITCODE -eq 0 -and $result) {
            __zoxide_cd $result $true
        }
    }

    function global:__zoxide_zi {
        $result = __zoxide_bin query -i '--' @args
        if ($LASTEXITCODE -eq 0 -and $result) {
            __zoxide_cd $result $true
        }
    }

    Set-Alias -Name z -Value __zoxide_z -Option AllScope -Scope Global -Force
    Set-Alias -Name zi -Value __zoxide_zi -Option AllScope -Scope Global -Force
}

