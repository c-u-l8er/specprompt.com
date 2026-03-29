# SpecPrompt — Agent Interface

SpecPrompt is the open standard for spec-driven AI development in the [&] Protocol ecosystem.

## MCP Tools (planned)

| Tool | Description |
|------|-------------|
| `spec_validate` | Validate a SPEC.md against the format standard |
| `spec_lint` | Check for best practices and common issues |
| `spec_generate` | Generate a SPEC.md from a natural language description |
| `spec_test_gen` | Generate test cases from acceptance criteria |
| `spec_diff` | Compare two spec versions |
| `spec_search` | Search FleetPrompt registry for similar specs |

## CLI

```bash
specprompt validate SPEC.md
specprompt lint SPEC.md
specprompt test-gen SPEC.md --output tests/
specprompt diff SPEC.md@v1.0 SPEC.md@v2.0
specprompt publish SPEC.md --registry fleetprompt
```

## Pipeline Position

```
SpecPrompt (define) → Agentelic (build) → FleetPrompt (distribute) → OpenSentience (run)
```

## Status

Spec complete. Implementation pending. See `docs/spec/README.md`.
