# ADR-0001: Webhook Integrity (Raw Bytes) & Idempotent Processing (SpecPrompt)
- **Status:** Accepted
- **Date:** 2026-01-31
- **Owners:** Engineering
- **Decision scope:** How SpecPrompt verifies payment-provider webhooks and how it processes them safely under retries, duplicates, and out-of-order delivery.
- **Related specs:**
  - `project_spec/spec_v1/00_MASTER_SPEC.md` (Flows B/C/D)
  - `project_spec/spec_v1/10_API_CONTRACTS.md` (§9 Webhooks, §6 Idempotency)
  - `project_spec/spec_v1/30_DATA_MODEL_CONVEX.md` (`paymentEvents`, `idempotencyKeys`, `entitlementEvents`)
  - `project_spec/spec_v1/40_SECURITY_SECRETS_COMPLIANCE.md` (§6 Webhook integrity)
  - `project_spec/spec_v1/60_TESTING_ACCEPTANCE.md` (§4.2–4.6, §6.2)

---

## Context

SpecPrompt is the portfolio’s commerce layer. It is the system-of-record for:
- orders (purchase attempts + state),
- payment events (verified, append-only),
- entitlements (commercial rights),
- fulfillment authorization (download tokens / signed URLs).

Payment providers (e.g., Stripe) deliver webhook events with “at least once” semantics:
- duplicates are common,
- events can arrive out of order,
- transient failures can cause retries,
- multiple event types may refer to the same logical purchase.

If SpecPrompt:
- verifies signatures incorrectly (e.g., against parsed/re-serialized JSON), or
- processes events non-idempotently,

then attackers can spoof events or normal retries can cause:
- duplicate entitlement grants,
- incorrect order state,
- confused support/audit trails,
- token/fulfillment leakage risks.

We need a v1-safe approach that is:
- cryptographically correct,
- deterministic under retries/replays,
- auditable (append-only evidence),
- secret-minimizing.

---

## Decision

### 1) Webhook verification MUST use raw request bytes (normative)

SpecPrompt MUST verify payment-provider webhook signatures over the **exact raw request body bytes** received by the server.

Rules:
- Read and retain the raw body bytes for verification.
- Verify using the provider’s recommended scheme/library.
- Reject verification failures with a stable error (e.g., `WEBHOOK_VERIFICATION_FAILED`), and **MUST NOT** mutate any state on verification failure.
- Verification MUST occur before parsing the body for processing.

Rationale:
- Many providers sign the raw payload bytes; re-serialization can change whitespace, ordering, encoding, and break verification.
- Verifying parsed JSON is both incorrect and dangerous.

### 2) Payment events are append-only and deduped by provider event id (normative)

SpecPrompt MUST persist a `paymentEvents` record for each verified webhook event, and MUST dedupe by:
- `(provider, providerEventId)`.

Rules:
- On webhook receipt and successful verification:
  1) Extract `providerEventId`.
  2) Lookup `(provider, providerEventId)`:
     - If exists: treat as duplicate and return success (`{ ok: true }`) without reprocessing.
     - If missing: insert a new `paymentEvents` record and proceed to processing.
- `paymentEvents` is append-only evidence. Updates (if any) are restricted to:
  - processing status fields like `processedAtMs`, `status`, `linkedOrderId`, and bounded safe error fields.

Rationale:
- Dedupe by provider event id is the most reliable “exactly once” anchor available in v1.

### 3) Webhook processing MUST be idempotent and converge deterministically (normative)

SpecPrompt MUST process webhook events such that:
- Duplicate deliveries do not duplicate side effects.
- Out-of-order event arrival does not create inconsistent state.
- Replaying an event (or replaying the whole stream) converges to the same final state.

Normative requirements:
- Processing MUST be safe to retry after partial failures.
- Order state transitions MUST be deterministic and based only on verified provider events + server-side state (never client assertions).
- Entitlement issuance/revocation MUST be idempotent and auditable.

### 4) Binding provider events to orders MUST be server-controlled (normative)

SpecPrompt MUST NOT trust client assertions in webhook payloads to locate internal orders unless the value is cryptographically bound by the provider and set by SpecPrompt.

Approved mapping strategies (in priority order):
1) **Provider metadata set by SpecPrompt at checkout creation**:
   - Store `orderId` (or an unguessable server-generated correlation id) in provider session/subscription metadata.
   - On webhook, extract metadata and resolve order deterministically.
2) **Server-stored provider object ids**:
   - Map via `providerCheckoutSessionId`, `providerSubscriptionId`, `providerInvoiceId`, etc., that SpecPrompt recorded when creating checkout.

Forbidden:
- Accepting an `orderId` from webhook content that was not set by SpecPrompt in provider metadata (or otherwise securely bound).

Rationale:
- Prevents forged “pay someone else’s order” mappings and reduces accidental cross-linking.

### 5) Entitlement issuance MUST be effectively-once (normative)

SpecPrompt MUST ensure a purchase produces at most one logical entitlement “grant” effect.

Canonical v1 approach:
- Current entitlement state is keyed by `(userId, productId)` and stored in `entitlements`.
- Every change produces an append-only `entitlementEvents` row.

Dedupe:
- Each entitlement event written due to a webhook MUST carry a stable `dedupeKey`, derived from a unique provider anchor, such as:
  - `dedupeKey = "ent:provider:" + provider + ":evt:" + providerEventId`
  - or, if needed, `dedupeKey = "ent:order:" + orderId + ":type:" + entitlementEventType`

Rules:
- If an `entitlementEvents` row with the same `dedupeKey` already exists, do not write another.
- If a webhook implies an entitlement grant and an active entitlement already exists for `(userId, productId)` with the same source purchase, treat as idempotent no-op (but still allow updating bounded “last seen” fields if you keep them, and do not emit duplicates).

Rationale:
- Avoids double-issuing rights and keeps audit clean under retries.

### 6) “Same idempotency key, different payload” MUST be a conflict (normative)

While this ADR is webhook-focused, it also standardizes idempotency behavior for replay safety:
- If any idempotency key is reused with a materially different payload, SpecPrompt MUST return `CONFLICT`.

This applies to:
- client idempotency keys (checkout creation, fulfillment token minting), and
- internal dedupe keys (entitlement events).

Rationale:
- Prevents attackers from “hijacking” a dedupe key and reduces ambiguity in replay logic.

---

## Consequences

### Positive
- Correct cryptographic verification prevents webhook spoofing.
- Robust dedupe prevents duplicate entitlements and inconsistent order states.
- Append-only evidence supports support, audits, and incident response.
- Deterministic convergence makes reprocessing and recovery safe.

### Tradeoffs / costs
- Requires careful raw-body handling in the HTTP layer.
- Requires extra storage for event ledgers (`paymentEvents`, `entitlementEvents`, `fulfillmentEvents`).
- Requires explicit mapping logic from provider objects → internal orders.

---

## Implementation notes (guidance)

### A) Minimal persisted webhook fields (safe-by-default)
Persist:
- `provider`, `providerEventId`, `type`, `receivedAtMs`, `verifiedAtMs`,
- optional `rawBodySha256` (for forensic correlation),
- bounded `summary` object with only the necessary provider ids and amounts.

Do not persist:
- full raw webhook body unbounded,
- signature header values,
- payment instrument details.

### B) Processing pipeline skeleton (recommended)
1) Receive webhook raw bytes
2) Verify signature over raw bytes
3) Dedup by `(provider, providerEventId)`:
   - insert `paymentEvents` if new
4) Resolve internal order reference (metadata preferred)
5) Apply deterministic order transition
6) Apply entitlement changes idempotently:
   - upsert `entitlements` current state
   - append `entitlementEvents` (dedupeKey)
7) Record fulfillment-related side effects only when requested by user via fulfillment endpoints (separate from webhook processing)

### C) Out-of-order policy (must be explicit)
Document and implement a deterministic policy for sequences like:
- success → refund (revoked/inactive)
- refund → success (do not silently un-revoke; require a new order/purchase)
- subscription cancel before activation (final state converges; no oscillation)
- multiple success-type events for the same purchase (dedupe; no duplicates)

If you change this policy later, write a new ADR.

---

## Acceptance criteria (this ADR is satisfied when)
1. An invalid webhook signature results in:
   - `WEBHOOK_VERIFICATION_FAILED`,
   - no `paymentEvents` insert,
   - no order transitions,
   - no entitlement issuance.
2. A duplicate webhook delivery with the same `(provider, providerEventId)`:
   - returns `{ ok: true }`,
   - does not create additional entitlements or duplicate entitlement events.
3. Processing is retry-safe:
   - if processing fails after inserting `paymentEvents`, retrying converges correctly without duplication.
4. Raw-body verification is real:
   - verification breaks if the payload is reserialized, and tests demonstrate the implementation uses raw bytes.
5. No secrets leak:
   - no raw webhook bodies unbounded in DB,
   - no signature headers, auth tokens, download tokens, or signed URL signatures in logs.

---

## Alternatives considered

### A) Verify signatures after parsing JSON
Rejected: incorrect and unsafe.

### B) No persistent paymentEvents table (best-effort only)
Rejected: duplicates and retries would duplicate side effects; weak auditability.

### C) Dedup only at “order level”
Rejected: multiple provider events can reference the same order; per-event dedupe is required and more precise.

---

## Related ADRs (future)
- ADR: Fulfillment mode (signed URLs vs token+proxy) and revocation semantics.
- ADR: Payment provider choice and event mapping details (if not already decided).
- ADR: Admin access model and audit requirements for manual overrides.