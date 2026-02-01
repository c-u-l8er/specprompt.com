# specprompt.com — API Contracts (v1)
Version: 1.0  
Status: Draft (normative once adopted)  
Audience: Engineering  
Last updated: 2026-01-31

This document defines the **SpecPrompt v1** HTTP API contracts for:
- checkout session creation
- payment provider webhooks → order state transitions
- entitlement issuance and querying
- fulfillment authorization (download tokens / signed URLs)
- normalized errors, pagination, and idempotency

Normative language:
- **MUST / MUST NOT / SHOULD / MAY** are used intentionally.

---

## 1) Principles

### 1.1 SpecPrompt is a commerce plane (hard rule)
SpecPrompt is the system-of-record for:
- **orders** (purchase attempts + state)
- **payment events** (verified, append-only)
- **entitlements** (commercial rights)
- **fulfillment** (download authorization + delivery audit)

SpecPrompt MUST NOT:
- execute agents (WHS responsibility)
- execute workflows (Agentromatic responsibility)
- replace FleetPrompt discovery/listings UI
- bypass Delegatic/Agentelic authorization (entitlement ≠ membership/role)
- mirror upstream execution logs/telemetry (references only)

### 1.2 Webhooks are authoritative only after verification
- Webhook requests MUST be cryptographically verified using the payment provider’s recommended scheme.
- If verification fails, SpecPrompt MUST return an error and MUST NOT mutate state.

### 1.3 Idempotency is required
- Client-initiated POST endpoints that can be retried MUST accept `Idempotency-Key`.
- Webhook processing MUST be idempotent by provider event id.
- The server MUST detect “same idempotency key, different payload” and return `CONFLICT`.

### 1.4 Consistent errors (required)
All non-2xx responses MUST return the normalized error envelope defined in §3.

### 1.5 Pagination (required for list endpoints)
List endpoints MUST be cursor-paginated and return:
- `items: T[]`
- `nextCursor: string | null`

### 1.6 Time representation
All timestamps are epoch milliseconds:
- `createdAtMs`, `updatedAtMs`, `expiresAtMs`, etc.

---

## 2) Common types

### 2.1 IDs (opaque strings)
All IDs are opaque strings; clients must not infer meaning:
- `productId`
- `planId`
- `orderId`
- `paymentEventId` (internal)
- `entitlementId`
- `artifactId`
- `downloadTokenId`

### 2.2 Enums

#### 2.2.1 PaymentProvider
- `stripe` (example)
- (add more later; do not break v1 behavior)

#### 2.2.2 OrderStatus (minimum v1)
- `pending_payment`
- `paid` (one-time settled)
- `active` (subscription active)
- `failed`
- `refunded`
- `canceled`
- `disputed` (optional but recommended)

#### 2.2.3 EntitlementStatus (v1)
- `active`
- `inactive`
- `revoked`

#### 2.2.4 DownloadTokenStatus (v1)
- `issued`
- `redeemed` (if single-use)
- `expired`
- `revoked`

### 2.3 Pagination
`Page<T>` response shape:
- `items: T[]`
- `nextCursor: string | null`

Request parameters:
- `cursor?: string` (opaque)
- `limit?: number` (default 50, max 200 recommended)

### 2.4 Eligibility policies (v1 minimum)
Entitlements carry an eligibility policy that the server evaluates.

`EligibilityPolicy` (tagged union):
- `{"type":"one_time_major","major": number}`
  - Eligible artifacts MUST match the same major version.
- `{"type":"subscription_updates_while_active","eligibleThroughMs": number | null}`
  - If subscription is active, `eligibleThroughMs` MAY be null and treated as “now”.
  - If subscription ended, `eligibleThroughMs` is the cutoff.

### 2.5 Asset references (references-only)
SpecPrompt products MAY refer to external ecosystem assets as metadata only:

`AssetRef` (optional, reference-only):
- `{"kind":"fleetprompt_listing","listingId": string, "releaseId"?: string}`
- `{"kind":"whs_agent","whsAgentId": string, "whsDeploymentId"?: string}`
- `{"kind":"agentromatic_workflow","agentromaticWorkflowId": string}`
- `{"kind":"spec_asset","specAssetId": string}`

Rules:
- SpecPrompt MUST treat all external IDs as opaque strings.
- SpecPrompt MUST NOT assume the caller owns the referenced asset.

---

## 3) Normalized errors (REQUIRED)

### 3.1 Error envelope
All errors MUST return:

```ProjectWHS/specprompt.com/project_spec/spec_v1/10_API_CONTRACTS.md#L1-999
{
  "error": {
    "code": "STRING",
    "message": "STRING",
    "requestId": "STRING",
    "details": {
      "hint": "STRING",
      "fields": [
        { "fieldName": "STRING", "message": "STRING" }
      ]
    }
  }
}
```

Notes:
- `requestId` MUST be present and stable for a request (generated server-side).
- `details` is optional; `fields` is optional and used for validation.

### 3.2 Error codes (v1)
Auth / access:
- `UNAUTHENTICATED`
- `UNAUTHORIZED`

Resource / routing:
- `NOT_FOUND`
- `CONFLICT`

Validation / limits:
- `VALIDATION_FAILED`
- `RATE_LIMITED`

Commerce-specific:
- `WEBHOOK_VERIFICATION_FAILED`
- `PAYMENT_PROVIDER_ERROR`
- `ENTITLEMENT_INACTIVE`
- `ARTIFACT_NOT_ELIGIBLE`
- `DOWNLOAD_TOKEN_INVALID`
- `DOWNLOAD_TOKEN_EXPIRED`

System:
- `INTERNAL`

### 3.3 Not found vs unauthorized strategy (IDOR-safe)
Recommended v1 strategy:
- For cross-tenant ids, return `NOT_FOUND` (do not leak existence).

### 3.4 HTTP mapping (recommended)
- `UNAUTHENTICATED` → 401
- `UNAUTHORIZED` → 403
- `NOT_FOUND` → 404
- `VALIDATION_FAILED` → 400
- `CONFLICT` → 409
- `RATE_LIMITED` → 429
- `WEBHOOK_VERIFICATION_FAILED` → 400 (or 401; choose one and stay consistent)
- `PAYMENT_PROVIDER_ERROR` → 502
- `INTERNAL` → 500

---

## 4) Authentication & authorization

### 4.1 User auth (required)
User-facing endpoints MUST require:
- `Authorization: Bearer <JWT>`

SpecPrompt MUST map the authenticated identity to a stable internal subject:
- recommended: `externalUserId` from the auth provider, mapped to internal `users` row

### 4.2 Webhook auth (required)
Webhook endpoints MUST NOT rely on user auth.
Instead they MUST verify provider signatures (see §9).

### 4.3 Admin operations (optional v1)
If admin endpoints exist, they MUST be separately gated (role/allowlist) and MUST be auditable.

---

## 5) Resource shapes (v1)

### 5.1 Product
```ProjectWHS/specprompt.com/project_spec/spec_v1/10_API_CONTRACTS.md#L1-999
{
  "productId": "string",
  "name": "string",
  "description": "string",
  "status": "active|inactive",
  "assetRef": { "kind": "fleetprompt_listing", "listingId": "string" },
  "createdAtMs": 0,
  "updatedAtMs": 0
}
```

### 5.2 Plan
```ProjectWHS/specprompt.com/project_spec/spec_v1/10_API_CONTRACTS.md#L1-999
{
  "planId": "string",
  "productId": "string",
  "type": "one_time|subscription",
  "currency": "USD",
  "amountCents": 0,
  "interval": "month|year|null",
  "status": "active|inactive",
  "provider": "stripe",
  "providerPriceId": "string|null",
  "eligibilityPolicy": { "type": "one_time_major", "major": 1 },
  "createdAtMs": 0,
  "updatedAtMs": 0
}
```

### 5.3 Order
```ProjectWHS/specprompt.com/project_spec/spec_v1/10_API_CONTRACTS.md#L1-999
{
  "orderId": "string",
  "userId": "string",
  "provider": "stripe",
  "status": "pending_payment",
  "productId": "string",
  "planId": "string",
  "quantity": 1,
  "assetRef": { "kind": "fleetprompt_listing", "listingId": "string", "releaseId": "string" },
  "providerCustomerId": "string|null",
  "providerCheckoutSessionId": "string|null",
  "providerSubscriptionId": "string|null",
  "createdAtMs": 0,
  "updatedAtMs": 0
}
```

### 5.4 Entitlement
```ProjectWHS/specprompt.com/project_spec/spec_v1/10_API_CONTRACTS.md#L1-999
{
  "entitlementId": "string",
  "userId": "string",
  "productId": "string",
  "status": "active",
  "eligibilityPolicy": { "type": "subscription_updates_while_active", "eligibleThroughMs": null },
  "source": {
    "orderId": "string",
    "provider": "stripe",
    "providerSubscriptionId": "string|null"
  },
  "createdAtMs": 0,
  "updatedAtMs": 0
}
```

### 5.5 Artifact
Artifacts are SpecPrompt-owned deliverables (recommended). They can represent external assets via `assetRef`, but the deliverable is controlled here.

```ProjectWHS/specprompt.com/project_spec/spec_v1/10_API_CONTRACTS.md#L1-999
{
  "artifactId": "string",
  "productId": "string",
  "version": "1.2.3",
  "major": 1,
  "status": "active|withdrawn",
  "assetRef": { "kind": "fleetprompt_listing", "listingId": "string", "releaseId": "string" },
  "storage": {
    "provider": "r2|s3|local",
    "key": "string",
    "contentType": "application/zip",
    "sizeBytes": 0
  },
  "sha256": "hex-string",
  "releasedAtMs": 0,
  "createdAtMs": 0
}
```

### 5.6 Download token
```ProjectWHS/specprompt.com/project_spec/spec_v1/10_API_CONTRACTS.md#L1-999
{
  "downloadTokenId": "string",
  "userId": "string",
  "artifactId": "string",
  "status": "issued",
  "expiresAtMs": 0,
  "singleUse": true,
  "createdAtMs": 0
}
```

---

## 6) Headers and idempotency

### 6.1 Request correlation
Servers SHOULD accept:
- `X-Request-Id: <string>`

Servers MUST always return:
- `X-Request-Id: <string>` (generated if missing)

Errors MUST include the same value as `error.requestId`.

### 6.2 Idempotency-Key (required for retryable POST)
Retryable POST endpoints MUST accept:
- `Idempotency-Key: <string>` (opaque, max length recommended: 200)

Idempotency rules:
- The server MUST dedupe based on `(userId, endpoint, idempotencyKey)`.
- If the same idempotency key is reused with a materially different request body, the server MUST return `CONFLICT`.

Endpoints that MUST support idempotency in v1:
- `POST /v1/checkout`
- `POST /v1/fulfillment/token`
- (admin) product/plan/artifact mutations if present

---

## 7) Endpoints (HTTP form, v1)

### 7.1 Health (optional but recommended)
#### 7.1.1 Health check
`GET /v1/health`

Response:
```ProjectWHS/specprompt.com/project_spec/spec_v1/10_API_CONTRACTS.md#L1-999
{ "ok": true }
```


---

## 8) Checkout

### 8.1 Create checkout session
`POST /v1/checkout`

Auth: required  
Idempotency: REQUIRED via `Idempotency-Key`

Request:
```ProjectWHS/specprompt.com/project_spec/spec_v1/10_API_CONTRACTS.md#L1-999
{
  "productId": "string",
  "planId": "string",
  "quantity": 1,
  "assetRef": { "kind": "fleetprompt_listing", "listingId": "string", "releaseId": "string" },
  "successUrl": "https://…",
  "cancelUrl": "https://…"
}
```


Rules:
- `quantity` MUST be bounded (recommended max 100).
- `successUrl` and `cancelUrl` MUST be allowlisted or validated to prevent open redirects.

Response (provider-agnostic):
```ProjectWHS/specprompt.com/project_spec/spec_v1/10_API_CONTRACTS.md#L1-999
{
  "order": {
    "orderId": "string",
    "status": "pending_payment",
    "productId": "string",
    "planId": "string",
    "createdAtMs": 0,
    "updatedAtMs": 0
  },
  "checkout": {
    "provider": "stripe",
    "checkoutSessionId": "string",
    "checkoutUrl": "https://…"
  }
}
```

Errors:
- `VALIDATION_FAILED` (bad ids, bad URLs)
- `NOT_FOUND` (product/plan not found or inactive; or choose `VALIDATION_FAILED` consistently)
- `RATE_LIMITED`
- `PAYMENT_PROVIDER_ERROR`

Notes:
- The order MUST remain `pending_payment` until verified webhooks transition it.

---

## 9) Webhooks (payment provider → SpecPrompt)

### 9.1 Receive payment provider webhook
`POST /v1/webhooks/payment`

Auth: none  
Verification: REQUIRED (provider signature)

Headers:
- Provider-specific signature headers (e.g., Stripe: `Stripe-Signature`)
- Content-Type must match provider signing requirements (often `application/json`)

Body:
- Raw provider webhook payload (treated as opaque by HTTP layer; verification uses raw bytes)

Response:
```ProjectWHS/specprompt.com/project_spec/spec_v1/10_API_CONTRACTS.md#L1-999
{ "ok": true }
```


Rules (normative):
- SpecPrompt MUST verify signature using raw bytes.
- SpecPrompt MUST store the verified event in an append-only table keyed by `providerEventId` (unique).
- Processing MUST be idempotent:
  - duplicates return `{ "ok": true }` and do not re-issue entitlements.
- SpecPrompt MUST NOT log raw webhook bodies in production logs unbounded:
  - store a bounded safe subset + a hash of raw body if needed.

Errors:
- `WEBHOOK_VERIFICATION_FAILED`
- `VALIDATION_FAILED` (unsupported event type / malformed payload)
- `INTERNAL`

### 9.2 Event mapping (provider-agnostic semantics)
SpecPrompt MUST map provider events to internal transitions:
- Payment succeeded → order transitions to `paid` or `active` and triggers entitlement issuance
- Payment failed → `failed`
- Refund → `refunded` and triggers entitlement revocation (per policy)
- Subscription canceled/unpaid → `canceled` and/or entitlement becomes `inactive`

Out-of-order events:
- The system MUST converge deterministically.
- Event processing MUST be safe to replay.

---

## 10) Orders

### 10.1 List my orders
`GET /v1/orders?cursor=...&limit=...`

Auth: required

Response:
```ProjectWHS/specprompt.com/project_spec/spec_v1/10_API_CONTRACTS.md#L1-999
{
  "items": [
    {
      "orderId": "string",
      "status": "active",
      "productId": "string",
      "planId": "string",
      "createdAtMs": 0,
      "updatedAtMs": 0
    }
  ],
  "nextCursor": "string|null"
}
```

Notes:
- Returned fields SHOULD be safe and minimal (no payment instrument details).

### 10.2 Get my order
`GET /v1/orders/:orderId`

Auth: required  
IDOR-safe: MUST return `NOT_FOUND` if the order is not owned by caller.

Response:
```ProjectWHS/specprompt.com/project_spec/spec_v1/10_API_CONTRACTS.md#L1-999
{
  "order": {
    "orderId": "string",
    "status": "active",
    "productId": "string",
    "planId": "string",
    "quantity": 1,
    "createdAtMs": 0,
    "updatedAtMs": 0
  }
}
```

---

## 11) Entitlements

### 11.1 List my entitlements
`GET /v1/entitlements?cursor=...&limit=...`

Auth: required

Response:
```ProjectWHS/specprompt.com/project_spec/spec_v1/10_API_CONTRACTS.md#L1-999
{
  "items": [
    {
      "entitlementId": "string",
      "productId": "string",
      "status": "active",
      "eligibilityPolicy": { "type": "one_time_major", "major": 1 },
      "createdAtMs": 0,
      "updatedAtMs": 0
    }
  ],
  "nextCursor": "string|null"
}
```

### 11.2 Check entitlement for product (optional convenience endpoint)
`GET /v1/entitlements/check?productId=...`

Auth: required

Response:
```ProjectWHS/specprompt.com/project_spec/spec_v1/10_API_CONTRACTS.md#L1-999
{
  "productId": "string",
  "hasActiveEntitlement": true,
  "entitlement": {
    "entitlementId": "string",
    "status": "active",
    "eligibilityPolicy": {
      "type": "subscription_updates_while_active",
      "eligibleThroughMs": null
    }
  }
}
```

Notes:
- MUST NOT allow checking entitlements for other users.
- Avoid any endpoint that checks by email/username (anti-enumeration).

---

## 12) Fulfillment

### 12.1 Mint download authorization (token or signed URL)
`POST /v1/fulfillment/token`

Auth: required  
Idempotency: REQUIRED via `Idempotency-Key`

Request:
```ProjectWHS/specprompt.com/project_spec/spec_v1/10_API_CONTRACTS.md#L1-999
{
  "productId": "string",
  "artifactId": "string"
}
```

Response (Pattern A: signed URL):
```ProjectWHS/specprompt.com/project_spec/spec_v1/10_API_CONTRACTS.md#L1-999
{
  "artifactId": "string",
  "mode": "signed_url",
  "downloadUrl": "https://…",
  "expiresAtMs": 0
}
```

Response (Pattern B: token):
```ProjectWHS/specprompt.com/project_spec/spec_v1/10_API_CONTRACTS.md#L1-999
{
  "artifactId": "string",
  "mode": "token",
  "downloadToken": "opaque-string",
  "expiresAtMs": 0
}
```

Rules:
- Server MUST validate:
  - artifact exists
  - artifact belongs to product
  - caller has active entitlement for product
  - entitlement eligibility covers artifact version / release time
- Tokens/URLs MUST be time-bounded.
- If tokens are single-use:
  - redemption MUST transition token status to `redeemed` and deny reuse.

Errors:
- `ENTITLEMENT_INACTIVE`
- `ARTIFACT_NOT_ELIGIBLE`
- `NOT_FOUND` (artifact not visible / wrong product / wrong tenant)
- `RATE_LIMITED`

### 12.2 Download by token (optional proxy)
If using “token + proxy download”:
`GET /v1/fulfillment/download?token=<opaque>`

Auth:
- MAY be optional if token is the bearer credential.
- Recommended v1 defense-in-depth: require both auth + token.

Behavior:
- Validates token:
  - exists, not expired, not revoked, not redeemed (if single-use)
  - belongs to requesting user (if auth required)
- Streams artifact bytes with correct `Content-Type`.

Errors:
- `DOWNLOAD_TOKEN_INVALID`
- `DOWNLOAD_TOKEN_EXPIRED`
- `UNAUTHENTICATED` (if auth required)
- `NOT_FOUND` (to reduce token enumeration; recommended)
- `RATE_LIMITED`

---

## 13) Admin endpoints (optional v1, recommended for operability)

These endpoints are optional in v1 but recommended to avoid manual DB edits. If implemented, they MUST be admin-gated and audited.

- `POST /v1/admin/products`
- `PATCH /v1/admin/products/:productId`
- `POST /v1/admin/plans`
- `PATCH /v1/admin/plans/:planId`
- `POST /v1/admin/artifacts`

Admin artifact registration MUST:
- record `sha256`
- validate `major` matches `version`
- record storage pointer (bucket/key), not raw bytes

---

## 14) Minimal v1 contract checklist (Definition of Done for API)
- [ ] Normalized errors implemented everywhere (§3)
- [ ] `POST /v1/checkout` creates an order and returns provider checkout URL (§8)
- [ ] `POST /v1/webhooks/payment` verifies signatures and is idempotent (§9)
- [ ] `GET /v1/orders` and `GET /v1/orders/:orderId` are tenant-safe (§10)
- [ ] `GET /v1/entitlements` is tenant-safe and stable (§11)
- [ ] `POST /v1/fulfillment/token` enforces eligibility and returns token/URL (§12)
- [ ] Rate limiting is in place for checkout + fulfillment + webhooks (§3.2)
- [ ] No secret leakage in logs/errors (provider secrets, raw webhook bodies) (§9.1)

---