# SpecPrompt

Content-addressed identity for specifications — a spec whose name is a hash of
what it says, so changing the claim changes the name. Elixir/OTP with a Phoenix
API and an MCP server. Part of the [ComputeDriven](https://computedriven.com)
world.

**Written 2026-08-16.** This repository had no README before that date. Every
figure below was measured that day with the command beside it.

---

## Status, honestly

| | |
|---|---|
| Version | `0.1.0` (`mix.exs`, app `:specprompt`) |
| Tests | **71 passing, 0 failures** — `mix test` |
| Marketing page | **live** — `https://specprompt.com` answers 200 |
| Application | **live on Fly** as app `specprompt` — `https://app.specprompt.com` answers 200 |
| Evidence rung | `live_deployed` |

**The test count is 71, not 93.** `COMPUTEDRIVEN_POSITIONING_PLAN.md` says 93;
the suite says 71. The suite counts itself and the plan does not. Quote
`mix test`; never hand-type this number.

**What is live is the prior design.** The marketing page describes
content-addressed spec identity. What is deployed predates that, which is why
the portfolio nav carries `status: "live · prior design"` rather than "shipped".
It runs; it is not yet the thing the page describes.

## Two modes, and only one of them is superseded

The spec defines a **filesystem mode** (git-based, no database, auth-optional,
for local CLI use) and a **registry mode** (multi-tenant, Supabase-backed). This
distinction matters more here than in the sibling repositories:

- **Filesystem mode is unaffected** by the data-layer ruling. It commits to git
  and needs no database at all.
- **Registry mode rests on the abandoned shared-Supabase layer** — `spec.specs`,
  workspace scoping, `amp.profiles` identity via Supabase Auth.

## Quick start

```bash
mix deps.get
mix compile --warnings-as-errors
mix test                       # 71 tests
mix format --check-formatted
mix phx.server
```

Deploy is `fly deploy` against `fly.toml` (app `specprompt`).

The deployed MCP endpoint answers on `POST /mcp`. Note it is content-type
particular — a bare JSON-RPC POST without the accept header it wants returns
**406**, which is the app refusing the request rather than failing to serve it.

## The specification is authoritative, and superseded in part

`docs/spec/README.md` (v1.1, dated February 2026) drives implementation. It
carries a supersession banner added 2026-08-15:

- **Superseded:** §5.2's Supabase schema, the `workspace_id` multi-tenancy,
  `supabase://auth` as the identity source — everything in registry mode that
  rests on the shared data layer abandoned by ruling on **2026-07-30**. The
  replacement, `studbook`, is a spec with no implementation and is blocked on an
  unruled confidentiality question. **Do not build against it yet.**
- **Not superseded:** the content-addressing design, the spec identity model, the
  filesystem mode, and the CLI. That is the part worth reading.

The spec was **not rewritten**. It is a dated design record and rewriting it
would fabricate a review nobody performed.

## A standing direction that affects this repository

Ruled 2026-08-15: **compute moves into the ComputeDriven OS, and the Fly.io apps
become storage or nothing.** This app is one of them. Nothing is torn down before
its OS-side replacement runs locally, but check `STACK_HUB.md` in the workspace
before planning new Fly-shaped work.

## The portfolio nav

`amp-nav.js` is a **deployed copy**. The source is
`ampersand-nav/src/amp-nav.js`, fanned out by `sync-nav.sh`. Edits here are lost
on the next sync.

## Conventions

- `mix format`, warnings-as-errors.
- Never commit secrets.
- `old_scrap/` is historical and not authoritative.

## Related

- [computedriven.com](https://computedriven.com) — the discipline this is built under
- [fleetprompt.com](https://fleetprompt.com) — the registry that installs what this names
- [bendscript.com](https://bendscript.com) — graph-first documents, which reference this
- [ampersandboxdesign.com](https://ampersandboxdesign.com) — the [&] Protocol
