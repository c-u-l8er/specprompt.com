# specprompt.com — Data Model (Convex) & Access Control (v1)
Version: 1.0  
Status: Draft (normative once adopted)  
Audience: Engineering  
Last updated: 2026-01-31

This document defines the **SpecPrompt v1** storage model and access-control rules with a **Convex-first** bias:
- Tables (collections), fields, and invariants
- Idempotency and dedupe ledgers (client requests + provider webhooks)
- Security boundaries (tenant isolation, webhook integrity, secret minimization)
- Indexing guidance for stable pagination and lookups

SpecPrompt is the portfolio **commerce** layer:
- It owns **orders**, **payment events**, **entitlements**, **fulfillment**, and an **append-only ledger**.
- It MUST NOT mirror upstream runtime logs/telemetry (WHS metrics, Agentromatic execution logs, Agentelic transcripts).

Normative language:
- **MUST / MUST NOT / SHOULD / MAY** are used intentionally.

---

## 0) Design goals

### 0.1 Goals (v1)
1. **Correctness under retries and replays**
   - client calls (checkout, fulfillment) are idempotent
   - webhooks are idempotent and tolerate duplicates/out-of-order events
2. **Auditability**
   - append-only event records for payment events and entitlement/fulfillment changes
3. **Tenant isolation**
   - users can only see their own orders/entitlements/tokens
4. **Secret minimization**
   - no webhook secrets in DB
   - no raw webhook payload stored unbounded

### 0.2 Non-goals (v1)
- Org-scoped entitlements (defer; integrate with Delegatic later)
- Full tax ledger / invoice accounting engine (provider-first)
- Offline-perpetual client licenses (avoid in v1)

---

## 1) Cross-cutting conventions

### 1.1 Identity model
SpecPrompt uses an authenticated identity provider (portfolio-shared assumption). Internally:

- `users.externalId` = stable auth subject id (e.g., Clerk `sub`)
- All user-scoped rows store `userId: Id<"users">`

Rules:
- Every user-facing query/mutation MUST resolve the caller to `users._id` first.
- `externalId` MUST be unique.

### 1.2 Time
All timestamps are epoch milliseconds:
- `createdAtMs`, `updatedAtMs`, `expiresAtMs`, `processedAtMs`, etc.

### 1.3 IDs and references
- Convex document IDs (`Id<"...">`) are the primary identifiers internally.
- If the API exposes ids as strings, treat them as opaque.

External references (references-only):
- `assetRef` objects may store opaque ids like `fleetpromptListingId`, `whsAgentId`, etc.
- SpecPrompt MUST NOT assume a caller owns referenced upstream ids.

### 1.4 Append-only vs mutable records (rule)
- Webhook-derived records SHOULD be append-only:
  - `paymentEvents` MUST be append-only
  - `entitlementEvents` MUST be append-only
  - `fulfillmentEvents` MUST be append-only
- “Current state” records MAY be updated:
  - `orders` status transitions
  - `entitlements` current status
  - `downloadTokens` status transitions (issued → redeemed/expired/revoked)

### 1.5 Payload limits (must enforce)
- Any persisted “raw-ish” payload must be bounded (e.g., <= 32KB) and redacted.
- Do not store unbounded arrays or nested objects from providers.

### 1.6 Secrets rule (normative)
SpecPrompt MUST NOT store:
- payment provider webhook secret
- full raw webhook bodies (unbounded)
- payment instrument details (card number, CVC, full bank data)

It MAY store:
- provider event id
- provider object ids (customer, subscription, checkout session)
- bounded safe summaries (amount, currency, product mapping)
- a `rawBodySha256` hash for forensic correlation (recommended)

---

## 2) Tables (normative schema)

Field types are conceptual (Convex `v.string()`, `v.number()`, etc.). Treat this as the normative “what exists and what it means”.

### 2.1 `users`
Purpose: internal user mapping.

Fields:
- `externalId: string` (unique)
- `email?: string` (optional; if available)
- `createdAtMs: number`
- `updatedAtMs: number`

Indexes (required):
- `by_externalId` on `externalId`

Invariants:
- Exactly one row per `externalId`.

---

### 2.2 `products`
Purpose: sellable unit (SKU-level), SpecPrompt-owned.

Fields:
- `slug: string` (unique within SpecPrompt; e.g., `agentelic-templates-pack`)
- `name: string`
- `description: string` (bounded; markdown ok if sanitized before UI)
- `status: "active" | "inactive"`
- `assetRef?: object` (references-only; see §2.12)
- `createdAtMs: number`
- `updatedAtMs: number`

Indexes (required):
- `by_slug` on `slug`
- `by_status` on `status`

Access control:
- Admin-only writes (create/update).
- User-facing reads may list `active` products (if you expose a product catalog).

Invariants:
- `slug` is unique.
- `inactive` products MUST NOT be purchasable.

---

### 2.3 `plans`
Purpose: pricing options for a product.

Fields:
- `productId: Id<"products">`
- `type: "one_time" | "subscription"`
- `currency: string` (e.g., `"USD"`)
- `amountCents: number`
- `interval: "month" | "year" | null` (required for subscription; null for one-time)
- `status: "active" | "inactive"`
- `provider: "stripe" | string`
- `providerPriceId?: string | null` (nullable; needed for provider mapping)
- `eligibilityPolicy: object` (tagged union; see §2.11)
- `createdAtMs: number`
- `updatedAtMs: number`

Indexes (required):
- `by_productId` on `productId`
- `by_providerPriceId` on `provider`, `providerPriceId` (composite recommended)

Invariants:
- `subscription` plans MUST have non-null `interval`.
- `providerPriceId` SHOULD be unique per provider when set.
- `inactive` plans MUST NOT be purchasable.

Access control:
- Admin-only writes.
- Reads are allowed as needed for checkout creation.

---

### 2.4 `orders`
Purpose: internal record of a checkout attempt and its current status.

Fields:
- `userId: Id<"users">`
- `provider: "stripe" | string`
- `status: "pending_payment" | "paid" | "active" | "failed" | "refunded" | "canceled" | "disputed"`
- `productId: Id<"products">`
- `planId: Id<"plans">`
- `quantity: number` (bounded; default 1)
- `assetRef?: object` (optional, references-only; see §2.12)

Provider correlation fields (all optional, set by server/webhooks):
- `providerCheckoutSessionId?: string | null`
- `providerCustomerId?: string | null`
- `providerSubscriptionId?: string | null`
- `providerPaymentIntentId?: string | null`
- `providerInvoiceId?: string | null`

Idempotency / client correlation:
- `clientOrderKey?: string | null` (optional; if you accept a client-generated key)

Metadata:
- `createdAtMs: number`
- `updatedAtMs: number`
- `lastEventAtMs?: number | null` (time of last processed payment event)
- `notes?: string | null` (admin-only; bounded)

Indexes (required):
- `by_userId_createdAt` on `userId`, `createdAtMs` (for listing)
- `by_provider_checkoutSession` on `provider`, `providerCheckoutSessionId` (for mapping webhook → order)
- `by_provider_subscription` on `provider`, `providerSubscriptionId` (for subscription lifecycle)
- `by_userId_status_updatedAt` on `userId`, `status`, `updatedAtMs` (optional optimization)

Invariants:
- Orders are user-scoped; never transferable in v1.
- Order status transitions MUST be deterministic and driven by verified provider events (except initial creation).

---

### 2.5 `paymentEvents` (append-only)
Purpose: store verified provider webhook events (or provider callbacks) for audit and idempotent processing.

Fields:
- `provider: "stripe" | string`
- `providerEventId: string` (unique per provider)
- `type: string` (provider event type)
- `receivedAtMs: number`
- `verifiedAtMs: number` (when signature verification succeeded)
- `processedAtMs?: number | null` (when we applied state transitions)
- `status: "verified" | "ignored" | "processed" | "failed"` (processing status)
- `rawBodySha256?: string | null` (recommended; hex)
- `summary: object`
  - bounded safe subset such as:
    - `amountCents?`, `currency?`
    - `checkoutSessionId?`
    - `customerId?`
    - `subscriptionId?`
    - `invoiceId?`
- `linkedOrderId?: Id<"orders"> | null` (set during processing when resolved)
- `errorCode?: string | null`
- `errorMessage?: string | null` (bounded, safe)

Indexes (required):
- `by_provider_providerEventId` on `provider`, `providerEventId`
- `by_linkedOrderId` on `linkedOrderId` (optional)
- `by_receivedAtMs` on `receivedAtMs` (optional for ops)

Invariants:
- MUST be append-only: never update payload fields except possibly:
  - `processedAtMs`, `status`, `linkedOrderId`, and bounded error fields
- `providerEventId` uniqueness MUST be enforced via lookup-before-insert.

---

### 2.6 `idempotencyKeys` (client-request idempotency ledger)
Purpose: dedupe client retries for user-facing POST endpoints.

Fields:
- `scope: "user" | "admin"` (v1: mostly `user`)
- `userId?: Id<"users"> | null` (required when scope is `user`)
- `endpoint: string` (canonical identifier, e.g., `POST /v1/checkout`)
- `idempotencyKey: string` (header value)
- `requestHashSha256: string` (hash of normalized request payload)
- `createdAtMs: number`
- `expiresAtMs: number` (TTL; recommended 24h)
- `result`:
  - `status: "succeeded" | "failed"`
  - `responseBody: object` (bounded) OR `responseRef: object` (if you store a pointer)
  - `errorCode?: string`
  - `errorMessage?: string` (bounded)

Indexes (required):
- `by_user_endpoint_key` on `userId`, `endpoint`, `idempotencyKey`
- `by_expiresAtMs` on `expiresAtMs` (for cleanup job)

Invariants:
- There MUST NOT exist two records for the same `(userId, endpoint, idempotencyKey)` with different `requestHashSha256`.
  - If seen, return `CONFLICT`.

---

### 2.7 `entitlements` (current state)
Purpose: the current entitlement status per user/product (commercial rights).

Fields:
- `userId: Id<"users">`
- `productId: Id<"products">`
- `status: "active" | "inactive" | "revoked"`
- `eligibilityPolicy: object` (tagged union; see §2.11)
- `source`:
  - `orderId: Id<"orders">`
  - `provider: "stripe" | string`
  - `providerSubscriptionId?: string | null`
- `createdAtMs: number`
- `updatedAtMs: number`

Indexes (required):
- `by_userId_updatedAt` on `userId`, `updatedAtMs`
- `by_userId_productId` on `userId`, `productId` (critical for “check entitlement” and dedupe)
- `by_productId_status` on `productId`, `status` (optional; for admin analytics)

Invariants:
- v1 recommendation: at most one entitlement per `(userId, productId)` representing the current state.
- Entitlement issuance MUST be idempotent (see `entitlementEvents` + webhook dedupe).

---

### 2.8 `entitlementEvents` (append-only)
Purpose: immutable audit trail for entitlement changes (grant/revoke/inactivate).

Fields:
- `entitlementId?: Id<"entitlements"> | null` (link once entitlement exists)
- `userId: Id<"users">`
- `productId: Id<"products">`
- `type: "granted" | "updated" | "revoked" | "inactivated"`
- `reason: "payment_succeeded" | "refund" | "chargeback" | "subscription_canceled" | "admin_override" | "reconcile"`
- `linkedOrderId?: Id<"orders"> | null`
- `linkedPaymentEventId?: Id<"paymentEvents"> | null`
- `details: object` (bounded, safe)
- `createdAtMs: number`

Dedupe fields (recommended):
- `dedupeKey: string` (e.g., `ent:evt:<providerEventId>` or `ent:order:<orderId>:<type>`)

Indexes (required):
- `by_userId_createdAt` on `userId`, `createdAtMs`
- `by_productId_createdAt` on `productId`, `createdAtMs` (optional)
- `by_dedupeKey` on `dedupeKey` (recommended)

Invariants:
- MUST be append-only.
- If `dedupeKey` is used, it MUST be enforced by lookup-before-insert.

---

### 2.9 `artifacts`
Purpose: deliverables eligible for fulfillment (downloadable packages, spec bundles, etc.).

Fields:
- `productId: Id<"products">`
- `version: string` (semver recommended)
- `major: number` (redundant denormalization for fast eligibility checks)
- `status: "active" | "withdrawn"`
- `assetRef?: object` (optional; references-only; see §2.12)
- `storage`:
  - `provider: "r2" | "s3" | "local" | string`
  - `key: string` (object key)
  - `contentType: string`
  - `sizeBytes: number`
- `sha256: string` (hex; required for files)
- `releasedAtMs: number`
- `createdAtMs: number`
- `updatedAtMs: number`

Indexes (required):
- `by_productId_releasedAt` on `productId`, `releasedAtMs`
- `by_productId_version` on `productId`, `version` (recommended)
- `by_productId_major_releasedAt` on `productId`, `major`, `releasedAtMs` (recommended for major-based eligibility)

Invariants:
- Artifacts are product-scoped.
- `withdrawn` artifacts MUST NOT be newly fulfillable, but may remain downloadable if previously issued tokens exist (policy choice; document in ADR).

Access control:
- Admin-only writes (register/withdraw).
- Reads:
  - user-facing should not list all artifacts unless needed; fulfillment path should fetch by id and then enforce eligibility.

---

### 2.10 `downloadTokens`
Purpose: time-bounded download authorization (token mode). If you only use signed URLs, you MAY omit this table.

Fields:
- `userId: Id<"users">`
- `artifactId: Id<"artifacts">`
- `status: "issued" | "redeemed" | "expired" | "revoked"`
- `tokenHashSha256: string` (hash of opaque token; DO NOT store raw token)
- `expiresAtMs: number`
- `singleUse: boolean`
- `issuedAtMs: number`
- `redeemedAtMs?: number | null`
- `createdAtMs: number`

Indexes (required):
- `by_tokenHash` on `tokenHashSha256`
- `by_userId_createdAt` on `userId`, `createdAtMs`
- `by_expiresAtMs` on `expiresAtMs` (cleanup)

Invariants:
- Token redemption must be atomic-ish:
  - lookup token by hash
  - verify not expired/revoked/redeemed (if single-use)
  - transition to redeemed (if single-use) before streaming bytes
- Tokens MUST be revocable by setting status to `revoked`.

---

### 2.11 `fulfillmentEvents` (append-only)
Purpose: audit token issuance/redemption and/or signed URL issuance.

Fields:
- `userId: Id<"users">`
- `productId: Id<"products">`
- `artifactId: Id<"artifacts">`
- `mode: "signed_url" | "token" | "proxy_stream"`
- `type: "authorized" | "delivered" | "denied"`
- `entitlementId?: Id<"entitlements"> | null`
- `orderId?: Id<"orders"> | null`
- `paymentEventId?: Id<"paymentEvents"> | null`
- `downloadTokenId?: Id<"downloadTokens"> | null`
- `requestId: string` (correlation)
- `details: object` (bounded, safe; no URLs if sensitive)
- `createdAtMs: number`

Indexes (required):
- `by_userId_createdAt` on `userId`, `createdAtMs`
- `by_artifactId_createdAt` on `artifactId`, `createdAtMs` (optional)

Invariants:
- MUST be append-only.
- Denials SHOULD be recorded (bounded) for supportability, but ensure no sensitive leakage.

---

### 2.12 Canonical shapes for embedded objects (normative)

#### 2.12.1 `eligibilityPolicy`
Stored on `plans` and `entitlements`. v1 supports:

- One-time major license:
  - `{ "type": "one_time_major", "major": number }`

- Subscription updates while active:
  - `{ "type": "subscription_updates_while_active", "eligibleThroughMs": number | null }`

Rules:
- Eligibility evaluation MUST be deterministic and purely server-side.

#### 2.12.2 `assetRef` (references-only)
Examples:
- `{ "kind": "fleetprompt_listing", "listingId": "string", "releaseId": "string" }`
- `{ "kind": "whs_agent", "whsAgentId": "string", "whsDeploymentId": "string" }`
- `{ "kind": "agentromatic_workflow", "agentromaticWorkflowId": "string" }`
- `{ "kind": "spec_asset", "specAssetId": "string" }`

Rules:
- Store only opaque strings.
- Do not treat as authorization.
- Do not validate existence cross-system in v1 unless you implement a best-effort, non-widening verification status (ADR).

---

## 3) Access control requirements (normative)

### 3.1 Global rule (MUST)
Every user-facing query/mutation MUST:
1. authenticate the caller
2. resolve `users._id`
3. enforce tenant isolation on every read/write

### 3.2 User-facing read rules (MUST)
A user MAY read:
- their own `orders`
- their own `entitlements`
- their own `downloadTokens` (if table exists)
- their own `fulfillmentEvents` (optional exposure)
- public/active `products` and `plans` if you expose catalog browsing

A user MUST NOT read:
- other users’ orders/entitlements/tokens/events
- raw `paymentEvents` (except possibly a minimal order-linked view; recommended: keep provider events internal)
- admin-only tables or fields (internal notes, provider secrets)

### 3.3 User-facing write rules (MUST)
A user MAY:
- create a checkout (creates `orders` + provider session)
- request fulfillment authorization (mint signed URL or download token)

A user MUST NOT:
- create/update products/plans/artifacts
- directly write payment events or entitlement events
- directly set an order to paid/active

### 3.4 Server-only operations (MUST)
The webhook receiver and internal processing MUST be server-only:
- writes to `paymentEvents`
- order state transitions based on provider events
- entitlement issuance/revocation
- any admin operations

### 3.5 Not-found vs unauthorized strategy (IDOR-safe)
Recommended v1 rule:
- If a user requests `orders/:id` or similar and does not own it, return `NOT_FOUND`.

---

## 4) Idempotency and dedupe (normative)

Convex does not provide unique constraints in the database; you MUST enforce uniqueness through deterministic lookups and rejection logic.

### 4.1 Client idempotency: `idempotencyKeys`
For endpoints with `Idempotency-Key`:
- Compute a stable `requestHashSha256` from a normalized JSON payload.
- Lookup `idempotencyKeys` by `(userId, endpoint, idempotencyKey)`:
  - If not found: insert record with `requestHashSha256`, then proceed; store the response in the record.
  - If found and hash matches: return the stored response (or follow stored failure deterministically).
  - If found and hash differs: return `CONFLICT`.

### 4.2 Webhook dedupe: `paymentEvents`
For webhook ingestion:
- Verification uses raw body bytes and provider signature.
- Extract `providerEventId` from the verified payload.
- Lookup `paymentEvents` by `(provider, providerEventId)`:
  - If exists: return `{ ok: true }` without reprocessing (idempotent).
  - If missing: insert new `paymentEvents` row (append-only) then process.

### 4.3 Exactly-once entitlement issuance (practical)
Entitlements MUST be issued deterministically based on:
- `orderId` and provider object ids (subscription/customer) from verified events

Recommended algorithm:
1. Resolve linked `orderId` from event (checkoutSessionId, subscriptionId, invoiceId).
2. Transition order state deterministically.
3. Compute entitlement “current state” key: `(userId, productId)`.
4. Upsert `entitlements` current state:
   - If active entitlement already exists and matches source: no-op or update eligibility policy if needed.
   - Record an `entitlementEvents` row with a `dedupeKey` derived from the provider event id.

---

## 5) Validation requirements (must)

### 5.1 Schema validation
- Validate enums strictly.
- Validate numeric bounds (amounts, quantities, TTLs).
- Validate URL allowlists where applicable (success/cancel URLs in checkout).

### 5.2 Cross-table invariants
- `orders.userId` MUST match the authenticated user for user-facing reads.
- `orders.planId` MUST belong to `orders.productId`.
- `plans.productId` MUST exist.
- `artifacts.productId` MUST exist.
- `downloadTokens.artifactId` MUST exist (and refer to correct product via lookup when auditing).

### 5.3 Provider object mapping safety
When mapping provider events to internal objects:
- never trust client-provided mapping
- do not accept “orderId” from webhooks unless it is cryptographically tied (e.g., provider metadata set by server on session creation)
- always reconcile using server-stored provider ids

---

## 6) Indexing guidance (Convex-specific)

Minimum required indexes (summary):
- `users.by_externalId`
- `orders.by_userId_createdAt`
- `orders.by_provider_checkoutSession`
- `orders.by_provider_subscription`
- `paymentEvents.by_provider_providerEventId`
- `entitlements.by_userId_productId`
- `artifacts.by_productId_major_releasedAt`
- `downloadTokens.by_tokenHash` (if tokens exist)
- `idempotencyKeys.by_user_endpoint_key`

Pagination guidance:
- Use a stable ordering (e.g., `createdAtMs desc`) and cursor derived from `(createdAtMs, _id)` to avoid duplicates under inserts.

---

## 7) Retention, deletion, and lifecycle semantics

### 7.1 Recommended retention defaults (v1)
- `paymentEvents`: retain long-term (audit) but keep stored payload minimal and bounded.
- `downloadTokens`: purge after expiration + grace window (e.g., 30 days) while retaining `fulfillmentEvents`.
- `idempotencyKeys`: purge after TTL (e.g., 24h) with a cleanup job.
- `fulfillmentEvents` and `entitlementEvents`: retain at least 90 days (or longer for support/audit).

### 7.2 Deletion semantics
- User deletion is out of scope in v1. If implemented later:
  - do not delete ledger records without an explicit policy (compliance/legal).
  - consider anonymization of `users` fields rather than hard delete.

---

## 8) Minimal v1 schema checklist (Definition of Done for data model)

- [ ] `users` table exists with unique `externalId` index
- [ ] `products`, `plans` exist with admin-only mutation policy
- [ ] `orders` exists with provider correlation fields and user-scoped listing index
- [ ] `paymentEvents` exists, append-only, deduped by `(provider, providerEventId)`
- [ ] `idempotencyKeys` exists and enforces retry safety for checkout + fulfillment
- [ ] `entitlements` exists with `(userId, productId)` lookup index
- [ ] `entitlementEvents` exists (append-only) and is written on each change
- [ ] `artifacts` exists with product/version/major indexing
- [ ] `downloadTokens` exists OR signed-URL-only fulfillment is documented (and tokens omitted)
- [ ] `fulfillmentEvents` exists (append-only) for issuance/redemption/denial audit
- [ ] Access control rules are implemented centrally and consistently (no per-endpoint drift)
- [ ] No secrets are stored (webhook secret, payment instrument details, raw bodies unbounded)

---

## 9) Open decisions (should become ADRs)
1. Payment provider choice and exact event mapping (Stripe recommended, but lock it).
2. Fulfillment mode:
   - signed URLs only vs token+proxy download
3. Artifact withdrawal behavior:
   - whether previously issued tokens remain valid
4. Admin model:
   - allowlist vs role table vs external admin group mapping
5. Whether SpecPrompt exposes a public product catalog, or is only called via FleetPrompt.

---