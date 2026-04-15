# SpecPrompt — Open Standard for Spec-Driven AI Development

Open standard and toolchain for spec-driven AI development. Defines a Markdown-based specification format (SPEC.md) that is human-readable and machine-parseable.

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
