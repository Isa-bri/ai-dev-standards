# ai-dev-standards

A personal library of Claude Code rules and subagents, plus a port to GitHub
Copilot's customization surfaces. Extracted from production experience so new
repositories can start from the distilled principles instead of re-deriving
them.

**How to use:** copy, don't symlink or git-subtree. Keeping the files local
means each project can adapt without worrying about breaking a shared pointer,
and the source of truth stays in this repo for the next project to start from.

---

## For an AI agent configuring this repo for a user

If you were pointed at this repo to set up a new (or existing) project, follow
this procedure instead of re-deriving one from the tables below:

1. **Determine the target project's shape.** Ask the user, or infer it:
   - Does it have platform-specific rules to apply? → `general` (none),
     `web` (Next.js/Tailwind/pnpm-workspace app), or `mobile` (React
     Native/Expo). Check for `app.json`/`expo` in `package.json` (mobile),
     a `pnpm-workspace.yaml` or Tailwind config (web), or neither (general).
   - Is it JS/TypeScript at all (any package manager)? Check for a
     `package.json`. If yes, the `javascript/` folder applies **in addition
     to** whichever of the three above you picked — it is not a fourth
     alternative to them, it layers on top.
   - Which AI tool(s) does the user want configured — Claude Code, GitHub
     Copilot, or both? Ask if it's not already obvious from what's installed
     (`.claude/` vs `.github/copilot-instructions.md` present already).
2. **Prefer the scripted install** (`scripts/setup-ai-standards.sh` on
   macOS/Linux, `scripts/setup-ai-standards.ps1` on Windows) over manually
   copying files — it merges instead of overwriting existing config, and
   covers the MCP server setup and dependency installs. See "Scripted
   install" below for the exact flags; pass every answer you already know as
   a flag so the script only prompts for what's genuinely undecided.
3. **After running the script** (or copying files by hand — see "Manual
   install" below), tell the user, or do it yourself if authorized to edit
   the target repo:
   - Fill in every `<...>` placeholder in the copied `CLAUDE.md` and/or
     `.github/copilot-instructions.md` with facts about *that* project
     (install/lint/test commands, dependency-direction boundaries, the
     project's own invariants). These are template placeholders, not
     optional — an agent reading an unfilled `<install>` command later will
     have nothing to run.
   - Delete sections of the copied template that don't apply.
   - If `--supabase-project-ref` wasn't passed and the project uses
     Supabase, still fill in `{{SUPABASE_PROJECT_REF}}` by hand in
     `.mcp.json`, or re-run the script with that flag.
   - Commit everything, so the next agent session in that repo picks it up.

Everything below this section is reference material for a human (or an agent
that wants the full rationale) — the four steps above are enough to execute
the setup end to end.

---

## Structure

```
general/     Rules and agents that apply to any project, any language, any framework
javascript/  Additive: pnpm/npm JS-TS tooling (Claude settings + Prettier hook)
mobile/      Additive: React Native / Expo platform traps + a QA agent
web/         Additive: pnpm-workspace / Tailwind platform traps
copilot/     Everything above, ported to GitHub Copilot's customization files
```

`general/` never assumes a package manager, a formatter, or a framework.
`javascript/`, `mobile/`, and `web/` are layers you copy on top of it — pick
`javascript/` whenever the project has a `package.json` (web or mobile app,
or a plain Node/TS service), and `mobile/`/`web/` on top of that only when
the project is actually a React Native/Expo app or a Next.js/Tailwind app.
A plain Node CLI, for instance, gets `general/` + `javascript/` and nothing
else.

### `general/`

- **`CLAUDE.md`** — Template `CLAUDE.md` to copy into a new project. Covers:
  invariants (the things where "we'll fix it in the next PR" isn't an option),
  pattern-registration discipline, dependency boundaries, conventions, testing
  philosophy, and context discipline for agents. Every `<...>` placeholder is
  something the consuming project fills in.

- **`agents/`** — Eight subagents. Copy into the project's `.claude/agents/`.
  All are language/framework-agnostic except `db-guardian`, which is written
  for a Postgres-style row-level-security model (it says so, and how to adapt
  it, at the top of the file) and `ux-auditor`/`ux-fixer`, whose examples use
  `.tsx` file paths purely as illustration.

  | Agent                  | When to use                                    |
  | ---------------------- | ----------------------------------------------- |
  | `architect.md`         | Design decisions before code exists            |
  | `code-reviewer.md`     | Quality gate after a non-trivial change        |
  | `security-reviewer.md` | Auth, secrets, CI, new dependency review       |
  | `test-writer.md`       | Missing tests, post-feature, post-bug-fix      |
  | `db-guardian.md`       | Migrations, RLS, policies, triggers, functions |
  | `ux-auditor.md`        | Full UX/UI audit, produces a batch action plan |
  | `ux-fixer.md`          | Executes one batch from `ux-auditor`'s plan    |
  | `context-guard.md`     | Watches for context-window bloat mid-session   |

- **`mcp/`** — a starter `.mcp.json` (MCP server list) for Claude Code. All
  of these are language-agnostic.
  | Server                | Purpose                                                         | Needs input?                                         | Needs a separate install?                          |
  | --------------------- | --------------------------------------------------------------- | ---------------------------------------------------- | -------------------------------------------------- |
  | `codegraphcontext`    | Code graph queries ("who calls this") instead of raw file reads | No                                                   | Yes — `cgc` CLI (`npm i -g @codegraphcontext/cli`) |
  | `playwright`          | Browser automation / E2E from the agent                         | No                                                   | No — runs via `npx` on first use                   |
  | `git`                 | Git operations as MCP tools instead of shelling out             | No                                                   | No — runs via `npx` on first use                   |
  | `tree-sitter`         | Symbol-level source parsing across languages                    | No                                                   | Yes — `pipx install mcp-server-tree-sitter`        |
  | `memory`              | Small persistent knowledge graph across sessions                | No — path is auto-derived from the project's dirname | No — runs via `npx` on first use                   |
  | `sequential-thinking` | Structured multi-step reasoning tool                            | No                                                   | No — runs via `npx` on first use                   |
  | `supabase`            | Supabase project schema/logs/SQL via MCP                        | **Yes** — your project's ref                         | No — hosted, HTTP transport                        |
  - **`mcp.json`** — the six always-generic servers.
  - **`mcp.supabase.json`** — the `supabase` server as a separate fragment,
    only merged in if you opt in during setup and provide a project ref.

### `javascript/`

- **`README.md`** — explains what belongs here and why (pnpm/npm-ecosystem
  tooling that both `web/` and `mobile/` projects share) and lists the
  `.claudeignore` lines to append for a JS/TS project.
- **`claude-settings/`** — `.claude/settings.json` plus the hook it wires up.
  Claude-Code-only; there's no Copilot equivalent, so this isn't ported to
  `copilot/` (same reasoning as `general/` not shipping a settings.json).
  - **`settings.json`** — a `PostToolUse` hook that runs Prettier on every
    file Claude edits or writes, and a starter `permissions.allow`/`deny`
    list covering commands that are safe and useful in any pnpm/TypeScript
    repo (`pnpm lint`/`typecheck`/`test`, read-only `git`, `ls`/`cat`/`find`,
    …). Add your own project's scripts on top of it.
  - **`hooks/format-edited.sh`** — the script the hook above calls. No-ops
    silently if the file type isn't formattable or `node_modules/.bin/prettier`
    doesn't exist, so it's safe to drop into any project. It's a bash
    script — on Windows it runs via Git Bash/WSL, the same shell Claude Code
    itself already needs there.

### `mobile/`

- **`RULES.md`** — Expo/React Native platform traps: URL polyfill gaps, Metro
  env-var inlining, generated `android/`/`ios/` directories, datetime picker
  platform splits, image picker Android 16 crash, `adb reverse` for on-device
  dev, cold-start navigation timing, Babel preset hoisting, and NativeWind
  token cache invalidation.

- **`agents/device-qa.md`** — Visual QA agent that runs the app on a
  connected device via adb and reports what diverges from the spec.

### `web/`

- **`RULES.md`** — pnpm/Tailwind traps: pnpm workspace config belongs in
  `pnpm-workspace.yaml` (not `package.json`, silently ignored ≥ 10.33);
  Tailwind v3 purges an unreferenced `.dark` class (needs `safelist`);
  `tailwind-merge` can't classify custom typography tokens without registration.

  _No `agents/` subfolder._ The `code-reviewer`, `security-reviewer`, and
  `db-guardian` agents in `general/` already cover the web layer. This is
  deliberate, not an oversight.

---

## How to install into a new project

The fastest path is `scripts/setup-ai-standards.sh` / `.ps1` (see below); the
manual steps are what they automate.

### Claude Code (manual)

1. Copy `general/CLAUDE.md` into the project root as `CLAUDE.md`. Fill in
   every `<...>` placeholder with project-specific facts. Delete sections
   that don't apply.
2. Copy `general/agents/*.md` into `.claude/agents/`.
3. If the project is JS/TypeScript (any package manager), also copy
   `javascript/claude-settings/settings.json` to `.claude/settings.json`
   and `javascript/claude-settings/hooks/format-edited.sh` to
   `.claude/hooks/format-edited.sh` (`chmod +x` it). If a `settings.json`
   already exists, merge `permissions.allow`/`deny` and
   `hooks.PostToolUse` by hand instead of overwriting it.
4. Copy `general/mcp/mcp.json` to `.mcp.json`, replacing
   `{{MEMORY_FILE_PATH}}` with a real path (e.g.
   `~/.claude/mcp-memory/<project-name>.json`). If the project uses
   Supabase, also merge in `general/mcp/mcp.supabase.json` with
   `{{SUPABASE_PROJECT_REF}}` replaced by the project's ref. List whatever
   server names you added under `enabledMcpjsonServers` in
   `.claude/settings.local.json`.
5. If the project is a React Native / Expo app, also copy
   `mobile/agents/device-qa.md` into `.claude/agents/` and link
   `mobile/RULES.md` from your `CLAUDE.md`.
6. If the project uses pnpm workspaces and/or Tailwind, link `web/RULES.md`
   from your `CLAUDE.md`.

### GitHub Copilot (manual)

See [`copilot/README.md`](copilot/README.md) for file placement and the
tool-name mapping table. `.mcp.json` and `.claude/settings.json` (and their
`javascript/` counterpart) are Claude Code concepts with no Copilot
equivalent, so the Copilot install path skips them entirely.

### Scripted install

**macOS / Linux:**

```bash
./scripts/setup-ai-standards.sh /path/to/target-repo \
  -t general \        # general | web | mobile
  -a claude \          # claude | copilot | both
  --js y \                          # y | n — also install javascript/ (pnpm/Prettier tooling)
  --mcp all \          # all | none — the standard MCP server set
  --supabase-project-ref <ref> \   # optional: adds the Supabase MCP server non-interactively
  --install-cgc y \                # optional: installs & indexes Code Graph Context
  --install-mcp-tools y             # optional: pipx-installs the tree-sitter MCP dependency
```

**Windows (PowerShell):**

```powershell
./scripts/setup-ai-standards.ps1 C:\path\to\target-repo `
  -Type general `                  # general | web | mobile
  -Agent claude `                  # claude | copilot | both
  -Js y `                          # y | n — also install javascript/ (pnpm/Prettier tooling)
  -Mcp all `                       # all | none — the standard MCP server set
  -SupabaseProjectRef <ref> `      # optional: adds the Supabase MCP server non-interactively
  -InstallCgc y `                  # optional: installs & indexes Code Graph Context
  -InstallMcpTools y               # optional: pipx-installs the tree-sitter MCP dependency
```

The two scripts are behavior-for-behavior equivalents (same flags, same
prompts, same merge semantics) — the PowerShell version merges JSON natively
(`ConvertFrom-Json`/`ConvertTo-Json`) instead of needing `jq` on `PATH`.

Any flag left out is prompted for interactively. For `claude`/`both`, the
scripts:

- copy `CLAUDE.md` and `.claude/agents/*.md` (appending to `CLAUDE.md` with
  an `<!-- APPENDED BY AI DEV STANDARDS -->` marker if one already exists);
- if `--js`/`-Js y`, copy `.claude/hooks/format-edited.sh` and merge
  `.claude/settings.json` (union of `permissions.allow`/`deny`, dedup'd; new
  `hooks.PostToolUse` entries appended, not duplicated) from `javascript/` —
  the bash script's merge requires `jq` on `PATH`; if `jq` is missing, it
  warns and leaves the merge to you (the PowerShell script never needs `jq`);
- merges the chosen MCP servers into `.mcp.json` the same way — **existing
  server entries always win** on a key collision, so a project's own
  hand-edited server config is never clobbered — and syncs
  `enabledMcpjsonServers` in `.claude/settings.local.json`. Same `jq`
  requirement/fallback (bash) as above;
- installs/indexes Code Graph Context and, optionally, runs
  `pipx install mcp-server-tree-sitter` for the tree-sitter MCP server. The
  remaining `npx`-based servers (`playwright`, `git`, `memory`,
  `sequential-thinking`) need no separate install — Claude Code fetches them
  on first connection.

Re-running a script against an already-set-up project is safe: it merges
rather than overwrites `.mcp.json` and `.claude/settings.json`, and appends
(with a marker) rather than clobbers `CLAUDE.md`/agent files.

---

## Updating these standards

Edit the source files in `general/`, `javascript/`, `mobile/`, and `web/`.
The `copilot/` folder is derived — update it to match after changing a
source file. Don't edit `copilot/` directly as the source of truth.
