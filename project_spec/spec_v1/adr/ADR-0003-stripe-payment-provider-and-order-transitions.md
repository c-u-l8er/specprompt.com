# ADR-0003: Stripe Payment Provider & Webhook Event → Order Transitions (SpecPrompt)
- **Status:** Accepted
- **Date:** 2026-02-01
- **Owners:** Engineering
- **Decision scope:** Lock Stripe as the v1 payment provider and define the canonical mapping from Stripe webhook events to SpecPrompt `orders.status` transitions (and the derived entitlement effects).

Related specs / ADRs:
- `project_spec/spec_v1/00_MASTER_SPEC.md` (Flows A–F; §6.2 order state machine; §13 open questions)
- `project_spec/spec_v1/10_API_CONTRACTS.md` (§9 Webhooks; §8 Checkout; §12 Fulfillment)
- `project_spec/spec_v1/adr/ADR-0001-webhook-integrity-and-idempotency.md` (raw-bytes verification + dedupe)
- `project_spec/spec_v1/adr/ADR-0002-entitlements-and-eligibility.md` (entitlement effects; revocation semantics)

---

## Context

SpecPrompt requires a payment provider for v1 that supports:
- hosted checkout (minimizes PCI scope),
- cryptographically verifiable webhooks,
- reliable object identifiers for correlation and dedupe,
- support for one-time purchases and subscriptions.

We must lock:
1) the payment provider (Stripe vs other), and
2) which provider event types are authoritative for driving SpecPrompt’s internal Order state machine.

Without a locked mapping, implementation will drift and v1 acceptance tests (checkout → webhook → entitlement → fulfillment → refund/chargeback) will be ambiguous.

---

## Decision

### 1) Provider choice: Stripe (normative)

SpecPrompt v1 uses **Stripe** as the payment provider.

- Checkout creation uses **Stripe Checkout** (recommended) because it provides a stable session lifecycle and simplifies client-side concerns.
- Webhook verification uses Stripe’s signing scheme and MUST be verified over **raw request body bytes** (see ADR-0001).

### 2) Authoritative webhook events (normative)

SpecPrompt treats the following Stripe events as authoritative inputs for order transitions in v1:

#### Primary “paid” / “purchase completed” signals
- `checkout.session.completed`
  - authoritative for “purchase completed” when:
    - `data.object.payment_status == "paid"` (for `mode="payment"`), OR
    - `mode="subscription"` and the session completed successfully (see mapping rules below).

#### Asynchronous payment flows (bank redirects, delayed confirmation)
- `checkout.session.async_payment_succeeded`
- `checkout.session.async_payment_failed`

#### Refunds and disputes (revocation-class events)
- `charge.refunded` (refund)
- `charge.dispute.created` (chargeback/dispute)

#### Subscription lifecycle (minimum viable)
- `customer.subscription.deleted` (subscription ended / canceled)
- `invoice.paid` (subscription renewal payment succeeded; keeps order/entitlement active)
- `invoice.payment_failed` (subscription payment failed; may lead to cancellation/inactivity per policy)

> Notes:
> - Stripe offers multiple equivalent signals (PaymentIntents, Invoices, Charges).
> - For v1, **Checkout session events are preferred** as the correlation anchor, and invoice/subscription events are used for subscription lifecycle.
> - PaymentIntent events MAY be ingested for debugging/forensics, but MUST NOT introduce duplicate entitlement issuance (see idempotency rules).

---

## Normative invariants

### A) Webhook verification and dedupe
1. Webhook signature verification MUST be performed using Stripe’s recommended scheme **over raw request bytes**.
2. Verified events MUST be persisted append-only in `paymentEvents` and deduped by:
   - `(provider="stripe", providerEventId=event.id)`.

If the same Stripe `event.id` is delivered multiple times:
- return success (`{ ok: true }`),
- do not apply side effects a second time.

### B) Binding events to internal orders MUST be server-controlled
SpecPrompt MUST bind Stripe objects to internal orders using server-controlled data, in priority order:

1. `checkout.session.metadata.orderId` set by SpecPrompt at checkout creation (preferred).
2. Server-stored Stripe object ids captured at checkout creation time, such as:
   - `orders.providerCheckoutSessionId`
   - `orders.providerPaymentIntentId` (if recorded)
   - `orders.providerSubscriptionId` (if recorded)

SpecPrompt MUST NOT trust any client-supplied “orderId” unless it was set by SpecPrompt into Stripe metadata (or is otherwise securely bound).

### C) Monotonic convergence under out-of-order delivery
Stripe events may arrive out of order. SpecPrompt MUST converge deterministically.

v1 order status precedence (highest wins) is:

1. `disputed`
2. `refunded`
3. `canceled`
4. `active`
5. `paid`
6. `failed`
7. `pending_payment`

Rules:
- A transition to a higher-precedence terminal status MUST NOT be undone by later lower-precedence events.
- If a lower-precedence event arrives after a higher-precedence status is already set, processing is a no-op (but the payment event is still recorded).

Rationale:
- Prevents oscillation and entitlement “flapping” under retries/out-of-order delivery.
- Keeps revocation semantics stable (refund/chargeback remain revocations even if a “paid” event is replayed).

---

## Event mapping: Stripe → SpecPrompt order transitions (normative)

This section is the canonical mapping for v1.

### 1) Checkout completion (one-time purchase)
**Stripe event:** `checkout.session.completed`  
**Condition:** `data.object.mode == "payment"` AND `data.object.payment_status == "paid"`

**Transition:**
- `pending_payment` → `paid`

**Required side effects (idempotent):**
- Persist `paymentEvents` row (dedupe by `event.id`)
- Upsert order linkage fields if present:
  - `orders.providerCheckoutSessionId = session.id`
  - `orders.providerCustomerId = session.customer` (if present)
  - `orders.providerPaymentIntentId = session.payment_intent` (if present)
- Trigger entitlement issuance (per entitlement policy; exactly-once)

**Notes:**
- If `payment_status != "paid"` (e.g., `unpaid`), do not mark `paid`.
- If order is already `paid|active|refunded|disputed|canceled`, do not downgrade.

---

### 2) Checkout completion (subscription purchase)
**Stripe event:** `checkout.session.completed`  
**Condition:** `data.object.mode == "subscription"`

**Transition:**
- `pending_payment` → `active` (recommended v1 behavior)

**Required side effects (idempotent):**
- Persist `paymentEvents` row (dedupe by `event.id`)
- Set:
  - `orders.providerCheckoutSessionId = session.id`
  - `orders.providerCustomerId = session.customer` (if present)
  - `orders.providerSubscriptionId = session.subscription` (if present)
- Trigger entitlement issuance with subscription eligibility policy:
  - initial state: active (eligible “while active”)

**Notes / caveats:**
- Some subscription setups can complete the session while payment finalization is asynchronous.
- If you observe inconsistent activation timing in practice, you MAY additionally require a confirming event (e.g., `invoice.paid`) before issuing entitlements, but that MUST be captured in a follow-up ADR and tests updated accordingly. v1 default is as above.

---

### 3) Asynchronous payment outcomes
**Stripe events:**
- `checkout.session.async_payment_succeeded`
- `checkout.session.async_payment_failed`

**Transitions:**
- `async_payment_succeeded`:
  - `pending_payment` → `paid` (for `mode="payment"`)
  - `pending_payment` → `active` (for `mode="subscription"`)
- `async_payment_failed`:
  - `pending_payment` → `failed`

**Side effects:**
- Record payment event (dedupe by `event.id`)
- Apply linkage field updates as available from the session
- On success: trigger entitlement issuance (idempotent)
- On failure: no entitlements; keep order terminal as `failed` unless a higher-precedence event arrives later

---

### 4) Refunds (revocation)
**Stripe event:** `charge.refunded`

**Transition:**
- `paid|active` → `refunded`
- `pending_payment|failed` → `refunded` (allowed; precedence applies)

**Side effects:**
- Record payment event (dedupe)
- Revoke entitlement deterministically (append-only entitlement event + current entitlement state update)
- Fulfillment MUST be denied after revocation (even if a user holds an older token/link, subject to fulfillment mode)

**Notes:**
- Partial refunds: v1 treats `charge.refunded` as refunded; if partial refunds must be supported later, add an ADR to define thresholds and partial entitlement policy.

---

### 5) Disputes / chargebacks (revocation)
**Stripe event:** `charge.dispute.created`

**Transition:**
- `paid|active|refunded|canceled|pending_payment|failed` → `disputed` (highest precedence)

**Side effects:**
- Record payment event (dedupe)
- Revoke entitlement immediately (append-only revocation event)
- Fulfillment MUST be denied after dispute (even if it was previously allowed)

---

### 6) Subscription renewals and failures (subscription lifecycle)
These events keep subscription-backed entitlements aligned with ongoing billing.

#### 6.1 Renewal success
**Stripe event:** `invoice.paid`

**Transition:**
- If order corresponds to the subscription: keep or set `active`:
  - `pending_payment|paid|failed` → `active` (if subscription is the product plan)
  - `active` remains `active`

**Side effects:**
- Record payment event (dedupe)
- Update subscription entitlement eligibility window if you track it explicitly:
  - e.g., set/extend `eligibleThroughMs` based on invoice period end (if modeled)

#### 6.2 Renewal payment failure
**Stripe event:** `invoice.payment_failed`

**Transition (v1 policy):**
- `active` MAY remain `active` temporarily, but SHOULD move to `canceled` (or `failed`) only once Stripe ends/cancels the subscription.
- v1 default:
  - record event only; do not immediately set `canceled` unless subscription is definitively ended.
  - entitlement remains active until `customer.subscription.deleted` arrives.

**Rationale:**
- Stripe often retries failed payments; immediately canceling entitlements can cause flapping.
- Definitive end is represented by subscription deletion/cancellation.

#### 6.3 Subscription ended/canceled
**Stripe event:** `customer.subscription.deleted`

**Transition:**
- `active` → `canceled`

**Side effects:**
- Record payment event (dedupe)
- Entitlement becomes `inactive` (or `revoked`, depending on your entitlement model):
  - v1 recommended: `inactive` (not punitive; simply no longer eligible)

---

## Implementation guidance (non-normative)

### Minimal Stripe objects to persist (safe-by-default)
Persist a bounded subset in `paymentEvents.summary`, such as:
- `event.type`, `event.id`, `created`
- key object ids:
  - `checkoutSessionId`, `paymentIntentId`, `chargeId`, `invoiceId`, `subscriptionId`, `customerId`
- amounts/currency (if needed for receipts), avoiding payment method details

Do NOT persist:
- raw webhook body unbounded,
- signature header contents,
- payment instrument details.

### Processing pipeline sketch
1. Receive webhook request and raw bytes.
2. Verify Stripe signature (raw bytes).
3. Dedup by `event.id` into `paymentEvents`.
4. Resolve internal order via `metadata.orderId` or stored provider ids.
5. Apply deterministic transition using precedence rules.
6. Apply entitlement grant/revoke (idempotent, append-only ledger).
7. Return `{ ok: true }`.

---

## Consequences

### Positive
- Locks v1 provider and makes webhook behavior testable.
- Deterministic transitions under duplicates/out-of-order delivery.
- Clear revocation semantics (refunds/disputes win).

### Tradeoffs
- Requires a small set of Stripe event types to be enabled and tested.
- Subscription lifecycle is intentionally minimal in v1; expanding to richer behaviors (trials, pauses, partial refunds) should be done via new ADRs.

---

## Acceptance criteria

This ADR is satisfied when:
1. SpecPrompt can create a Stripe Checkout session with `metadata.orderId`.
2. `POST /v1/webhooks/payment` verifies Stripe signatures over raw bytes and dedupes by `event.id`.
3. The following end-to-end flows are proven:
   - checkout → `checkout.session.completed` → order `paid|active` → entitlement granted
   - refund (`charge.refunded`) → order `refunded` → entitlement revoked/inactive → fulfillment denied
   - dispute (`charge.dispute.created`) → order `disputed` → entitlement revoked/inactive → fulfillment denied
4. Duplicate webhook deliveries do not create duplicate entitlements or fulfillment grants.
5. Out-of-order delivery converges using the precedence rules without oscillation.

---