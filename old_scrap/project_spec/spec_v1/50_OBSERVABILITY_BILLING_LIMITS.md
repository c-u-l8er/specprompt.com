# specprompt.com — Observability, Retention, Abuse Controls, and Operational Limits (v1)
Version: 1.0  
Status: Draft (normative once adopted)  
Audience: Engineering  
Last updated: 2026-01-31

This document defines **SpecPrompt v1** operational requirements:
- **observability** (logs, metrics, tracing/correlation, audit/ledger events)
- **retention and deletion** (what we keep, for how long, and why)
- **anti-fraud / anti-abuse posture** for commerce and fulfillment
- **rate limits and operational limits** (bounded cost, bounded blast radius)

SpecPrompt is the portfolio’s **commerce/monetization layer** (Layer 6). It owns:
- Orders
- Verified payment events (append-only)
- Entitlements (current state + append-only entitlement events)
- Fulfillment authorization (download tokens/signed URLs) + fulfillment events (append-only)

SpecPrompt MUST NOT:
- execute agents/workflows
- mirror upstream telemetry or execution logs from other portfolio products
- store unbounded raw payment provider payloads or secrets

Related specs:
- `project_spec/spec_v1/00_MASTER_SPEC.md`
- `project_spec/spec_v1/10_API_CONTRACTS.md`
- `project_spec/spec_v1/30_DATA_MODEL_CONVEX.md`
- `project_spec/spec_v1/40_SECURITY_SECRETS_COMPLIANCE.md`
- `project_spec/spec_v1/60_TESTING_ACCEPTANCE.md`

Normative language:
- **MUST / MUST NOT / SHOULD / MAY** are used intentionally.

---

## 1) Goals and non-goals

### 1.1 Goals (v1 MUST)
1. **Detect and diagnose** failures in:
   - checkout creation
   - webhook verification and processing
   - entitlement issuance and revocation
   - fulfillment authorization and download delivery
2. **Prove correctness** with audit trails:
   - for any purchase, trace: order → payment events → entitlement events → fulfillment events
3. **Bound operational risk**:
   - prevent obvious abuse/spam of checkout/fulfillment endpoints
   - prevent token brute force / enumeration
   - protect webhook endpoint from accidental self-DoS while not breaking provider retries
4. **Support safe retention**:
   - keep enough data for support/audit
   - delete short-lived sensitive artifacts (tokens, idempotency keys) on a schedule

### 1.2 Non-goals (v1 MUST NOT)
- Perfect fraud prevention (v1 is “baseline” with strong integrity checks + rate limits)
- Building a full analytics warehouse
- Reconstructing provider-level accounting in SpecPrompt (provider remains authoritative for payments)

---

## 2) Canonical definitions (what we mean)

### 2.1 Units and concepts
- **Request**: one HTTP call to SpecPrompt.
- **Webhook event**: one payment provider event (identified by `providerEventId`).
- **Order**: SpecPrompt record of a purchase attempt and state machine.
- **Entitlement**: current state record granting rights to a user for a product.
- **Entitlement event**: append-only record of entitlement changes.
- **Fulfillment authorization**: minting a download token or signed URL.
- **Fulfillment event**: append-only record of authorization/delivery/denial.

### 2.2 Correlation IDs (required)
SpecPrompt MUST consistently produce and propagate:
- `requestId` (aka `X-Request-Id`)
- `orderId`
- `providerEventId` (from webhook payload)
- `providerCheckoutSessionId` / `providerSubscriptionId` / `providerCustomerId` (as applicable)
- `entitlementId` (or `(userId, productId)` in v1)
- `artifactId`
- `downloadTokenId` (if token mode is implemented)

These IDs MUST be treated as opaque identifiers and MUST NOT embed secrets.

---

## 3) Observability pillars (what we collect)

### 3.1 Logs (MUST)
SpecPrompt MUST produce structured, machine-parsable logs for:
- incoming requests (excluding raw bodies for sensitive routes)
- webhook verification failures (without leaking signature headers or raw body)
- payment event ingestion + processing outcomes
- order transitions
- entitlement issuance/revocation
- fulfillment authorization decisions and denials
- download token redemption attempts (if proxy mode exists)
- rate limit enforcement decisions
- admin actions (if any)

Logs MUST be:
- **safe** (no secrets, no tokens, no signed URL query params)
- **bounded** (truncate long strings, avoid dumping large JSON blobs)

### 3.2 Metrics (MUST)
SpecPrompt MUST emit metrics sufficient to operate v1 safely, including:

**Traffic & health**
- `http_requests_total{route,method,status}`
- `http_request_duration_ms{route,method,status}` (histogram)
- `http_5xx_total{route}`

**Checkout**
- `checkout_create_total{status}` (success/fail)
- `checkout_create_idempotent_replay_total` (same idempotency key)
- `checkout_create_conflict_total` (idempotency conflict)

**Webhooks**
- `webhook_requests_total{provider,status}` (verified/failed/ignored)
- `webhook_verification_failed_total{provider}`
- `webhook_dedup_hits_total{provider}` (duplicate providerEventId)
- `webhook_processing_duration_ms{provider}` (histogram)
- `webhook_processing_failed_total{provider,reason}`

**Orders**
- `order_state_transitions_total{from,to}`
- `orders_active_total` (gauge; optional but useful)

**Entitlements**
- `entitlement_grants_total{productId}`
- `entitlement_revocations_total{productId,reason}`
- `entitlement_events_total{type,reason}`

**Fulfillment**
- `fulfillment_authorize_total{mode,status}` (v1 default: token/proxy_stream; allowed/denied)
- `fulfillment_denied_total{reason}` (inactive entitlement, not eligible, not found)
- `download_token_redeem_total{status}` (v1 default: proxy download)
- `download_token_redeem_failed_total{reason}` (expired/revoked/not_found)
- `artifact_downloads_total{artifactId}` (optional; beware cardinality)

**Abuse controls**
- `rate_limited_total{route,scope}` (ip/user/provider)
- `suspicious_activity_total{type}` (optional signals, see §7.3)

Cardinality rule:
- Metrics MUST avoid unbounded label cardinality. Prefer:
  - `productId` (bounded count)
  - avoid raw user ids, order ids, event ids, token ids as labels

### 3.3 Tracing / correlation (SHOULD)
If distributed tracing is available, SpecPrompt SHOULD:
- create a trace/span per request
- attach correlation IDs as span attributes (bounded, safe)
- link webhook ingestion span to processing spans (if asynchronous processing exists)

If tracing is not implemented in v1, logs MUST be sufficient to correlate via `requestId` and domain IDs.

---

## 4) Audit and evidence model (append-only events)

SpecPrompt MUST treat these tables as the primary evidence trail (see `30_DATA_MODEL_CONVEX.md`):
- `paymentEvents` (append-only)
- `entitlementEvents` (append-only)
- `fulfillmentEvents` (append-only)

### 4.1 Required audit invariants (MUST)
- Every verified webhook event produces a `paymentEvents` record (deduped by providerEventId).
- Every entitlement state change produces an `entitlementEvents` record.
- Every fulfillment authorization attempt produces a `fulfillmentEvents` record:
  - at least for successful authorizations; denials SHOULD also be recorded in a bounded way.

### 4.2 What audit MUST NOT contain
Audit event payloads MUST NOT contain:
- raw webhook bodies (unbounded)
- webhook signature header values
- auth bearer tokens
- download tokens
- signed URL query params / signatures
- payment method details

---

## 5) Retention and deletion policies (v1 defaults)

These defaults MUST be set before production. Exact durations can be tuned, but the categories and rationale MUST remain.

### 5.1 Retention categories

**R1 — Long-lived, minimal accounting/audit evidence**
- `paymentEvents` (verified events, bounded summary)
- `orders` (minimal order records and state)
- `entitlementEvents` and current `entitlements`

Retention:
- Keep long-term (>= 1 year recommended), but keep payload minimal and bounded.
- Rationale: dispute resolution, refunds, customer support, auditability.

**R2 — Operational support evidence**
- `fulfillmentEvents` (authorization/delivery/denial)
Retention:
- >= 90 days recommended (or align with your support window).
- Rationale: support “why can’t I download X?” and detect abuse.

**R3 — Short-lived security tokens and idempotency ledgers**
- `downloadTokens` (if token mode exists)
- `idempotencyKeys`
Retention:
- tokens: purge after expiry + grace window (e.g., 30 days) to support incident investigation
- idempotency keys: purge after TTL (e.g., 24 hours) to reduce storage and risk
- Rationale: minimize sensitive surface and storage costs.

### 5.2 Deletion semantics (MUST)
- Purge jobs MUST be **idempotent** and safe to retry.
- Purge jobs MUST NOT break auditability:
  - When deleting short-lived token records, preserve the corresponding `fulfillmentEvents`.
- If you delete user data later:
  - do not hard-delete ledger tables without an explicit policy (legal/compliance considerations)
  - consider anonymizing user profile fields while retaining aggregate commerce evidence (future work)

---

## 6) Operational limits and rate limits

### 6.1 General rules (MUST)
- All externally accessible endpoints MUST enforce:
  - request body size limits
  - CPU/timeout constraints where applicable
- All list endpoints MUST paginate with a bounded `limit`.

### 6.2 Rate limiting strategy (v1 baseline)
SpecPrompt SHOULD enforce layered rate limiting by:
- **IP-based** (anonymous or unauthenticated abuse)
- **User-based** (authenticated abuse)
- **Provider-based** (webhooks; careful)

Suggested limit buckets (tune values as you learn):
- Checkout creation:
  - per user: low/medium threshold (prevents spam)
  - per IP: low threshold (prevents brute force)
- Fulfillment authorization:
  - per user: low threshold
  - per IP: low threshold
- Download redemption (token mode):
  - per token hash: very low threshold
  - per IP: low threshold (block brute force)
- Webhook endpoint:
  - rate limit by provider IP ranges if feasible, otherwise:
    - high thresholds + request-level protection
  - DO NOT block legitimate provider retries; prefer:
    - dedupe-first fast path
    - minimal work before verification
    - small constant-time reject path for invalid signatures

### 6.3 Behavioral limits (MUST)
To prevent cost explosions and fraud via edge cases:
- Checkout creation MUST validate and bound:
  - `quantity`
  - allowed `successUrl` and `cancelUrl` hosts (prevent open redirect)
- Fulfillment authorization MUST validate and bound:
  - artifact existence
  - eligibility policies
  - artifact status (withdrawn handling)
- If signed URL mode:
  - signed URL TTL MUST be short-lived
- If token mode:
  - token TTL MUST be short-lived
  - tokens SHOULD be single-use by default
  - token lookup failures SHOULD respond `NOT_FOUND` to reduce enumeration

---

## 7) Anti-fraud and abuse posture (v1)

SpecPrompt v1 is not a full fraud engine, but MUST enforce the basics.

### 7.1 “Source of truth” rules (MUST)
- **Payment state is provider-driven**:
  - clients cannot mark orders paid/active
- **Entitlements are derived**:
  - only from verified provider events and internal policy
- **Fulfillment is entitlement-gated**:
  - you cannot download without active entitlement and eligibility

### 7.2 Payment and entitlement anomalies (SHOULD detect)
SpecPrompt SHOULD flag (metrics + logs + optional internal alerts):
- repeated checkout creation attempts with failures
- repeated fulfillment denials:
  - `ENTITLEMENT_INACTIVE`, `ARTIFACT_NOT_ELIGIBLE`, token invalid
- high rate of token redemption failures from a single IP or user
- repeated webhook verification failures (could indicate misconfiguration or attack)

### 7.3 Minimal fraud signals (optional v1)
If you implement additional signals, keep them bounded and non-invasive:
- user-level “risk score” as a small enum:
  - `normal | elevated | blocked`
- block or challenge behavior:
  - block fulfillment authorization when `blocked`
  - throttle when `elevated`

This MUST be auditable and reversible.

---

## 8) Dashboards and alerts (v1 minimum)

### 8.1 Minimum operational dashboards (SHOULD)
At minimum, operators should be able to see:

**D1 — Webhook health**
- webhook verification failures over time
- webhook processing latency
- webhook dedupe hit rate

**D2 — Checkout funnel**
- checkout create success/fail rates
- order state distribution (pending vs paid/active vs failed/refunded)

**D3 — Entitlement events**
- grants per product
- revocations per reason

**D4 — Fulfillment**
- authorization allowed vs denied
- token redemption failures (if token mode)
- top artifacts by download count (bounded; avoid per-user)

**D5 — Abuse controls**
- rate-limited counts per route
- suspicious activity counts

### 8.2 Alerts (MUST for production readiness)
Minimum alert conditions:
- sustained increase in 5xx rate on any critical route:
  - `/v1/checkout`
  - `/v1/webhooks/payment`
  - `/v1/fulfillment/token`
- webhook verification failures spike (could indicate secret mismatch or attack)
- webhook processing backlog/latency spike (if asynchronous)
- high rate of fulfillment denials spike (could indicate entitlement processing failures)

Alerts MUST be safe (no secrets, no tokens).

---

## 9) Runbooks (v1 minimum)

Before production, you SHOULD have lightweight runbooks for:

### 9.1 “Webhooks failing verification”
Checklist:
- confirm webhook secret configured correctly
- confirm raw body verification path is used (not parsed/re-serialized)
- confirm provider endpoint URL is correct
- confirm time drift isn’t causing provider to retry unexpectedly (provider-specific)
- verify no WAF/CDN rewriting body

### 9.2 “Users can’t download after purchase”
Checklist:
- find order by `orderId` or provider checkout session id
- verify relevant `paymentEvents` exist and are processed
- verify `entitlements` current state for the user/product
- verify `entitlementEvents` show a grant
- verify artifact eligibility (major version / eligibleThroughMs)
- check fulfillment denials and reasons

### 9.3 “Token brute-force attack”
Checklist:
- confirm rate limits are firing
- temporarily tighten token redemption thresholds
- consider requiring auth+token (defense-in-depth) if token-only mode is too risky
- rotate any exposed signing keys if leakage suspected
- review logs for leakage signals (but do not log tokens)

---

## 10) Acceptance criteria (Definition of Done for this module)

SpecPrompt v1 observability/limits are “done” when:

1. **Correlation is real**
   - You can trace a purchase end-to-end using:
     - `orderId`
     - `providerEventId`
     - `entitlementEvents`
     - `fulfillmentEvents`

2. **Webhook pipeline is operable**
   - Verification failures are visible via metrics/logs.
   - Duplicate events are deduped and observable (`webhook_dedup_hits_total` increases).

3. **Retention is implemented**
   - short-lived tables (idempotency keys, download tokens) have a purge strategy
   - audit/ledger events are retained according to policy
   - purges are idempotent and do not break auditability

4. **Rate limits are enforced**
   - checkout spam and token brute force are meaningfully constrained
   - webhook endpoint is protected without breaking legitimate provider delivery

5. **No secrets leak**
   - logs and metrics do not include:
     - provider secrets
     - signature headers
     - auth tokens
     - download tokens
     - signed URL query signatures

6. **Dashboards/alerts exist**
   - operators can see health for checkout/webhooks/fulfillment
   - at least minimal alerting is configured for the critical failure modes

---