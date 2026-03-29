# SpecPrompt Documentation

> **Prompts are transient. Specs persist.**

Welcome to the documentation hub for **SpecPrompt** — an open standard and
toolchain for spec-driven AI development. SpecPrompt defines a Markdown-based
specification format (SPEC.md) that is both human-readable and machine-parseable,
serving as the source of truth for agent behavior.

SpecPrompt is the **standards layer** of the [&] Protocol ecosystem — the format
that bridges agent definition with execution, testing, and deployment.

---

## Why SpecPrompt?

Spec-Driven Development (SDD) has emerged as the industry consensus for AI-assisted
development in 2026. GitHub Spec Kit, AWS Kiro, Cursor rules, and Next Moca ADL all
use different specification formats. Teams switching tools lose context.

SpecPrompt defines the interoperable standard — a Markdown-native format that is:

1. **Markdown-native** — `.md` files, no proprietary format
2. **Human-first** — readable by any team member, parseable by any agent
3. **Versioned** — lives in git. Branching, diffing, merging.
4. **Testable** — acceptance criteria are machine-executable
5. **Composable** — specs reference other specs
6. **Tool-agnostic** — works with any SDD-compatible tool

---

## Documentation Map


```{toctree}
:maxdepth: 1
:caption: Homepages

[&] Ampersand Box <https://ampersandboxdesign.com>
Graphonomous <https://graphonomous.com>
BendScript <https://bendscript.com>
WebHost.Systems <https://webhost.systems>
Agentelic <https://agentelic.com>
AgenTroMatic <https://agentromatic.com>
Delegatic <https://delegatic.com>
Deliberatic <https://deliberatic.com>
FleetPrompt <https://fleetprompt.com>
GeoFleetic <https://geofleetic.com>
OpenSentience <https://opensentience.org>
SpecPrompt <https://specprompt.com>
TickTickClock <https://ticktickclock.com>
```

```{toctree}
:maxdepth: 1
:caption: Root Docs

[&] Protocol Docs <https://docs.ampersandboxdesign.com>
Graphonomous Docs <https://docs.graphonomous.com>
BendScript Docs <https://docs.bendscript.com>
WebHost.Systems Docs <https://docs.webhost.systems>
Agentelic Docs <https://docs.agentelic.com>
AgenTroMatic Docs <https://docs.agentromatic.com>
Delegatic Docs <https://docs.delegatic.com>
Deliberatic Docs <https://docs.deliberatic.com>
FleetPrompt Docs <https://docs.fleetprompt.com>
GeoFleetic Docs <https://docs.geofleetic.com>
OpenSentience Docs <https://docs.opensentience.org>
SpecPrompt Docs <https://docs.specprompt.com>
TickTickClock Docs <https://docs.ticktickclock.com>
```

```{toctree}
:maxdepth: 2
:caption: SpecPrompt Docs

spec/README
```

---

## The SPEC.md Format

Every spec follows a structured Markdown format with YAML frontmatter:

```markdown
---
name: agent-name
version: 1.0.0
runtime: opensentience | any
author: team-or-person
created: 2026-01-15
updated: 2026-02-22
tags: [category, domain]
dependencies:
  - graphonomous
---

## Purpose
What this agent does and why.

## Capabilities
- capability:scope (description)

## Constraints
- Hard and soft behavioral boundaries

## Acceptance Tests
- Given [precondition] -> [expected behavior]
```

**Required sections:** Purpose, Capabilities, Constraints, Acceptance Tests.

---

## Toolchain

### CLI

```bash
specprompt validate SPEC.md      # Validate against format standard
specprompt lint SPEC.md          # Check for best practices
specprompt test-gen SPEC.md      # Generate test scaffolding
specprompt diff SPEC.md@v1 SPEC.md@v2  # Diff two versions
specprompt publish SPEC.md       # Publish to FleetPrompt registry
```

### MCP Tools

| Tool | Description |
|------|------------|
| `spec_validate` | Validate against format standard |
| `spec_lint` | Check for best practices |
| `spec_generate` | Generate from natural language |
| `spec_test_gen` | Generate test cases from acceptance criteria |
| `spec_diff` | Compare two spec versions |
| `spec_search` | Search FleetPrompt registry |

### Reference Parsers

Available in **Elixir** and **TypeScript**. Formal PEG grammar included in the
specification for building conformant parsers.

---

## Ecosystem Integration

| Product | How It Uses SpecPrompt |
|---------|----------------------|
| **Agentelic** | Specs are the primary input to the build pipeline |
| **OpenSentience** | Agent manifests reference SPEC.md for permission derivation |
| **Graphonomous** | Learning happens within spec-defined boundaries |
| **FleetPrompt** | Specs are published as discoverable templates |
| **Delegatic** | Multi-agent orchestration specs define agent roles |

---

## Interoperability

- **AGENTS.md** — complementary (codebase conventions vs. agent behavior specs)
- **Next Moca ADL** — bidirectional import/export
- **ampersand.json** — bidirectional mapping (capabilities, constraints, governance)

---

## Project Links

- **Spec:** [Product Specification](spec/README.md)
- **[&] Protocol ecosystem:** `AmpersandBoxDesign/`

---

*[&] Ampersand Box Design — specprompt.com*
