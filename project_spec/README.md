# SpecPrompt.com — Product Specification

**Date:** February 22, 2026
**Status:** v1.1
**Author:** [&] Ampersand Box Design
**License:** MIT (open standard)

---

## Executive Summary

SpecPrompt is an **open standard and toolchain for spec-driven AI development**. It defines a Markdown-based specification format (SPEC.md) that is both human-readable and machine-parseable, serving as the source of truth for agent behavior. Prompts are transient — specs persist.

SpecPrompt is the **standards layer** of the [&] Ampersand Box portfolio:

```
SpecPrompt (Standards)    → defines agent behavior as versioned specs  ← THIS
    ↓
Agentelic (Engineering)   → builds, tests, deploys agents against specs
    ↓
OpenSentience (Runtime)   → governs, executes, observes agents locally
    ↓
Graphonomous (Memory)     → continual learning knowledge graphs
    ↓
FleetPrompt (Distribution) · Delegatic (Orchestration)
```

---

## 1. The Problem

Spec-Driven Development (SDD) has emerged as the industry consensus for AI-assisted development in 2026:

- **Thoughtworks Technology Radar** (Dec 2025): "Spec-driven development remains an emerging practice... we're likely to see even more change in 2026."
- **InfoQ** (Feb 2026): "Specifications become the shared interface where product, architecture, engineering, and quality collaborate."
- **The New Stack** (Feb 2026): "Vibe coding got us here. Spec-driven development is what comes next."
- **AWS Kiro**: Amazon's new AI IDE centers entirely on spec-driven development.
- **GitHub Spec Kit**: Open-source toolkit for generating specs that guide coding agents.
- **Next Moca ADL** (Feb 2026): Agent Definition Language released as a vendor-neutral spec for *defining* agents (InfoQ). Uses JSON Schema. Focused on identity, permissions, tools, and governance metadata — comparable to OpenAPI for REST. However, ADL is definition-only; it doesn't address execution, testing, or deployment pipelines.

The convergence is clear: the industry needs a standard. GitHub Spec Kit uses one format, Kiro uses another, Cursor rules a third, ADL a fourth. Teams switching tools lose context. SpecPrompt defines the interoperable standard that bridges definition (like ADL) with execution (like Agentelic) — a Markdown-native format that is both human-readable and machine-parseable.

---

## 2. Design Principles

1. **Markdown-native** — Specs are .md files. No proprietary format.
2. **Human-first** — Readable by any team member, parseable by any agent.
3. **Versioned** — Lives in git alongside code. Branching, diffing, merging.
4. **Testable** — Acceptance criteria are machine-executable.
5. **Composable** — Specs can reference other specs (dependencies).
6. **Tool-agnostic** — Works with any SDD-compatible tool, not just Agentelic.

---

## 3. The SPEC.md Format

### 3.1 Structure

```markdown
---
# YAML frontmatter (machine-parsed)
name: agent-name
version: semver
runtime: opensentience | any
author: team-or-person
created: ISO-8601
updated: ISO-8601
tags: [category, domain]
dependencies:
  - graphonomous
  - inventory-api
---

## Purpose
<Free-form description of what this agent does and why>

## Capabilities
<List of MCP tools/resources the agent requires>
- permission:scope (description)
- permission:scope (description)

## Constraints
<Behavioral boundaries the agent must never violate>
- Hard constraints (e.g., "never process orders > $10K")
- Soft constraints (e.g., "prefer concise responses")

## Acceptance Tests
<Testable scenarios in Given/When/Then or equivalent>
- Given [precondition] → [expected behavior]
- Given [edge case] → [expected handling]

## Architecture
<Optional: system design notes for the implementing agent>

## Dependencies
<MCP servers, APIs, or other specs this agent requires>

## Changelog
<Version history with semantic versioning>
```

### 3.2 Parsing Rules

1. **Frontmatter** is required. YAML between `---` delimiters.
2. **Sections** are identified by `## Heading` (H2 level).
3. **Required sections**: Purpose, Capabilities, Constraints, Acceptance Tests.
4. **Optional sections**: Architecture, Dependencies, Changelog, Notes.
5. **Capabilities** format: `- capability:scope (description)`
6. **Acceptance Tests** format: `- Given [X] → [Y]` or `- When [X], then [Y]`
7. **Constraints** are free-text but parseable by LLMs for enforcement.

### 3.3 Example: Complete Spec

```markdown
---
name: customer-support-v2
version: 2.1.0
runtime: opensentience
author: ops-team
created: 2026-02-15
updated: 2026-02-22
tags: [support, customer-facing, e-commerce]
dependencies:
  - graphonomous
  - orders-api
  - notifications-service
---

## Purpose

Handle customer inquiries about order status, process refunds
within policy limits, and escalate complex issues to human agents.
Maintains conversational context via Graphonomous for returning
customers.

## Capabilities

- orders:read (look up order status, tracking, history)
- refunds:create (process refunds up to $500)
- notifications:send (email confirmations to customers)
- graphonomous:retrieve_context (recall customer history)
- graphonomous:learn_from_interaction (record new knowledge)

## Constraints

- Never disclose internal pricing, margins, or supplier information
- Never process refunds exceeding $500 without human approval
- Never share one customer's data with another customer
- Always confirm refund amount before processing
- Rate limit: max 50 interactions per hour per customer
- Response time: < 5 seconds for status queries

## Acceptance Tests

- Given valid order #123 → return current status and tracking link
- Given order not found → respond with helpful alternatives
- Given refund request for $200 → process and confirm via email
- Given refund request for $750 → escalate to human with context
- Given repeat customer → greet by name using Graphonomous context
- Given abusive language → maintain professional tone, offer escalation
- Given system outage → inform customer, provide ticket number
- Given request for internal pricing → decline politely

## Architecture

Uses Graphonomous for long-term customer memory. Each interaction
is recorded via learn_from_interaction. Customer history is
retrieved at conversation start via retrieve_context.

Refund workflow: validate order → confirm amount with customer →
check $500 limit → process via refunds:create → notify via email.

## Dependencies

- graphonomous (MCP server, local)
- orders-api (MCP server, remote: orders.internal.company.com)
- notifications-service (MCP server, remote: notify.internal.company.com)

## Changelog

- 2.1.0 (2026-02-22): Added Graphonomous integration for customer memory
- 2.0.0 (2026-02-01): Rewrote from prompt-based to spec-driven
- 1.0.0 (2026-01-15): Initial release (vibe-coded, deprecated)
```

---

## 4. Toolchain

### 4.1 CLI

```bash
# Validate a spec
specprompt validate SPEC.md

# Lint for best practices
specprompt lint SPEC.md

# Generate test scaffolding
specprompt test-gen SPEC.md --output tests/

# Diff two spec versions
specprompt diff SPEC.md@v1.0 SPEC.md@v2.0

# Publish to FleetPrompt registry
specprompt publish SPEC.md --registry fleetprompt
```

### 4.2 MCP Server

SpecPrompt exposes itself as an MCP server for AI-assisted spec authoring:

| Tool | Description |
|------|------------|
| `spec_validate` | Validate a SPEC.md against the format standard |
| `spec_lint` | Check for best practices and common issues |
| `spec_generate` | Generate a SPEC.md from a natural language description |
| `spec_test_gen` | Generate test cases from acceptance criteria |
| `spec_diff` | Compare two spec versions |
| `spec_search` | Search FleetPrompt registry for similar specs |

### 4.3 Reference Parser

Available in Elixir and TypeScript:

```elixir
defmodule SpecPrompt.Parser do
  @type spec :: %{
    frontmatter: map(),
    purpose: String.t(),
    capabilities: [%{capability: String.t(), scope: String.t(), description: String.t()}],
    constraints: [String.t()],
    acceptance_tests: [%{given: String.t(), expected: String.t()}],
    architecture: String.t() | nil,
    dependencies: [String.t()],
    changelog: [%{version: String.t(), date: String.t(), description: String.t()}]
  }

  @spec parse(String.t()) :: {:ok, spec()} | {:error, [String.t()]}
  def parse(markdown) do
    # 1. Extract YAML frontmatter
    # 2. Parse H2 sections
    # 3. Extract structured data from each section
    # 4. Validate required sections present
    # 5. Return structured spec or validation errors
  end
end
```

---

## 5. Ecosystem Integration

| Product | How It Uses SpecPrompt |
|---------|----------------------|
| **Agentelic** | Specs are the primary input to the build pipeline |
| **OpenSentience** | Agent manifests reference SPEC.md for permission derivation |
| **Graphonomous** | Learning happens within spec-defined boundaries |
| **FleetPrompt** | Specs are published as discoverable templates |
| **Delegatic** | Multi-agent orchestration specs define agent roles and handoffs |

---

## 6. Gap Analysis & Competitive Landscape

### 6.1 Market Gap: No Standard Agent Spec Format

GitHub Spec Kit, AWS Kiro, and various community efforts all use different specification formats. **Next Moca's Agent Definition Language (ADL)** was released in Feb 2026 under Apache 2.0 — validating the thesis that a standard definition layer is needed (InfoQ, Feb 2026). ADL focuses on declarative agent definitions but doesn't address execution or testing. SpecPrompt fills the complete gap — from definition to testing to deployment. The opportunity mirrors how OpenAPI standardized REST API descriptions.

### 6.2 SDD Tools

| Tool | Focus | Gap SpecPrompt Fills |
|------|-------|---------------------|
| **Next Moca ADL** (Feb 2026) | Declarative agent definitions | Definition-only, no execution/testing/deployment pipeline |
| GitHub Spec Kit | Spec generation | Proprietary format, no registry |
| AWS Kiro | AI IDE | Amazon-specific, not interoperable |
| Cursor rules | IDE context | No formal spec format |
| AGENTS.md | Convention | No toolchain, no testing |

### 6.3 Industry Validation

1. **InfoQ on SDD** (Feb 19, 2026): "Specifications become the shared interface where product, architecture, engineering, and quality collaborate."
2. **The New Stack** (Feb 18, 2026): "Vibe coding got us here. Spec-driven development is what comes next."
3. **Thoughtworks Technology Radar** (Dec 2025): SDD as emerging practice with "even more change in 2026."
4. **Next Moca ADL** (Feb 2026): Agent Definition Language released under Apache 2.0 — validates the need for a standard, but ADL is definition-only.
5. **AWS Kiro**: Amazon's AI IDE centers on spec-driven development — major vendor validation.
6. **GitHub Spec Kit**: Open-source toolkit for spec generation — community validation.

---

## 7. Revenue Model

| Stream | Price | Target |
|--------|-------|--------|
| Open Standard + CLI | Free (MIT) | Community adoption, ecosystem growth |
| Hosted Registry | $19/mo | Teams publishing/discovering specs |
| Enterprise Features | $99/mo/team | Private registries, compliance templates, SSO |
| Agentelic Bundle | Included | Integrated spec editing and testing |

---

## 8. Implementation Roadmap

| Phase | Timeline | Deliverables |
|-------|----------|-------------|
| 0: Format | Q1 2026 | SPEC.md format v1.0, reference parser (Elixir + TypeScript) |
| 1: Toolchain | Q2 2026 | CLI (validate, lint, test-gen), MCP server |
| 2: Integration | Q3 2026 | Agentelic build pipeline integration, OpenSentience manifest integration |
| 3: Registry | Q4 2026 | FleetPrompt spec registry, publishing, discovery, forking |
| 4: Evolution | Q1 2027 | Graphonomous feedback loop, spec auto-refinement suggestions |

---

## 9. Success Criteria

| Metric | MVP (6 months) | PMF (18 months) |
|--------|----------------|-----------------|
| Specs published | 100+ | 2,000+ |
| Parser downloads | 500+ | 5,000+ |
| Tool integrations | 3+ (Agentelic, Cursor, Claude) | 10+ |
| Community contributors | 20+ | 100+ |
| Industry mentions | 3+ | 10+ |

---

*[&] Ampersand Box Design — specprompt.com*
