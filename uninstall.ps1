[CmdletBinding()]
param(
    [ValidateSet("all", "gpt", "claude")]
    [string]$Target = "all",
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"

$IntentCompilerRoot = $PSScriptRoot
$IntentCompilerName = "intent-compiler"
$IntentCompilerCodexMarketplace = "intent-compiler-local"
$IntentCompilerClaudeMarketplace = "intent-compiler-plugins"

function Write-Step {
    param([string]$Message)
    Write-Host "`n==> $Message" -ForegroundColor Cyan
}

function Get-NormalizedPath {
    param([Parameter(Mandatory)][string]$Path)
    return [IO.Path]::GetFullPath($Path).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
}

function Test-SamePath {
    param(
        [Parameter(Mandatory)][string]$Left,
        [Parameter(Mandatory)][string]$Right
    )
    return (Get-NormalizedPath $Left) -eq (Get-NormalizedPath $Right)
}

function Remove-IntentCompilerDirectory {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$ExpectedParent
    )

    $IntentCompilerFullPath = Get-NormalizedPath $Path
    $IntentCompilerFullParent = Get-NormalizedPath $ExpectedParent
    $IntentCompilerActualParent = Get-NormalizedPath (Split-Path -Parent $IntentCompilerFullPath)
    $IntentCompilerLeaf = Split-Path -Leaf $IntentCompilerFullPath

    if ($IntentCompilerLeaf -ne $IntentCompilerName -or $IntentCompilerActualParent -ne $IntentCompilerFullParent) {
        throw "Refusing to remove an unexpected plugin directory."
    }
    if (-not (Test-Path -LiteralPath $IntentCompilerFullPath)) {
        Write-Host "The Codex fallback plugin directory is already absent."
        return
    }

    $IntentCompilerManifest = Join-Path $IntentCompilerFullPath ".codex-plugin\plugin.json"
    $IntentCompilerMarker = Join-Path $IntentCompilerFullPath ".intent-compiler-installed.json"
    $IntentCompilerOwned = $false
    if (Test-Path -LiteralPath $IntentCompilerMarker) {
        try {
            $IntentCompilerMarkerJson = Get-Content -Raw -LiteralPath $IntentCompilerMarker | ConvertFrom-Json
            $IntentCompilerOwned = $IntentCompilerMarkerJson.plugin -eq $IntentCompilerName
        }
        catch {
            $IntentCompilerOwned = $false
        }
    }
    if (-not $IntentCompilerOwned -and (Test-Path -LiteralPath $IntentCompilerManifest)) {
        try {
            $IntentCompilerManifestJson = Get-Content -Raw -LiteralPath $IntentCompilerManifest | ConvertFrom-Json
            $IntentCompilerOwned = $IntentCompilerManifestJson.name -eq $IntentCompilerName
        }
        catch {
            $IntentCompilerOwned = $false
        }
    }
    if (-not $IntentCompilerOwned) {
        throw "Refusing to remove an unrecognized plugin directory."
    }

    if ($DryRun) {
        Write-Host "Would remove the Codex fallback plugin directory."
    }
    else {
        Remove-Item -LiteralPath $IntentCompilerFullPath -Recurse -Force
        Write-Host "Removed the Codex fallback plugin directory."
    }
}

function Remove-CodexFallback {
    $IntentCompilerUserProfile = [Environment]::GetFolderPath("UserProfile")
    $IntentCompilerInstallParent = Join-Path $IntentCompilerUserProfile "plugins"
    $IntentCompilerInstallPath = Join-Path $IntentCompilerInstallParent $IntentCompilerName
    $IntentCompilerMarketplacePath = Join-Path $IntentCompilerUserProfile ".agents\plugins\marketplace.json"

    Write-Step "Removing the OpenAI/Codex personal marketplace fallback"
    if (Test-Path -LiteralPath $IntentCompilerMarketplacePath) {
        $IntentCompilerMarketplace = Get-Content -Raw -LiteralPath $IntentCompilerMarketplacePath | ConvertFrom-Json
        $IntentCompilerPlugins = @($IntentCompilerMarketplace.plugins)
        $IntentCompilerUpdatedPlugins = @($IntentCompilerPlugins | Where-Object { $_.name -ne $IntentCompilerName })

        if ($IntentCompilerUpdatedPlugins.Count -ne $IntentCompilerPlugins.Count) {
            if ($DryRun) {
                Write-Host "Would remove '$IntentCompilerName' from the personal Codex marketplace."
            }
            else {
                $IntentCompilerMarketplace.plugins = $IntentCompilerUpdatedPlugins
                $IntentCompilerJson = $IntentCompilerMarketplace | ConvertTo-Json -Depth 20
                [IO.File]::WriteAllText($IntentCompilerMarketplacePath, $IntentCompilerJson + [Environment]::NewLine, [Text.UTF8Encoding]::new($false))
                Write-Host "Removed '$IntentCompilerName' from the personal Codex marketplace."
            }
        }
        else {
            Write-Host "Codex marketplace entry is already absent."
        }
    }
    else {
        Write-Host "Codex personal marketplace is already absent."
    }

    Remove-IntentCompilerDirectory -Path $IntentCompilerInstallPath -ExpectedParent $IntentCompilerInstallParent
}

function Invoke-CodexCliRemoval {
    $IntentCompilerCodex = Get-Command codex -ErrorAction SilentlyContinue
    if (-not $IntentCompilerCodex) {
        Write-Host "Codex CLI is unavailable; skipping CLI registry cleanup."
        return
    }
    if ($DryRun) {
        Write-Host "Would use the CLI's advertised remove/uninstall commands when available."
        return
    }

    try {
        $IntentCompilerPluginHelp = (& $IntentCompilerCodex.Source plugin --help 2>&1 | Out-String)
        if ($LASTEXITCODE -eq 0) {
            $IntentCompilerRemoveVerb = $null
            if ($IntentCompilerPluginHelp -match '(?m)^\s*uninstall\b') { $IntentCompilerRemoveVerb = "uninstall" }
            elseif ($IntentCompilerPluginHelp -match '(?m)^\s*remove\b') { $IntentCompilerRemoveVerb = "remove" }

            if ($IntentCompilerRemoveVerb) {
                $null = (& $IntentCompilerCodex.Source plugin $IntentCompilerRemoveVerb "$IntentCompilerName@$IntentCompilerCodexMarketplace" 2>&1 | Out-String)
                $IntentCompilerRemoveExitCode = $LASTEXITCODE
                if ($IntentCompilerRemoveExitCode -ne 0) {
                    Write-Warning "Codex CLI did not remove the plugin; fallback cleanup will still run."
                }
            }

            $IntentCompilerMarketplaceHelp = (& $IntentCompilerCodex.Source plugin marketplace --help 2>&1 | Out-String)
            $IntentCompilerMarketplaceVerb = $null
            if ($IntentCompilerMarketplaceHelp -match '(?m)^\s*remove\b') { $IntentCompilerMarketplaceVerb = "remove" }
            elseif ($IntentCompilerMarketplaceHelp -match '(?m)^\s*delete\b') { $IntentCompilerMarketplaceVerb = "delete" }
            elseif ($IntentCompilerMarketplaceHelp -match '(?m)^\s*rm\b') { $IntentCompilerMarketplaceVerb = "rm" }
            if ($IntentCompilerMarketplaceVerb) {
                $null = (& $IntentCompilerCodex.Source plugin marketplace $IntentCompilerMarketplaceVerb $IntentCompilerCodexMarketplace 2>&1 | Out-String)
                $IntentCompilerMarketplaceExitCode = $LASTEXITCODE
                if ($IntentCompilerMarketplaceExitCode -ne 0) {
                    Write-Warning "Codex CLI did not remove the repository marketplace."
                }
            }
        }
    }
    catch {
        Write-Warning "Codex CLI cleanup was unavailable."
    }
}

function Uninstall-ForCodex {
    Write-Step "Uninstalling GPT / ChatGPT / Codex integration"
    Invoke-CodexCliRemoval
    Remove-CodexFallback
}

function Uninstall-ForClaude {
    Write-Step "Uninstalling Claude Code integration"
    $IntentCompilerClaude = Get-Command claude -ErrorAction SilentlyContinue
    if (-not $IntentCompilerClaude) {
        if ($DryRun) {
            Write-Host "Would uninstall $IntentCompilerName@$IntentCompilerClaudeMarketplace and remove its user marketplace."
            return
        }
        throw "Claude Code CLI was not found, so its plugin registry cannot be safely changed."
    }

    $IntentCompilerPluginId = "$IntentCompilerName@$IntentCompilerClaudeMarketplace"
    if ($DryRun) {
        Write-Host "Would run: claude plugin uninstall $IntentCompilerPluginId --scope user"
        Write-Host "Would remove the local marketplace only after verifying that it belongs to this repository."
        return
    }

    $IntentCompilerInstalled = $false
    try {
        $IntentCompilerListRaw = (& $IntentCompilerClaude.Source plugin list --json 2>&1 | Out-String)
        if ($LASTEXITCODE -eq 0) {
            $IntentCompilerInstalledPlugins = @($IntentCompilerListRaw | ConvertFrom-Json)
            $IntentCompilerInstalled = @($IntentCompilerInstalledPlugins | Where-Object { $_.id -eq $IntentCompilerPluginId -and $_.scope -eq "user" }).Count -gt 0
        }
    }
    catch {
        Write-Warning "Could not inspect Claude plugins; an official uninstall will be attempted."
        $IntentCompilerInstalled = $true
    }

    if ($IntentCompilerInstalled) {
        $null = (& $IntentCompilerClaude.Source plugin uninstall $IntentCompilerPluginId --scope user 2>&1 | Out-String)
        $IntentCompilerUninstallExitCode = $LASTEXITCODE
        if ($IntentCompilerUninstallExitCode -ne 0) {
            throw "Claude plugin uninstall failed."
        }
        Write-Host "Uninstalled Claude plugin: $IntentCompilerPluginId"
    }
    else {
        Write-Host "Claude plugin is already absent."
    }

    $IntentCompilerMarketplacesRaw = (& $IntentCompilerClaude.Source plugin marketplace list --json 2>&1 | Out-String)
    if ($LASTEXITCODE -ne 0) {
        throw "Could not inspect Claude marketplaces safely."
    }
    $IntentCompilerMarketplaces = @($IntentCompilerMarketplacesRaw | ConvertFrom-Json)
    $IntentCompilerMarketplace = @($IntentCompilerMarketplaces | Where-Object { $_.name -eq $IntentCompilerClaudeMarketplace }) | Select-Object -First 1

    if (-not $IntentCompilerMarketplace) {
        Write-Host "Claude marketplace is already absent."
        return
    }

    $IntentCompilerMarketplaceSource = if ($IntentCompilerMarketplace.path) {
        $IntentCompilerMarketplace.path
    }
    else {
        $IntentCompilerMarketplace.installLocation
    }
    if (-not $IntentCompilerMarketplaceSource -or -not (Test-SamePath $IntentCompilerMarketplaceSource $IntentCompilerRoot)) {
        Write-Warning "Preserving marketplace '$IntentCompilerClaudeMarketplace' because it does not point to this source repository."
        return
    }

    $null = (& $IntentCompilerClaude.Source plugin marketplace remove $IntentCompilerClaudeMarketplace --scope user 2>&1 | Out-String)
    $IntentCompilerMarketplaceExitCode = $LASTEXITCODE
    if ($IntentCompilerMarketplaceExitCode -ne 0) {
        throw "Claude marketplace removal failed."
    }
    Write-Host "Removed Claude marketplace: $IntentCompilerClaudeMarketplace"
}

try {
    switch ($Target) {
        "gpt" { Uninstall-ForCodex }
        "claude" { Uninstall-ForClaude }
        "all" {
            Uninstall-ForCodex
            Uninstall-ForClaude
        }
    }

    Write-Host "`nIntent Compiler uninstall complete. The source repository was preserved." -ForegroundColor Green
}
catch {
    [Console]::Error.WriteLine("ERROR: Intent Compiler uninstall failed. No unverified directory was removed.")
    exit 1
}
