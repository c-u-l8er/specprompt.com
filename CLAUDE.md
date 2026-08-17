# SpecPrompt — Open Standard for Spec-Driven AI Development

Open standard and toolchain for spec-driven AI development. Defines a Markdown-based specification format (SPEC.md) that is human-readable and machine-parseable.


## The landing page is GENERATED. Do not hand-edit `index.html`.

`/index.html`, `/derive.js` and `/form.js` are emitted by `build-site.mjs` from
`records/surface.json`, `src/landing.html`, `src/shell.css`, `src/derive.js` and
`src/form.js`. **An edit to the served HTML is silently reverted by the next
build.** Change the record or the template.

```
./site.sh     # run the suite(s), emit the site, run the publication gate
```

`build-site.mjs` does not quote a test count — it **executes** the suite, parses
what the runner prints, and refuses to emit anything if a number has moved off
`records/tests.json`. That is how the count on this page stopped being a thing
anyone could type.

`launch-gate.mjs` reads the emitted artifact and refuses to publish when it and
the records disagree: a retracted claim reinstated, a rung invented, a CTA the
rung has not earned, an unrendered token, a `mailto:` or an email address, a
text token below 4.5:1, a same-origin link that resolves to nothing, an
artifact that is not what this build emitted, an identifying-animation constant
leaking into the copy, or a button whose colour is decided by a non-button
rule. **It prints its own total** &mdash; 115 on 2026-08-17, and that figure is
the only one in this repository that is not derived, which is why it carries a
date. **Do not hand-type a check count anywhere:** it went from 92 to 115 in a
single session, and a typed count is exactly how a printed number and a
published one drift apart.

Built against **`shell-r9`**, recorded as `shell_revision` in
`records/surface.json`. The whole shell is documented in
`ProjectAmp2/agents/SHELL.md`.

**The band says "a specification in the ComputeDriven world", not "the specification
layer of ComputeDriven", and that is deliberate.** `ampersand-nav` records this
domain as `place: 3`, whose `renderPlacement()` gives the layer sentence to
`place: 2` only. The old eyebrow claimed the layer and is now blocklisted.

**Contact is the Formspree endpoint ruled by Travis (SHELL.md r9)**, as a real
`<form>` that posts with scripting off; `src/form.js` only upgrades it to an
inline reply and prints success solely on a 2xx. No `mailto:` anywhere.

## Source-of-truth spec

- `docs/spec/README.md` — SpecPrompt product specification

## Role in [&] Ecosystem

SpecPrompt is the **standards layer**:

```
SpecPrompt (Standards) → Agentelic (Engineering) → OpenSentience (Runtime) → Graphonomous (Memory)
```

SpecPrompt defines the interoperable format that bridges agent definition with execution, testing, and deployment.

## The SPEC.md format

Markdown files with YAML frontmatter. Required sections: Purpose, Capabilities, Constraints, Acceptance Tests. Human-readable, machine-parseable, git-versioned.

## Toolchain

- CLI: validate, lint, test-gen, test-compile (--output/--approve/--status), diff, publish
- MCP server: 8 tools (spec_validate, spec_lint, spec_generate, spec_test_gen, spec_test_compile, spec_test_approve, spec_diff, spec_search)
- Reference parser in Elixir (TypeScript parser planned)
- Formal PEG grammar for conformant parser development

## Interoperability

- Bidirectional with Next Moca ADL (`lib/specprompt/interop/adl.ex`)
- Bidirectional with ampersand.json (`lib/specprompt/interop/ampersand.ex`)
- Complementary to AGENTS.md

## Build commands

```
# Elixir
mix deps.get
mix compile --warnings-as-errors
mix test
mix format --check-formatted
mix escript.build    # produces ./specprompt CLI

# TypeScript parser
cd npm && npm install && npm test
```

## Status

All 6 BUILD.md phases implemented. 93 tests (71 Elixir + 22 TypeScript), 0 failures.

- Phase 1: Parser + Validator + Linter + Differ + CLI (validate, lint, diff)
- Phase 2: Test Compiler (compile prompts, approve, status) + Test Generator
- Phase 3: MCP Server (all 8 tools) + Publisher (CloudEvents)
- Phase 4: Supabase migration (`ampersand-supabase/migrations/100_spec_schema.sql`, `101_spec_rls.sql`)
- Phase 5: Registry CRUD (`lib/specprompt/registry.ex` — Supabase client via :httpc)
- Phase 6: TypeScript parser (`npm/` — @specprompt/parser, identical output to Elixir parser)
- Interop: ampersand.json + ADL bidirectional mapping
- Deploy: Dockerfile + fly.toml
