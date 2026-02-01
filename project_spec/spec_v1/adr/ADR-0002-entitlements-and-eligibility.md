# ADR-0002: Entitlements & Eligibility Policies (SpecPrompt)
- **Status:** Accepted
- **Date:** 2026-01-31
- **Owners:** Engineering
- **Decision scope:** Define SpecPrompt’s entitlement semantics and the minimum v1 eligibility policies for artifact fulfillment.

---

## Context

SpecPrompt is the portfolio’s **commerce/monetization layer** (Layer 6). It must support:
- Selling products/plans (one-time and subscription)
- Issuing **entitlements** based on verified payment-provider events
- Authorizing **fulfillment** (downloads/licenses) based on entitlement eligibility

Constraints and risks:
- **Entitlements are not authorization**: Downstream products (WHS/Agentromatic/Agentelic/Delegatic) must continue enforcing their own membership/ownership/role checks. SpecPrompt should never become an auth bypass.
- **Webhooks are at-least-once**: Payment providers retry; events can arrive duplicated or out of order.
- **Fulfillment tokens/URLs are sensitive**: Must be time-bounded, revocable, and auditably issued.
- **Eligibility must be deterministic**: Two calls with the same server-side state must produce the same eligibility outcome. Avoid “client says they’re eligible” patterns.

We need a small, safe, implementation-ready set of eligibility policies that cover:
- One-time purchase licensing patterns
- Subscription “updates while active” patterns
- Clear revocation behavior under refunds/chargebacks/cancellation

---

## Decision

### 1) Define “Entitlement” as a commercial right grant (normative)

An **entitlement** is a SpecPrompt-owned grant that determines whether a subject is eligible to receive fulfillment artifacts.

Rules:
- Entitlements **grant commercial rights**, not runtime permissions.
- Entitlements MUST NOT be treated as:
  - Delegatic org membership/role
  - Agentelic telespace membership/role
  - WHS agent invocation permission
  - Agentromatic workflow execution permission

Downstream products MAY query SpecPrompt to learn whether a user is entitled, but MUST still enforce their own authorization checks.

---

### 2) V1 entitlement subject scope: user-scoped only (normative)

In v1, entitlements are scoped to **one user**:
- `subjectType = "user"`
- `subject = userId (internal) / externalId (identity provider subject)`

Org-scoped entitlements are deferred to a later version (expected to integrate with Delegatic).

---

### 3) V1 eligibility is artifact-based and server-evaluated (normative)

Eligibility is evaluated against SpecPrompt-owned **artifacts** (deliverables):
- Eligibility evaluation MUST be server-side only.
- Eligibility evaluation MUST be deterministic and derived from:
  - entitlement state + policy
  - artifact metadata (e.g., `version`, `major`, `releasedAtMs`, `status`)
- Clients MUST NOT be able to influence eligibility decisions beyond selecting a product/plan/artifact id.

---

### 4) V1 policies: support exactly two policy families (normative)

SpecPrompt v1 supports these eligibility policies:

#### Policy P1 — One-time major-version license (`one_time_major`)
Shape:
- `{ "type": "one_time_major", "major": <number> }`

Semantics:
- Entitlement covers artifacts whose `artifact.major == policy.major`.
- Artifacts with `major > policy.major` are not eligible.
- Artifacts with `major < policy.major` MAY be eligible (recommended: yes) **only if** those artifacts are still `active`. (This is a product choice; v1 recommended stance is “same major only” to keep it simple. If you allow `< major`, document it explicitly and test it.)

Recommended v1 stance (simple and strict):
- Eligible iff `artifact.major == policy.major` and `artifact.status == "active"`.

Use cases:
- “Buy v1.x forever; pay again for v2.x.”

#### Policy P2 — Subscription updates while active (`subscription_updates_while_active`)
Shape:
- `{ "type": "subscription_updates_while_active", "eligibleThroughMs": <number|null> }`

Semantics:
- If subscription is **active**: `eligibleThroughMs` MAY be null and treated as “no cutoff” (eligible up to now).
- If subscription is **inactive** (ended): `eligibleThroughMs` MUST be a cutoff time:
  - artifact is eligible iff `artifact.releasedAtMs <= eligibleThroughMs` and `artifact.status == "active"`.

Recommended v1 stance:
- While active: eligible for any `active` artifact of the product.
- After end: eligible only for artifacts released up to the cutoff timestamp.

Use cases:
- “Access updates while subscribed; keep access to what you had when you canceled.”

---

### 5) Revocation and withdrawal semantics (normative)

#### 5.1 Entitlement status states (v1)
`entitlements.status` is one of:
- `active`
- `inactive`
- `revoked`

Rules:
- `revoked` is used for punitive/legal/payment integrity events (refund/chargeback).
- `inactive` is used for subscription ended (normal lifecycle).

SpecPrompt MUST record changes via append-only `entitlementEvents`.

#### 5.2 How revocation affects fulfillment
- If entitlement is `revoked` or `inactive`, new fulfillment authorizations MUST be denied deterministically.
- Existing authorizations:
  - If using **signed URL** fulfillment: previously issued signed URLs may remain valid until expiry; therefore signed URLs MUST be short-lived.
  - If using **token + proxy** fulfillment: the download endpoint SHOULD re-check entitlement at redemption time to ensure revocation blocks downloads immediately.

This is a deliberate tradeoff; v1 defaults should minimize the time window of “already minted” authorizations.

#### 5.3 Artifact withdrawal
Artifacts have a status:
- `active` (eligible)
- `withdrawn` (not eligible for new fulfillment)

Policy:
- Withdrawn artifacts MUST NOT be eligible for *new* authorizations, regardless of entitlement policy.
- Whether previously issued authorizations remain valid until expiry depends on fulfillment mode; keep TTLs short.

---

### 6) Idempotency requirements for issuance (normative)

Because payment events are retried and can be duplicated/out-of-order:
- Entitlement issuance MUST be idempotent.
- The system MUST converge deterministically under duplicates and replays.

Practical v1 rule:
- Maintain exactly one current entitlement per `(userId, productId)`.
- Write append-only `entitlementEvents` for each state change, deduped by a stable `dedupeKey` (recommended derived from `providerEventId` and action type).

---

## Consequences

### Positive
- Clear separation of responsibilities:
  - SpecPrompt grants commercial rights and controls fulfillment
  - Other products enforce runtime authorization and governance
- Simple, implementable v1 policies that cover common monetization models
- Deterministic eligibility evaluation and auditable state transitions
- Supports “paid updates” and “major-version licensing” without complex licensing engines

### Negative / Tradeoffs
- Org-level licensing is deferred; some B2B use cases require future work.
- Revocation immediacy depends on fulfillment mode:
  - signed URLs can’t be force-revoked after issuance without proxying
- Policy expressiveness is limited in v1 (no seat counts, feature flags, or custom eligibility rules beyond these two)

---

## Alternatives considered

### A) “Entitlement implies authorization” across portfolio products
Rejected:
- Creates confused-deputy risks and collapses governance boundaries.
- Hard to reason about tenant isolation across multiple systems.

### B) Offline-perpetual license keys verified entirely client-side
Rejected for v1:
- Hard to revoke.
- Higher leakage risk and complicated support story.

### C) Only subscription model, no one-time licensing
Rejected:
- Doesn’t match desired monetization flexibility and “paid updates” models.

### D) Fine-grained per-version entitlements (one entitlement per artifact)
Deferred:
- More complex data model and state transitions.
- v1 can achieve the same effect via artifact metadata + eligibility policies.

---

## Implementation notes (guidance)

### Data model alignment
- `plans.eligibilityPolicy` stores one of the policy shapes above.
- `entitlements.eligibilityPolicy` stores the resolved policy for the user/product, plus:
  - subscription cutoff `eligibleThroughMs` if subscription ended
- `artifacts` MUST include:
  - `productId`, `version`, `major`, `releasedAtMs`, `status`

### API alignment
- `POST /v1/fulfillment/token` must:
  1) load entitlement for `(userId, productId)`
  2) load artifact by `artifactId` and confirm artifact belongs to product
  3) evaluate eligibility deterministically
  4) issue signed URL or download token (time-bounded), and write a fulfillment event

### Testing alignment
Minimum required tests (see `60_TESTING_ACCEPTANCE.md`):
- One-time major eligibility:
  - major match eligible
  - major mismatch not eligible
- Subscription eligibility:
  - active => eligible
  - canceled with cutoff => eligible only up to cutoff
- Revocation:
  - revoked entitlement blocks new fulfillment
- Duplicate provider events do not duplicate entitlements (idempotency)

---

## Acceptance criteria
This ADR is satisfied when:
1. SpecPrompt can represent an entitlement with either `one_time_major` or `subscription_updates_while_active` policy.
2. Eligibility evaluation is deterministic and server-side.
3. Refund/chargeback/cancellation events transition entitlement state deterministically and are auditable (append-only events).
4. Fulfillment authorization blocks ineligible artifacts and returns stable error codes (e.g., `ENTITLEMENT_INACTIVE`, `ARTIFACT_NOT_ELIGIBLE`).
5. No other product treats “entitlement exists” as authorization; it is only a commerce gate.

---

## Related specs
- `ProjectWHS/specprompt.com/project_spec/spec_v1/00_MASTER_SPEC.md`
- `ProjectWHS/specprompt.com/project_spec/spec_v1/10_API_CONTRACTS.md`
- `ProjectWHS/specprompt.com/project_spec/spec_v1/30_DATA_MODEL_CONVEX.md`
- `ProjectWHS/specprompt.com/project_spec/spec_v1/40_SECURITY_SECRETS_COMPLIANCE.md`
- `ProjectWHS/specprompt.com/project_spec/spec_v1/60_TESTING_ACCEPTANCE.md`
