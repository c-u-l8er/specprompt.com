SpecPrompt
==========

SpecPrompt is **Layer 6 (Commerce & Monetization)** in the WHS 6-layer ecosystem.

It provides:
- **Checkout & payments integration**
- **Licensing / entitlements**
- **Fulfillment** (download tokens and/or signed URLs)
- **Append-only commerce ledger** (orders, payment events, entitlement events, fulfillment events)

SpecPrompt **does not**:
- execute WHS agents (that’s **WebHost.Systems**)
- execute Agentromatic workflows (that’s **Agentromatic**)
- replace marketplace discovery/listings UI (that’s **FleetPrompt**)
- bypass Delegatic/Agentelic/WHS authorization (entitlement ≠ membership/role)

---

## Where to read the current spec (v1)

The **normative, implementation-ready v1 spec** lives here:

- `project_spec/spec_v1/README.md` — spec overview + reading order
- `project_spec/spec_v1/00_MASTER_SPEC.md` — master engineering spec (scope, flows, invariants, acceptance)
- `project_spec/spec_v1/10_API_CONTRACTS.md` — API shapes, normalized errors, pagination, idempotency
- `project_spec/spec_v1/30_DATA_MODEL_CONVEX.md` — data model + access control + invariants (Convex)
- `project_spec/spec_v1/40_SECURITY_SECRETS_COMPLIANCE.md` — threat model, webhook integrity, secrets, token safety
- `project_spec/spec_v1/50_OBSERVABILITY_BILLING_LIMITS.md` — observability, retention, abuse controls, operational limits
- `project_spec/spec_v1/60_TESTING_ACCEPTANCE.md` — test plan + release gates
- `project_spec/spec_v1/REALIGNMENT_PLAN.md` — spec-to-implementation checklist

ADRs (architecture decisions):
- `project_spec/spec_v1/adr/ADR-0001-webhook-integrity-and-idempotency.md`
- `project_spec/spec_v1/adr/ADR-0002-entitlements-and-eligibility.md`

---

## Portfolio context (one-liner)

Portfolio taxonomy (canonical):
- **WebHost.Systems (WHS)** = agents (deploy/invoke/telemetry/limits/billing for runtime usage)
- **Agentromatic** = workflows (definitions/executions/logs)
- **Agentelic** = telespaces (rooms/messages/automations referencing WHS + Agentromatic)
- **Delegatic** = organizations (governance/policies; reference-first)
- **FleetPrompt** = marketplace/distribution (discovery/listings/install handoff)
- **SpecPrompt** = commerce (checkout, licensing, entitlements, fulfillment)

---

## Notes on scope and boundaries

SpecPrompt’s core boundary rules:
1. **Webhook truth**: payment-provider webhooks are authoritative only after **cryptographic verification over raw request bytes**.
2. **Idempotency**: client POSTs and webhook processing must be safe under retries/duplicates/out-of-order delivery.
3. **References, not copies**: do not mirror upstream runtime logs/telemetry/transcripts; store only references and bounded commerce metadata.
4. **Entitlement ≠ authorization**: other systems must still enforce their own tenant isolation and role checks.

---

## Notes on older materials

If other scratch docs exist outside `project_spec/spec_v1/`, treat them as **non-normative** background. The source of truth is `project_spec/spec_v1/`.