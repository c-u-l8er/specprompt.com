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

- CLI: validate, lint, test-gen, diff, publish
- MCP server: spec_validate, spec_lint, spec_generate, spec_test_gen, spec_diff, spec_search
- Reference parsers in Elixir and TypeScript
- Formal PEG grammar for conformant parser development

## Interoperability

- Bidirectional with Next Moca ADL
- Bidirectional with ampersand.json
- Complementary to AGENTS.md

## Status

This is a spec + marketing site. No implementation code yet. Implementation will be Elixir/OTP + TypeScript.
