# SpecPrompt.com — Product Specification

> **SUPERSEDED IN PART — the data layer. Added 2026-08-15; the rest of this document stands.**
>
> This is a dated design record and has **not** been rewritten: rewriting it would fabricate a
> design review nobody performed. What it gets wrong is one layer, named here so it can be read
> around.
>
> **The shared-Supabase route was abandoned by Travis on 2026-07-30**, replaced by `studbook`
> (`studbook/docs/spec/README.md` — a spec with no implementation; do not build from it yet).
> Anything below that specifies Supabase tables, RLS policies, Supabase Auth or `amp.profiles`
> identity is describing a route that is no longer taken. `ampersand-supabase/` is **archived, not
> failed** — it still runs, and nothing migrates off it until studbook can hold the same data with
> the same guarantees.
>
> The blocker is one unruled question — where confidentiality comes from. See `CONFIDENTIALITY.md`
> and `THREAT_MODEL.md` in the repository root.
>
> **The product, API, UX and protocol design in this document are unaffected.** Read them.
>
> `REVISION_REGISTER.md` tracks what else in the tree still contradicts a decision already made.

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

# Generate test scaffolding (natural language → code skeleton)
specprompt test-gen SPEC.md --output tests/

# Compile acceptance tests into executable assertions (bridges to Agentelic DSL)
# LLM-assisted on first pass, cached by {source_hash, test_index}
# Requires human approval before use in dark factory pipeline
specprompt test-compile SPEC.md --output tests/compiled.json
specprompt test-compile SPEC.md --approve          # mark compiled tests as reviewed
specprompt test-compile SPEC.md --status            # show compilation + approval status

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
| `spec_test_compile` | Compile acceptance tests into executable Agentelic DSL assertions (LLM-assisted) |
| `spec_test_approve` | Mark compiled tests as human-reviewed and approved for dark factory use |
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

### 4.4 Formal Grammar (PEG)

The SPEC.md format is defined by a Parsing Expression Grammar. Conforming parsers MUST accept documents matching this grammar:

```peg
SpecDocument  <- Frontmatter Section+ EOF
Frontmatter   <- '---' NEWLINE YamlBlock '---' NEWLINE
YamlBlock     <- (!('---' NEWLINE) .)*

Section       <- RequiredSection / OptionalSection
RequiredSection <- PurposeSection / CapabilitiesSection / ConstraintsSection / AcceptanceSection
OptionalSection <- ArchitectureSection / DependenciesSection / ChangelogSection / CustomSection

PurposeSection       <- '## Purpose' NEWLINE FreeText
CapabilitiesSection  <- '## Capabilities' NEWLINE CapabilityLine+
ConstraintsSection   <- '## Constraints' NEWLINE ConstraintLine+
AcceptanceSection    <- '## Acceptance Tests' NEWLINE TestLine+
ArchitectureSection  <- '## Architecture' NEWLINE FreeText
DependenciesSection  <- '## Dependencies' NEWLINE DependencyLine+
ChangelogSection     <- '## Changelog' NEWLINE ChangelogEntry+
CustomSection        <- '## ' SectionName NEWLINE FreeText

CapabilityLine  <- '- ' CapabilityId ':' Scope ' (' Description ')' NEWLINE
CapabilityId    <- [a-z_]+
Scope           <- [a-z_]+
Description     <- (!NEWLINE .)+

ConstraintLine  <- '- ' ConstraintText NEWLINE
ConstraintText  <- 'Hard: ' (!NEWLINE .)+ / 'Soft: ' (!NEWLINE .)+ / (!NEWLINE .)+

TestLine        <- '- Given ' Condition ' → ' Expected NEWLINE
                 / '- When ' Condition ', then ' Expected NEWLINE
Condition       <- (!(' → ' / ', then ') .)+
Expected        <- (!NEWLINE .)+

DependencyLine  <- '- ' DependencyName ' (' DependencyDetail ')' NEWLINE
ChangelogEntry  <- '- ' Version ' (' Date '): ' ChangeDescription NEWLINE

FreeText        <- (!('## ') .)+
SectionName     <- (!NEWLINE .)+
NEWLINE         <- '\r\n' / '\n'
```

### 4.5 Required Frontmatter Fields

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `name` | string | YES | Agent name, lowercase-hyphenated |
| `version` | semver | YES | Semantic version (major.minor.patch) |
| `runtime` | string | NO | Target runtime (opensentience, any, custom) |
| `author` | string | YES | Team or person |
| `created` | ISO-8601 | YES | Creation date |
| `updated` | ISO-8601 | YES | Last modification date |
| `tags` | string[] | NO | Categorization tags |
| `dependencies` | string[] | NO | Named dependencies (MCP servers, APIs) |
| `ampersand_ref` | string | NO | Path or URL to corresponding ampersand.json declaration |
| `adl_ref` | string | NO | Path or URL to corresponding ADL agent definition (interop) |
| `governance` | object | NO | Inline governance hints (maps to ampersand.json governance) |
| `workspace_id` | binary_id | NO | Workspace scope (registry mode only — for multi-tenant Supabase storage) |
| `visibility` | enum | NO | `private` \| `workspace` \| `public` (registry mode only, default: `workspace`) |
| `source_hash` | string | NO | SHA-256 of raw SPEC.md content (auto-computed, used for compiled test caching) |

### 4.6 Parsed Spec Data Model (Ecto Schema)

```elixir
defmodule SpecPrompt.Spec do
  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}

  schema "spec.specs" do
    # Multi-tenancy (shared Supabase ecosystem)
    belongs_to :workspace, Amp.Workspaces.Workspace, type: :binary_id  # amp.workspaces
    field :user_id, :binary_id                # amp.profiles (Supabase Auth) — spec author

    # Frontmatter
    field :name, :string
    field :version, :string
    field :runtime, :string, default: "any"
    field :author, :string
    field :created, :date
    field :updated, :date
    field :tags, {:array, :string}, default: []
    field :dependency_names, {:array, :string}, default: []
    field :ampersand_ref, :string
    field :adl_ref, :string

    # Source
    field :source_path, :string               # git-relative path to SPEC.md (for filesystem mode)
    field :source_hash, :string               # SHA-256 of raw SPEC.md content
    field :repo_url, :string                  # GitHub/GitLab repo URL (for registry mode)

    # Parsed sections
    field :purpose, :string
    embeds_many :capabilities, SpecPrompt.Capability
    embeds_many :constraints, SpecPrompt.Constraint
    embeds_many :acceptance_tests, SpecPrompt.AcceptanceTest
    embeds_many :compiled_tests, SpecPrompt.CompiledTest  # machine-executable test compilation
    field :architecture, :string
    embeds_many :dependencies, SpecPrompt.Dependency
    embeds_many :changelog_entries, SpecPrompt.ChangelogEntry

    # Validation metadata
    field :parse_errors, {:array, :string}, default: []
    field :parsed_at, :utc_datetime_usec
    field :visibility, Ecto.Enum, values: [:private, :workspace, :public], default: :workspace

    timestamps()
  end
end

defmodule SpecPrompt.Capability do
  use Ecto.Schema
  embedded_schema do
    field :capability, :string    # e.g. "orders"
    field :scope, :string         # e.g. "read"
    field :description, :string   # e.g. "look up order status"
    field :maps_to, :string       # optional: &-prefixed capability key (e.g. "&memory.graph")
  end
end

defmodule SpecPrompt.Constraint do
  use Ecto.Schema
  embedded_schema do
    field :text, :string
    field :type, Ecto.Enum, values: [:hard, :soft, :unclassified]
    field :maps_to_governance, :string  # optional: maps to ampersand.json governance.hard or governance.soft
  end
end

defmodule SpecPrompt.AcceptanceTest do
  use Ecto.Schema
  embedded_schema do
    field :given, :string        # precondition (natural language)
    field :expected, :string     # expected behavior (natural language)
    field :format, Ecto.Enum, values: [:given_then, :when_then]
  end
end

@doc """
CompiledTest is the machine-executable form of an AcceptanceTest.
Generated by `specprompt test-compile` or the `spec_test_compile` MCP tool.

The compilation step bridges natural-language acceptance criteria and
Agentelic's deterministic testing DSL. Compilation is LLM-assisted on
first pass, then cached by `{source_hash, test_index}`. Human review
is required for the first compilation of each test; subsequent
recompilations of unchanged tests reuse the approved mapping.
"""
defmodule SpecPrompt.CompiledTest do
  use Ecto.Schema
  embedded_schema do
    field :test_index, :integer               # index into acceptance_tests[]
    field :setup, :map                        # precondition fixture: mocked tool states, input data
    field :input, :string                     # agent input (derived from `given`)
    field :assertions, {:array, :map}         # list of Agentelic.Test.DSL assertions:
    #   %{type: :contains, value: "tracking link"}
    #   %{type: :tool_called, tool: "get_order", args: %{id: 123}}
    #   %{type: :tool_not_called, tool: "process_refund"}
    #   %{type: :escalated, value: true}
    #   %{type: :constraint_respected, constraint_index: 3}
    field :approved, :boolean, default: false  # human-reviewed?
    field :approved_by, :string               # reviewer identity
    field :compiled_at, :utc_datetime_usec
    field :compiler_model, :string            # LLM model used for compilation (provenance)
  end
end

defmodule SpecPrompt.Dependency do
  use Ecto.Schema
  embedded_schema do
    field :name, :string
    field :type, :string         # "MCP server", "API", "spec"
    field :location, :string     # URL, local path, or "remote: host"
  end
end

defmodule SpecPrompt.ChangelogEntry do
  use Ecto.Schema
  embedded_schema do
    field :version, :string
    field :date, :date
    field :description, :string
  end
end
```

### 4.7 Validation Rules (Normative)

Parsers MUST enforce:

1. Frontmatter present and valid YAML
2. `name`, `version`, `author`, `created`, `updated` fields present
3. `version` is valid semver
4. All four required sections present: Purpose, Capabilities, Constraints, Acceptance Tests
5. At least one capability, one constraint, and one acceptance test
6. Capability lines match the `capability:scope (description)` format
7. Acceptance test lines match `Given X → Y` or `When X, then Y` format
8. If `ampersand_ref` is present, the referenced file must be valid ampersand.json

Parsers SHOULD warn on:

1. Empty sections (present but no content)
2. Acceptance tests that don't reference any declared capability
3. Constraints that use ambiguous language ("try to", "usually", "sometimes")
4. Missing changelog for versions > 1.0.0
5. Compiled tests present but `approved` is false (unapproved tests will not be used in dark factory pipeline)
6. Compiled test `test_index` does not correspond to an acceptance test in the spec
7. Compiled test `source_hash` does not match current SPEC.md `source_hash` (tests may be stale — re-approve after spec change)

### 4.8 Interoperability

#### AGENTS.md Complementary Positioning

SpecPrompt and AGENTS.md serve complementary roles:

| Concern | AGENTS.md | SpecPrompt SPEC.md |
|---------|-----------|-------------------|
| **What it tells** | How to work in this codebase (commands, conventions, boundaries) | What this agent does and how to verify it works |
| **Audience** | Coding agents (Copilot, Codex, Cursor) | Build pipelines, test frameworks, governance systems |
| **Scope** | Per-project conventions | Per-agent behavioral specification |
| **Testing** | No | Built-in acceptance criteria |
| **Governance** | Boundaries only | Constraints + escalation + capability permissions |
| **Versioning** | Implicit (git) | Explicit (semver in frontmatter) |

**Integration pattern:** A project contains AGENTS.md (how to work here) + one or more SPEC.md files (what each agent does). Agentelic reads both: AGENTS.md for build conventions, SPEC.md for agent behavior specification.

#### ADL Interoperability

SpecPrompt can export to and import from Next Moca's Agent Definition Language:

```bash
# Export SpecPrompt → ADL
specprompt export --format adl SPEC.md > agent.adl.json

# Import ADL → SpecPrompt (generates scaffold SPEC.md from ADL definition)
specprompt import --from adl agent.adl.json > SPEC.md
```

Mapping:

| SpecPrompt | ADL |
|-----------|-----|
| `name` | `agent.name` |
| `capabilities` | `tools` + `permissions` |
| `constraints.hard` | `governance.constraints` |
| `dependencies` | `dependencies` |
| `version` | `version` |

ADL covers agent *definition* (identity, tools, permissions). SpecPrompt adds *behavioral specification* (purpose, acceptance tests, architecture). Together they provide the complete agent description layer.

#### ampersand.json Mapping

SpecPrompt specs map bidirectionally to ampersand.json declarations:

```bash
# Generate ampersand.json from SPEC.md
specprompt export --format ampersand SPEC.md > agent.ampersand.json

# Validate SPEC.md against its linked ampersand.json
specprompt validate --check-ampersand SPEC.md
```

The `ampersand_ref` frontmatter field links a spec to its [&] Protocol declaration. The validator checks that:
- Every capability in SPEC.md has a corresponding `&`-prefixed binding in ampersand.json
- Every hard constraint in SPEC.md appears in ampersand.json `governance.hard`
- Every escalation condition in SPEC.md maps to ampersand.json `governance.escalate_when`

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

## 5.1 PULSE Loop Manifest

SpecPrompt is a **PULSE-conforming loop** under OS-010. As the standards layer it has the simplest loop in the portfolio: it does not host runtime cycles — its loop is the **spec lifecycle** (author → validate → test-gen → diff → publish). This makes SpecPrompt the easiest case study for PULSE adoption: a loop with no concurrency, no consensus, and no streaming.

**Loop ID:** `specprompt.spec_lifecycle`
**Loop name:** SpecPrompt Spec Lifecycle Loop
**Version:** 0.1.0
**Owner:** specprompt.com
**Workspace scope:** optional

**Phases (5 canonical kinds):**

| Phase ID | Kind | Description |
|---|---|---|
| `retrieve_spec` | `retrieve` | Load SPEC.md from filesystem or git ref; resolve linked `ampersand.json` |
| `route_action` | `route` | Choose next action: `validate`, `lint`, `test-gen`, `diff`, `publish` |
| `act_transform` | `act` | Run the chosen toolchain command; emit derived artifact (test scaffold, diff report, manifest) |
| `learn_lint` | `learn` | Update lint heuristics from author accept/reject of suggestions |
| `consolidate_versions` | `consolidate` | Archive old SPEC.md versions, run version diff against ADL/ampersand.json siblings |

**Closure:** `consolidate_versions → retrieve_spec` via git, guarantee `eventual`.

**Cadence:** `manual` (CLI/MCP invocation). Fallback `event` (git pre-commit hook, CI trigger).

**Substrates:**
- `memory`: `graphonomous://workspace/{ws_id}` (lint heuristics, test compilation cache)
- `policy`: `delegatic://workspace/{ws_id}` (spec visibility, publish permissions)
- `audit`: git history + `supabase://spec.specs` (dual: git for filesystem mode, Supabase for registry mode)
- `auth`: `supabase://auth` (Supabase Auth — shared [&] ecosystem identity. Filesystem mode remains auth-optional for local CLI use, but registry mode and dark factory pipeline require auth.)
- `transport`: `mcp` + `cli`
- `time`: optional

**Invariants enabled:** `phase_atomicity`, `feedback_immutability` (git enforces), `outcome_grounding`, `trace_id_propagation` (CLI run id).

**Cross-loop connections:**
- `spec_to_agentelic` — emits `ConsolidationEvent` (spec published) from `consolidate_versions` to `agentelic.build_pipeline.retrieve_spec`

**Why this matters:** SpecPrompt demonstrates that PULSE conformance has **zero infrastructure cost** for simple tools. A CLI that reads files, runs transforms, and writes git commits can declare a valid PULSE manifest with no runtime, no message bus, and no consensus engine. PULSE scales **down** as well as up.

### 5.2 Supabase Schema (Registry Mode)

When running in registry mode (not filesystem-only), SpecPrompt uses the shared Supabase instance. No dedicated schema range is allocated because specs are lightweight — they share the `amp.*` core schema for identity and use a single `spec` schema for storage.

```sql
-- Schema: spec.*
-- Migration range: not yet allocated (candidate: 100-109, or extend amp.*)

CREATE TABLE spec.specs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id UUID REFERENCES amp.workspaces(id),
  user_id UUID REFERENCES auth.users(id),
  name TEXT NOT NULL,
  version TEXT NOT NULL,
  source_hash TEXT NOT NULL,          -- SHA-256 of raw SPEC.md
  source_path TEXT,                   -- git-relative path (filesystem mode)
  repo_url TEXT,                      -- GitHub/GitLab URL (registry mode)
  parsed JSONB NOT NULL,              -- full parsed spec as JSON
  compiled_tests JSONB DEFAULT '[]',  -- compiled test assertions (approved)
  visibility TEXT DEFAULT 'workspace' CHECK (visibility IN ('private', 'workspace', 'public')),
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now(),
  UNIQUE(workspace_id, name, version)
);

ALTER TABLE spec.specs ENABLE ROW LEVEL SECURITY;
-- RLS: workspace-based multi-tenancy (same pattern as all [&] products)
```

**Dual-mode operation:** SpecPrompt supports two modes:
- **Filesystem mode** (default): Specs live as `.md` files in git. CLI tools operate on local files. No auth required. This is the zero-cost mode described above.
- **Registry mode**: Specs are stored in Supabase for discovery, sharing, and dark factory pipeline integration. Requires Supabase Auth. Workspace-scoped. This is required for multi-tenant dark factory operation.

Filesystem-mode specs can be promoted to registry-mode via `specprompt publish --registry supabase`.

### 5.3 Dark Factory Pipeline Trigger Protocol

SpecPrompt is the entry point of the dark factory pipeline. When a spec changes, the pipeline must trigger automatically. This section defines the trigger protocol shared across all [&] pipeline stages.

**Event format:** CloudEvents v1 envelope (consistent with PULSE cross-loop signals)

```json
{
  "specversion": "1.0",
  "type": "org.pulse.consolidation_event",
  "source": "specprompt.spec_lifecycle/consolidate_versions",
  "subject": "spec/{workspace_id}/{spec_name}/{version}",
  "data": {
    "workspace_id": "uuid",
    "spec_name": "customer-support",
    "version": "2.1.0",
    "source_hash": "sha256:...",
    "compiled_tests_hash": "sha256:...",
    "trigger": "git_push | manual | ci_webhook"
  }
}
```

**Trigger chain (dark factory conveyor belt):**

```
1. Spec change detected (git push, manual CLI, or CI webhook)
   → SpecPrompt emits ConsolidationEvent to Agentelic

2. Agentelic receives ConsolidationEvent
   → retrieve_spec phase pulls updated spec
   → 4-stage pipeline runs (parse → generate → compile → test)
   → On test pass: emits ConsolidationEvent to FleetPrompt

3. FleetPrompt receives ConsolidationEvent
   → retrieve_artifact phase pulls tested artifact
   → Validation + trust scoring
   → Publish to registry
   → On publish: emits ConsolidationEvent to deploy target

4. Deploy target (OpenSentience/WebHost) receives ConsolidationEvent
   → Staged deployment (staging → canary → production)
   → On deploy: emits OutcomeSignal back to Agentelic + PRISM

5. PRISM observes OutcomeSignal
   → Benchmarks the deployed agent
   → Emits ReputationUpdate to FleetPrompt
```

**Transport options (ordered by complexity):**
1. **Supabase Realtime** (recommended for MVP): Listen on `spec.specs` inserts/updates. Zero infrastructure. All [&] products already share the Supabase instance.
2. **GitHub webhooks**: Push events on spec repos trigger Agentelic builds. Requires webhook endpoint.
3. **PULSE event bus** (future): Full CloudEvents HTTP endpoint. Required for cross-organization dark factories.

**GitHub Actions integration:**

```yaml
# .github/workflows/dark-factory.yml
name: Dark Factory Pipeline
on:
  push:
    paths: ['**/SPEC.md', '**/*.ampersand.json']

jobs:
  pipeline:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Validate spec
        run: specprompt validate SPEC.md
      - name: Compile tests
        run: specprompt test-compile SPEC.md --require-approved
      - name: Trigger Agentelic build
        run: |
          curl -X POST $AGENTELIC_WEBHOOK_URL \
            -H "Authorization: Bearer $AGENTELIC_API_KEY" \
            -d '{"spec_path": "SPEC.md", "source_hash": "'$(sha256sum SPEC.md | cut -d' ' -f1)'"}'
```

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
| 1: Toolchain | Q2 2026 | CLI (validate, lint, test-gen, test-compile, test-approve), MCP server, Supabase schema + RLS |
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
