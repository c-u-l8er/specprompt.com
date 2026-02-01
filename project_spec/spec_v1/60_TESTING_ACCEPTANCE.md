# specprompt.com — Testing Plan & Acceptance Criteria (v1)
Version: 1.0  
Status: Draft (normative once adopted)  
Audience: Engineering  
Last updated: 2026-01-31

This document defines the **SpecPrompt v1** testing strategy and acceptance criteria, with an explicit focus on:
- **webhook integrity + idempotency**
- **order and entitlement correctness under retries/out-of-order events**
- **fulfillment security (tokens/signed URLs), replay resistance, and revocation**
- **tenant isolation (IDOR)**

SpecPrompt is the portfolio’s **commerce/monetization layer** (Layer 6). It is the system-of-record for:
- orders
- payment events (verified, append-only)
- entitlements (commercial rights)
- fulfillment authorization + delivery audit

SpecPrompt MUST NOT execute agents/workflows and MUST NOT treat entitlements as authorization for other products.

---

## 1) Testing philosophy (what we optimize for)

### 1.1 Priorities (in order)
1. **Correctness under adversarial inputs**
   - forged webhooks must not mutate state
   - cross-tenant access must not succeed
2. **Idempotency and replay safety**
   - duplicate webhook deliveries never duplicate entitlements
   - duplicate client POSTs with same Idempotency-Key return stable results
3. **Deterministic entitlement eligibility**
   - eligibility depends only on server-side truth (entitlement state + policy + artifact metadata)
4. **Fulfillment security**
   - tokens/URLs expire; replay fails; revocation blocks new authorizations
5. **Auditability**
   - for any purchase, you can trace: order → paymentEvents → entitlementEvents → fulfillmentEvents

### 1.2 “Done” definition for v1
SpecPrompt v1 is “done” when the acceptance criteria in §10 pass and release gates in §9 are satisfied on staging.

### 1.3 Test pyramid (recommended)
- **Unit tests (MUST):** pure logic and deterministic utilities
- **Integration tests (MUST):** API + DB + processing pipelines (mock payment provider where needed)
- **E2E tests (SHOULD):** a small number of golden-path flows (may run nightly)
- **Security tests (MUST):** IDOR + webhook spoofing + token replay + leakage scans

---

## 2) Environments & prerequisites

### 2.1 Environments
- **Local dev**
  - Mock payment provider events and signature verification keys.
  - Use local artifact storage (or stubbed storage signer).
- **Staging**
  - Uses staging payment provider environment (or still mock provider but with real signature verification code paths).
  - Uses a real object storage bucket (recommended) for signed URL behavior testing.
- **Production**
  - Only run non-destructive smoke tests.

### 2.2 Identity and auth prerequisites
- A stable external identity (`externalUserId`) is available.
- Tests must be able to:
  - create two distinct users A and B,
  - acquire valid auth tokens for both,
  - call authenticated endpoints as each.

### 2.3 Payment provider prerequisites (staging)
One of the following must be available:
- A staging provider environment (e.g., Stripe test mode) with webhook signing secret configured, OR
- A deterministic “provider webhook test harness” that:
  - signs payloads using the same verification library/code path,
  - can emit duplicate/out-of-order events.

### 2.4 Artifact storage prerequisites
Pick one:
- **Signed URL mode**: a storage signer available in staging (R2/S3).
- **Token + proxy download mode**: a download endpoint that streams from storage and enforces token rules.

---

## 3) Unit test plan (REQUIRED)

Unit tests must be fast, deterministic, and not depend on external services.

### 3.1 Eligibility policy evaluator (MUST)
Test a pure function that answers:
- `isArtifactEligible(entitlement, artifact) -> boolean`

Cases:
- **P1 one_time_major**
  - major matches ⇒ eligible
  - major mismatch ⇒ not eligible
- **P2 subscription_updates_while_active**
  - active (eligibleThroughMs null) ⇒ eligible for any released artifact (up to “now” semantics)
  - ended with eligibleThroughMs:
    - artifact releasedAtMs <= eligibleThroughMs ⇒ eligible
    - artifact releasedAtMs > eligibleThroughMs ⇒ not eligible
- Withdrawn artifacts:
  - if artifact.status = withdrawn, default expected: not eligible for new fulfillment (documented policy)
  - ensure behavior matches chosen rule

### 3.2 Idempotency-Key hashing/normalization (MUST)
Test deterministic request hashing for idempotency enforcement:
- same semantic JSON, different key order ⇒ same hash (if you normalize)
- same idempotency key, different payload hash ⇒ triggers CONFLICT classification

### 3.3 Webhook envelope parsing (MUST)
Given a verified webhook payload (already verified), ensure:
- providerEventId extraction works
- event type mapping logic classifies events into a small set of internal intents:
  - payment_succeeded
  - payment_failed
  - refund
  - dispute
  - subscription_canceled/unpaid

Out-of-order classification:
- “refund after success” yields a revocation intent
- “success after refund” is handled deterministically (documented policy; typically remains revoked/inactive unless a new purchase occurs)

### 3.4 Download token generation and verification helpers (MUST, if token mode exists)
- token generation:
  - sufficient entropy (test length/format constraints, not randomness)
- token hashing:
  - stable hash for same token bytes
  - hash is not reversible (cannot test reversibility; test that raw token is not persisted)
- expiry logic:
  - now > expiresAtMs ⇒ expired
- single-use enforcement transitions (logic-level)

### 3.5 Normalized error envelope helpers (MUST)
- errors always include:
  - `error.code`, `error.message`, `error.requestId`
- validation errors include `details.fields[]` with correct field names
- no internal stack traces in `message`

### 3.6 URL allowlist validation (MUST)
If checkout supports `successUrl`/`cancelUrl`:
- allowlisted host passes
- non-https fails (except explicit dev bypass flag)
- open-redirect attempts fail (e.g., `https://trusted.com.evil.com/`)

---

## 4) Integration test plan (REQUIRED)

Integration tests validate behavior across API + DB + processing pipeline.

### 4.1 Checkout creation (MUST)
Test `POST /v1/checkout`:
- creates an order in `pending_payment`
- returns checkout session info (provider, checkoutUrl/sessionId)
- enforces idempotency:
  - same `Idempotency-Key` and same payload returns the same `orderId`
  - same `Idempotency-Key` and different payload returns `CONFLICT`
- validates URL allowlist
- rate limit behavior (basic):
  - repeated spam calls lead to `RATE_LIMITED` (if implemented)

### 4.2 Webhook verification (MUST)
Test webhook endpoint `POST /v1/webhooks/payment`:
- invalid signature ⇒ `WEBHOOK_VERIFICATION_FAILED` and **no DB state changes**
- valid signature ⇒ records payment event and returns `{ok:true}`
- raw body handling:
  - ensure verification uses raw bytes (hard to assert directly; infer by using payloads that break if re-serialized)
- bounded storage:
  - stored event summary is bounded
  - raw body is not stored unbounded (verify absence of raw full body field if applicable)

### 4.3 Webhook idempotency (MUST)
- send the exact same valid webhook twice (same providerEventId):
  - second call returns `{ok:true}`
  - does not create a second paymentEvent row
  - does not create a second entitlement grant event
- if your design stores `processedAtMs`:
  - verify it is set once and not duplicated

### 4.4 Order state transitions (MUST)
Construct a typical one-time purchase flow:
1. Create checkout → order pending
2. Send payment_succeeded webhook → order becomes paid
3. List orders → contains order with paid status

Construct subscription flow:
1. Create checkout with subscription plan
2. Send subscription_active / invoice_paid webhook(s) → order becomes active
3. Send subscription_canceled webhook → order becomes canceled (or entitlement inactive) per policy

Out-of-order:
- cancellation event arrives before activation event:
  - system converges to deterministic final state (documented policy)
  - no entitlement duplication
  - order state does not oscillate unpredictably

### 4.5 Exactly-once entitlement issuance (MUST)
Given a payment success:
- entitlement is created or updated exactly once for `(userId, productId)`
- repeated payment success webhook (duplicate providerEventId) does not create duplicate entitlements
- if multiple events refer to the same purchase:
  - entitlement remains a single current record (if that’s your model)
  - entitlementEvents are deduped by a stable dedupeKey (recommended)

### 4.6 Refund/dispute revocation (MUST)
- After entitlement is active:
  - send refund webhook ⇒ entitlement becomes revoked/inactive (per policy)
  - new fulfillment authorizations are denied deterministically:
    - `ENTITLEMENT_INACTIVE` or `ARTIFACT_NOT_ELIGIBLE` (choose one for this case and stay consistent)
- Ensure revocation is auditable:
  - entitlementEvents appended
  - payment event recorded
  - no deletion of prior records

### 4.7 Fulfillment authorization (MUST)
Test `POST /v1/fulfillment/token`:
- with active entitlement and eligible artifact ⇒ returns signed URL or token
- with inactive entitlement ⇒ denied (correct error code)
- with non-eligible artifact (e.g., different major) ⇒ denied (`ARTIFACT_NOT_ELIGIBLE`)
- idempotency:
  - same Idempotency-Key + same payload returns same authorization response
  - same key + different payload returns `CONFLICT`

### 4.8 Download token redemption (MUST if token+proxy mode exists)
Test `GET /v1/fulfillment/download?token=...`:
- valid token downloads content successfully
- single-use:
  - second redemption fails deterministically (recommended: NOT_FOUND to reduce enumeration)
- expiry:
  - after expiry, redemption fails deterministically (`DOWNLOAD_TOKEN_EXPIRED` or NOT_FOUND per policy)
- revocation:
  - revoked token fails deterministically
- defense-in-depth (if auth required in addition to token):
  - token used by wrong user fails

### 4.9 Signed URL mode validation (MUST if signed URL mode exists)
- signed URL expires:
  - after expiry, storage returns failure (403/401 depending on provider)
- signed URL is not logged:
  - validate logs do not contain query signatures (see §6.4 leakage scan)

Note: if you can’t reliably test storage expiry in CI, test:
- signer output includes an `expiresAtMs` and TTL bounds,
- minted URLs are short-lived by configuration,
and run a nightly staging test for actual expiry.

---

## 5) End-to-end (E2E) test plan (SHOULD)

E2E tests validate the full user experience across system boundaries.

### 5.1 E2E-01: One-time purchase → entitlement → download
1. User signs in
2. Create checkout session
3. Complete payment (provider test harness)
4. Webhook delivered/processed
5. Entitlement visible in `/v1/entitlements`
6. Fulfillment authorization succeeds and download works

### 5.2 E2E-02: Subscription active → updates while active
1. User purchases subscription plan
2. Entitlement policy is subscription_updates_while_active
3. A new artifact is released
4. Fulfillment authorization works while subscription active
5. Subscription canceled
6. Artifact released after eligibleThroughMs is not eligible

### 5.3 E2E-03: Refund → entitlement revoked → download blocked
1. Active entitlement exists
2. Refund event delivered
3. New fulfillment denied
4. Existing token behavior matches policy:
   - if proxy mode checks entitlement at download time: block
   - if signed URL issued earlier: URL may still work until expiry; ensure TTL is short

---

## 6) Security-focused test suite (REQUIRED)

### 6.1 Tenant isolation / IDOR tests (MUST)
Using two users A and B:

Orders:
- B cannot `GET /v1/orders/:orderIdOfA`
  - response MUST be `NOT_FOUND` (recommended) or consistent denial policy
- B cannot infer existence via timing/side channels (best-effort; ensure same envelope shape)

Entitlements:
- B cannot read A’s entitlements via list or any get-by-id endpoint (if any exists)
- `GET /v1/entitlements/check?productId=...` only checks current user

Tokens:
- If token redemption requires auth binding:
  - B cannot redeem A’s token successfully
- If token redemption is token-only (not recommended):
  - enforce strict single-use + short TTL + aggressive rate limiting and record this as a risk; add tests accordingly

### 6.2 Webhook spoofing tests (MUST)
- Invalid signature:
  - returns `WEBHOOK_VERIFICATION_FAILED`
  - does not create paymentEvent rows
  - does not mutate orders or entitlements
- Payload tampering:
  - change one byte in body, keep signature ⇒ verification fails
- Replay:
  - same providerEventId delivered twice ⇒ no duplicate side effects

### 6.3 Confused deputy protections (MUST)
SpecPrompt MUST NOT provide any endpoint that:
- checks entitlement by email/username for third parties
- allows client-side assertions to mark orders paid
- returns sensitive provider payloads

Write tests that ensure:
- no endpoint exists (or rejects) for “check entitlement for arbitrary user”
- admin-only endpoints require admin auth and cannot be invoked by normal users

### 6.4 Secrets leakage tests (MUST)
Automated scan of logs and persisted records for common secret patterns:
- Verify the following never appear in:
  - response bodies
  - logs
  - stored JSON fields
- Patterns:
  - `Stripe-Signature`
  - `Authorization: Bearer`
  - `token=` for download tokens (if token in URL exists)
  - storage signed URL query params like `X-Amz-Signature` (S3) or equivalent
  - webhook secret string (test config should include a known marker value and ensure it never appears)

### 6.5 Rate limiting / abuse tests (SHOULD; MUST if public)
- brute-force token redemption attempts are rate-limited
- repeated checkout creation attempts are rate-limited
- webhook endpoint rate limiting does not break legitimate provider delivery (if you rate limit webhooks, ensure allowlist by provider IPs or high thresholds)

---

## 7) Resilience and failure-mode tests (REQUIRED)

### 7.1 Partial failures during webhook processing
Simulate:
- event verified and inserted
- processing fails mid-way (e.g., before entitlement issuance)
Then:
- retry processing (or replay webhook) results in:
  - eventual consistent order state
  - entitlement issued exactly once
  - no duplication

### 7.2 Concurrency and races
Simulate:
- two webhook deliveries concurrently (same providerEventId)
Expected:
- only one paymentEvent row exists
- only one entitlement issuance occurs
- final order state is correct

Simulate:
- concurrent client POSTs with same Idempotency-Key
Expected:
- one order created
- others return stored response, not duplicates

### 7.3 Storage/signing failures
If signed URL mode:
- signer failure returns `PAYMENT_PROVIDER_ERROR` or `INTERNAL`? (choose a stable code for “fulfillment provider error”, recommended: `INTERNAL` or a dedicated `FULFILLMENT_PROVIDER_ERROR`)
- ensure failure is safe and auditable (fulfillmentEvents denied recorded optionally)

If proxy mode:
- storage fetch failure yields deterministic error without leaking internal details.

---

## 8) Performance and load testing (recommended)
Not required for v1 sign-off, but recommended baselines:
- webhook endpoint can process bursts (provider retries) without timeouts
- fulfillment token minting can handle normal usage
- list endpoints paginate efficiently

---

## 9) Release gates (must-pass checklist)

Before declaring SpecPrompt v1 ready:
- [ ] Unit tests pass (eligibility, idempotency hashing, token helpers).
- [ ] Integration tests pass:
  - checkout idempotency
  - webhook verification + idempotency
  - entitlement exactly-once issuance
  - refund/chargeback revocation
  - fulfillment authorization (and download path if proxy mode)
- [ ] Security suite passes:
  - IDOR suite
  - webhook spoofing suite
  - secrets leakage scan
- [ ] Staging smoke run:
  - complete one golden purchase → entitlement → fulfillment flow end-to-end
- [ ] Manual review: no endpoints violate “entitlement ≠ authorization” boundary.

---

## 10) Acceptance criteria (system-level definition of done)

SpecPrompt v1 is accepted when all of the following are true:

### 10.1 Webhook integrity and idempotency are proven
- Forged webhooks cannot mutate state.
- Duplicate webhooks (same providerEventId) do not:
  - duplicate entitlements,
  - duplicate ledger events beyond idempotent markers,
  - corrupt order state.

### 10.2 Entitlement correctness is proven under retries and out-of-order events
- One-time purchase yields exactly one active entitlement for the product.
- Subscription purchase yields active entitlement while subscription is active.
- Refund/chargeback/cancellation yields deterministic revocation/inactivation.
- Eligibility policies behave deterministically:
  - major-version gating works
  - subscription “eligibleThroughMs” cutoff works

### 10.3 Fulfillment security is proven
- Fulfillment authorization requires an active entitlement and eligibility.
- Download tokens / signed URLs are time-bounded.
- Token replay is denied (single-use or equivalent policy).
- Revocation blocks new fulfillment authorizations deterministically.
- Token or signed URL secrets are not leaked to logs.

### 10.4 Tenant isolation (IDOR) is proven
- User B cannot access User A’s orders/entitlements/tokens.
- Cross-tenant resource access behaves as NOT_FOUND (recommended) consistently.

### 10.5 Auditability is real
For a single purchase you can trace, using stored records:
- order creation (pending)
- verified payment event(s)
- order transition (paid/active)
- entitlement grant event and current entitlement state
- fulfillment authorization and delivery/denial events
All without storing unbounded raw webhook bodies or sensitive payment instrument details.

---

## 11) Appendix: Minimal test matrix (quick reference)

### Unit (MUST)
- Eligibility policies:
  - one_time_major
  - subscription_updates_while_active
- Idempotency hashing and conflict detection
- Token hashing + expiry logic (if token mode)
- URL allowlist validator

### Integration (MUST)
- Checkout idempotency
- Webhook verification + dedupe
- Exactly-once entitlement issuance
- Refund/dispute revocation
- Fulfillment authorization correctness

### Security (MUST)
- IDOR suite (A vs B)
- Webhook spoofing suite
- Secrets leakage scan
- Token replay suite (if token mode)

### E2E (SHOULD)
- One-time purchase → entitlement → download
- Subscription active → updates eligibility
- Refund → revocation blocks fulfillment