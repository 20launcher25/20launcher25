---
name: ui-ux-pro-max
description: "Searchable design database for web and mobile UI: 161 color palettes by product type, 57 font pairings, 67 UI styles with CSS/AI-prompt keywords, 161 product-type patterns, landing page structures, chart selection rules, icon sets, and per-stack implementation guidelines for 16 stacks (React, Next.js, Vue, Nuxt, Svelte, Astro, Angular, Laravel, SwiftUI, React Native, Flutter, Jetpack Compose, Tailwind, shadcn/ui, Three.js). Use when picking a concrete palette, font pairing, visual style, or landing structure for a product type, or when you need stack-specific UI guidance. Also generates a persistable design system (MASTER.md + per-page overrides). Not needed for generic accessibility, contrast, spacing, or touch-target rules."
---

# UI/UX Pro Max — Design Database

CSV database + BM25 search. Returns **concrete values** (hex codes, font names, section
orders, library picks) chosen by product type — the part that is not worth guessing.

Generic UI craft — WCAG contrast, 44pt touch targets, animation timing, form validation,
navigation patterns — is not in here on purpose. Apply that from your own knowledge and use
this skill for the data lookups below.

## Command

```bash
python ~/.claude/skills/ui-ux-pro-max/scripts/search.py "<query>" --domain <domain> [-n 3]
```

Scripts and data live next to this file, in `scripts/` and `data/`. Needs Python 3.10+, no extra packages
(on Windows the command may be `python` or `py`).

## Domains

| `--domain` | Returns |
|---|---|
| `color` | Full palette by product type: primary/secondary/accent, on-* pairs, background, card, muted, border, destructive, ring |
| `typography` | Font pairings with Google Fonts imports |
| `google-fonts` | Individual font lookup (weights, variable, language coverage) |
| `style` | Visual styles: colors, effects, light/dark support, perf, complexity, CSS keywords, AI-prompt keywords, implementation checklist |
| `product` | Product type → recommended style, landing pattern, dashboard style, palette focus |
| `landing` | Section order, CTA placement, color strategy, conversion notes |
| `chart` | Chart type per data type, thresholds, library recommendation, a11y fallback |
| `ux` | Issue → Do/Don't with good/bad code examples and severity |
| `icons` | Icon sets and usage |
| `react` | React/Next.js performance patterns (rerender, memo, suspense, bundle) |
| `web` | Native/app interface guidelines (safe areas, Dynamic Type, accessibility labels) |

Omit `--domain` to auto-detect. `-n` sets result count (default 3). `--json` for raw output.

## Stacks

```bash
python ".../search.py" "<query>" --stack <stack>
```

`react` `nextjs` `vue` `nuxtjs` `nuxt-ui` `svelte` `astro` `angular` `laravel`
`html-tailwind` `shadcn` `threejs` `swiftui` `react-native` `flutter` `jetpack-compose`

## Design system generation

One call that searches product + style + color + typography + landing in parallel and
resolves them against reasoning rules into a single coherent system with anti-patterns:

```bash
python ".../search.py" "<product> <industry> <tone>" --design-system -p "Project Name" [-f markdown]
```

Query quality drives everything here — BM25 over keyword columns. Combine product +
industry + tone + density (`"beauty spa wellness calm premium"`), not just `"website"`.
If the result feels off, re-run with different adjectives rather than overriding by hand.

### Persisting it

```bash
python ".../search.py" "<query>" --design-system --persist -p "Project Name" [--page "dashboard"] [-o <dir>]
```

Writes into the **current working directory** unless `-o` is given:

```
design-system/<project-slug>/MASTER.md          global source of truth
design-system/<project-slug>/pages/<page>.md    per-page overrides
```

`<project-slug>` is the lowercased `-p` value with spaces as dashes; without `-p` it is
`default`. Retrieval rule: when building a page, read the page override if it exists —
it wins over MASTER.md — otherwise use MASTER.md alone.

Run this from the target project's root, or pass `-o`; otherwise the folder lands wherever
the shell happens to be.

## When to reach for it

Use it when the answer is a **specific value you would otherwise invent**: which palette
suits a fintech dashboard, which fonts pair for a luxury brand, what sections a SaaS
landing needs and in what order, which chart fits this data shape, what a given style
demands in CSS.

Skip it for backend, infra, or pure code-quality work, and for UI questions you can already
answer without a lookup.

## Workflow

1. `--design-system` first for anything new — one call gives a coherent starting set.
2. `--domain` to deepen whichever dimension is still uncertain.
3. `--stack` for implementation specifics in the project's actual stack.
4. Apply your own UI/UX judgement on top: the database supplies values, not craft.

Domain to reach for by concern: accessibility and interaction → `ux`; style and product
fit → `style`, `product`; layout and responsive → `ux`; typography and color → `typography`,
`color`; charts → `chart`.
