function pwgen {
    param([string]$url = 'https://localhost:7095')

    npx playwright codegen $url `
        --load-storage ".\Portal.UnitTests\bin\Debug\net8.0\playwright\.auth\rep.local.json"
}

function pwtest {
    param(
        [Parameter(Mandatory)]
        [string]$name,
        [switch]$headless
    )

    $headlessFlag = if ($headless) { 'true' } else { 'false' }

    dotnet test `
        --filter $name `
        -- Playwright.BrowserName=chromium `
        Playwright.LaunchOptions.Headless=$headlessFlag `
        Playwright.LaunchOptions.Channel=msedge `
        PWDEBUG=1
}
