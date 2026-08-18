[CmdletBinding()]
param(
    [ValidateSet("all", "gpt", "claude")]
    [string]$Target = "all",
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"

$IntentCompilerRoot = $PSScriptRoot
$IntentCompilerPackage = Join-Path $IntentCompilerRoot "plugins\intent-compiler"
$IntentCompilerName = "intent-compiler"
$IntentCompilerCodexMarketplace = "intent-compiler-local"
$IntentCompilerClaudeMarketplace = "intent-compiler-plugins"

function Write-Step {
    param([string]$Message)
    Write-Host "`n==> $Message" -ForegroundColor Cyan
}

function Copy-DirectoryContents {
    param(
        [Parameter(Mandatory)][string]$Source,
        [Parameter(Mandatory)][string]$Destination
    )

    New-Item -ItemType Directory -Force -Path $Destination | Out-Null
    foreach ($IntentCompilerEntry in Get-ChildItem -Force -LiteralPath $Source) {
        Copy-Item -LiteralPath $IntentCompilerEntry.FullName -Destination $Destination -Recurse -Force
    }
}

function Install-CodexFallback {
    $IntentCompilerUserProfile = [Environment]::GetFolderPath("UserProfile")
    $IntentCompilerInstallParent = Join-Path $IntentCompilerUserProfile "plugins"
    $IntentCompilerInstallPath = Join-Path $IntentCompilerInstallParent $IntentCompilerName
    $IntentCompilerMarketplacePath = Join-Path $IntentCompilerUserProfile ".agents\plugins\marketplace.json"

    Write-Step "Installing the OpenAI/Codex package through the personal marketplace fallback"
    if ($DryRun) {
        Write-Host "Would copy the plugin into the current user's plugin directory."
        Write-Host "Would register the plugin in the current user's personal marketplace."
        return
    }

    Copy-DirectoryContents -Source $IntentCompilerPackage -Destination $IntentCompilerInstallPath
    $IntentCompilerMarker = [pscustomobject]@{
        plugin = $IntentCompilerName
        markerVersion = 1
    } | ConvertTo-Json
    [IO.File]::WriteAllText(
        (Join-Path $IntentCompilerInstallPath ".intent-compiler-installed.json"),
        $IntentCompilerMarker + [Environment]::NewLine,
        [Text.UTF8Encoding]::new($false)
    )
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $IntentCompilerMarketplacePath) | Out-Null

    if (Test-Path -LiteralPath $IntentCompilerMarketplacePath) {
        $IntentCompilerMarketplace = Get-Content -Raw -LiteralPath $IntentCompilerMarketplacePath | ConvertFrom-Json
    }
    else {
        $IntentCompilerMarketplace = [pscustomobject]@{
            name = "personal"
            interface = [pscustomobject]@{ displayName = "Personal" }
            plugins = @()
        }
    }

    if (-not ($IntentCompilerMarketplace.PSObject.Properties.Name -contains "interface")) {
        $IntentCompilerMarketplace | Add-Member -NotePropertyName interface -NotePropertyValue ([pscustomobject]@{ displayName = "Personal" })
    }
    elseif (-not $IntentCompilerMarketplace.interface) {
        $IntentCompilerMarketplace.interface = [pscustomobject]@{ displayName = "Personal" }
    }
    if (-not ($IntentCompilerMarketplace.PSObject.Properties.Name -contains "plugins")) {
        $IntentCompilerMarketplace | Add-Member -NotePropertyName plugins -NotePropertyValue @()
    }
    elseif (-not $IntentCompilerMarketplace.plugins) {
        $IntentCompilerMarketplace.plugins = @()
    }

    $IntentCompilerEntry = [pscustomobject]@{
        name = $IntentCompilerName
        source = [pscustomobject]@{
            source = "local"
            path = "./plugins/intent-compiler"
        }
        policy = [pscustomobject]@{
            installation = "INSTALLED_BY_DEFAULT"
            authentication = "ON_INSTALL"
        }
        category = "Productivity"
    }

    $IntentCompilerUpdatedPlugins = @()
    $IntentCompilerReplaced = $false
    foreach ($IntentCompilerExisting in @($IntentCompilerMarketplace.plugins)) {
        if ($IntentCompilerExisting.name -eq $IntentCompilerName) {
            $IntentCompilerUpdatedPlugins += $IntentCompilerEntry
            $IntentCompilerReplaced = $true
        }
        else {
            $IntentCompilerUpdatedPlugins += $IntentCompilerExisting
        }
    }
    if (-not $IntentCompilerReplaced) {
        $IntentCompilerUpdatedPlugins += $IntentCompilerEntry
    }
    $IntentCompilerMarketplace.plugins = $IntentCompilerUpdatedPlugins

    $IntentCompilerJson = $IntentCompilerMarketplace | ConvertTo-Json -Depth 20
    [IO.File]::WriteAllText($IntentCompilerMarketplacePath, $IntentCompilerJson + [Environment]::NewLine, [Text.UTF8Encoding]::new($false))
    Write-Host "Installed the OpenAI/Codex plugin in the current user's plugin directory."
}

function Install-ForCodex {
    Write-Step "Installing for GPT / ChatGPT / Codex"
    $IntentCompilerCodex = Get-Command codex -ErrorAction SilentlyContinue
    if ($DryRun) {
        if ($IntentCompilerCodex) {
            Write-Host "Would register this repository as a local Codex marketplace."
            Write-Host "Would run: codex plugin add $IntentCompilerName@$IntentCompilerCodexMarketplace"
        }
        else {
            Write-Host "Codex CLI is unavailable; the personal marketplace fallback would be used."
        }
        Install-CodexFallback
        return
    }

    $IntentCompilerInstalled = $false
    if ($IntentCompilerCodex) {
        try {
            $null = (& $IntentCompilerCodex.Source plugin marketplace add $IntentCompilerRoot 2>&1 | Out-String)
            $IntentCompilerMarketplaceExitCode = $LASTEXITCODE
            if ($IntentCompilerMarketplaceExitCode -eq 0) {
                $null = (& $IntentCompilerCodex.Source plugin add "$IntentCompilerName@$IntentCompilerCodexMarketplace" 2>&1 | Out-String)
                $IntentCompilerInstalled = ($LASTEXITCODE -eq 0)
            }
        }
        catch {
            Write-Warning "Codex CLI installation was unavailable; using the local fallback."
        }
    }

    if (-not $IntentCompilerInstalled) {
        Install-CodexFallback
    }
    else {
        Write-Host "Installed OpenAI/Codex plugin from the repository marketplace."
    }
}

function Install-ForClaude {
    Write-Step "Installing for Claude Code"
    $IntentCompilerClaude = Get-Command claude -ErrorAction SilentlyContinue
    if (-not $IntentCompilerClaude) {
        throw "Claude Code CLI was not found. Install Claude Code, then run this installer again with -Target claude."
    }

    $IntentCompilerPluginId = "$IntentCompilerName@$IntentCompilerClaudeMarketplace"
    if ($DryRun) {
        Write-Host "Would validate and register this repository as a local Claude marketplace."
        Write-Host "Would install or update: $IntentCompilerPluginId"
        return
    }

    $null = (& $IntentCompilerClaude.Source plugin validate $IntentCompilerRoot --strict 2>&1 | Out-String)
    $IntentCompilerValidateExitCode = $LASTEXITCODE
    if ($IntentCompilerValidateExitCode -ne 0) {
        throw "Claude marketplace validation failed."
    }

    $null = (& $IntentCompilerClaude.Source plugin marketplace add $IntentCompilerRoot --scope user 2>&1 | Out-String)
    $IntentCompilerMarketplaceExitCode = $LASTEXITCODE
    if ($IntentCompilerMarketplaceExitCode -ne 0) {
        throw "Claude marketplace registration failed."
    }

    $IntentCompilerInstallHelp = (& $IntentCompilerClaude.Source plugin install --help 2>&1 | Out-String)
    $IntentCompilerInstallArgs = @("plugin", "install", $IntentCompilerPluginId, "--scope", "user")
    if ($IntentCompilerInstallHelp -match "--yes") {
        $IntentCompilerInstallArgs += "--yes"
    }

    $null = (& $IntentCompilerClaude.Source @IntentCompilerInstallArgs 2>&1 | Out-String)
    $IntentCompilerInstallExitCode = $LASTEXITCODE
    if ($IntentCompilerInstallExitCode -ne 0) {
        Write-Host "Plugin may already be installed; attempting an update."
        $null = (& $IntentCompilerClaude.Source plugin update $IntentCompilerPluginId --scope user 2>&1 | Out-String)
        $IntentCompilerUpdateExitCode = $LASTEXITCODE
        if ($IntentCompilerUpdateExitCode -ne 0) {
            throw "Claude plugin installation and update both failed."
        }
    }
    Write-Host "Installed Claude Code plugin: $IntentCompilerPluginId"
}

try {
    if (-not (Test-Path -LiteralPath $IntentCompilerPackage)) {
        throw "The Intent Compiler plugin package was not found in this repository."
    }

    switch ($Target) {
        "gpt" { Install-ForCodex }
        "claude" { Install-ForClaude }
        "all" {
            Install-ForCodex
            Install-ForClaude
        }
    }

    Write-Host "`nIntent Compiler installation complete." -ForegroundColor Green
    Write-Host "Start a new ChatGPT/Codex task or Claude Code session before testing the plugin."
}
catch {
    [Console]::Error.WriteLine("ERROR: Intent Compiler installation failed. Check directory permissions and the required platform CLI, then retry.")
    exit 1
}
