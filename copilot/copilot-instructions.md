# Project engineering rules

This file is automatically included in every Copilot request. It sets the
engineering bar for this repository. Replace the `<...>` placeholders with
project-specific facts before committing this file.

---

## Commands

The main verification command is `<full-verify>` (e.g. `pnpm verify`). It
runs lint, type-check, and tests in the right order. Run it once, at the end
of a task, not after every small edit.

Note any non-obvious ordering (`<e.g. generate types from migrated schema
before typechecking>`). Note which steps already run automatically on commit
so you don't duplicate them.

---

## Invariants

These are the things where "we'll fix it in the next PR" is not a real option
because by then the damage has already happened. Treat a change that breaks
one of them as wrong by construction, not as an edge case.

1. **Every resource that holds another user's data is access-controlled by
   default**, not by remembering to add a check in every query. Row-level
   security, per-tenant scoping, capability tokens — whichever the stack uses
   — must be on before any data can be read or written.
2. **A privileged credential lives in exactly one place** (a server-only
   function, a backend service) and is never reachable from client code,
   a public bundle, or a log line. A public/publishable key embedded in a
   client bundle is not itself the vulnerability; the question is whether a
   *privileged* key can be reached.
3. **Sensitive fields never leave the resource that owns them.** A
   list/search endpoint that needs a coarse version of a precise field derives
   it once, at write time — it doesn't trust every future reader to redact.
4. **Money is an integer in its smallest unit**, never a float. Rounding
   happens in exactly one direction, and every layer that computes the same
   number agrees on which direction.
5. **A rate, price, or policy that can change over time is stored on the
   record it applied to**, not read live from a constant.
6. **State with a lifecycle transitions through an explicit, enumerable set
   of edges** — illegal transitions are rejected where the state lives, not
   just where it's set from.
7. **Authorization is enforced at the layer that can't be bypassed** (the
   database, the API gateway). A check in the client or UI is a courtesy,
   never the actual gate.
8. **CI actions are pinned by commit SHA**, not a mutable tag. Workflows
   declare minimal `permissions:`.

_Add this project's own invariants here._

---

## Recording a new pattern

When you adopt a new pattern, write it down in the same commit that introduces
it. Undocumented, it survives until the next person opens the file and picks
something different.

A pattern entry needs four things: what to do, the problem it avoids, where
it's enforced (lint, type, test, CI — or "convention only"), and one example
file. Apply the pattern to existing code in the same commit — a pattern that
only applies to new files creates two conventions instead of one. When a
pattern changes, update its entry.

---

## Dependency boundaries

State the dependency direction: `<e.g. apps → api → core → nothing>`. Treat
lint-enforced boundaries as load-bearing: a proposal that requires disabling a
boundary rule is wrong, not an edge case. No linter escape hatches
(`eslint-disable`, `# noqa`, `@ts-ignore`) on boundary rules.

---

## Conventions

- **Language:** `<state which parts of the codebase are always in one
  language and which match the product language>`.
- Strict typing: no `any`, no non-null assertions, no unchecked casts without
  a comment explaining why the type system genuinely can't express this.
- Comments explain *why*, not *what* — the code already says what.
- Timestamps come from the server/database, never the client device.
- A single place translates low-level errors (database error code, HTTP
  status) into what the rest of the app deals with. Raw infrastructure errors
  don't reach the UI.
- An applied migration (or any other one-way, already-shipped change) doesn't
  get edited — you correct it with a new one.
- Use the project's design token system (colors, spacing, typography, motion)
  — never literal values.

---

## Testing

Tests exist where being wrong is expensive; coverage percentage is not the
goal.

**Write a test when:** an authorization rule has a non-trivial case (a
counterparty, a role, an acceptance state) — include the unauthorized actor,
not just the happy path; a state transition is added — valid case and rejected
case; money is involved — compare rounding against every layer that computes
the same number; a business rule is intentionally duplicated in two
layers — write a test that mechanically compares the two instead of trusting
that someone remembers to update both; a bug is fixed — write a test that
fails before the fix and passes after.

**Don't write a test for:** a getter, a straight row-to-DTO mapping, or
anything the type system already guarantees.

---

## Design placement

Where a new capability belongs — descend only when the level above genuinely
doesn't fit:

1. **The data layer** — if it's an invariant that must hold for every client
   of the API.
2. **Pure domain logic** — if it's a business rule testable without network
   or storage.
3. **The data-access layer** — if it's a query, a mapping, or error
   translation.
4. **The app/UI** — if it's presentation, navigation, or screen-local state.

YAGNI wins by default. Two occurrences don't justify an abstraction. A
different context is not duplication — don't unify code that will diverge for
unrelated reasons. Prefer a data structure that makes an invalid state
unrepresentable over validation scattered everywhere. If understanding a new
design requires opening more than two files, the design lost.

---

## Context discipline

Read a slice, not a whole file, when only a slice is relevant. Don't read
generated or vendored files (lockfiles, generated types, build output,
`node_modules`). Don't re-read what you just edited. Run the full
verification once, at the end, not after every small edit. Don't paste a
large diff into a response — say what changed and where.

## Token minmax

Apply these measures to avoid context bloat:

### Code Graph Context (CGC)

Use CGC for symbol-level structural querying rather than bulk text reading.
It provides precise subgraphs (callers, callees, definitions) instead of
raw file text, often saving 10-100x tokens on navigation.

### Path-scoped instructions (`applyTo`)

Do not put language/framework rules in this global file. Use separate
`.instructions.md` files (e.g., `frontend.instructions.md`) in the
`.github/instructions/` directory with an `applyTo` glob:

```markdown
---
applyTo:
  - webapp/src/**
---
```
Only load rules when matching files are active.

### GitHub Content Exclusion

Configure Content Exclusion in GitHub Enterprise / Org settings to globally
block Copilot from seeing large or sensitive paths:
- `dist/**`, `build/**`, `coverage/**`
- `**/*.snap`
- Media assets, fonts, and binaries
- If JS/TypeScript: `node_modules/**`, `*.lock`, `*.lockb`,
  `**/*.tsbuildinfo` too (see `javascript/README.md` in the ai-dev-standards
  source repo)

### Extreme Budget Minmaxing (IDE Behavior)

If you are operating on a heavily restricted credit budget, context setup is not enough. You must alter how you interact with the IDE:

1. **Disable Automatic Inline Suggestions**: Copilot triggers a completion request on almost every keystroke, draining credits silently in the background. Go to your IDE settings and disable automatic suggestions (`editor.inlineSuggest.enabled = false` in VS Code) or set a long delay. Trigger them manually only when needed (e.g., `Alt+\`).
2. **Restrict Open Tabs**: Copilot uses all currently open tabs to build its context window. Having 10 files open means 10 files are processed on every chat message. **Keep a maximum of 1 or 2 tabs open** at any time.
3. **Use Explicit Selection over Whole-File Context**: When using Copilot Chat (or Cmd+I), highlight the exact 5-10 lines of code you want to discuss rather than asking a question with the whole file open. This forces Copilot to prioritize the selection instead of reading the entire file.
4. **Avoid Open-Ended Chat Conversations**: Start a new chat session (clear history) the moment you switch to a new sub-task. Long chat threads carry their entire history as context on every new prompt, which exponentially burns tokens/credits.
