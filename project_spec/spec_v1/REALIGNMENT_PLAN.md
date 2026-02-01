# specprompt.com — Spec-to-Implementation Realignment Plan (v1)
Version: 1.0  
Status: Actionable checklist (spec → code)  
Audience: Engineering  
Last updated: 2026-01-31

This document is a **single checklist** to keep the SpecPrompt implementation aligned with the v1 spec set under `project_spec/spec_v1/`, specifically:
- checkout creation
- payment webhook verification + event processing
- order state machine correctness
- entitlement issuance/revocation (idempotent)
- fulfillment authorization + download delivery (tokens/signed URLs)
- auditability and secret-minimization

If there is drift:
1. Fix **security + correctness** drift first (IDOR, webhook integrity, idempotency).
2. Fix **contract shape** drift second (API request/response shapes).
3. For any intentional semantic change, write an ADR and update the spec set.

---

## 0) How to use this plan (operating procedure)
1. Treat these as normative spec sources:
   - `spec_v1/00_MASTER_SPEC.md` (behavior and flows)
   - `spec_v1/10_API_CONTRACTS.md` (wire contracts)
   - `spec_v1/30_DATA_MODEL_CONVEX.md` (tables/invariants/idempotency)
   - `spec_v1/40_SECURITY_SECRETS_COMPLIANCE.md` (threat model + secrets)
   - `spec_v1/60_TESTING_ACCEPTANCE.md` (release gates + tests)

2. For each section below:
   - apply the **Spec patch** items (docs) if the docs disagree,
   - apply the **Implementation tasks** (code/data model),
   - then prove it with the **Acceptance checks**.

3. Do not ship to production until §9 “Release gates” is satisfied.

---

## 1) Canonical v1 decisions (lock these)
These are the decisions SpecPrompt v1 MUST follow across all specs and code.

### 1.1 Entitlements are commercial rights, not runtime authorization
- Entitlements MUST NOT be interpreted as:
  - Delegatic org membership/role
  - Agentelic telespace membership/role
  - WHS agent invocation permission
  - Agentromatic workflow execution permission
- Downstream products MAY check entitlements, but MUST still enforce their own authorization.

### 1.2 Webhooks are authoritative only after verification (raw bytes)
- The webhook endpoint MUST verify provider signatures over **raw request body bytes**.
- Unverified webhooks MUST NOT mutate any state.

### 1.3 Idempotency is required for:
- Client POST endpoints that can be retried:
  - `POST /v1/checkout`
  - `POST /v1/fulfillment/token` (or equivalent)
- Webhook processing:
  - dedupe by `(provider, providerEventId)`
- Entitlement issuance:
  - exactly-once per logical purchase (and safe under duplicates/out-of-order events)

### 1.4 Append-only audit trail is non-negotiable
SpecPrompt MUST have an append-only ledger for:
- payment events ingested/verified
- entitlement events (grant/revoke/inactivate)
- fulfillment events (authorized/denied/delivered)
Orders and current entitlements may be mutable current-state views, but event history must remain append-only.

### 1.5 Secrets rule (no leaks, minimal storage)
- No webhook secrets, provider API keys, storage signing credentials, auth tokens, or download tokens in logs.
- Do not store raw webhook payloads unbounded. Store a safe bounded subset and optionally a hash.

---

## 2) Known “easy to drift” areas (what this plan prevents)
These are common failure modes that you should actively check for drift:

1. **“Paid” state driven by client**  
   Client redirect success is not proof of payment. Only verified webhooks transition orders.

2. **Webhook verification on parsed JSON**  
   Re-serialization breaks signature verification and invites spoofing risk.

3. **Duplicate webhook delivery duplicates entitlements**  
   Providers retry aggressively; you must treat events as “at least once”.

4. **Token leakage**  
   Download tokens in URLs/logs/referrers, signed URL query params in logs.

5. **Authorization confusion**  
   Treating “has entitlement” as permission to perform privileged operations elsewhere.

---

## 3) Realignment checklist — Data model & invariants (Convex)
Target: `spec_v1/30_DATA_MODEL_CONVEX.md`

### 3.1 Tables that MUST exist
- `users`
- `products`
- `plans`
- `orders`
- `paymentEvents` (append-only, deduped by provider event id)
- `idempotencyKeys` (client idempotency ledger)
- `entitlements` (current state)
- `entitlementEvents` (append-only)
- `artifacts`
- `fulfillmentEvents` (append-only)
- `downloadTokens` (only if using token+proxy mode; omit if signed-URL-only)

### 3.2 Required invariants (MUST be enforced in code)
- `users.externalId` is unique.
- `paymentEvents` are unique by `(provider, providerEventId)`:
  - duplicates must not create new rows or side effects.
- `idempotencyKeys` are unique by `(userId, endpoint, idempotencyKey)`:
  - same key + different payload hash → `CONFLICT`.
- `entitlements` are unique by `(userId, productId)` for “current state” in v1.
- `entitlementEvents` are append-only; ideally deduped by a stable `dedupeKey` derived from providerEventId.
- `fulfillmentEvents` are append-only.
- `downloadTokens` (if used) store ONLY token hashes, not raw tokens; include expiry and revocation fields.

### 3.3 Spec patches (if docs disagree)
- If any doc suggests storing raw webhook bodies unbounded, patch it to “bounded subset + rawBodySha256 optional”.
- If any doc suggests embedding event arrays inside `orders` or `entitlements`, patch it to “append-only events in separate tables”.

### 3.4 Acceptance checks
- You can show, for a single purchase:
  - one order row
  - one (or more) paymentEvents rows keyed by providerEventId
  - one current entitlement row
  - at least one entitlementEvents row
  - at least one fulfillmentEvents row after download authorization
- Duplicated providerEventId does not create new entitlements or duplicate grant events.

---

## 4) Realignment checklist — API contracts
Target: `spec_v1/10_API_CONTRACTS.md`

### 4.1 Normalized error envelope (MUST)
- All non-2xx responses return the normalized envelope:
  - stable `code`, safe `message`, `requestId`, optional `details.fields[]`.
- Choose and enforce a consistent IDOR strategy:
  - recommended: `NOT_FOUND` for cross-user resources.

Acceptance:
- Automated contract tests prove envelope shape for:
  - auth failures
  - validation failures
  - not-found
  - conflicts (idempotency mismatch)

### 4.2 Checkout endpoint (MUST be idempotent)
- `POST /v1/checkout`:
  - requires auth
  - requires `Idempotency-Key`
  - creates an order in `pending_payment`
  - creates provider checkout session and returns `checkoutUrl`/id
- The order MUST NOT transition to `paid/active` until webhooks do it.

Acceptance:
- Retrying the same request with the same idempotency key returns the same `orderId`.
- Reusing the same idempotency key with a different body returns `CONFLICT`.

### 4.3 Webhook endpoint (MUST verify raw bytes)
- `POST /v1/webhooks/payment`:
  - no user auth
  - verifies signature over raw bytes
  - stores paymentEvents append-only
  - processes idempotently
  - returns `{ ok: true }` even on duplicates (recommended)

Acceptance:
- Invalid signature produces no state change (no paymentEvents row created, no order changes, no entitlements created).
- Duplicate webhook delivery does not duplicate entitlements.

### 4.4 Entitlements endpoints (MUST be tenant-safe)
- `GET /v1/entitlements`:
  - returns only current user’s entitlements
- Optional `GET /v1/entitlements/check?productId=...`:
  - only checks current user
  - no email-based checks

Acceptance:
- User B cannot read user A’s entitlements.

### 4.5 Fulfillment endpoints (MUST enforce eligibility)
- `POST /v1/fulfillment/token`:
  - requires auth
  - requires `Idempotency-Key`
  - validates entitlement and eligibility policy against artifact metadata
  - returns either:
    - signed URL (short-lived), or
    - download token (short-lived, preferably single-use)

Acceptance:
- Wrong major version returns `ARTIFACT_NOT_ELIGIBLE`.
- Inactive entitlement returns `ENTITLEMENT_INACTIVE`.
- Same key + same payload returns same response; key mismatch with different payload returns `CONFLICT`.

---

## 5) Realignment checklist — Webhook processing pipeline correctness
Target: `spec_v1/00_MASTER_SPEC.md`, `spec_v1/40_SECURITY_SECRETS_COMPLIANCE.md`, `spec_v1/30_DATA_MODEL_CONVEX.md`

### 5.1 Canonical processing stages (MUST)
1. Receive webhook raw bytes.
2. Verify signature.
3. Persist paymentEvents record (dedupe by providerEventId).
4. Resolve internal order reference safely:
   - preferred: provider metadata set by SpecPrompt at checkout creation (e.g., `orderId` correlation)
   - fallback: server-stored provider object ids (session/subscription/invoice ids)
5. Apply deterministic order state transition.
6. Issue/revoke/inactivate entitlements idempotently.
7. Write entitlementEvents and (optionally) operational logs safely.

### 5.2 Out-of-order events (MUST converge deterministically)
Define a deterministic policy for:
- success → refund
- refund → success (usually remains revoked/inactive unless a new order exists; do not “unrevoke” silently)
- subscription cancel before activation
- duplicate events with same event id
- multiple events for same purchase (invoice paid + checkout completed)

Acceptance:
- A replay test suite proves eventual convergence to the same final state regardless of event order, without duplicating entitlements.

---

## 6) Realignment checklist — Fulfillment security
Target: `spec_v1/40_SECURITY_SECRETS_COMPLIANCE.md`, `spec_v1/10_API_CONTRACTS.md`, `spec_v1/60_TESTING_ACCEPTANCE.md`

### 6.1 Choose one fulfillment mode (and document it)
- Mode A: Signed URLs (recommended default)
- Mode B: Token + proxy download

Whichever is implemented MUST be the one described in the API contracts and tests.

### 6.2 Token rules (if token mode exists)
- Tokens MUST be:
  - time-bounded
  - revocable
  - stored hashed (never raw)
  - single-use by default (recommended)
- Token redemption should be:
  - auth + token (recommended defense-in-depth), OR
  - token-only with very strict rate limiting and recorded risk (not recommended)

### 6.3 Signed URL rules (if signed URL mode exists)
- URLs MUST be short-lived.
- URLs MUST NOT be logged (especially query signatures).
- If entitlement is revoked, new signed URLs must be denied deterministically.

Acceptance:
- Leakage scan confirms signed URL signatures and tokens are absent from logs.

---

## 7) Realignment checklist — Secrets, logging, and evidence
Target: `spec_v1/40_SECURITY_SECRETS_COMPLIANCE.md`

### 7.1 Logging rules (MUST)
Never log:
- webhook signature headers
- bearer auth tokens
- download tokens
- signed URL query parameters that include signatures
- raw webhook bodies in production (unbounded)

### 7.2 Stored data minimization (MUST)
- Persist minimal payment metadata:
  - provider ids, amounts/currency, event type, timestamps, rawBodySha256 optional
- Do not persist full payment instrument data.
- Do not persist raw webhook bodies unbounded.

### 7.3 Audit/evidence requirements (MUST)
For a purchase, you must be able to reconstruct:
- order creation
- verified payment events
- entitlement grant/revocation
- fulfillment authorizations and deliveries/denials

All from SpecPrompt’s own records, without relying solely on provider dashboards.

---

## 8) Spec-to-code mapping table (what to trust)
Use this table to avoid “fixing the wrong thing” when drift appears.

| Domain | Canonical v1 spec | Notes |
|---|---|---|
| Core flows / invariants | `spec_v1/00_MASTER_SPEC.md` | Behavior source-of-truth. |
| HTTP contracts | `spec_v1/10_API_CONTRACTS.md` | Shapes, errors, idempotency semantics. |
| DB schema + dedupe | `spec_v1/30_DATA_MODEL_CONVEX.md` | Tables/invariants/indexes. |
| Security posture | `spec_v1/40_SECURITY_SECRETS_COMPLIANCE.md` | Webhook integrity, secret minimization, IDOR stance. |
| Tests / release gates | `spec_v1/60_TESTING_ACCEPTANCE.md` | Definition of done. |

---

## 9) Release gates (must-pass checklist)
You may ship SpecPrompt v1 only when all of these are true:

### 9.1 Webhook integrity
- Invalid webhook signature yields:
  - no paymentEvents insertion
  - no order transitions
  - no entitlements issued
- Duplicate webhook event id yields no duplicate side effects.

### 9.2 Idempotency correctness
- `POST /v1/checkout` is idempotent via Idempotency-Key:
  - same key + same payload = same orderId
  - same key + different payload = CONFLICT
- `POST /v1/fulfillment/token` is idempotent the same way.

### 9.3 Tenant isolation (IDOR)
- Cross-user reads by id behave as NOT_FOUND (recommended) across:
  - orders
  - entitlements
  - download tokens (if present)
  - fulfillment events (if exposed)

### 9.4 Entitlement correctness
- Exactly-once entitlement issuance under duplicates.
- Refund/dispute/cancellation revokes/inactivates deterministically and audibly.

### 9.5 Fulfillment safety
- Tokens/URLs are short-lived.
- Replay behavior matches policy (single-use tokens or equivalent).
- No token/URL signature leakage in logs.

### 9.6 Auditability
- You can trace order → payment events → entitlement events → fulfillment events for a purchase.

---

## 10) Open decisions (track as ADRs before production)
Create ADRs under `spec_v1/adr/` for these decisions if not already captured:
1. Payment provider choice + exact webhook event mapping.
2. Fulfillment mode (signed URL vs proxy download) and revocation semantics for already-issued authorizations.
3. Eligibility policy set supported in v1 (one_time_major and/or subscription_updates_while_active).
4. Admin access model (allowlist vs role mapping) and which admin actions exist in v1.
5. Error strategy (“NOT_FOUND vs UNAUTHORIZED”) and consistency rules across endpoints.
6. Whether SpecPrompt exposes a public product catalog or is called only by FleetPrompt.

---

## 11) Output artifacts (what you should have after completing this plan)
- A codebase where:
  - webhook verification is correct (raw bytes)
  - idempotency is enforced for client POSTs
  - paymentEvents are deduped and append-only
  - entitlement issuance is exactly-once and auditable
  - fulfillment is safe and time-bounded
  - logs are secret-free and bounded
- A test suite that passes the release gates in §9.
- ADRs for the decisions in §10.
