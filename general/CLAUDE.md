# Project rules — template

This file is a starting point, not a finished `CLAUDE.md`. Copy it into a new
project as `CLAUDE.md`, then fill in every `<...>` placeholder with facts about
that specific project. Delete sections that don't apply; add sections this
template doesn't anticipate. The goal is a file that stops an agent from
breaking something a code reviewer wouldn't have thought to check for either —
not a style guide.

If the project is mobile (React Native/Expo) or web (Next.js/Tailwind), also
copy the matching `mobile/RULES.md` or `web/RULES.md` from this repo into the
project's docs and link it from here.

## Commands

```bash
<install>              # e.g. pnpm install / npm ci
<lint-and-typecheck>    # whatever runs in CI before merge
<test>
<full-verify>            # the one command that runs all of the above
```

Note here anything non-obvious about command _order_ (e.g. "types are
generated from the migrated schema, so migrate before typechecking") and which
of these already run automatically via a pre-commit hook, so an agent doesn't
duplicate work a hook already does.

## Invariants

List the things that are expensive to get wrong — the ones where "we'll fix it
in the next PR" isn't a real option because by then the damage (a data leak, a
wrong charge, a corrupted state) has already happened. Enumerate yours; this
template can't guess them, but here's the shape they tend to take:

1. **Every table/resource that holds another user's data is access-controlled
   by default**, not by remembering to add a check in every query that touches
   it. (Row-level security, per-tenant scoping, capability tokens — whichever
   your stack uses.)
2. **A privileged credential lives in exactly one place** (a server-only
   function, a backend service) and is never reachable from client code, a
   public bundle, or a log line.
3. **Sensitive fields never leave the resource that owns them.** A list/search
   endpoint that needs a coarse version of a precise field (an approximate
   location from an exact address, a masked card number from a full one)
   derives it once, at write time, rather than trusting every future reader to
   redact it correctly.
4. **Money is an integer in its smallest unit**, never a float. Rounding
   happens in exactly one direction, and code and any generated data agree on
   which one.
5. **A rate, price, or policy that can change over time is stored on the
   record it applied to**, not read live from a constant — otherwise changing
   the constant rewrites history.
6. **State that has a lifecycle transitions through an explicit, enumerable
   set of edges**, not an implicit set of flags that happen to combine into
   states. Illegal transitions are rejected where the state lives, not just
   where it's set from.
7. **Authorization is enforced at the layer that can't be bypassed** (the
   database, the API gateway) — a check in the client or the UI is a courtesy,
   never the actual gate.
8. **A CI action pinned to a mutable tag is a supply-chain hole.** Pin
   third-party actions by commit SHA; grant workflows the minimum
   `permissions:` they need.

## Recording a new pattern

**When you adopt a new pattern, write it down in the same commit that
introduces it.** Undocumented, it survives until the next person opens the
file and picks something different — now there are two ways to do the same
thing.

A pattern entry needs four things: what to do, the problem it avoids, where
it's enforced (lint rule, type, test, CI — or "convention only, no
enforcement"), and one example file.

Automate enforcement where you can. If the decision is expensive to reverse,
write an ADR too. Apply the pattern to existing code in the same commit —
a pattern that only applies to new files creates two conventions instead of
one.

The reverse also holds: when a pattern changes, update its entry. A stale
record is worse than no record.

## Boundaries

If the codebase has layers (domain logic that doesn't know about the network
or a database; an API/data layer that's the only thing that talks to
storage; apps/UI that only talk to the data layer), state the dependency
direction explicitly and let a lint rule enforce it — not code review memory.
`eslint-disable` (or your linter's equivalent escape hatch) on a boundary rule
means the boundary itself is wrong, not that the exception is fine.

## Conventions

- State your language convention explicitly if the product is localized: which
  parts of the codebase are always in one language (identifiers, table names,
  developer-facing error messages) and which parts mirror the product's
  language (user-facing copy) — and say so even when the answer is "everything
  is English," because an agent won't assume that by default.
- Strict typing, no escape hatches (`any`, non-null assertions, unchecked
  casts) without a comment justifying why the type system genuinely can't
  express this.
- A comment explains _why_, not _what_ — the code already says what.
- Timestamps come from the server/database, never the client device.
- A single place translates low-level errors (a database error code, an HTTP
  status) into what the rest of the app deals with — don't let raw
  infrastructure errors reach the UI in fifteen different `catch` blocks.
- An applied migration (or any other one-way, already-shipped change) doesn't
  get edited after the fact — you correct it with a new one.

## Testing

Tests exist where being wrong is expensive; coverage percentage is not the
goal.

**Write a test when:** an authorization rule has a non-trivial case (a
counterparty, a role, an acceptance state) — and test the unauthorized actor,
not just the happy path; a state transition is added — valid case and rejected
case; money is involved — compare rounding against whatever else computes the
same number (a database function, a second service) so the two don't quietly
drift apart; a business rule is intentionally duplicated in two languages/
layers — write a test that mechanically compares the two instead of trusting
that someone remembers to update both.

**Don't write a test for:** a getter, a straight row-to-DTO mapping, or
anything the type system already guarantees.

## Traps this project has already learned about

Keep a running list here of the non-obvious things that compiled, passed
lint, and only broke on the device / in production / under load. This section
earns its keep over months, not on day one — start it empty and add to it the
first time something wastes an afternoon. See `mobile/RULES.md` and
`web/RULES.md` in this repo for a starter set of platform-level traps that
are worth carrying into most React Native or Next.js/Tailwind projects.

## Design

Where a new capability belongs — descend only when the level above genuinely
doesn't fit:

1. **The data layer**, if it's an invariant that must hold for every client of
   the API (uniqueness, a state transition, authorization, a materialized
   aggregate).
2. **Pure domain logic**, if it's a business rule testable without network or
   storage.
3. **The data-access layer**, if it's a query, a mapping, or error
   translation.
4. **The app/UI**, if it's presentation, navigation, or screen-local state.

- YAGNI wins by default. Two occurrences don't justify an abstraction; three
  in genuinely identical contexts do. A different context is not duplication
  (AHA over DRY) — don't unify code that happens to look similar today but
  will diverge tomorrow for unrelated reasons.
- Prefer a data structure that makes an invalid state unrepresentable over
  validation scattered across every place that state gets read.
- If understanding a new design requires opening more than two files, the
  design lost, even if it's technically correct.

## Context discipline

- Read a slice, not a whole file, when only a slice is relevant.
- Don't read generated or vendored files (lockfiles, generated types,
  build output, `node_modules`).
- Don't re-read what you just edited.
- Send broad, open-ended searches to a subagent that returns a conclusion,
  not a pile of file contents.
- Don't paste a large diff into a response; say what changed and where.
- Run the full verification once, at the end, not after every small edit.
