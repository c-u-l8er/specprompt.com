# specprompt.com — MASTER ENGINEERING SPEC (v1)
Version: 1.0  
Status: Draft (normative once adopted)  
Audience: Engineering  
Last updated: 2026-01-31

SpecPrompt is the portfolio’s **commerce/monetization layer** (Layer 6). It provides **checkout, licensing, entitlements, fulfillment**, and an **auditable commerce ledger** for commercial assets across the ecosystem.

Portfolio context (canonical layering):
- **Layer 1 — WebHost.Systems (WHS):** deploy/invoke runtimes, telemetry, usage limits, usage-based billing
- **Layer 2 — Agentromatic:** workflow definitions, executions, execution logs (orchestration-of-record)
- **Layer 3 — Agentelic:** telespaces (rooms/messages/membership) + installs/automations (reference-first)
- **Layer 4 — Delegatic:** orgs/policies/governance (deny-by-default, reference-first)
- **Layer 5 — FleetPrompt:** marketplace/discovery/listings/install handoff (distribution)
- **Layer 6 — SpecPrompt (this):** payments + licensing + entitlements + fulfillment (commerce)

Normative language:
- **MUST / MUST NOT / SHOULD / MAY** are used intentionally.

---

## 0) Executive summary

### 0.1 What you are building (v1)
A secure, idempotent commerce service that:
1. Creates checkout sessions for authenticated users purchasing products/plans.
2. Processes payment-provider events (webhooks) into an internal **Order** state machine.
3. Issues **Entitlements** exactly-once, based on paid/active purchase state.
4. Provides **Fulfillment** endpoints:
   - list entitlements
   - authorize download/version eligibility
   - mint revocable download tokens / signed URLs (provider-backed)
5. Maintains an append-only **commerce ledger** (orders, payment events, entitlement grants, fulfillment events).

### 0.2 What you are not building (v1)
SpecPrompt v1 MUST NOT:
- Execute agents (WHS runtime responsibility).
- Execute workflows (Agentromatic responsibility).
- Replace FleetPrompt discovery/listings.
- Bypass Delegatic/Agentelic authorization (entitlements are not “membership”).
- Implement enterprise procurement/SSO/org billing workflows (defer).
- Build a full publisher payout marketplace (Stripe Connect) unless explicitly added later.

---

## 1) Scope, goals, non-goals

### 1.1 Goals (v1 MUST)
- **G1 — Deterministic checkout → entitlement pipeline**
  - Create checkout for a product/plan.
  - Convert payment events into an internal order state.
  - Issue entitlements exactly once (idempotent webhook processing).
- **G2 — Secure entitlement verification**
  - Provide a stable API for other portfolio products to verify entitlement status (server-side).
- **G3 — Fulfillment**
  - Allow eligible users to download artifacts or receive license tokens.
  - Support revocation by invalidating entitlements and/or download tokens.
- **G4 — Auditability**
  - Persist an append-only ledger with correlation IDs linking:
    - checkout session → payment events → order → entitlement grants → fulfillment deliveries.
- **G5 — Tenant isolation**
  - Users can only access their own orders/entitlements/fulfillment artifacts.
  - Admin operations are explicitly separated and gated.

### 1.2 Non-goals (v1 MUST NOT)
- Org-scoped entitlements (defer; integrate with Delegatic later).
- Complex tax engine (use provider-managed taxes if available; keep minimal otherwise).
- “Unlimited offline license checks” (avoid unrevocable client-side licenses in v1).
- Storing large upstream artifacts inside the primary DB (use object storage / provider).

### 1.3 Assumptions
- A shared identity provider exists across products (e.g., a stable external subject id).
- Webhooks are available from the payment provider and can be verified cryptographically.
- Artifact storage exists (S3/R2/etc.) or the payment provider supports file delivery; SpecPrompt remains authoritative for authorization.

---

## 2) Key decisions (ADR-style summaries)

These are v1 decisions that the implementation MUST follow. Capture as ADRs in `spec_v1/adr/` when you implement.

1. **Entitlements are grants of commercial rights, not runtime authorization.**
2. **Reference-first storage:** store references to external assets; do not copy execution logs/telemetry.
3. **Webhook-driven state is idempotent:** payment events can arrive multiple times and out of order; processing must be safe.
4. **Fulfillment uses revocable tokens:** do not ship perpetual bearer tokens without server checks.

---

## 3) Glossary (canonical terms)

- **Product / SKU:** A sellable unit (e.g., spec pack, workflow template pack, agent bundle, add-on).
- **Plan:** A pricing option for a product (one-time purchase or subscription).
- **Order:** SpecPrompt’s internal record of a purchase attempt and its outcome.
- **Payment Provider:** External system (e.g., Stripe) that performs checkout and emits webhooks.
- **Payment Event:** Verified webhook event from the payment provider.
- **Entitlement:** A grant to a subject (user in v1) indicating rights (download access, update eligibility, feature access).
- **Eligibility Policy:** Rules for which versions/artifacts are available under an entitlement (e.g., “major version 1.x”, “updates while active”).
- **Fulfillment Artifact:** Deliverable content (downloadable file, license token, receipt).
- **Download Token:** Revocable, time-bounded token that authorizes downloading a specific artifact.

---

## 4) System architecture

### 4.1 High-level components
- **SpecPrompt API (control plane)**
  - Auth, tenancy checks, admin gating
  - Checkout session creation
  - Entitlement queries and fulfillment token minting
- **Payment Provider**
  - Checkout UI/session
  - Webhooks for payment/renewal/refunds/disputes
- **Webhook Receiver**
  - Verifies webhook signatures
  - Enqueues/stores payment events
  - Applies idempotent state transitions
- **Commerce Ledger**
  - Orders
  - Payment events
  - Entitlement grants/revocations
  - Fulfillment events
- **Artifact Storage / Delivery**
  - Object storage for artifacts (recommended)
  - Signed URLs or streaming proxy (optional v1)

### 4.2 Boundaries (hard rules)
- SpecPrompt MUST NOT trust clients for:
  - order payment state
  - entitlement issuance
  - refund/chargeback status
- SpecPrompt MUST treat payment provider webhooks as authoritative, but only after verification.
- SpecPrompt MUST NOT leak sensitive payment details to other portfolio systems.
- SpecPrompt MUST NOT allow cross-tenant reads by id (IDOR-safe strategy is required; recommended: `NOT_FOUND` for foreign ids).

### 4.3 Data ownership and references
SpecPrompt is the source of truth for:
- orders and their states
- entitlements and their status
- fulfillment and download token issuance
- commerce audit/ledger data

SpecPrompt stores only references to portfolio assets, such as:
- `fleetpromptListingId` (optional)
- `whsAgentId` (optional)
- `agentromaticWorkflowId` (optional)
- `specAssetId` / `artifactId` (recommended: SpecPrompt-owned artifact ids)

SpecPrompt MUST NOT copy:
- Agentromatic executions/logs
- WHS telemetry streams
- Agentelic room transcripts

---

## 5) Canonical data flows (v1)

This section is normative: implementations MUST preserve these semantics even if endpoint names differ.

### Flow A — Create checkout (user → SpecPrompt → provider)
1. User is authenticated.
2. Client calls SpecPrompt to create a checkout:
   - inputs: `productId`, `planId`, optional `assetRef`, optional `quantity`, return URL/cancel URL.
3. SpecPrompt validates:
   - product/plan exists and is active
   - user is eligible to purchase (optional anti-abuse)
4. SpecPrompt creates an internal **Order** in state `pending_payment`.
5. SpecPrompt creates a provider checkout session and returns:
   - `checkoutSessionUrl` (or session id) + `orderId`.

**Invariants**
- Order creation MUST be idempotent if a client retries (use an Idempotency-Key or clientOrderId).
- The authoritative “paid” transition happens only via verified webhooks (Flow B/C).

### Flow B — Payment completed (provider webhook → SpecPrompt)
1. Provider sends webhook(s) indicating payment success:
   - e.g., checkout completed, invoice paid, subscription active.
2. SpecPrompt verifies webhook signature and basic invariants (timestamp window if supported).
3. SpecPrompt records a **PaymentEvent** (append-only) with `providerEventId` uniqueness.
4. SpecPrompt transitions the Order state deterministically:
   - `pending_payment` → `paid` (or `active` for subscription)
5. SpecPrompt issues entitlements (Flow D).

**Invariants**
- Processing MUST be idempotent by `providerEventId`.
- If events arrive out of order, SpecPrompt MUST converge to the correct final state without double-issuing entitlements.

### Flow C — Refund/chargeback/subscription canceled (provider webhook → SpecPrompt)
1. Provider sends webhook(s) indicating entitlement should no longer be active:
   - refund, dispute, subscription canceled/unpaid.
2. SpecPrompt verifies webhook.
3. SpecPrompt records PaymentEvent (append-only).
4. SpecPrompt transitions Order state and/or entitlement state:
   - `active` → `inactive` or `revoked` depending on policy.

**Invariants**
- Revocation MUST be auditable and deterministic.
- Revocation MUST NOT delete prior records; append-only changes.

### Flow D — Issue entitlement (SpecPrompt internal)
Given a paid/active purchase event:
1. Compute the entitlement key:
   - `(subjectId, productId, entitlementScopeKey)` where v1 scope is user-level.
2. Check if an active entitlement already exists for this purchase:
   - If yes: do not create a duplicate; ensure it is consistent and return existing.
3. Create an entitlement grant record (append-only) and update current entitlement status.
4. Record linkage to:
   - `orderId`
   - `providerCustomerId` (optional)
   - `providerSubscriptionId` (optional)
   - eligibility policy

**Invariants**
- Entitlement issuance MUST be exactly-once per logical purchase (idempotent).
- Entitlement calculations MUST NOT depend on client input once payment is verified.

### Flow E — Fulfillment: authorize download (user → SpecPrompt)
1. User requests fulfillment for an artifact/version:
   - inputs: `productId` + `artifactId` (or version constraint)
2. SpecPrompt verifies:
   - user owns an active entitlement that covers the requested artifact/version
   - artifact exists and is available
3. SpecPrompt issues a download token (Flow F) or returns a signed URL.

**Invariants**
- Authorization is server-side only.
- Cross-user artifact access MUST be blocked.

### Flow F — Download token redemption (user/tool → SpecPrompt/storage)
Two acceptable v1 patterns:

**Pattern F1 (recommended): signed URL minting**
- SpecPrompt mints a time-bounded signed URL for object storage and returns it.

**Pattern F2: SpecPrompt download proxy**
- SpecPrompt issues a token and offers a download endpoint that streams from storage after token validation.

**Invariants**
- Tokens/URLs MUST be time-bounded.
- Revocation MUST be possible (invalidate token or entitlement).
- All fulfillments MUST be logged (append-only fulfillment events).

---

## 6) Product requirements (engineering-focused)

### 6.1 Products and plans
- SpecPrompt MUST support:
  - products with stable ids
  - plans for each product:
    - `one_time`
    - `subscription`
- Plan metadata MUST include:
  - currency, amount, interval (for subscription), status, provider price id mapping (if applicable)

### 6.2 Order state machine (minimum)
Order states (minimum v1):
- `pending_payment`
- `paid` (one-time success)
- `active` (subscription active)
- `failed`
- `refunded`
- `canceled`
- `disputed` (optional but recommended)

Rules:
- Provider events drive transitions.
- Transitions are monotonic where possible; if reversals occur (refund), they are recorded and reconciled deterministically.

### 6.3 Entitlement model (v1)
Entitlement fields (conceptual):
- `subjectType = "user"` (v1 only)
- `subjectExternalId` (or internal user id)
- `productId`
- `status = active|inactive|revoked`
- `eligibilityPolicy`:
  - one-time: “major version line” or “perpetual artifact set”
  - subscription: “updates while active” (eligibleThroughMs derived from subscription periods)
- references to purchase:
  - `orderId`
  - `providerSubscriptionId?`
  - `providerCustomerId?`

### 6.4 Eligibility policies (v1 minimum)
SpecPrompt MUST implement at least one of these policy families:

**Policy P1 — One-time major version license**
- Purchase grants access to all artifacts tagged `major = X`.
- No access to `major > X`.

**Policy P2 — Subscription updates while active**
- While subscription is active: access to all artifacts released up to “now”.
- After subscription ends: access to artifacts released up to `eligibleThroughMs`.

The exact policy choice for each product/plan is config-driven.

### 6.5 Fulfillment artifacts
Artifacts can represent:
- downloadable packages (zip/tar)
- “license token” documents
- receipts/invoices (from provider or generated)

SpecPrompt MUST maintain integrity metadata:
- `sha256` for files (required for downloadable packages)
- storage pointer (bucket/key), not raw bytes in DB

### 6.6 Admin surface (v1 minimal)
- A minimal admin-only capability to:
  - create products/plans
  - register artifacts and version tags
  - map provider price ids to internal plan ids
- Admin endpoints MUST be separate and protected.

---

## 7) API surface (normative pointers)

SpecPrompt v1 SHOULD ship a stable contract set (typically in `10_API_CONTRACTS.md`). At minimum, the API must support:

### User-facing
- `POST /v1/checkout` → create checkout session
- `GET /v1/orders` → list my orders
- `GET /v1/entitlements` → list my entitlements
- `POST /v1/fulfillment/token` → mint download token or signed URL
- `GET /v1/fulfillment/download` (optional proxy) → download by token

### Webhooks (server-only)
- `POST /v1/webhooks/payment-provider` → receive and verify webhooks

### Admin-only (optional v1, but recommended)
- product/plan CRUD
- artifact registration
- entitlement admin overrides (highly audited; avoid if possible in v1)

All endpoints MUST:
- enforce authentication (except webhooks)
- enforce tenant isolation
- return normalized errors

---

## 8) Data model (normative pointers)

SpecPrompt should document its schema and invariants in `30_DATA_MODEL_CONVEX.md` (or equivalent). Minimum tables/collections:

- `users` (identity mapping, if not delegated to another system)
- `products`
- `plans`
- `orders`
- `paymentEvents` (append-only; unique by provider event id)
- `entitlements` (current state)
- `entitlementGrants` / `entitlementEvents` (append-only changes; recommended)
- `artifacts`
- `downloadTokens` (optional; if not using signed URLs only)
- `fulfillmentEvents` (append-only)

Key invariants:
- No duplicate `paymentEvents` for a provider event id.
- Entitlement issuance is deduped per logical purchase.
- Download tokens are time-bounded and revocable.

---

## 9) Security requirements (implementation-grade)

### 9.1 Tenant isolation (MUST)
- All reads and writes MUST be scoped to the authenticated user.
- Cross-user resources accessed by id MUST return safe failures (recommended: `NOT_FOUND`).

### 9.2 Webhook integrity (MUST)
- Webhooks MUST be verified using provider-recommended signature verification.
- Verification failures MUST NOT mutate state.
- Store the verified event (append-only) and process it idempotently.

### 9.3 Secrets handling (MUST)
- Provider secrets MUST remain server-side only.
- Logs and errors MUST NOT include:
  - webhook secret
  - raw payment instrument details
  - full webhook bodies in production logs (store only bounded safe subsets + hashed raw body if needed)

### 9.4 Confused deputy prevention (MUST)
- Entitlements MUST NOT be treated as authorization to:
  - join telespaces
  - invoke agents
  - trigger workflows
- Any bridge from SpecPrompt to other products MUST:
  - be server-to-server
  - be explicitly scoped and audited
  - never accept client assertions as proof

### 9.5 Abuse controls (SHOULD, minimal v1)
- Rate limit:
  - checkout creation
  - fulfillment token minting
  - download attempts
- Implement basic anti-enumeration protections:
  - opaque ids
  - consistent error strategy
  - no “does this email have an entitlement?” endpoints

---

## 10) Observability and retention (v1)

### 10.1 Auditability (MUST)
- Every state transition must produce an append-only event record, including:
  - order state transitions
  - entitlement grants/revocations
  - download token issuance/redemption
- Each record should include:
  - `requestId` / correlation id
  - timestamps
  - safe summaries (no secrets)

### 10.2 Retention (v1 defaults)
- Payment events: retain long-term (as required for accounting/audit), but store minimal necessary fields.
- Download tokens: retain short-term (e.g., 30 days) after expiration for audit, then purge.
- Fulfillment events: retain at least 90 days (or longer if needed for support).

Exact durations can be moved to `50_OBSERVABILITY_BILLING_LIMITS.md` later; defaults must be defined before production.

---

## 11) UI requirements (v1 minimum, optional)
SpecPrompt may be API-first in v1. If a UI exists:
- “My purchases / entitlements” page
- “Download” experience for eligible artifacts
- Clear status for subscription active/inactive
- No exposing sensitive billing details beyond what is safe and necessary

---

## 12) Testing strategy (minimum viable)

Minimum required test suites (can be in `60_TESTING_ACCEPTANCE.md` later):

### 12.1 Unit tests (MUST)
- Eligibility policy evaluator:
  - one-time major version
  - subscription active vs expired
- Webhook verification wrapper (mocked provider)
- Idempotency logic for payment event processing
- Download token mint/verify/expiry/revocation

### 12.2 Integration tests (MUST)
- Create checkout → simulate webhook → entitlement issued → fulfillment authorized
- Refund webhook → entitlement revoked → fulfillment denied
- Duplicate webhook delivery does not duplicate entitlements
- Cross-user IDOR attempts blocked

### 12.3 Security tests (MUST)
- Webhook spoofing rejected
- Token replay after expiry rejected
- Rate limit behavior (basic)

---

## 13) Open questions (must answer before v1 sign-off)
1. Payment provider choice (Stripe vs alternative) and exact webhook event mapping.
2. Artifact storage choice (S3/R2/etc.) and signed URL strategy.
3. Eligibility policy standardization:
   - which policies are supported in v1
   - how artifacts are tagged/versioned for eligibility
4. Identity model:
   - does SpecPrompt maintain its own `users` mapping or depend on shared identity middleware?

---

## 14) Acceptance criteria (definition of done for v1)

SpecPrompt v1 is “done” when you can demonstrate, end-to-end:

1. **Checkout creation**
   - Authenticated user can create a checkout for a product/plan.
   - Retries do not create duplicate orders (idempotency proven).

2. **Webhook-driven entitlement issuance**
   - A verified payment success event transitions an order into paid/active.
   - Exactly one entitlement is issued for the purchase, even with duplicate webhooks.

3. **Fulfillment**
   - User can list their entitlements.
   - User can request a fulfillment download token or signed URL for an eligible artifact.
   - Download succeeds and creates a fulfillment audit event.

4. **Revocation**
   - Refund/chargeback/subscription canceled events revoke eligibility deterministically.
   - After revocation, fulfillment is denied (even if a user tries older links/tokens).

5. **Security**
   - Webhook spoofing attempts are rejected (no state change).
   - Cross-user access to orders/entitlements is blocked (IDOR-safe).
   - No secrets appear in logs/errors.

6. **Auditability**
   - For a single purchase, you can trace:
     - order → payment events → entitlement grant → fulfillment events
     - using correlation ids and timestamps, without relying on external systems.

---