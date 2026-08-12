# Copilot customization files

This folder is a port of the `general/`, `mobile/`, and `web/` content to
GitHub Copilot's current customization surfaces. Edit the source folders, not
this one — changes here will be overwritten the next time the port is updated.

---

## File placement

Copy these files into the consuming project's `.github/` directory:

| Source (this folder) | Destination in consuming project |
| -------------------- | -------------------------------- |
| `copilot-instructions.md` | `.github/copilot-instructions.md` |
| `instructions/mobile.instructions.md` | `.github/instructions/mobile.instructions.md` |
| `instructions/web.instructions.md` | `.github/instructions/web.instructions.md` |
| `agents/architect.agent.md` | `.github/agents/architect.agent.md` |
| `agents/code-reviewer.agent.md` | `.github/agents/code-reviewer.agent.md` |
| `agents/security-reviewer.agent.md` | `.github/agents/security-reviewer.agent.md` |
| `agents/test-writer.agent.md` | `.github/agents/test-writer.agent.md` |
| `agents/db-guardian.agent.md` | `.github/agents/db-guardian.agent.md` |
| `agents/ux-auditor.agent.md` | `.github/agents/ux-auditor.agent.md` |
| `agents/ux-fixer.agent.md` | `.github/agents/ux-fixer.agent.md` |
| `agents/device-qa.agent.md` | `.github/agents/device-qa.agent.md` (mobile projects only) |

Only copy the files that apply to your project's platform.

---

## Copilot customization surfaces (verified Aug 2026)

| Surface | File pattern | When it applies |
| ------- | ------------ | --------------- |
| Repo-wide rules | `.github/copilot-instructions.md` | Always on, for every Copilot request in the repo |
| Path-scoped rules | `.github/instructions/*.instructions.md` | Applied when the open file matches the `applyTo` glob in frontmatter |
| Agents (custom chat modes) | `.github/agents/*.agent.md` | Invoked explicitly by name in Copilot Chat |

> **Note:** `.chatmode.md` is the deprecated predecessor of `.agent.md`. Do not use it.

---

## Tool-name mapping

Claude Code and Copilot have different tool names for equivalent capabilities.
The agent files use Copilot's names; this table explains the mapping for
reference when updating agents from the source.

| Claude Code tool | Copilot equivalent |
| ---------------- | ------------------ |
| `Read` | _(implicit — agents can always read files)_ |
| `Grep`, `Glob` | `search/codebase`, `search/usages` |
| `Edit`, `Write` | `edit` |
| `Bash` | `runCommands` |
| `WebFetch`, `WebSearch` | `web/fetch` |

---

## Agent frontmatter fields

Each `*.agent.md` file uses this frontmatter:

```yaml
---
name: <agent-name>            # shown in the Copilot Chat agent picker
description: <one sentence>   # shown in the picker; used to match intent
tools:                        # Copilot tool names this agent may use
  - search/codebase
  - edit
  - runCommands
model: claude-opus-4          # preferred model; Copilot falls back if unavailable
---
```

The body is the system prompt for the agent.

---

## Path-scoped instruction frontmatter

```yaml
---
applyTo: "apps/mobile/**,packages/ui/**"   # comma-separated globs
---
```

When any file matching the glob is open or referenced, Copilot includes this
instruction file automatically.
