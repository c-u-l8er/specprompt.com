# ADR-0004: Fulfillment Mode — Token + Proxy Download with Entitlement Re-Checks (SpecPrompt)
- **Status:** Accepted
- **Date:** 2026-02-01
- **Owners:** Engineering
- **Decision scope:** How SpecPrompt authorizes and delivers downloadable fulfillment artifacts in v1.

- **Related specs:**
  - `project_spec/spec_v1/00_MASTER_SPEC.md` (Flows E/F; fulfillment invariants)
  - `project_spec/spec_v1/10_API_CONTRACTS.md` (§12 Fulfillment; token shape; optional proxy endpoint)
  - `project_spec/spec_v1/30_DATA_MODEL_CONVEX.md` (`downloadTokens`, `fulfillmentEvents`, `entitlements`)
  - `project_spec/spec_v1/40_SECURITY_SECRETS_COMPLIANCE.md` (secrets handling; safe logging)
  - `project_spec/spec_v1/60_TESTING_ACCEPTANCE.md` (revocation + fulfillment tests)
  - `project_spec/spec_v1/adr/ADR-0001-webhook-integrity-and-idempotency.md` (ledger/idempotency expectations)

---

## Context

SpecPrompt is the portfolio’s commerce layer. It must deliver “digital goods” (artifacts, spec packs, bundles) to users who have valid entitlements. Fulfillment is security- and revenue-critical because:

- Users and crawlers can share links.
- Webhooks can later revoke purchase validity (refunds, disputes, subscription cancellation).
- Object storage signed URLs are bearer links that, once issued, cannot be revoked by SpecPrompt unless the URL expires or the storage layer supports immediate revocation of individual URLs (typically it does not).

The master spec permits two patterns in v1:

- Pattern F1: signed URL minting (simpler, but weak revocation once URL is minted).
- Pattern F2: SpecPrompt download proxy (token authorizes a server-controlled download path).

We must pick one for v1 to prevent implementation drift and to lock the revocation semantics.

---

## Decision

### 1) SpecPrompt v1 fulfillment MUST use **token + proxy download** (normative)

SpecPrompt v1 MUST implement fulfillment as:

1. User requests authorization for a specific artifact.
2. SpecPrompt mints a **time-bounded, opaque download token** (short TTL).
3. Client redeems token via a SpecPrompt **download endpoint** that streams the artifact.
4. SpecPrompt MUST re-check entitlement and token validity at redemption time.

Pattern F1 (signed URL minting) is NOT the default v1 fulfillment mode and MUST NOT be used for core artifact delivery unless explicitly added in a later ADR.

Rationale:
- Proxy delivery allows immediate revocation enforcement at download time.
- Token leakage blast radius is bounded (short TTL) and revocable.
- SpecPrompt remains authoritative for access control, audits, and rate limiting.

---

## Normative requirements

### 2) Token minting endpoint (authorization step)

SpecPrompt MUST expose an authenticated endpoint (see `10_API_CONTRACTS.md §12.1`) that:

- Requires user authentication.
- Accepts `artifactId` (and optionally `productId` / version constraint per API contracts).
- Verifies:
  - The artifact exists and is deliverable.
  - The caller has an **active entitlement** that makes the artifact eligible.
  - The entitlement is not revoked/inactive.
- Mints a download token with:
  - `token` (opaque bearer string returned to the client)
  - `downloadTokenId` (internal id) and status tracked server-side
  - `userId` and `artifactId` binding
  - `expiresAtMs`
  - `singleUse = true` (v1 default)
- Emits an append-only `fulfillmentEvents` entry for minting (see §6).

Idempotency:
- The mint endpoint MUST accept `Idempotency-Key` and MUST detect “same idempotency key, different payload” as `CONFLICT`.
- A retry with the same key and same request hash SHOULD return the same token response (or a deterministically re-minted equivalent) without duplicating ledger effects.

### 3) Token redemption endpoint (download step)

SpecPrompt MUST expose a download endpoint (see `10_API_CONTRACTS.md §12.2`) that:

- Accepts the opaque token (query string or header, per API contract).
- Validates token state:
  - token exists
  - status is `issued`
  - current time < `expiresAtMs`
  - (if `singleUse`) token has not been redeemed
- Re-checks authorization at redemption time (MUST):
  - The token is bound to `userId` and `artifactId`.
  - The request is performed by the same authenticated user OR the token is explicitly defined as bearer-only.
  - The user still has an active entitlement for the artifact.
  - The order/entitlement has not been refunded/charged back/canceled in a way that revokes eligibility.

Delivery:
- On success, SpecPrompt streams bytes from artifact storage to the client.
- SpecPrompt SHOULD support `Range` requests for large artifacts (recommended; not required for correctness in v1).
- SpecPrompt MUST set safe download headers (e.g., `Content-Type`, `Content-Disposition`) based on server-side artifact metadata, not client input.

Single-use semantics (v1 default):
- If `singleUse = true`, SpecPrompt MUST atomically transition token status:
  - `issued` → `redeemed`
  - and reject subsequent redeems deterministically.
- To avoid token enumeration and information leakage, subsequent redeems SHOULD return `NOT_FOUND` or `DOWNLOAD_TOKEN_INVALID` consistently (choose one across the service).

### 4) Revocation semantics (refunds / disputes / subscription end)

SpecPrompt MUST treat the following as revocation triggers (policy is driven by verified provider events per `ADR-0001`):

- Refund events → entitlement becomes `revoked` or `inactive` (per product policy) and downloads are denied.
- Dispute/chargeback → entitlement becomes `revoked` and downloads are denied immediately.
- Subscription canceled/unpaid → entitlement becomes `inactive` and downloads are denied unless eligibility policy explicitly allows access after end date (generally no for “updates while active”).

Critical rule:
- Revocation MUST apply at download time. Even if a token was minted before revocation, redemption MUST fail if entitlement is no longer valid.

### 5) TTL and leakage model

- Download tokens MUST be short-lived.
  - Recommended v1 default TTL: 5–15 minutes.
- Tokens MUST be opaque and unguessable:
  - minimum 128 bits of entropy; 192–256 bits recommended
  - URL-safe encoding is recommended
- Tokens MUST NOT embed secrets, order metadata, or upstream credentials.

Storage:
- Prefer storing only a hash of the token (e.g., `sha256(token)`), never the raw token, to minimize leakage impact.
- If hashing is used, comparisons MUST be constant-time best effort.

Logging:
- Tokens MUST NOT appear in logs (including query strings) in production logs.
- Webhook bodies, payment instrument data, and storage signed URLs MUST NOT be logged.

### 6) Auditability: fulfillment events ledger

SpecPrompt MUST write append-only fulfillment audit events to `fulfillmentEvents` for at minimum:

- `FULFILLMENT_TOKEN_MINTED` (token issued)
- `FULFILLMENT_DOWNLOAD_STARTED` (optional but recommended)
- `FULFILLMENT_DOWNLOAD_SUCCEEDED`
- `FULFILLMENT_DOWNLOAD_DENIED` (include safe denial reason code, not secrets)
- `FULFILLMENT_TOKEN_REDEEMED` (for single-use tokens)

Dedupe/idempotency:
- `FULFILLMENT_TOKEN_MINTED` should be deduped by mint request idempotency key.
- Download-related events should be safe under retries; consider a stable request id hash to avoid unbounded duplicates.

Data minimization:
- Fulfillment events MUST NOT store raw user agent strings unbounded; store bounded hashes or truncated strings if needed.
- Fulfillment events MUST NOT store artifact bytes, URLs containing tokens, or storage credentials.

---

## Consequences

### Positive
- Enforces revocation at the moment of download (refund/dispute/subscription end becomes effective immediately).
- Centralizes authorization checks in SpecPrompt, reducing accidental entitlement bypass.
- Enables consistent rate limiting, abuse detection, and audit trails.
- Keeps object storage access private; clients never directly access storage credentials.

### Tradeoffs / costs
- Higher operational load: SpecPrompt serves download bytes (bandwidth + latency).
- Requires streaming implementation and careful header handling.
- Range requests and large-file support may require additional engineering (recommended).

---

## Alternatives considered

### A) Signed URL minting (Pattern F1)
Rejected for v1 default because:
- Cannot revoke already-issued URLs reliably; revocation relies on extremely short TTLs.
- “Link sharing” becomes harder to control and audit.
- Makes refund/chargeback semantics weaker (users may still download if they already have the URL).

Allowed later only via explicit ADR that locks TTL, storage provider, and revocation posture, and documents the risk acceptance.

### B) Signed token locally verified by storage/CDN
Deferred. Could reduce bandwidth on SpecPrompt, but increases key distribution/rotation complexity and still risks “revocation gap” depending on caching behavior.

---

## Implementation notes (guidance)

- Token binding:
  - v1 minimum: bind to `userId` + `artifactId` server-side.
  - Optional hardening: also bind to `orderId` or `entitlementId`, and store an `issuedForEntitlementStatusVersion` to detect state changes.
- To avoid logging query tokens, prefer passing token in an `Authorization: Bearer <token>` header for the download endpoint if your client supports it. If query string is used, ensure logging middleware redacts it.
- Consider returning `NOT_FOUND` for invalid/expired tokens to reduce enumeration.

---

## Acceptance criteria (this ADR is satisfied when)

1. A user with an active entitlement can:
   - mint a download token for an eligible artifact
   - redeem it successfully via SpecPrompt proxy download
   - see a fulfillment audit trail in `fulfillmentEvents`

2. A refunded/chargeback purchase causes:
   - entitlement revoked/inactive deterministically (via verified webhooks)
   - download redemption denied even if the token was minted before revocation

3. Token safety:
   - tokens expire and cannot be redeemed after `expiresAtMs`
   - single-use tokens cannot be redeemed twice
   - tokens are not logged and are not stored in plaintext (hash preferred)

4. Retry safety:
   - mint endpoint is idempotent with `Idempotency-Key`
   - download endpoint is safe under retries and does not create ambiguous state

---