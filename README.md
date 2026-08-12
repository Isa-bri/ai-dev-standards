# ai-dev-standards

A personal library of Claude Code rules and subagents, plus a port to GitHub
Copilot's customization surfaces. Extracted from production experience so new
repositories can start from the distilled principles instead of re-deriving
them.

**How to use:** copy, don't symlink or git-subtree. Keeping the files local
means each project can adapt without worrying about breaking a shared pointer,
and the source of truth stays in this repo for the next project to start from.

---

## Structure

```
general/     Rules and agents that apply to any project regardless of platform
mobile/      React Native / Expo additions
web/         pnpm-workspace / Tailwind additions
copilot/     Everything above, ported to GitHub Copilot's customization files
```

### `general/`

- **`CLAUDE.md`** — Template `CLAUDE.md` to copy into a new project. Covers:
  invariants (the things where "we'll fix it in the next PR" isn't an option),
  pattern-registration discipline, dependency boundaries, conventions, testing
  philosophy, and context discipline for agents. Every `<...>` placeholder is
  something the consuming project fills in.

- **`agents/`** — Seven subagents. Copy into the project's `.claude/agents/`.
  | Agent | When to use |
  | ----- | ----------- |
  | `architect.md` | Design decisions before code exists |
  | `code-reviewer.md` | Quality gate after a non-trivial change |
  | `security-reviewer.md` | Auth, secrets, CI, new dependency review |
  | `test-writer.md` | Missing tests, post-feature, post-bug-fix |
  | `db-guardian.md` | Migrations, RLS, policies, triggers, functions |
  | `ux-auditor.md` | Full UX/UI audit, produces a batch action plan |
  | `ux-fixer.md` | Executes one batch from `ux-auditor`'s plan |

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

### Claude Code

1. Copy `general/CLAUDE.md` into the project root as `CLAUDE.md`. Fill in
   every `<...>` placeholder with project-specific facts. Delete sections
   that don't apply.
2. Copy `general/agents/*.md` into `.claude/agents/`.
3. If the project is a React Native / Expo app, also copy
   `mobile/agents/device-qa.md` into `.claude/agents/` and link
   `mobile/RULES.md` from your `CLAUDE.md`.
4. If the project uses pnpm workspaces and/or Tailwind, link `web/RULES.md`
   from your `CLAUDE.md`.

### GitHub Copilot

See [`copilot/README.md`](copilot/README.md) for file placement and the
tool-name mapping table.

---

## Updating these standards

Edit the source files in `general/`, `mobile/`, and `web/`. The `copilot/`
folder is derived — update it to match after changing a source file. Don't
edit `copilot/` directly as the source of truth.
