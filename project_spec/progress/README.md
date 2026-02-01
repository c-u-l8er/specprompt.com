# project_spec/progress — Daily Engineering Progress Logs (SpecPrompt)

This folder contains **daily, append-only engineering progress logs** for the `specprompt.com` v1 implementation effort.

- These logs are **non-normative** (they do not define requirements).
- The **normative spec** remains `project_spec/spec_v1/` (especially `00_MASTER_SPEC.md`, `10_API_CONTRACTS.md`, and ADRs in `spec_v1/adr/`).
- The purpose here is to document **what changed**, **why**, and **what’s next**, day-by-day, in a way that’s easy to audit.

If a progress log conflicts with `project_spec/spec_v1/`, **the spec wins**.

---

## Folder structure

- `progress/README.md` — this index + conventions (you are here)
- `progress/YYYY-MM-DD.md` — one file per day

Recommended: create a new file for each day you do meaningful work, even if it’s short.

---

## Naming convention

Daily logs MUST be named:

- `YYYY-MM-DD.md` (UTC date recommended)

Examples:
- `2026-01-31.md`
- `2026-02-01.md`

---

## Writing rules (conventions)

### 1) Append-only
- Do **not** rewrite history.
- If you need to correct something from a prior day, add a note in today’s log under **Corrections**.

### 2) Traceability and scope
Each daily log SHOULD include:
- What you shipped (high-level)
- Key decisions (with references to ADRs/spec sections)
- Files/dirs touched (short list)
- What’s still missing / follow-ups
- Known issues or risks
- Validation performed (typecheck/tests/manual steps)

### 3) Keep it implementation-focused
This is an engineering log, not a product diary. Prefer:

- “Implemented webhook verification over raw request bytes and deduped by `(provider, providerEventId)`”
over
- “Worked on webhooks”

### 4) No secrets
Never include:
- API keys, tokens, credentials
- raw payment provider webhook bodies
- download tokens / signed URL query strings
- private customer/payment instrument data

Use placeholders:
- `STRIPE_WEBHOOK_SECRET=***`
- `downloadToken=***`
- `https://example.com/download?token=***`

### 5) Ledger-first mindset
SpecPrompt is a commerce ledger. When you ship something that mutates state, note:
- which append-only table/ledger row is written (e.g., `paymentEvents`, `entitlementEvents`, `fulfillmentEvents`)
- what the dedupe key is (e.g., `(provider, providerEventId)`, `dedupeKey`)
- what idempotency key surface exists (e.g., `Idempotency-Key`)

### 6) Call out convergence/idempotency guarantees explicitly
When you change webhook processing or fulfillment, explicitly record:
- how duplicates are handled
- how out-of-order events converge (and any monotonicity rules)
- what happens on partial failures + retries

---

## Daily log template

Copy/paste this into a new `YYYY-MM-DD.md` file:

---

# YYYY-MM-DD — Progress Log (SpecPrompt)

## Summary (1–3 bullets)
- …
- …

## Spec/ADR alignment notes
- ✅ Implemented: (reference relevant doc sections)
- ⚠️ Deviations: (explain why; plan to reconcile)
- ❓ Open questions discovered: (link to spec “Open questions” if applicable)

## What shipped today
### API / Webhooks
- …

### Commerce ledger & state machine
- …

### Entitlements
- …

### Fulfillment / artifacts
- …

## Key decisions made (lock v1 behavior)
- Decision: …
  - Rationale: …
  - References: `spec_v1/adr/ADR-....md`, `10_API_CONTRACTS.md §...`

## Data model / migrations
- Schema changes:
  - …
- Invariants enforced:
  - …

## Security & secrets
- Webhook integrity:
  - (raw-body verification, signature checks, dedupe strategy)
- Fulfillment protection:
  - (token TTL, single-use policy, revocation behavior)
- Logging:
  - (no raw webhooks, no tokens, no secrets)

## Files touched (high-level)
- `...`
- `...`

## Validation performed
- Typecheck/tests:
  - …
- Manual verification:
  - …

## Known issues / risks
- …

## Next steps
- [ ] …
- [ ] …

## Corrections (if needed)
- …

---

## Suggested index section (optional)

If you want this README to also act like an index, keep an “Index” section updated manually:

### Index
- `YYYY-MM-DD.md` — short title

(Keeping it manual is fine; automation can come later if needed.)

---

## Why this exists

This folder supports:
- auditability (“what changed when?”),
- implementation pacing (“are we converging on v1 acceptance criteria?”),
- easier handoffs and reviews (especially around idempotency + ledger semantics).

Progress logs are intentionally practical and implementation-oriented. Normative requirements live in `project_spec/spec_v1/`.