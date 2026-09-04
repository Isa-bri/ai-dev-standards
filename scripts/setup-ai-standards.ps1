<#
.SYNOPSIS
    Bootstraps a new (or existing) repository with the AI development standards
    from the ai-dev-standards repo. Windows port of setup-ai-standards.sh —
    same behavior, PowerShell-native (uses ConvertFrom-Json/ConvertTo-Json
    instead of jq, so no external JSON tool dependency on Windows).

.DESCRIPTION
    Token-reducing rules ("Context discipline") are included automatically in
    every CLAUDE.md / copilot-instructions.md file this script installs.

    .mcp.json and .claude/settings.json are only installed for -Agent claude|both
    — they're a Claude Code concept and have no Copilot equivalent.

.PARAMETER Path
    Path to the repo to set up (default: current directory).
.PARAMETER Agent
    AI tool: claude, copilot, or both.
.PARAMETER Type
    Project type: general, web, or mobile.
.PARAMETER InstallCgc
    y/n — install Code Graph Context (CGC) for token reduction.
.PARAMETER Mcp
    all/none — MCP servers to add to .mcp.json.
.PARAMETER SupabaseProjectRef
    Include the Supabase MCP server with this ref.
.PARAMETER InstallMcpTools
    y/n — install CLI deps the MCP servers need (tree-sitter, via pipx).
.PARAMETER Js
    y/n — also install javascript/ (pnpm/Prettier tooling).

.EXAMPLE
    ./setup-ai-standards.ps1 C:\path\to\target-repo -Agent claude -Type web -Js y -Mcp all
#>

[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string]$Path,

    [ValidateSet("claude", "copilot", "both")]
    [string]$Agent,

    [ValidateSet("general", "web", "mobile")]
    [string]$Type,

    [ValidateSet("y", "n")]
    [string]$InstallCgc,

    [ValidateSet("all", "none")]
    [string]$Mcp,

    [string]$SupabaseProjectRef,

    [ValidateSet("y", "n")]
    [string]$InstallMcpTools,

    [ValidateSet("y", "n")]
    [string]$Js
)

$ErrorActionPreference = "Stop"

# --------------- helpers -----------------------------------------------------

function Write-Info    { param([string]$Message) Write-Host "[info]  $Message" -ForegroundColor Cyan }
function Write-Success { param([string]$Message) Write-Host "[done]  $Message" -ForegroundColor Green }
function Write-Warn    { param([string]$Message) Write-Host "[warn]  $Message" -ForegroundColor Yellow }

# Every prompt routes through these two. When the host is non-interactive
# (CI, a piped script, an AI agent running this), Read-Host would either throw
# or block forever, and $ErrorActionPreference = "Stop" would abort the run
# partway through with a half-configured repo. In that case each prompt logs
# and takes its documented default instead.
$script:Interactive = [Environment]::UserInteractive -and -not [Console]::IsInputRedirected

function Read-YesNo {
    param([string]$Prompt, [string]$Default = "n")
    if (-not $script:Interactive) {
        Write-Info "Non-interactive host -- defaulting to '$Default': $Prompt"
        return $Default
    }
    $reply = Read-Host $Prompt
    if ([string]::IsNullOrWhiteSpace($reply)) { return $Default }
    return $reply
}

function Select-Option {
    param([string]$Prompt, [string]$Default, [string[]]$Options)
    if (-not $script:Interactive) {
        Write-Info "Non-interactive host -- defaulting to '$Default': $Prompt"
        return $Default
    }
    Write-Host $Prompt -ForegroundColor White
    for ($i = 0; $i -lt $Options.Length; $i++) {
        Write-Host "  $($i + 1)) $($Options[$i])"
    }
    while ($true) {
        $choice = Read-Host "Choice [1-$($Options.Length)]"
        if ($choice -match '^\d+$' -and [int]$choice -ge 1 -and [int]$choice -le $Options.Length) {
            return $Options[[int]$choice - 1]
        }
        Write-Warn "Please enter a number between 1 and $($Options.Length)."
    }
}

function Test-YesTrue {
    param([string]$Value)
    return $Value -match '^[Yy]'
}

# --------------- argument resolution ------------------------------------------

if (-not $Path) { $Path = (Get-Location).Path }
if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
    Write-Error "Target directory '$Path' does not exist."
    exit 1
}
$Target = (Resolve-Path -LiteralPath $Path).Path

$StandardsDir = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
if (-not (Test-Path -LiteralPath (Join-Path $StandardsDir "general/CLAUDE.md"))) {
    Write-Error "Cannot find general/CLAUDE.md relative to this script. Run it from inside the ai-dev-standards repo."
    exit 1
}

Write-Host ""
Write-Host "=== AI Dev Standards Setup ===" -ForegroundColor White
Write-Host ""
Write-Info "Standards source : $StandardsDir"
Write-Info "Target repo      : $Target"
Write-Host ""

# --------------- project type & AI tooling -----------------------------------

if (-not $Type) {
    $choice = Select-Option "What type of project is this?" "general" @(
        "general  (no platform-specific rules)",
        "web      (pnpm workspaces / Tailwind)",
        "mobile   (React Native / Expo)"
    )
    $Type = $choice.Split(" ")[0]
}

if (-not $Agent) {
    $choice = Select-Option "Which AI tool(s) do you want to configure?" "claude" @(
        "claude   (Claude Code -- copies CLAUDE.md + .claude/agents/)",
        "copilot  (GitHub Copilot -- copies .github/copilot-instructions.md + agents)",
        "both     (install both)"
    )
    $Agent = $choice.Split(" ")[0]
}

# Default to detecting it rather than guessing: a package.json is the whole test.
if (-not $Js) {
    $jsDefault = if (Test-Path -LiteralPath (Join-Path $Target "package.json")) { "y" } else { "n" }
    $Js = Read-YesNo "Is this a Node/pnpm (JS or TypeScript) project? (y/n)" $jsDefault
}

# --------------- copy / append functions --------------------------------------

function Copy-OrAppend-File {
    param([string]$Src, [string]$Dst)
    $dstDir = Split-Path -Parent $Dst
    if ($dstDir -and -not (Test-Path -LiteralPath $dstDir)) {
        New-Item -ItemType Directory -Path $dstDir -Force | Out-Null
    }
    $relDst = $Dst.Substring($Target.Length).TrimStart('\', '/')
    if (Test-Path -LiteralPath $Dst) {
        Write-Warn "File already exists: $relDst"
        Write-Info "Appending standard rules to existing file..."
        Add-Content -LiteralPath $Dst -Value "`n`n<!-- APPENDED BY AI DEV STANDARDS -->`n"
        Add-Content -LiteralPath $Dst -Value (Get-Content -LiteralPath $Src -Raw)
        Write-Success "Appended -> $relDst"
    } else {
        Copy-Item -LiteralPath $Src -Destination $Dst
        Write-Success "Copied -> $relDst"
    }
}

function Copy-Dir {
    param([string]$SrcDir, [string]$DstDir)
    if (-not (Test-Path -LiteralPath $DstDir)) {
        New-Item -ItemType Directory -Path $DstDir -Force | Out-Null
    }
    Get-ChildItem -LiteralPath $SrcDir -Filter "*.md" -File -ErrorAction SilentlyContinue | ForEach-Object {
        Copy-OrAppend-File -Src $_.FullName -Dst (Join-Path $DstDir $_.Name)
    }
}

# --------------- OS and MCP tool dependency install ----------------------------

# CodeGraphContext is a *Python* package: PyPI `codegraphcontext`, CLI `cgc`.
# It has never been published to npm -- the old `npm i -g @codegraphcontext/cli`
# here 404'd and, with $ErrorActionPreference = "Stop", killed the whole setup
# run before any file was written.
function Install-Cgc {
    if (Get-Command cgc -ErrorAction SilentlyContinue) {
        Write-Info "cgc is already on PATH -- skipping install."
    } elseif (Get-Command pipx -ErrorAction SilentlyContinue) {
        Write-Info "Installing codegraphcontext via pipx..."
        try { pipx install codegraphcontext } catch {
            Write-Warn "pipx install failed -- skipping CGC setup. Install it by hand with:"
            Write-Warn "  pipx install codegraphcontext"
            return
        }
    } elseif (Get-Command pip -ErrorAction SilentlyContinue) {
        Write-Info "pipx not found -- installing codegraphcontext with pip --user..."
        try { pip install --user codegraphcontext } catch {
            Write-Warn "pip install failed -- skipping CGC setup."
            return
        }
    } else {
        Write-Warn "CodeGraphContext needs Python (pipx or pip) and neither was found."
        Write-Warn "Install it later with: pipx install codegraphcontext"
        return
    }

    if (-not (Get-Command cgc -ErrorAction SilentlyContinue)) {
        Write-Warn "Installed, but 'cgc' is not on PATH yet -- open a new shell, then run:"
        Write-Warn "  cd '$Target'; cgc index; cgc mcp setup"
        return
    }

    # Indexing needs a running Neo4j (see 'cgc neo4j setup'). Neither step is
    # allowed to abort the setup run: the config files matter more than the
    # index, and both are safe to re-run later.
    Write-Info "Indexing target repository ($Target)..."
    Push-Location $Target
    try { cgc index } catch {
        Write-Warn "cgc index failed (is Neo4j running? try 'cgc neo4j setup') -- continuing."
    } finally { Pop-Location }

    Write-Info "Setting up MCP server..."
    try { cgc mcp setup } catch {
        Write-Warn "cgc mcp setup failed -- run it by hand later. Continuing."
    }

    Write-Success "CGC installed and configured."
}

function Install-McpToolDeps {
    Write-Host ""
    Write-Info "--- Token Optimization Setup ---"
    Write-Info "Detected OS: Windows"

    if (-not $script:InstallCgc) {
        $script:InstallCgc = Read-YesNo "Do you want to install Code Graph Context (CGC) for extreme token optimization? (y/n)" "n"
    }

    if (Test-YesTrue $script:InstallCgc) {
        Install-Cgc
    } else {
        Write-Info "Skipping CGC installation."
    }

    if ($script:Mcp -eq "none") { return }

    if (-not $script:InstallMcpTools) {
        $script:InstallMcpTools = Read-YesNo "Install the tree-sitter MCP server's CLI dependency via pipx now? (y/n)" "n"
    }

    if (Test-YesTrue $script:InstallMcpTools) {
        if (-not (Get-Command pipx -ErrorAction SilentlyContinue)) {
            Write-Warn "pipx is not installed -- skipping tree-sitter MCP server setup."
            Write-Warn "Install pipx, then run: pipx install mcp-server-tree-sitter"
        } else {
            Write-Info "Installing mcp-server-tree-sitter via pipx..."
            try {
                pipx install mcp-server-tree-sitter
                Write-Success "tree-sitter MCP dependency installed."
            } catch {
                Write-Warn "pipx install failed -- the server will still work via 'pipx run' on first use."
            }
        }
    } else {
        Write-Info "Skipping MCP tool dependency install (npx-based servers still work on first use)."
    }
}

# --------------- install Claude Code files -------------------------------------

function Install-Claude {
    Write-Host ""
    Write-Info "--- Installing Claude Code files ---"

    Copy-OrAppend-File -Src (Join-Path $StandardsDir "general/CLAUDE.md") -Dst (Join-Path $Target "CLAUDE.md")
    Copy-Dir -SrcDir (Join-Path $StandardsDir "general/agents") -DstDir (Join-Path $Target ".claude/agents")

    if ($Type -eq "mobile") {
        Copy-OrAppend-File -Src (Join-Path $StandardsDir "mobile/RULES.md") -Dst (Join-Path $Target "docs/mobile-rules.md")
        Copy-OrAppend-File -Src (Join-Path $StandardsDir "mobile/agents/device-qa.md") -Dst (Join-Path $Target ".claude/agents/device-qa.md")
        Write-Info "Remember to add 'See docs/mobile-rules.md' to CLAUDE.md"
    }

    if ($Type -eq "web") {
        Copy-OrAppend-File -Src (Join-Path $StandardsDir "web/RULES.md") -Dst (Join-Path $Target "docs/web-rules.md")
        Write-Info "Remember to add 'See docs/web-rules.md' to CLAUDE.md"
    }
}

# --------------- install .claude/settings.json + hooks (JS/pnpm only) ----------

function Install-Javascript {
    Write-Host ""
    Write-Info "--- Installing javascript/ (pnpm/Prettier tooling) ---"

    $hooksDir = Join-Path $Target ".claude/hooks"
    if (-not (Test-Path -LiteralPath $hooksDir)) { New-Item -ItemType Directory -Path $hooksDir -Force | Out-Null }
    Copy-Item -LiteralPath (Join-Path $StandardsDir "javascript/claude-settings/hooks/format-edited.sh") `
              -Destination (Join-Path $hooksDir "format-edited.sh")
    Write-Success "Copied -> .claude/hooks/format-edited.sh"
    Write-Info "format-edited.sh is a bash script -- Claude Code on Windows runs hooks through Git Bash or WSL, both of which are typically already required for Claude Code itself."

    $src = Join-Path $StandardsDir "javascript/claude-settings/settings.json"
    $dst = Join-Path $Target ".claude/settings.json"

    if (-not (Test-Path -LiteralPath $dst)) {
        $dstDir = Split-Path -Parent $dst
        if (-not (Test-Path -LiteralPath $dstDir)) { New-Item -ItemType Directory -Path $dstDir -Force | Out-Null }
        Copy-Item -LiteralPath $src -Destination $dst
        Write-Success "Copied -> .claude/settings.json"
        return
    }

    $existing = Get-Content -LiteralPath $dst -Raw | ConvertFrom-Json
    $new = Get-Content -LiteralPath $src -Raw | ConvertFrom-Json

    if (-not $existing.permissions) { $existing | Add-Member -NotePropertyName permissions -NotePropertyValue ([pscustomobject]@{}) }
    $existingAllow = @($existing.permissions.allow)
    $existingDeny  = @($existing.permissions.deny)
    $mergedAllow = @($existingAllow + @($new.permissions.allow) | Select-Object -Unique)
    $mergedDeny  = @($existingDeny  + @($new.permissions.deny)  | Select-Object -Unique)
    $existing.permissions | Add-Member -NotePropertyName allow -NotePropertyValue $mergedAllow -Force
    $existing.permissions | Add-Member -NotePropertyName deny  -NotePropertyValue $mergedDeny  -Force

    if (-not $existing.hooks) { $existing | Add-Member -NotePropertyName hooks -NotePropertyValue ([pscustomobject]@{}) }
    $existingHooks = @($existing.hooks.PostToolUse)
    $newHooks = @($new.hooks.PostToolUse)
    $existingJson = $existingHooks | ForEach-Object { $_ | ConvertTo-Json -Compress -Depth 10 }
    $toAdd = $newHooks | Where-Object { ($_ | ConvertTo-Json -Compress -Depth 10) -notin $existingJson }
    $mergedHooks = @($existingHooks + $toAdd)
    $existing.hooks | Add-Member -NotePropertyName PostToolUse -NotePropertyValue $mergedHooks -Force

    ($existing | ConvertTo-Json -Depth 20) | Set-Content -LiteralPath $dst -NoNewline
    Write-Success "Merged -> .claude/settings.json"
}

function Add-JsClaudeIgnore {
    $ignoreFile = Join-Path $Target ".claudeignore"
    if (-not (Test-Path -LiteralPath $ignoreFile)) { return }
    if ((Get-Content -LiteralPath $ignoreFile -Raw) -match '(?m)^node_modules/$') { return }
    $jsEntries = @"

# generated / vendored (JS/TS)
node_modules/
.pnp/
.next/
.expo/
.turbo/
*.tsbuildinfo

# lockfiles (agent must not read, not edit)
package-lock.json
yarn.lock
pnpm-lock.yaml
bun.lockb
"@
    Add-Content -LiteralPath $ignoreFile -Value $jsEntries
    Write-Success "Appended JS/TS entries -> .claudeignore"
}

# --------------- install .mcp.json ----------------------------------------------

function Expand-Template {
    param([string]$Src, [string]$Dst, [string]$MemoryFilePath, [string]$SupabaseRef)
    $content = Get-Content -LiteralPath $Src -Raw
    $content = $content -replace [regex]::Escape("{{MEMORY_FILE_PATH}}"), ($MemoryFilePath -replace '\\', '\\\\')
    $content = $content -replace [regex]::Escape("{{SUPABASE_PROJECT_REF}}"), $SupabaseRef
    Set-Content -LiteralPath $Dst -Value $content -NoNewline
}

function Merge-JsonObjects {
    param($Base, $Overlay)
    # Shallow merge at the top level for mcpServers: overlay fills in only missing keys.
    $result = [ordered]@{}
    foreach ($p in $Base.PSObject.Properties) { $result[$p.Name] = $p.Value }
    foreach ($p in $Overlay.PSObject.Properties) {
        if (-not $result.Contains($p.Name)) { $result[$p.Name] = $p.Value }
    }
    return [pscustomobject]$result
}

function Install-Mcp {
    Write-Host ""
    Write-Info "--- Installing .mcp.json ---"

    if (-not $script:Mcp) {
        $script:Mcp = Read-YesNo "Add the standard MCP server set to .mcp.json? (all/none)" "all"
    }

    if ($script:Mcp -eq "none") {
        Write-Info "Skipping MCP server setup."
        return
    }

    $projectName = Split-Path -Leaf $Target
    $memoryDir = Join-Path $env:USERPROFILE ".claude/mcp-memory"
    if (-not (Test-Path -LiteralPath $memoryDir)) { New-Item -ItemType Directory -Path $memoryDir -Force | Out-Null }
    $memoryFilePath = Join-Path $memoryDir "$projectName.json"

    $tmpDir = Join-Path ([System.IO.Path]::GetTempPath()) ([System.Guid]::NewGuid().ToString())
    New-Item -ItemType Directory -Path $tmpDir -Force | Out-Null
    try {
        $includeSupabase = "n"
        if ($script:SupabaseProjectRef) {
            $includeSupabase = "y"
        } else {
            # Non-interactively this answers "n": -SupabaseProjectRef is the only
            # way to opt in without a console, and it was already checked above.
            $includeSupabase = Read-YesNo "Does this project use Supabase? Add the Supabase MCP server? (y/n)" "n"
            if (Test-YesTrue $includeSupabase) {
                $script:SupabaseProjectRef = Read-YesNo "Supabase project ref" ""
            }
        }

        Expand-Template -Src (Join-Path $StandardsDir "general/mcp/mcp.json") -Dst (Join-Path $tmpDir "mcp.json") `
            -MemoryFilePath $memoryFilePath -SupabaseRef $script:SupabaseProjectRef

        $serverNames = @("codegraphcontext", "playwright", "git", "tree-sitter", "memory", "sequential-thinking")

        $mcpJsonPath = Join-Path $tmpDir "mcp.json"
        if ((Test-YesTrue $includeSupabase) -and $script:SupabaseProjectRef) {
            Expand-Template -Src (Join-Path $StandardsDir "general/mcp/mcp.supabase.json") -Dst (Join-Path $tmpDir "mcp.supabase.json") `
                -MemoryFilePath $memoryFilePath -SupabaseRef $script:SupabaseProjectRef
            $base = Get-Content -LiteralPath $mcpJsonPath -Raw | ConvertFrom-Json
            $overlay = Get-Content -LiteralPath (Join-Path $tmpDir "mcp.supabase.json") -Raw | ConvertFrom-Json
            $base.mcpServers = Merge-JsonObjects -Base $base.mcpServers -Overlay $overlay.mcpServers
            ($base | ConvertTo-Json -Depth 20) | Set-Content -LiteralPath (Join-Path $tmpDir "mcp.merged.json") -NoNewline
            $mcpJsonPath = Join-Path $tmpDir "mcp.merged.json"
            $serverNames += "supabase"
        }

        $dst = Join-Path $Target ".mcp.json"

        if (-not (Test-Path -LiteralPath $dst)) {
            Copy-Item -LiteralPath $mcpJsonPath -Destination $dst
            Write-Success "Created -> .mcp.json"
        } else {
            # Existing server entries always win on a key collision.
            $existing = Get-Content -LiteralPath $dst -Raw | ConvertFrom-Json
            $newServers = (Get-Content -LiteralPath $mcpJsonPath -Raw | ConvertFrom-Json).mcpServers
            $existing.mcpServers = Merge-JsonObjects -Base $existing.mcpServers -Overlay $newServers
            ($existing | ConvertTo-Json -Depth 20) | Set-Content -LiteralPath $dst -NoNewline
            Write-Success "Merged -> .mcp.json (existing server entries were kept as-is)"
        }

        $settingsLocal = Join-Path $Target ".claude/settings.local.json"
        $settingsLocalDir = Split-Path -Parent $settingsLocal
        if (-not (Test-Path -LiteralPath $settingsLocalDir)) { New-Item -ItemType Directory -Path $settingsLocalDir -Force | Out-Null }

        if (Test-Path -LiteralPath $settingsLocal) {
            $settings = Get-Content -LiteralPath $settingsLocal -Raw | ConvertFrom-Json
            $existingList = @($settings.enabledMcpjsonServers)
            $settings | Add-Member -NotePropertyName enabledMcpjsonServers -NotePropertyValue (@($existingList + $serverNames) | Select-Object -Unique) -Force
        } else {
            $settings = [pscustomobject]@{ enabledMcpjsonServers = @($serverNames) }
        }
        ($settings | ConvertTo-Json -Depth 20) | Set-Content -LiteralPath $settingsLocal -NoNewline
        Write-Success "Updated -> .claude/settings.local.json (enabledMcpjsonServers)"
    } finally {
        Remove-Item -LiteralPath $tmpDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# --------------- install GitHub Copilot files -----------------------------------

function Install-Copilot {
    Write-Host ""
    Write-Info "--- Installing GitHub Copilot files ---"

    Copy-OrAppend-File -Src (Join-Path $StandardsDir "copilot/copilot-instructions.md") -Dst (Join-Path $Target ".github/copilot-instructions.md")
    Copy-Dir -SrcDir (Join-Path $StandardsDir "copilot/agents") -DstDir (Join-Path $Target ".github/agents")

    if ($Type -eq "mobile") {
        Copy-OrAppend-File -Src (Join-Path $StandardsDir "copilot/instructions/mobile.instructions.md") -Dst (Join-Path $Target ".github/instructions/mobile.instructions.md")
        Write-Info "Add '# files: **/*.{ts,tsx}' applyTo glob to mobile.instructions.md if needed"
    }

    if ($Type -eq "web") {
        Copy-OrAppend-File -Src (Join-Path $StandardsDir "copilot/instructions/web.instructions.md") -Dst (Join-Path $Target ".github/instructions/web.instructions.md")
    }
}

# --------------- generate .claudeignore -----------------------------------------

# Claude Code reads .claudeignore, Copilot does not -- this used to live at the
# end of Install-Copilot, so -Agent claude (the common case) silently never got
# one. It belongs to every install path.
function New-ClaudeIgnore {
    Write-Host ""
    Write-Info "--- Generating .claudeignore ---"
    $ignoreFile = Join-Path $Target ".claudeignore"
    if (-not (Test-Path -LiteralPath $ignoreFile)) {
        @"
# generated / vendored build output
dist/
build/
out/
coverage/

# binaries / media
*.png
*.jpg
*.jpeg
*.gif
*.webp
*.svg
*.ico
*.mp4
*.mov
*.pdf
*.woff
*.woff2

# secrets / IDE
.env
.env.*
!.env.example
.DS_Store
.idea/
.vscode/
*.log
"@ | Set-Content -LiteralPath $ignoreFile -NoNewline
        Write-Success "Created -> .claudeignore"
    } else {
        Write-Warn "Already exists, skipping: .claudeignore"
    }
}

# --------------- run -------------------------------------------------------------

Install-McpToolDeps

switch ($Agent) {
    "claude" {
        Install-Claude
        if (Test-YesTrue $Js) { Install-Javascript }
        Install-Mcp
    }
    "copilot" {
        Install-Copilot
    }
    "both" {
        Install-Claude
        if (Test-YesTrue $Js) { Install-Javascript }
        Install-Mcp
        Install-Copilot
    }
}

New-ClaudeIgnore

if (Test-YesTrue $Js) { Add-JsClaudeIgnore }

Write-Host ""
Write-Host "=== Token-reducing rules & tools (already included in files above) ===" -ForegroundColor White
Write-Host ""
Write-Host "  The standards enforce extreme token discipline. Review these mechanisms:"
Write-Host ""
Write-Host "  - Code Graph Context (CGC): Use an MCP server for symbol-level codebase"
Write-Host "    queries instead of raw file reading. Highly recommended."
Write-Host "  - Scoped Instructions: Use 'applyTo' in Copilot to only inject rules"
Write-Host "    when matching files are open."
Write-Host "  - Context Discipline: Baked into CLAUDE.md & copilot-instructions.md:"
Write-Host "    - Read slices, not full files."
Write-Host "    - Send broad searches to subagents that return conclusions."
Write-Host "    - Minify large tool outputs before returning them to context."
Write-Host "    - Don't paste large diffs -- say what changed and where."
Write-Host ""

Write-Host "=== Next steps ===" -ForegroundColor White
Write-Host ""
Write-Host "  1. Fill in every <...> placeholder in the copied files:"
if ($Agent -eq "claude" -or $Agent -eq "both") {
    Write-Host "       $Target\CLAUDE.md"
}
if ($Agent -eq "copilot" -or $Agent -eq "both") {
    Write-Host "       $Target\.github\copilot-instructions.md"
}
Write-Host ""
Write-Host "  2. Delete any sections that don't apply to this project."
Write-Host "  3. Add project-specific invariants under '## Invariants'."
Write-Host "  4. Commit everything so agents pick it up on the first run."
Write-Host ""
Write-Success "Setup complete."
