# pnpm / Tailwind (web) — platform traps

These are non-obvious facts about pnpm workspaces and Tailwind CSS that have
burned real projects. Copy this into a project's `docs/` and link it from
`CLAUDE.md` under "Traps this project has already learned about."

Each item compiled, passed lint, and only failed silently in a specific
configuration or version. None of them produce clear errors when they
bite.

---

## pnpm workspace configuration

**pnpm workspace configuration belongs in `pnpm-workspace.yaml`, not in the
`pnpm` field of `package.json`.** From pnpm 10.33 onward the `package.json`
field is silently ignored — no error, just no effect. This matters especially
for `overrides` (used to pin transitive dependencies for security patches):
if they live in `package.json`, a security gate that checks them will report
green without the patches actually being applied.

## Tailwind v3 — `.dark` class purged by content scanning

**Tailwind v3 purges the `.dark` class from a preset if no scanned file
writes it as a literal class string.** A preset that adds `.dark` rules via
`addBase` generates valid CSS at build time; the Tailwind content scan then
removes it because it found no usage. The result is that a JS-toggled dark
mode (`classList.add('dark')`) has no CSS rules to apply — the class is added
to the DOM but nothing changes.

The fix is `safelist: ['dark']` in `tailwind.config.js`. The symptom is
invisible at build time (the class appears in source) and only shows up when
measuring the rendered color. Add a rendered-color assertion to your dark-mode
tests rather than trusting that the class name exists.

## Tailwind v3 — custom typography scale in `twMerge` / `tailwind-variants`

**`tailwind-merge` (used internally by `tailwind-variants`) can't tell whether
a custom `text-*` class is a size or a color — it defaults to treating unknown
`text-*` classes as color.** When two `text-*` classes are merged, the library
resolves the "color wins" conflict and discards one. A custom scale like
`text-headline-medium` can silently lose to a color class like `text-on-surface`,
or vice versa. The rendered element ends up with the browser default font size
instead of the one the token implies.

The fix is to register your custom typography scale in the `twMerge` config
(or the `createTV` equivalent) so the library knows which class group each
token belongs to. This is only detectable by measuring the rendered
`font-size` — the class exists in the CSS output, correctly.
