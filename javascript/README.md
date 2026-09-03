# JavaScript / TypeScript (pnpm) — tooling additions

This folder holds the parts of the standards that are specific to the
**pnpm/Node JS-TS toolchain** — not to any particular framework. Both
`web/` (Next.js/Tailwind) and `mobile/` (React Native/Expo) projects are
JS-ecosystem projects, so this folder is copied *in addition to* `general/`
for either of them, and on its own for a plain Node/TypeScript project
(a CLI, a backend service) that isn't "web" or "mobile" in the `web/`/
`mobile/` sense.

`general/` stays free of any assumption about package manager, formatter,
or language — copy this folder on top of it whenever the project is
JS/TS-based.

---

## Contents

- **`claude-settings/settings.json`** — a starter `.claude/settings.json`:
  a `PostToolUse` hook wired to Prettier, plus `permissions.allow`/`deny`
  entries for `pnpm lint`/`typecheck`/`test`/`format`, read-only `git`, and
  common read-only shell commands. Adjust the `pnpm` commands if the
  project uses `npm`/`yarn`/`bun` instead.
- **`claude-settings/hooks/format-edited.sh`** — the script the hook above
  calls. Runs `node_modules/.bin/prettier --write` on every `.ts`/`.tsx`/
  `.js`/`.jsx`/`.mjs`/`.cjs`/`.json`/`.md`/`.yml`/`.yaml` file Claude edits
  or writes. No-ops silently if Prettier isn't installed, so it's safe to
  drop into any JS/TS project regardless of whether it uses Prettier.

## `.claudeignore` additions

`general/CLAUDE.md`'s `.claudeignore` sample only lists entries that apply
to every language (`dist/`, `build/`, `.env*`, IDE cruft, …). If the
project is JS/TS-based, append these JS-ecosystem-specific lines too:

```
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
```

## Install

1. Copy `claude-settings/settings.json` to `.claude/settings.json` and
   `claude-settings/hooks/format-edited.sh` to
   `.claude/hooks/format-edited.sh` (`chmod +x` it). If a `settings.json`
   already exists, merge `permissions.allow`/`deny` and
   `hooks.PostToolUse` by hand instead of overwriting it.
2. Append the `.claudeignore` additions above to the project's
   `.claudeignore`.

`scripts/setup-ai-standards.sh` / `.ps1` do both of these automatically
when you answer "yes" to "Is this a Node/pnpm project?" during setup.
