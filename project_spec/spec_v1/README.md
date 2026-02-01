# specprompt.com — Spec v1 (Commerce & Monetization Layer)
Version: 1.0  
Status: Draft scaffold (normative once the referenced spec files exist)  
Audience: Engineering  
Last updated: 2026-01-31

SpecPrompt is the portfolio’s **commerce/monetization layer** (“Layer 6” in the 6-layer stack). It is responsible for **payments, licensing, entitlements, and fulfillment** for commercial assets across the ecosystem.

Portfolio taxonomy (canonical):
- **WHS (WebHost.Systems)** = agents (deploy/invoke/telemetry/limits/billing for runtime usage)
- **Agentromatic** = workflows (definitions/executions/logs)
- **Agentelic** = telespaces (rooms/messages/automations that reference WHS + Agentromatic)
- **Delegatic** = organizations (governance/policies that contain telespaces and constrain actions)
- **FleetPrompt** = marketplace/distribution (discovery/listing/install surfaces)
- **SpecPrompt** = **commerce** (checkout, licensing, entitlements, transactions, fulfillment)

**Core stance:** SpecPrompt monetizes *assets* and grants *rights* (entitlements). It does **not** execute agents/workflows, and it must not bypass governance/permission boundaries elsewhere.

---

## 0) What SpecPrompt is (canonical definition)

SpecPrompt is a commerce service that:
- defines **products** (SKUs) for portfolio assets (e.g., prompt/spec packs, workflow templates, agent bundles, add-ons)
- handles **checkout** and **payment events**
- issues **entitlements** (license grants + update eligibility rules)
- provides **fulfillment** (download access, license keys/tokens, invoices/receipts)
- supports **B2C** and “B2B-lite” (teams/orgs later, via Delegatic)

SpecPrompt can be used by:
- FleetPrompt Marketplace to monetize listings (purchase/subscribe)
- Direct purchase flows (e.g., “Buy this spec pack”) independent of marketplace discovery
- Internal portfolio products to verify entitlements at runtime boundaries (server-side checks only)

---

## 1) Hard boundaries (must remain true)

### 1.1 SpecPrompt is not a runtime and not a marketplace
- SpecPrompt MUST NOT execute WHS invocations or Agentromatic executions.
- SpecPrompt MUST NOT replace FleetPrompt discovery/listings UI.
- SpecPrompt MUST NOT mint “superpowers” that bypass Delegatic/Agentelic/WHS authorization.

### 1.2 Entitlements are grants of rights, not implicit authorization
- An entitlement MAY allow **download/updates/support** or **feature access**.
- An entitlement MUST NOT be treated as “member of a telespace” or “admin of an org”.
- Runtime systems (WHS/Agentromatic/Agentelic) MUST continue enforcing their own tenant isolation and role checks.

### 1.3 References, not copies (portfolio-consistent)
SpecPrompt SHOULD store:
- references to external assets (agent IDs, workflow IDs, package IDs, listing IDs)
- bounded metadata needed for commerce (price, tax category, SKU, version tags)

SpecPrompt MUST NOT:
- duplicate Agentromatic execution logs
- store WHS telemetry/event streams
- become the source of truth for “what happened at runtime”

---

## 2) Goals and non-goals (v1)

### 2.1 Goals (v1 MUST)
1. Define products (SKUs) and pricing plans (one-time and subscription).
2. Support checkout and payment state transitions (via a payment provider).
3. Issue entitlements deterministically and idempotently from payment events.
4. Provide fulfillment endpoints:
   - “List my entitlements”
   - “Can I download version X?”
   - “Give me a token/link for download”
5. Keep secrets safe:
   - no provider secrets in client-visible payloads
   - no secret leakage in logs/errors
6. Auditable transactions:
   - append-only transaction ledger + event correlation IDs

### 2.2 Non-goals (v1 MUST NOT)
- Full enterprise billing procurement flows (invoicing portals, PO workflows) beyond minimal receipts.
- Complex tax engine implementation (use provider-managed taxes if available; keep rules minimal).
- Organization-wide entitlements with delegated admins (defer; integrate with Delegatic later).
- Building a full seller/publisher payout system unless explicitly added later.

---

## 3) How this spec should be used

### 3.1 Normative vs non-normative
- **Normative**: `project_spec/spec_v1/*.md` and `project_spec/spec_v1/adr/*.md`
- **Non-normative**: `project_spec/progress/*` logs, notes, scratch docs

If a progress log conflicts with `spec_v1`, the spec wins.

### 3.2 Recommended reading order (once files exist)
1. `00_MASTER_SPEC.md` — system behavior, invariants, flows, acceptance criteria
2. `10_API_CONTRACTS.md` — endpoints, error envelopes, idempotency, pagination
3. `30_DATA_MODEL_CONVEX.md` — schema + indexes + invariants
4. `40_SECURITY_SECRETS_COMPLIANCE.md` — threat model, secrets, webhooks integrity
5. `50_OBSERVABILITY_BILLING_LIMITS.md` — audit, retention, rate limits, fraud/abuse posture
6. `60_TESTING_ACCEPTANCE.md` — unit/integration/E2E plans and release gates
7. `adr/*` — decisions and rationale

---

## 4) Primary concepts (glossary-lite)

- **Product / SKU**: Sellable unit (e.g., “SpecPrompt Pack: Agentelic v1 templates”).
- **Plan**: Pricing option (one-time or subscription).
- **Order**: A checkout attempt and its resulting purchase record.
- **Payment Event**: Provider webhook or internal event that changes order state.
- **Entitlement**: Grant to a user (or later, org) enabling:
  - access to artifacts
  - updates for a period
  - usage credits (optional; carefully bounded)
- **Fulfillment Artifact**: Deliverable content (downloadable package, license token, receipt).

---

## 5) Integration model (how SpecPrompt composes with the rest)

### 5.1 SpecPrompt ↔ FleetPrompt (marketplace)
- FleetPrompt Marketplace is the **discovery + listing surface**.
- SpecPrompt is the **checkout + entitlement issuer**.
- Marketplace calls SpecPrompt to:
  - create checkout sessions for listings
  - confirm entitlement status for a user
  - generate fulfillment/download tokens

### 5.2 SpecPrompt ↔ WHS (runtime usage)
- WHS enforces runtime usage limits and billing for compute/requests.
- SpecPrompt MAY sell:
  - add-on “usage credits” or plan upgrades
- If SpecPrompt affects WHS limits, it MUST do so via a controlled, auditable bridge:
  - never by editing usage counters directly
  - never by accepting client-side assertions

### 5.3 SpecPrompt ↔ Agentromatic / Agentelic (assets and packaging)
- SpecPrompt can monetize:
  - workflow templates (Agentromatic definitions)
  - telespace templates (Agentelic scaffolds)
  - “packs” that contain references + signed manifests
- SpecPrompt should prefer distributing **artifacts/manifests** that other products can import with verification, rather than copying internal DB state.

### 5.4 SpecPrompt ↔ Delegatic (org governance)
- v1 entitlements are user-scoped by default.
- Later: org-scoped entitlements align with Delegatic org membership + policy.
- Delegatic remains the governance plane; SpecPrompt only grants commercial rights.

---

## 6) v1 file set (what should exist in this folder)

This README expects the following files to be created to make SpecPrompt v1 implementation-ready:

- `spec_v1/00_MASTER_SPEC.md`
- `spec_v1/10_API_CONTRACTS.md`
- `spec_v1/30_DATA_MODEL_CONVEX.md`
- `spec_v1/40_SECURITY_SECRETS_COMPLIANCE.md`
- `spec_v1/50_OBSERVABILITY_BILLING_LIMITS.md`
- `spec_v1/60_TESTING_ACCEPTANCE.md`
- `spec_v1/REALIGNMENT_PLAN.md` (optional but recommended)
- `spec_v1/adr/ADR-0001-*.md` (key decisions)

Suggested ADR topics (minimum set):
- ADR: Payment provider choice and webhook verification model
- ADR: Entitlement semantics (one-time vs subscription vs “paid updates”)
- ADR: References-not-copies for cross-product assets
- ADR: Idempotency strategy for webhook/event processing
- ADR: Download token format and revocation strategy

---

## 7) v1 acceptance criteria (high level)

SpecPrompt v1 is “done” when you can:

1. Create a product + plan (admin/dev-only is fine in v1).
2. Create a checkout for an authenticated user.
3. Receive a payment provider event and:
   - mark the order paid (or failed)
   - issue an entitlement exactly once (idempotent)
4. List entitlements for the current user.
5. Request a fulfillment artifact/download token and validate it server-side.
6. Prove security invariants:
   - webhook spoofing attempts are rejected
   - no secrets in logs/errors
   - cross-user entitlement access is blocked (IDOR-safe)

---

## 8) Progress logs (non-normative)

Daily implementation progress logs (if used) should live in:
- `project_spec/progress/YYYY-MM-DD.md`

Rules:
- append-only
- no secrets
- link back to relevant spec sections / ADRs

---