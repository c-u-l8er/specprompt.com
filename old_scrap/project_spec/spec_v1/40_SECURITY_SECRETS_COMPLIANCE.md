# specprompt.com — Security, Secrets, and Compliance (v1)
Version: 1.0  
Status: Draft (normative once adopted)  
Audience: Engineering  
Last updated: 2026-01-31

SpecPrompt is the portfolio’s **commerce/monetization layer** (Layer 6). This document defines the v1 security posture and implementation-grade requirements for:
- **tenant isolation**
- **webhook integrity**
- **secrets handling**
- **fulfillment token safety**
- **logging/auditability**
- a pragmatic v1 compliance posture (not a certification claim)

Normative language:
- **MUST / MUST NOT / SHOULD / MAY** are used intentionally.

---

## 1) Security objectives (what we protect)

### 1.1 Primary assets (v1)
1. **Entitlement correctness**
   - Who has access to what product/artifact/version, and when that access starts/ends.
2. **Order correctness**
   - The order state machine must reflect verified payment reality (not client claims).
3. **Fulfillment integrity**
   - Downloads/licenses must only be deliverable to eligible users, with revocation support.
4. **Webhook integrity**
   - Only authentic payment-provider events may mutate commerce state.
5. **Confidentiality of secrets**
   - Payment provider secrets, webhook secrets, storage signing credentials, internal auth keys.

### 1.2 Core security goals (v1)
SpecPrompt v1 MUST:
- Enforce **tenant isolation** on every read and write.
- Prevent **webhook spoofing** from minting entitlements or moving orders.
- Prevent **token leakage/replay** from granting unauthorized downloads.
- Prevent **information leakage** (ID existence, payment metadata, secret values).
- Provide **auditability** for all state transitions, without storing sensitive payloads.

### 1.3 Explicit security boundaries
SpecPrompt is a **commerce plane** only.
- SpecPrompt MUST NOT execute WHS agent invocations.
- SpecPrompt MUST NOT execute Agentromatic workflows.
- SpecPrompt MUST NOT treat entitlements as authorization for:
  - joining Agentelic telespaces
  - acting as Delegatic org member/admin
  - running privileged operations in other products

---

## 2) Threat model (practical)

### 2.1 Actors
- **A1: Legitimate buyer** (authenticated user)
- **A2: Legitimate admin** (operator with elevated access)
- **A3: Malicious user** (authenticated but trying to steal access)
- **A4: Unauthenticated attacker** (internet-level attacker)
- **A5: Bot/scraper** (abuse / brute force / enumeration)
- **A6: Compromised dependency / supply chain attacker**
- **A7: Compromised payment provider account or leaked webhook secret**

### 2.2 Attack surfaces
- Public HTTP endpoints (if any)
- Authenticated HTTP endpoints:
  - checkout creation
  - orders/entitlements listing
  - fulfillment authorization
  - download-by-token (if implemented)
- Webhook endpoint
- Admin endpoints (if present)
- Storage (artifact bucket), signed URL minting
- Logs and error reporting sinks
- Configuration and environment variables

### 2.3 Required mitigations (v1)
This section enumerates required mitigations aligned to a minimal v1.

#### T1: Cross-tenant access (IDOR)
**Threat:** User B reads/uses User A’s `orderId`, `entitlementId`, `downloadToken` or `artifactId` to steal access.

**Mitigations (MUST):**
- Every user-facing read MUST validate ownership via server-resolved `userId`.
- The system MUST apply an IDOR-safe error strategy:
  - recommended: return `NOT_FOUND` when a resource is not owned/visible.
- Any token redemption MUST bind the token to the user (or require auth + token) unless explicitly designed otherwise.

#### T2: Webhook spoofing / payment event tampering
**Threat:** Attacker forges a webhook request to mark an order as paid/active and mint entitlements.

**Mitigations (MUST):**
- Verify webhooks using provider-recommended signature verification over **raw request bytes**.
- Reject unverified webhooks without state changes.
- Dedupe by `(provider, providerEventId)` and process idempotently.
- Do not trust client-supplied `orderId` in webhook payloads unless cryptographically bound (e.g., server-set provider metadata).

#### T3: Token replay / leakage in fulfillment
**Threat:** Download token leaks (logs, referrers, browser history). Attacker reuses it to download artifacts.

**Mitigations (MUST):**
- Tokens MUST be time-bounded (`expiresAtMs`) and revocable.
- Prefer storing only a **hash** of tokens; never store raw tokens.
- Single-use tokens SHOULD be enabled by default.
- If download is via signed URL, signed URLs MUST be short-lived and never logged.

#### T4: Secret leakage via logs/errors/analytics
**Threat:** Webhook secret, provider API key, storage credentials, or sensitive payment payload leaks.

**Mitigations (MUST):**
- Do not log secrets.
- Do not store raw webhook bodies unbounded.
- Errors returned to clients must be safe and must not contain secrets or raw provider payloads.
- Redact common secret patterns in logs (best-effort).

#### T5: Confused deputy / cross-system privilege widening
**Threat:** A user convinces SpecPrompt to grant entitlements or perform fulfillment that effectively grants privileges in other systems.

**Mitigations (MUST):**
- SpecPrompt entitlements MUST be treated strictly as commercial rights.
- If SpecPrompt integrates with other products:
  - integration MUST be server-to-server
  - effects MUST be audited
  - integration MUST NOT bypass the other product’s authorization checks

#### T6: Abuse / DoS
**Threat:** Attackers spam checkout creation or fulfillment endpoints, causing cost/availability issues.

**Mitigations (SHOULD, and MUST if exposed broadly):**
- Rate limit:
  - checkout creation
  - fulfillment token minting
  - download attempts
  - webhook endpoint (careful: don’t break provider delivery; rate limit by provider IP ranges where possible)
- Add quotas per user and per IP (or equivalent signals).

#### T7: SSRF/open-redirect via checkout URLs
**Threat:** Malicious `successUrl`/`cancelUrl` can be used for open redirect or phishing, or to abuse internal infrastructure.

**Mitigations (MUST):**
- Validate return URLs against an allowlist of origins/hosts controlled by you.
- Reject non-https URLs (except local dev if explicitly allowed behind a dev flag).

---

## 3) Authentication & identity security

### 3.1 User authentication (required)
- All user-facing endpoints MUST require authenticated requests via `Authorization: Bearer <JWT>`.
- The system MUST map the authenticated identity to a stable internal `users` row (`externalId -> users._id`) server-side.

### 3.2 Session security
- Only accept tokens from the expected issuer(s).
- Enforce reasonable clock skew tolerance for JWT verification (implementation detail).
- Reject missing/invalid auth tokens with `UNAUTHENTICATED`.

### 3.3 Identity mapping invariants
- `externalId` MUST be unique.
- The mapping MUST be centralized so all endpoints share consistent semantics.

---

## 4) Authorization and tenant isolation (IDOR posture)

### 4.1 Tenant model (v1 baseline)
v1 is **user-scoped**:
- Orders, entitlements, download tokens, and fulfillment events are owned by a single `userId`.

Org-scoped entitlements are deferred to later versions (Delegatic integration).

### 4.2 Required authorization checks (MUST)
For any resource fetched by id:
- The server MUST load the resource and verify ownership matches `currentUserId`.
- If not owned, respond in an IDOR-safe way (recommended: `NOT_FOUND`).

### 4.3 Admin operations (if implemented)
Admin endpoints MUST:
- be strictly gated (allowlist / role mapping / separate admin identity provider group)
- never be exposed to standard users
- be audited with append-only events
- avoid returning more data than necessary (especially provider data)

---

## 5) Secrets strategy (normative)

### 5.1 Core rule (MUST)
SpecPrompt MUST NOT store plaintext secrets in:
- the primary database
- logs
- analytics events
- error envelopes returned to clients

### 5.2 Secret categories
**Category S1 — Payment provider secrets**
- webhook signing secret
- API keys / restricted keys
- connect/payout secrets (if introduced later)

**Category S2 — Storage credentials**
- object storage keys/roles
- signing keys used for signed URLs (if any)

**Category S3 — Internal service auth secrets**
- server-to-server auth keys for internal integrations (if any)

### 5.3 Secret storage and access (server-side only)
- Secrets MUST live in server-side environment/config (or a dedicated secrets manager).
- Secrets MUST NOT be shipped to clients.
- Secrets MUST NOT be returned by any endpoint.

### 5.4 Token storage (download tokens)
If SpecPrompt issues bearer tokens for downloads:
- Store only `tokenHashSha256` (or equivalent secure hash).
- Never store raw token value.
- Never log token value.
- Tokens MUST have `expiresAtMs` and a revocation path.

### 5.5 Redaction requirements (best-effort, deterministic)
Server logs and error reporting SHOULD:
- redact common secret-bearing keys/headers:
  - `authorization`, `cookie`, `set-cookie`, `x-api-key`, `api_key`, `token`, `secret`, `signature`
- redact known provider signature headers (e.g., `Stripe-Signature`)
- avoid logging raw request bodies for:
  - webhook endpoint
  - checkout creation
  - fulfillment token minting

---

## 6) Webhook integrity (payment provider → SpecPrompt)

### 6.1 Verification is mandatory (MUST)
Webhook endpoint MUST:
1. Read raw request body bytes.
2. Verify signature using provider’s library/algorithm over raw bytes (no re-serialized JSON).
3. Reject failures with `WEBHOOK_VERIFICATION_FAILED`.
4. Only after verification:
   - parse payload
   - extract provider event id/type
   - store a bounded, safe subset + optional raw body hash for correlation

### 6.2 Idempotency and replay safety (MUST)
- Webhook processing MUST be idempotent by `(provider, providerEventId)`.
- Duplicate events MUST not:
  - issue duplicate entitlements
  - transition order state incorrectly
  - mint duplicate “grant events” without dedupe keys

### 6.3 Provider-to-order binding (MUST)
SpecPrompt MUST be able to map verified provider events to internal `orders` without trusting client assertions.

Recommended approach:
- When creating provider checkout session, set provider metadata with:
  - `orderId` (internal id) OR a stable, unguessable correlation id created server-side
- On webhook, extract metadata and resolve the order.

If metadata is unavailable:
- map via server-stored provider object ids:
  - `checkoutSessionId`, `subscriptionId`, `invoiceId`, etc.

### 6.4 Minimal stored event data (MUST)
Persist only:
- provider event id, type, verified timestamp
- correlated provider object ids (customer/subscription/checkout session)
- minimal amounts/currency if needed
- `rawBodySha256` (optional)
- a bounded summary object

Do NOT persist:
- full raw body unbounded
- full customer PII beyond what is necessary
- payment method details

---

## 7) Entitlement safety model

### 7.1 Entitlements are not authorization (MUST)
- Entitlements MUST NOT be interpreted as membership, admin rights, or runtime permissions in other products.
- If another product checks entitlements, it MUST still enforce its own authz.

### 7.2 Eligibility evaluation is server-side (MUST)
Eligibility policy evaluation MUST:
- be deterministic
- rely only on server-side data:
  - entitlement state + policy
  - artifact metadata (version/major/releasedAt)
- never trust client provided “eligibleThrough” or “major” claims

### 7.3 Revocation behavior (MUST)
Revocation triggers:
- refunds
- chargebacks
- subscription cancellation/unpaid (per policy)

Revocation MUST:
- be durable and auditable (append-only event record)
- immediately block new fulfillment authorizations
- invalidate active download tokens if feasible (recommended):
  - either explicitly revoke tokens, or
  - enforce entitlement check at download time (proxy mode)

---

## 8) Fulfillment security (downloads, tokens, signed URLs)

### 8.1 Preferred fulfillment mode (v1 default)
SpecPrompt v1 default fulfillment mode is:
- Mint short-lived **download tokens** and use a **download proxy** endpoint (Pattern B).

Signed URLs (Pattern A) are optional in v1 and MUST NOT be used as the default fulfillment mode unless explicitly accepted in a later ADR.

All fulfillment modes MUST be time-bounded and auditable.

### 8.2 Token/URL lifetimes (MUST)
- Download tokens MUST expire quickly (minutes recommended; v1 default should be very short).
- If signed URLs are used (optional v1), they MUST expire quickly (minutes recommended).
- Long-lived links MUST NOT be used in v1.

### 8.3 Avoid token leakage via URL query params (SHOULD)
If using tokens:
- Avoid putting tokens in URLs when possible (e.g., Authorization header).
If token-in-URL is used:
- ensure tokens are short-lived and single-use
- ensure `Referrer-Policy` is strict at the UI layer to reduce leakage (implementation detail)

### 8.4 Download endpoint hardening (MUST if implemented)
If implementing `GET /v1/fulfillment/download?token=...`:
- MUST validate token hash
- MUST validate expiry and status
- MUST enforce single-use semantics if enabled (transition to redeemed before streaming bytes)
- SHOULD require user auth in addition to token (defense-in-depth)
- MUST rate limit repeated failures to reduce token enumeration

---

## 9) Logging, auditability, and evidence

### 9.1 Audit events (MUST)
SpecPrompt MUST maintain append-only records for:
- payment events ingested/verified
- order state transitions
- entitlement events (granted/updated/revoked/inactivated)
- fulfillment authorization and delivery/denial events
- admin operations (if present)

### 9.2 Correlation (MUST)
Every request SHOULD have a `requestId` (or equivalent) that is:
- returned in error envelopes
- stored on ledger/audit events where relevant

### 9.3 Safe logging (MUST)
Logs MUST NOT include:
- webhook secret
- raw webhook bodies unbounded
- bearer tokens (auth tokens, download tokens)
- storage signed URLs (if they include signature query params)
- payment method details

---

## 10) Transport security and API hardening

### 10.1 TLS (MUST)
- All external endpoints MUST require HTTPS in production.

### 10.2 CORS (SHOULD)
- Restrict CORS to known origins for browser clients.
- Webhook endpoint SHOULD not require CORS (server-to-server), but must still be protected by signature verification.

### 10.3 Input validation (MUST)
- Validate all fields:
  - IDs: string, bounded
  - URLs (success/cancel): allowlist origins
  - quantities: bounded
  - TTLs: bounded
- Reject unknown fields where feasible (to reduce footguns and injection surfaces).

### 10.4 Normalized errors (MUST)
- Always return normalized error envelope.
- Do not leak internal stack traces or provider responses.

---

## 11) Compliance posture (v1)

### 11.1 What v1 aims for
SpecPrompt v1 aims for a pragmatic, supportable posture:
- correct ledgers and audit trails
- data minimization
- safe deletion/retention defaults

### 11.2 What v1 is NOT claiming
SpecPrompt v1 is not claiming certification (e.g., SOC 2, PCI DSS).
Instead:
- Use provider-hosted checkout to reduce PCI scope (recommended).
- Store minimal payment metadata and rely on provider for sensitive payment data.

### 11.3 PII handling
Assume PII exists (emails, names).
- Do not store more PII than needed.
- Ensure PII is not included in logs/analytics unredacted.

### 11.4 Retention (high-level requirements)
Retention rules MUST be explicitly defined before production, at minimum for:
- paymentEvents (minimal subset, long-lived)
- downloadTokens (short-lived; purge after expiry + audit window)
- idempotencyKeys (short TTL; purge)
- fulfillmentEvents / entitlementEvents (retain for support; define duration)

---

## 12) Security testing checklist (v1)

### 12.1 Tenant isolation (MUST)
- User B cannot read User A’s orders by id (IDOR-safe response).
- User B cannot read User A’s entitlements by id/list.
- User B cannot use User A’s download token to download.

### 12.2 Webhook spoofing (MUST)
- Invalid signature yields no state changes.
- Duplicate webhook event id does not re-issue entitlements.

### 12.3 Idempotency behavior (MUST)
- Same `Idempotency-Key` + same payload returns same result.
- Same `Idempotency-Key` + different payload returns `CONFLICT`.

### 12.4 Secrets leakage (MUST)
- Ensure logs do not contain:
  - webhook signature header
  - auth tokens
  - download tokens
  - signed URL query signatures
- Ensure DB does not store webhook secret or raw bodies unbounded.

### 12.5 Token replay (MUST if single-use)
- Redeeming a single-use token twice fails deterministically.
- Expired tokens are rejected.
- Revoked entitlements block new tokens.

### 12.6 Abuse controls (SHOULD)
- Rate limiting prevents:
  - checkout spam
  - fulfillment spam
  - download brute forcing

---

## 13) Security acceptance criteria (Definition of Done for this module)

SpecPrompt v1 security is “done” when:
1. **Webhook integrity proven**
   - forged webhooks cannot move order state or mint entitlements
   - duplicate events are idempotent and do not double-issue entitlements
2. **Tenant isolation proven**
   - a basic IDOR suite passes across orders/entitlements/tokens
3. **Secrets posture proven**
   - no secrets appear in logs, error envelopes, or persisted fields
4. **Fulfillment safety proven**
   - tokens/URLs expire and cannot be replayed to steal downloads
   - revocation blocks fulfillment deterministically
5. **Auditability proven**
   - you can trace: order → payment events → entitlement event → fulfillment event
   - with correlation ids and timestamps, without relying on provider dashboards

---