# SpecPrompt — Implementation Build Prompt
**Version:** 1.0 | **Date:** April 2026 | **Type:** Full Implementation (CLI + MCP + Supabase)

---

## Your Mission

You are building **SpecPrompt** — the standards layer of the [&] Protocol dark factory pipeline. SpecPrompt defines the SPEC.md format (machine-parseable agent specifications) and provides the CLI toolchain, MCP server, and Supabase registry that make specs the entry point for autonomous code generation.

**Read `docs/spec/README.md` fully before writing a single line.** It is the authoritative spec.

SpecPrompt is the **first stage** of the dark factory pipeline:
```
SpecPrompt (spec in) → Agentelic (build) → OS-008 (enforce) → FleetPrompt (distribute) → RuneFort (observe)
```

---

## Target Stack

```
Language:   Elixir 1.17+ / OTP 27
CLI:        Mix escript (specprompt validate, lint, test-gen, test-compile, diff, publish)
MCP:        JSON-RPC over HTTP (spec_validate, spec_lint, spec_generate, spec_test_gen,
            spec_test_compile, spec_test_approve, spec_diff, spec_search)
Database:   PostgreSQL via shared Supabase (spec.* schema, migration range TBD)
Auth:       Supabase Auth (shared [&] ecosystem — amp.profiles, amp.workspaces)
Parser:     PEG grammar (see spec section 4.4) — implement in both Elixir and TypeScript
Testing:    ExUnit (Elixir), Vitest (TypeScript parser)
Deploy:     Fly.io (MCP server) + npm (TypeScript parser)
```

---

## Dual-Mode Architecture

SpecPrompt operates in two modes. Both must work from day one:

### Filesystem Mode (default, zero-cost)
- CLI reads `.md` files from local git repos
- No auth, no database, no network
- All tools work offline: validate, lint, test-gen, test-compile, diff
- Audit via git history
- This is the "PULSE scales down" demonstration

### Registry Mode (multi-tenant dark factory)
- Specs stored in Supabase `spec.specs` table
- Workspace-scoped via `amp.workspaces`
- Auth via Supabase Auth (same identity as all [&] products)
- Visibility: private | workspace | public
- Pipeline triggers via Supabase Realtime or CloudEvents webhooks
- Required for dark factory automation

---

## Repository Structure

Create this structure inside `specprompt.com/`:

```
specprompt.com/
├── lib/
│   ├── specprompt/
│   │   ├── parser.ex              # PEG-based SPEC.md parser (section 4.3-4.4)
│   │   ├── spec.ex                # SpecPrompt.Spec Ecto schema (section 4.6)
│   │   ├── capability.ex          # SpecPrompt.Capability embedded schema
│   │   ├── constraint.ex          # SpecPrompt.Constraint embedded schema
│   │   ├── acceptance_test.ex     # SpecPrompt.AcceptanceTest embedded schema
│   │   ├── compiled_test.ex       # SpecPrompt.CompiledTest embedded schema (NEW)
│   │   ├── dependency.ex          # SpecPrompt.Dependency embedded schema
│   │   ├── changelog_entry.ex     # SpecPrompt.ChangelogEntry embedded schema
│   │   ├── validator.ex           # Validation rules (section 4.7 — all MUST + SHOULD rules)
│   │   ├── linter.ex              # Best-practice linting
│   │   ├── differ.ex              # Spec version diffing
│   │   ├── test_generator.ex      # Generate test scaffolding from acceptance tests
│   │   ├── test_compiler.ex       # Compile natural language tests → Agentelic DSL assertions (NEW)
│   │   ├── publisher.ex           # Publish to FleetPrompt registry or Supabase
│   │   ├── registry.ex            # Supabase registry client (spec.specs CRUD)
│   │   ├── interop/
│   │   │   ├── ampersand.ex       # Bidirectional ampersand.json mapping (section 4.8)
│   │   │   └── adl.ex             # Bidirectional ADL mapping (section 4.8)
│   │   └── mcp/
│   │       ├── server.ex          # MCP JSON-RPC server (section 4.2)
│   │       └── tools.ex           # Tool definitions and handlers
│   ├── specprompt.ex              # Application entry point
│   └── cli.ex                     # CLI escript entry point
├── test/
│   ├── parser_test.exs
│   ├── validator_test.exs
│   ├── linter_test.exs
│   ├── test_compiler_test.exs
│   ├── differ_test.exs
│   └── fixtures/
│       ├── valid_spec.md          # Use the customer-support example from spec section 3.3
│       ├── invalid_spec.md        # Missing required sections
│       └── compiled_tests.json    # Pre-compiled test assertions
├── npm/                           # TypeScript parser package (@specprompt/parser)
│   ├── src/
│   │   ├── parser.ts
│   │   ├── types.ts
│   │   └── index.ts
│   ├── test/
│   │   └── parser.test.ts
│   ├── package.json
│   └── tsconfig.json
├── mix.exs
├── Dockerfile
└── fly.toml
```

---

## Implementation Order

### Phase 1: Parser + Validator (week 1)

1. **Implement PEG parser** (`lib/specprompt/parser.ex`)
   - Parse YAML frontmatter (all fields from spec section 4.5, including new `workspace_id`, `visibility`, `source_hash`)
   - Parse H2 sections: Purpose, Capabilities, Constraints, Acceptance Tests, Architecture, Dependencies, Changelog
   - Extract structured data into `SpecPrompt.Spec` schema
   - Compute `source_hash` (SHA-256 of raw SPEC.md content)
   - Return `{:ok, %SpecPrompt.Spec{}}` or `{:error, [errors]}`

2. **Implement validator** (`lib/specprompt/validator.ex`)
   - All 8 MUST rules from spec section 4.7
   - All 7 SHOULD warnings (including 3 new compiled test warnings)
   - Return structured validation result with line numbers

3. **Implement CLI** (`lib/cli.ex`)
   - `specprompt validate SPEC.md` — parse + validate, exit 0/1
   - `specprompt lint SPEC.md` — validate + SHOULD warnings

4. **Write tests** against the customer-support example from spec section 3.3

### Phase 2: Test Compilation (week 2)

This is the critical dark factory bridge — turning natural language acceptance tests into executable assertions.

1. **Implement test compiler** (`lib/specprompt/test_compiler.ex`)
   - Input: `%SpecPrompt.Spec{}` with `acceptance_tests`
   - For each acceptance test, generate a `%SpecPrompt.CompiledTest{}`:
     - `setup`: mocked tool states derived from the `given` clause
     - `input`: agent input derived from the `given` clause
     - `assertions`: list of Agentelic DSL assertions:
       - `%{type: :contains, value: "..."}` — expected text in output
       - `%{type: :tool_called, tool: "...", args: %{}}` — expected tool invocation
       - `%{type: :tool_not_called, tool: "..."}` — forbidden tool invocation
       - `%{type: :escalated, value: true/false}` — escalation check
       - `%{type: :constraint_respected, constraint_index: N}` — constraint enforcement
   - Compilation is **LLM-assisted on first pass**: send the spec + acceptance test to an LLM, ask it to generate the assertion mapping
   - Cache compiled tests by `{source_hash, test_index}` — unchanged tests reuse prior compilations
   - Mark all compiled tests as `approved: false` initially

2. **Implement approval workflow**
   - `specprompt test-compile SPEC.md --output tests/compiled.json` — compile all tests
   - `specprompt test-compile SPEC.md --approve` — mark all compiled tests as approved
   - `specprompt test-compile SPEC.md --status` — show compilation + approval status
   - Only approved tests are used by Agentelic in the dark factory pipeline

3. **Important constraint**: The test compiler itself does NOT call LLMs. It generates a structured prompt that an external LLM (via Agentelic or the user's own API key) processes. SpecPrompt is a tool, not an agent. The MCP server version (`spec_test_compile`) returns the prompt for the agent to execute.

### Phase 3: MCP Server (week 3)

1. **Implement MCP server** (`lib/specprompt/mcp/server.ex`)
   - JSON-RPC over HTTP, MCP protocol v2025-03-26
   - Tools: `spec_validate`, `spec_lint`, `spec_generate`, `spec_test_gen`, `spec_test_compile`, `spec_test_approve`, `spec_diff`, `spec_search`
   - `spec_test_compile` returns the compilation prompt (not the result) — the agent does the LLM call
   - `spec_search` queries the Supabase registry

2. **Implement Supabase registry** (`lib/specprompt/registry.ex`)
   - CRUD on `spec.specs` table
   - Workspace-scoped queries
   - Visibility filtering (private → only owner, workspace → workspace members, public → everyone)

### Phase 4: Supabase Migration (week 3)

1. **Create migration** in `ampersand-supabase/migrations/`:
   - Allocate range (suggest 100-109 for spec.*)
   - Create `spec.specs` table per spec section 5.2
   - Enable RLS with workspace-based policies (same pattern as `kag.*`, `rune.*`)

### Phase 5: Pipeline Triggers (week 4)

1. **Implement CloudEvents emitter** (`lib/specprompt/publisher.ex`)
   - On `specprompt publish`, emit `ConsolidationEvent` to Agentelic
   - CloudEvents v1 envelope format per spec section 5.3
   - Transport: Supabase Realtime (insert into `spec.specs` triggers) or HTTP POST

2. **Implement GitHub Actions template** (`.github/workflows/dark-factory.yml`)
   - On push to `**/SPEC.md`: validate, compile tests (require approved), trigger Agentelic webhook

### Phase 6: TypeScript Parser (week 4)

1. **Port parser to TypeScript** (`npm/src/parser.ts`)
   - Same PEG grammar, same validation rules
   - Publish as `@specprompt/parser` on npm
   - Used by Agentelic's TypeScript agents and RuneFort's client-side spec display

---

## Key Constraints

- **SpecPrompt does NOT make LLM calls.** The test compiler generates prompts; the agent executes them.
- **Filesystem mode must work without any network.** No Supabase, no auth, no MCP server required for basic validate/lint/diff.
- **Registry mode requires Supabase Auth.** All queries scoped to workspace_id via RLS.
- **Compiled tests require human approval** before use in the dark factory pipeline. This is the trust boundary.
- **Parser must be deterministic.** Same input → same parse tree. No LLM in the parser.
- **Use the customer-support SPEC.md example** (spec section 3.3) as the canonical test fixture.

---

## Integration Points

| System | Direction | Protocol | What |
|--------|-----------|----------|------|
| **Agentelic** | SpecPrompt → Agentelic | CloudEvents / Supabase Realtime | ConsolidationEvent on spec publish |
| **FleetPrompt** | SpecPrompt → FleetPrompt | spec_search MCP tool | Search published specs in registry |
| **Graphonomous** | SpecPrompt → Graphonomous | MCP retrieve/act | Store lint heuristics, retrieve prior compilations |
| **Delegatic** | SpecPrompt → Delegatic | Policy substrate | Spec visibility, publish permissions |
| **ampersand.json** | Bidirectional | File I/O | Export/import capability mappings |
| **ADL** | Bidirectional | File I/O | Export/import Next Moca agent definitions |

---

## Success Criteria

- [x] `specprompt validate` correctly validates the customer-support example (pass) and an invalid spec (fail with line numbers)
- [x] `specprompt test-compile` generates compilable assertions for all 8 acceptance tests in the example
- [x] `specprompt test-compile --approve` marks tests as approved
- [x] MCP server discovers tools via `tools/list` and executes all 8 tools
- [x] Supabase migration applies cleanly alongside existing `amp.*`, `kag.*`, `rune.*` schemas
- [x] TypeScript parser produces identical parse results to Elixir parser on all test fixtures
- [x] Pipeline trigger emits CloudEvents on spec publish
