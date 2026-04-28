# SpecPrompt — User Stories

Canonical user-story catalog. Used for Playwright tests + Claude Design input.

**Scope:** Spec-driven development toolchain — parser, validator, linter, test-compiler, registry.
**Unit-test surface covered:** `test/**` (71 tests).

---

## Story 1 · Write and validate agent specification

- **Persona:** Product engineer defining agent behavior before engineering begins
- **Goal:** Write a human-readable spec that parses correctly and becomes the contract with engineering
- **Prerequisite:** Engineer has text editor
- **Steps:**
  1. Create SPEC.md with YAML frontmatter (name, version, author)
  2. Write Purpose section
  3. List Capabilities (orders:read, refunds:create, graphonomous:*)
  4. List Constraints (hard + soft)
  5. Write Acceptance Tests in Given/When/Then format
  6. Run `specprompt validate SPEC.md`
- **Success:** Zero validation errors; spec ready for Agentelic build pipeline
- **Covers:** `SpecPrompt.Parser.parse`, `Validator.check_required_sections`, frontmatter validation — ~25 unit tests
- **UI status:** `/validate` route exists today (textarea paste → result)
- **Claude Design hook:** SvelteKit-style editor with live validation + section templates + Markdown preview

## Story 2 · Generate and approve compiled tests

- **Persona:** QA engineer converting natural-language acceptance tests into executable assertions
- **Goal:** Bridge spec acceptance criteria → deterministic test code without manual coding
- **Prerequisite:** SPEC.md with 6+ acceptance tests
- **Steps:**
  1. Run `specprompt test-compile SPEC.md --output tests/compiled.json`
  2. LLM generates Agentelic.Test.DSL assertions
  3. QA reviews setup, input, assertions
  4. Approve with `--approve` flag
  5. Approved tests cached by `{source_hash, test_index}`
- **Success:** Agentelic build pulls approved tests and runs deterministic suite
- **Covers:** `TestCompiler.compile`, `TestCompiler.generate_dsl`, approval + cache — ~15 unit tests
- **UI status:** mcp-only (CLI + MCP tool)
- **Claude Design hook:** Approval workflow — side-by-side diff viewer (natural language ↔ compiled assertions)

## Story 3 · Diff spec versions and gate rollouts

- **Persona:** Product manager reviewing changes between agent spec versions
- **Goal:** Understand what behavior changed between v2.0.0 and v2.1.0 before rolling out
- **Prerequisite:** Multiple SPEC.md versions in git history
- **Steps:**
  1. Run `specprompt diff SPEC.md@v2.0.0 SPEC.md@v2.1.0`
  2. Structured diff: added/removed capabilities, changed constraints, new tests
  3. Review: no breaking changes
  4. Approve spec change; triggers Agentelic build
- **Success:** Clear change history; product team can gate rollouts by spec diffs
- **Covers:** `Differ.diff_specs`, `Differ.section_diff`, constraint diff — ~10 unit tests
- **UI status:** planned
- **Claude Design hook:** Side-by-side diff viewer with added/removed badges + rollout gate UI

## Story 4 · Browse the spec registry

- **Persona:** Engineering team discovering reusable specs
- **Goal:** Find existing spec for "customer support agent" rather than writing from scratch
- **Prerequisite:** Specs published to `spec.specs` Supabase table
- **Steps:**
  1. Navigate to `/registry`
  2. Browse spec cards by workspace / public / tag
  3. Click a spec to view full SPEC.md rendered
  4. Click "Fork into workspace" to copy as starting point
- **Success:** Spec discoverable; easy to fork
- **Covers:** `Registry.list_specs`, `Registry.fetch_by_hash`, ACL filtering — ~12 unit tests
- **UI status:** `/registry` route exists today
- **Claude Design hook:** Registry grid with visibility filters + preview on hover

## Story 5 · Generate spec from natural language

- **Persona:** Non-technical product owner describing agent requirements
- **Goal:** Bootstrap agent spec from description; engineer refines
- **Prerequisite:** SpecPrompt MCP server available
- **Steps:**
  1. Call `spec_generate` MCP tool with natural-language description
  2. Tool generates SPEC.md scaffold (Purpose, Capabilities, Constraints, Tests)
  3. Engineer fills in details; runs `specprompt lint SPEC.md`
  4. Linter flags ambiguous constraint language ("try to", "sometimes")
  5. Engineer updates constraints; lint passes
- **Success:** Spec bootstrapped in minutes instead of hours
- **Covers:** `Generator.generate_from_description`, `Linter.check_constraint_language` — ~9 unit tests
- **UI status:** mcp-only
- **Claude Design hook:** Textarea input + real-time SPEC.md preview pane

---

**Tests to implement first:** Story 1 (validate — has existing UI at `/validate`), Story 4 (browse registry — existing UI at `/registry`).
