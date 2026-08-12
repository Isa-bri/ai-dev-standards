---
applyTo: "apps/web/**,apps/admin/**,packages/ui/**,web/**,*.config.{js,ts,mjs}"
---

# pnpm / Tailwind web platform rules

These rules apply automatically when a web file is open. They are non-obvious
facts that fail silently — no error, just no effect.

## pnpm workspace configuration

pnpm workspace configuration belongs in `pnpm-workspace.yaml`, not in the
`pnpm` field of `package.json`. From pnpm 10.33 onward the `package.json`
field is silently ignored. This includes `overrides` for security patches:
if they live in `package.json`, a security gate reports green without the
patches being applied.

## Tailwind v3 — `.dark` class purged

Tailwind v3 purges the `.dark` class from a preset if no scanned file writes
it as a literal class string. `safelist: ['dark']` in `tailwind.config.js`
is required before a JS-toggled dark mode can work. Verify with a
rendered-color assertion, not by checking that the class name exists.

## Tailwind v3 — custom typography tokens in `tailwind-merge`

`tailwind-merge` (used internally by `tailwind-variants`) can't classify a
custom `text-*` token as size or color — it defaults to color. When a size
token and a color token are merged, one is silently discarded. Register custom
typography scale tokens in the `twMerge` config (or the `createTV` equivalent).
Verify by measuring the rendered `font-size`, not by reading the CSS output.
