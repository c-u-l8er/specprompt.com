/* ==========================================================================
   specprompt.com publication gate. No dependencies.

       node launch-gate.mjs        (run it via ./site.sh)

   It reads the ARTIFACT — the emitted index.html, derive.js and form.js — and
   refuses when the artifact says something the records do not support.
   build-site.mjs already refuses on count drift; this refuses on the other
   ways a page lies: a retracted claim coming back, a rung invented, a call to
   action the rung has not earned, an unrendered token, a mailbox, an
   unreadable caveat, a button whose colour is decided by the wrong rule, an
   animation whose internals have leaked into the copy.

   SHELL.md §4, revision shell-r9. Every check has a reason and most have a
   scar. Three of them are corrections this shell paid for in public:

     r6a  COUNT a blocklisted string, do not DETECT it. The reference gate
          asked "is the retraction present?" and then permitted the string
          everywhere once the answer was yes, so a page could keep its
          retraction AND put the sentence back in the hero. Bounded here with
          an explicit min and max per string.
     r6b  PROVE THE ARTIFACT IS THIS BUILD'S. If the build throws, the previous
          index.html stays on disk and a gate that reads it approves a stale
          file. Hashes are recorded at emit and re-derived here.
     r8   STRIP COMMENTS AS THEIR OWN PASS. `<[^>]+>` stops at the first `>`,
          so an HTML comment containing one is only half-removed and its
          remainder is counted as visible page text. Every text-derived check
          below goes through visibleText(), which strips comments first.
     r8   RESOLVE THE CASCADE, do not read declared tokens. `.top nav a` beats
          `.btn` on specificity and painted the header CTA unreadable on nine
          surfaces while every contrast check passed, because contrast checks
          read tokens and browsers paint computed values.
   ========================================================================== */
import { readFileSync, existsSync } from "fs";
import { createHash } from "crypto";

const read = (p) => readFileSync(p, "utf8");
const J = (p) => JSON.parse(read(p));
const sha = (s) => createHash("sha256").update(s).digest("hex");

const surface = J("./records/surface.json");
const tests = J("./records/tests.json");

let pass = 0,
    fail = 0;
function T(name, ok, detail = "") {
    console.log(`${ok ? "PASS" : "FAIL"}  ${name}${detail ? " — " + detail : ""}`);
    ok ? pass++ : fail++;
}

const ARTIFACTS = ["./index.html", "./derive.js", "./form.js"];
for (const f of ARTIFACTS) {
    if (!existsSync(f)) {
        console.error(`FAIL  missing artifact ${f} — run the build first`);
        process.exit(1);
    }
}
const landing = read("./index.html");
const anim = read("./derive.js");

/* ==========================================================================
   THE TEXT EXTRACTOR — r8. Comments are their own pass, and they come first.

   Confirmed on a sibling surface: naive `<[^>]+>` stripping left a lone glyph
   from a hero comment on the page's "visible text", and two checks read it —
   one of them the retraction counter, whose entire job is telling visible from
   hidden. Everything below that reasons about what a reader sees goes through
   here.
   ========================================================================== */
const ENT = {
    "&nbsp;": " ", "&ensp;": " ", "&mdash;": "—", "&ndash;": "–", "&minus;": "−",
    "&rarr;": "→", "&uarr;": "↑", "&amp;": "&", "&copy;": "©", "&lt;": "<", "&gt;": ">",
    "&quot;": '"', "&times;": "×", "&middot;": "·", "&hellip;": "…", "&ldquo;": "“",
    "&rdquo;": "”", "&rsquo;": "’", "&sect;": "§",
};
function stripToText(html) {
    return html
        .replace(/<!--[\s\S]*?-->/g, " ")
        .replace(/<script[\s\S]*?<\/script>/gi, " ")
        .replace(/<style[\s\S]*?<\/style>/gi, " ")
        .replace(/<[^>]*>/g, "\n");
}
function visibleText(html) {
    return stripToText(html)
        .split("\n")
        .map((s) => s.replace(/&\w+;/g, (e) => (e in ENT ? ENT[e] : e)).trim())
        .filter(Boolean);
}
/* r12 — TEST PHRASES AGAINST NODES, NOT A FLATTENED BLOB.
   `html.replace(/<[^>]+>/g," ")` is the usual next step after stripping
   comments, and it merges every text node into one run so that a rule like
   `includes("Get started")` can match text a reader never sees together — or,
   where the blob is then split on whitespace, can never match at all. Two
   multi-word rules on a sibling surface were silently unfalsifiable that way,
   one of them "no signup CTA at the spec rung". visibleText() splits ON tags,
   so each text node survives as one node; PHRASE() asks the nodes. */
const NODES = visibleText(landing);
const PHRASE = (p) => NODES.some((n) => n.toLowerCase().includes(p.toLowerCase()));
/* Kept for substring questions that are deliberately node-agnostic (a stray
   email address, a dangling § citation) — never for a phrase rule. */
const VISIBLE = NODES.join("\n");
/* And the markup with comments removed, for questions about what was emitted
   rather than what is read — an href in a comment is not a link either. */
const MARKUP = landing.replace(/<!--[\s\S]*?-->/g, " ");

/* Prove the extractor itself, on this artifact. A silent regression here
   silently weakens four other checks. */
{
    const comments = [...landing.matchAll(/<!--([\s\S]*?)-->/g)].map((m) => m[1]);
    const withAngle = comments.filter((c) => c.includes(">"));
    const leaked = withAngle
        .flatMap((c) => c.split(">").slice(1).join(">").split(/\s+/))
        .map((w) => w.trim())
        .filter((w) => w.length > 6)
        .filter((w) => VISIBLE.includes(w) && !stripToText(MARKUP).includes(w));
    T("the text extractor removes comments before tags (r8)", leaked.length === 0,
        `${comments.length} comments, ${withAngle.length} containing '>' — none leaked`);
    /* r12 — and it must keep a text node whole, or every multi-word rule below
       is unfalsifiable while reporting PASS. Proved against a phrase this page
       actually contains and one it does not, so a refactor that shreds nodes
       into words fails HERE rather than silently disarming the blocklists. */
    const multi = NODES.filter((n) => n.split(" ").length > 3).length;
    T("the text extractor keeps text nodes whole (r12)",
        multi > 0 && PHRASE(surface.question) && !PHRASE("a phrase this page does not contain"),
        `${NODES.length} nodes, ${multi} of more than three words; the surface question is findable as one phrase`);
}

/* ---------- 1. release identity ---------- */
const mixVersion = (/version:\s*"([^"]+)"/.exec(read("./mix.exs")) || [])[1];
T("release identity: mix.exs == records/surface.json", mixVersion === surface.version,
    `${mixVersion} / ${surface.version}`);
const STAMP = `SPECPROMPT v${surface.version} · RECORDS ${surface.verified_at}`;
T("/ carries the canonical stamp", landing.includes(STAMP));
T("the surface records the shell revision it was built against",
    /^shell-r\d+$/.test(surface.shell_revision || ""), surface.shell_revision);

/* ---------- 2. r6b — the artifact is THIS build's ---------- */
{
    if (!existsSync("./records/build.json")) {
        T("the build recorded what it emitted", false, "records/build.json missing — the build never completed");
    } else {
        const build = J("./records/build.json");
        const bad = ARTIFACTS.map((p) => p.replace("./", "")).filter(
            (name) => sha(read("./" + name)) !== build.artifacts[name]
        );
        T("every artifact hashes to what the build recorded emitting", bad.length === 0,
            bad.length ? `STALE: ${bad.join(", ")} — the build threw and left the previous file` : `${ARTIFACTS.length} artifacts`);
        const srcBad = Object.entries(build.sources).filter(([p, h]) => sha(read("./" + p)) !== h);
        T("no source was edited after the emit", srcBad.length === 0,
            srcBad.length ? `CHANGED SINCE BUILD: ${srcBad.map(([p]) => p).join(", ")}` : `${Object.keys(build.sources).length} sources`);
        T("the build and the record agree on the shell revision",
            build.shell_revision === surface.shell_revision);
    }
}
T("/ has no unrendered build token", !/\{\{\w+\}\}/.test(landing));
T("/ declares its canonical URL", landing.includes(`<link rel="canonical" href="${surface.origin}/">`));
T("/ declares the surface's falsifiable question",
    landing.includes(`<meta name="falsifiable-question" content="${surface.question}">`));

/* ---------- 3. the content ships without JavaScript ----------
   SHELL.md §8.4: the animation may require JS; the page's meaning may not, and
   after r9 neither may the correction form. So: nothing inline, and exactly
   three external scripts — the portfolio nav, the identity animation, and the
   form's progressive upgrade. */
{
    const tags = [...landing.matchAll(/<script\b([^>]*)>([\s\S]*?)<\/script>/gi)];
    T("the landing page ships no inline JavaScript", tags.every((t) => t[2].trim() === ""),
        `${tags.length} script tags`);
    const srcs = tags.map((t) => (/\bsrc="([^"]+)"/.exec(t[1]) || [])[1]).filter(Boolean);
    T("the landing page loads only the nav, the animation and the form upgrade",
        srcs.length === 3 && srcs.includes("/amp-nav.js") && srcs.includes("/derive.js") && srcs.includes("/form.js"),
        srcs.join(", "));
    T("the animation and the form upgrade are deferred",
        tags.filter((t) => /\/(derive|form)\.js/.test(t[1])).every((t) => /\bdefer\b/.test(t[1])));
}

/* ---------- 4. r6a — retracted claims may not come back, and the check
   COUNTS rather than DETECTS ----------
   Each string is allowed inside the retraction block, once, because naming the
   wrong claim is what a retraction is. Bounded above AND below: a page that
   quietly drops its retraction fails the same check that catches a page which
   reinstates the claim. */
const retractBlock = (() => {
    const i = landing.indexOf('<div class="retract">');
    if (i < 0) return "";
    const j = landing.indexOf("</section>", i);
    return j < 0 ? landing.slice(i) : landing.slice(i, j);
})();
const tally = (hay, needle) => hay.split(needle).length - 1;
T("the retraction block is present and findable", retractBlock.length > 0);
for (const r of surface.retracted) {
    const onPage = tally(landing, r.string);
    const inBlock = tally(retractBlock, r.string);
    T(`/ quotes "${r.string.slice(0, 46)}${r.string.length > 46 ? "…" : ""}" exactly once, inside the retraction`,
        onPage === 1 && inBlock === 1,
        `${onPage} on the page, ${inBlock} inside the retraction (min 1, max 1)`);
}
T("/ carries the retraction rather than a silent edit",
    /Retraction &mdash;/.test(landing) && /contradicting/.test(landing));

/* ---------- 5. no mailbox, and the ruled correction channel is wired ----------
   r9: Travis ruled the Formspree endpoint for this domain. It must be a REAL
   form — action, method, novalidate — so it posts with scripting off; a fetch
   bolted to a button is the dead-control defect this portfolio keeps finding. */
/* The retraction block is the one place a retracted string may appear, and an
   email address that USED to be published is exactly such a string. So these
   two ask about the page OUTSIDE the retraction — the same rule as the
   blocklist above, which bounds the count inside it to one. */
const OUTSIDE = landing.replace(retractBlock, " ");
const OUTSIDE_TEXT = visibleText(OUTSIDE).join("\n");
T("/ advertises no mailto: link", !/href="\s*mailto:/i.test(landing));
T("/ names no mailto: outside the retraction that removed one", !OUTSIDE.includes("mailto:"));
T("/ publishes no email address outside the retraction",
    !/[\w.+-]+@[\w-]+\.[\w.]+/.test(OUTSIDE_TEXT),
    (/[\w.+-]+@[\w-]+\.[\w.]+/.exec(OUTSIDE_TEXT) || [])[0] || "none in visible text");
T("the correction channel is the ruled Formspree endpoint",
    surface.contact.kind === "formspree" && /^https:\/\/formspree\.io\/f\//.test(surface.contact.endpoint),
    surface.contact.endpoint);
{
    const form = (/<form\b[^>]*class="say"[^>]*>[\s\S]*?<\/form>/.exec(landing) || [""])[0];
    T("/ carries a real form, not a fetch bolted to a button",
        /action="[^"]+"/.test(form) && /method="POST"/i.test(form) && /\bnovalidate\b/.test(form));
    T("the form posts to the ruled endpoint", form.includes(`action="${surface.contact.endpoint}"`));
    /* r12 — SCOPE A STRUCTURAL CHECK TO THE ELEMENT. Testing
       `/name="_gotcha"/` against the document passes with the honeypot deleted,
       because the inlined stylesheet still carries `.say input[name=_gotcha]`
       — a CSS selector satisfying a check about markup. This finds the <input>
       and requires all three attributes on THAT element. */
    const honeypot = [...form.matchAll(/<input\b[^>]*>/gi)]
        .find((el) => /\bname="_gotcha"/.test(el[0]));
    T("the form carries the _gotcha honeypot as an element, hidden from people",
        !!honeypot && /\btabindex="-1"/.test(honeypot[0]) && /\baria-hidden="true"/.test(honeypot[0]),
        honeypot ? honeypot[0].slice(0, 88) : "no <input name=\"_gotcha\"> element in the form");
    T("the reply paragraph announces itself to a screen reader",
        /class="say-msg"[^>]*role="status"[^>]*aria-live="polite"/.test(form));
    T("the form upgrade prints success only on a real 2xx",
        /if \(r\.ok\)/.test(read("./form.js")) && !/say\("Sent/.test(read("./form.js").split("if (r.ok)")[0]));
    T("the secondary correction route is a live URL, not a mailbox",
        /^https:\/\//.test(surface.contact.url) && !surface.contact.url.startsWith("mailto"));
}

/* ---------- 6. every rung on the artifact is a real rung ---------- */
const RUNGS = ["spec", "in_tree", "live_local", "live_deployed", "external", "?"];
{
    const chips = [...landing.matchAll(/<span class="rung" data-rung="([^"]*)"[^>]*>([^<]*)<\/span>/g)];
    T("/ renders at least one rung chip", chips.length > 0, `${chips.length} chips`);
    T("/ renders only real rungs", chips.every((c) => RUNGS.includes(c[1])),
        chips.map((c) => c[1]).filter((r) => !RUNGS.includes(r)).join(", ") || "all valid");
    T("/ chip text always equals its stored rung", chips.every((c) => c[1] === c[2]));
    T("/ never defaults an unknown rung",
        !/data-rung=""/.test(landing) && !/data-rung="undefined"/.test(landing) && !/data-rung="null"/.test(landing));
    T("the surface rung is one of the five", RUNGS.slice(0, 5).includes(surface.surface_rung), surface.surface_rung);
    T("the surface rung is the rung of its best-evidenced artifact",
        surface.artifacts.some((a) => a.rung === surface.surface_rung),
        `${surface.surface_rung} — ${(surface.artifacts.find((a) => a.rung === surface.surface_rung) || {}).name}`);
}

/* ---------- 7. the band may only claim what the PLACE permits, and it must
   refuse in BOTH directions ----------
   The place is a record in ampersand-nav, not a choice made here, and this
   page embeds that nav one element below the band. r5 §4: refusing a layer
   claim a place has not earned is only half of it — a band that quietly DROPS
   the sentence its place requires is the same defect inverted. */
T("the surface declares its place", [1, 2, 3, 4].includes(surface.tier), `place ${surface.tier}`);
T("/ band carries the declared place", landing.includes(`<div class="band" data-tier="${surface.tier}">`));
T("the placement band bounds what its rung covers", landing.includes(surface.surface_rung_covers));
{
    const SENTENCES = {
        2: `is the <b>${surface.layer}</b> layer of ${surface.parent}`,
        3: `is <b>a specification</b> in the ${surface.parent} world`,
        4: `A <b>${surface.parent}</b> project`,
    };
    const mine = SENTENCES[surface.tier];
    T(`/ band carries the sentence place ${surface.tier} requires`, !!mine && landing.includes(mine), mine);
    const wrong = Object.entries(SENTENCES)
        .filter(([p]) => Number(p) !== surface.tier && landing.includes(SENTENCES[p]))
        .map(([p]) => `place ${p}`);
    T("/ band carries no OTHER place's sentence", wrong.length === 0, wrong.join(", ") || "only its own");
    /* Not just the band: the PAGE may not claim a layer at place 3, because
       the nav rendered under it says "a specification". The prior hero eyebrow
       read "The specification layer of the ComputeDriven stack" and that is
       what this catches. Measured outside the retraction, which quotes the
       sentence once on purpose. */
    T("/ makes no layer claim anywhere on the page at place 3",
        surface.tier !== 3 || !new RegExp(`layer of (the )?${surface.parent}`, "i").test(OUTSIDE_TEXT),
        (new RegExp(`.{0,40}layer of (the )?${surface.parent}.{0,20}`, "i").exec(OUTSIDE_TEXT) || [])[0] || "none outside the retraction");
    T("/ embeds the nav whose placement it agrees with",
        landing.includes(`<amp-nav property="specprompt">`));
}

/* ---------- 8. every §N on the page resolves in the spec it cites ----------
   FENCES ARE STRIPPED FIRST: a markdown heading inside a fenced code block is
   not a heading, and reading one as a section has already bitten a lane. */
{
    const specPath = "./" + surface.spec_file;
    T("the spec file this surface cites exists", existsSync(specPath), surface.spec_file);
    if (existsSync(specPath)) {
        const md = read(specPath).replace(/^```[\s\S]*?^```/gm, "");
        const heads = new Set([...md.matchAll(/^#{1,6}\s+(\d+(?:\.\d+)*)\.?\s/gm)].map((m) => m[1]));
        const used = new Set([...md.matchAll(/§\s?(\d+(?:\.\d+)*)/g)].map((m) => m[1]));
        const cited = [...new Set([...VISIBLE.matchAll(/§\s?(\d+(?:\.\d+)*)/g)].map((m) => m[1]))];
        const dangling = cited.filter((c) => !heads.has(c) && !used.has(c));
        T("every § citation on the page resolves in the spec it cites", dangling.length === 0,
            dangling.length
                ? `DANGLING: ${dangling.map((d) => "§" + d).join(", ")} — ${heads.size} headings in ${surface.spec_file}`
                : `${cited.length} citations, all resolved against ${heads.size} headings`);
    }
}

/* ---------- 9. the rung has a NAMED witness, and it is approved ---------- */
T("the surface names the gate that witnesses its rung",
    !!surface.rung_witness && !!surface.gates[surface.rung_witness], surface.rung_witness);
T("the witnessing gate is approved, with its evidence",
    surface.gates[surface.rung_witness] &&
        surface.gates[surface.rung_witness].status === "approved" &&
        ["evidence", "reviewer", "date"].every((f) => surface.gates[surface.rung_witness][f]),
    surface.rung_witness);

/* ---------- 10. SITES.md §0.7 — the rung gates the call to action ---------- */
const VERBS = {
    spec: ["Read", "Challenge", "Implement"],
    in_tree: ["Inspect the source", "Run the tests"],
    live_local: ["Use it", "Reproduce it locally"],
    live_deployed: ["Use the deployed artifact"],
    external: ["See independent evidence", "Contribute another result"],
};
{
    const groups = [...landing.matchAll(/<div class="ctagroup"><div class="tag[^"]*">(\w+) &mdash;[\s\S]*?<\/div><\/div>/g)];
    T("/ has at least one call to action", groups.length > 0, `${groups.length} groups`);
    const bad = [];
    for (const g of groups) {
        const allowed = VERBS[g[1]] || [];
        for (const v of [...g[0].matchAll(/<span class="verb">([^<]*)<\/span>/g)]) {
            const verb = v[1].replace(/&mdash;/g, "—");
            if (!allowed.includes(verb)) bad.push(`${verb} @ ${g[1]}`);
        }
    }
    T("/ asks only what its rung has earned", bad.length === 0, bad.join("; ") || "ok");
    T("every artifact rung on this surface has its own CTA group",
        [...new Set(surface.artifacts.map((a) => a.rung))].every((r) => groups.some((g) => g[1] === r)),
        [...new Set(surface.artifacts.map((a) => a.rung))].join(", "));
}

/* ---------- 11. the status block, and the review ledger ---------- */
for (const label of ["Status", "Last verified", "Source", "Limit", "Next rung"]) {
    T(`the status block states ${label}`, landing.includes(`<dt>${label}</dt>`));
}
T("the LIMIT names something the evidence does NOT establish",
    /does not establish|does not claim|has not/i.test(surface.status.limit));
const NEED = ["evidence", "reviewer", "date"];
const gates = Object.entries(surface.gates).filter(([k]) => k !== "_comment");
T("review ledger: every gate has a valid status",
    gates.every(([, g]) => ["pending", "approved"].includes(g.status)));
T("review ledger: no approval without its evidence",
    gates.every(([, g]) => g.status !== "approved" || NEED.every((f) => g[f])));
T("review ledger: the external rung is not self-awarded",
    surface.surface_rung !== "external" || surface.gates.second_implementation.status === "approved");

/* ---------- 12. the published counts are the ones that were run ---------- */
{
    for (const s of tests.suites) {
        T(`/ publishes the ${s.id} suite's re-run count`, landing.includes(`${s.total} tests`), `${s.total}`);
    }
    T("/ publishes the total the record froze", landing.includes(`${tests.total} tests`), `${tests.total}`);
    T("no suite on this page reports a failure", tests.suites.every((s) => s.failures === 0));
    /* Both directions: an id on the page that is not in the record is an id
       somebody typed, which is the whole defect class. */
    const onPage = new Set([...VISIBLE.matchAll(/\bsem-[0-9a-f]{8,}\b/g)].map((m) => m[0]));
    const inRecord = new Set([...read("./records/surface.json").matchAll(/\bsem-[0-9a-f]{8,}\b/g)].map((m) => m[0]));
    const extra = [...onPage].filter((id) => !inRecord.has(id));
    const missing = [...inRecord].filter((id) => !onPage.has(id));
    T("no identity on the page is absent from the record", extra.length === 0,
        extra.length ? `UNRECORDED: ${extra.join(", ")}` : `${onPage.size} on the page`);
    T("every identity in the record is published", missing.length === 0, missing.join(", ") || "none held back");
    T("the identity is published with the date it was measured on",
        landing.includes(surface.identity.measured_at));
    T("the record admits the identity was not re-derived by this build",
        /NOT re-derived/i.test(surface.gates.identity_two_os.reviewer));
}

/* ---------- 13. the honest status language survives the redesign ----------
   The external audit named this domain as the template the rest of the
   portfolio should copy, and this is the column it meant. A redesign is
   allowed to move it; it is not allowed to soften it. */
{
    /* THE VOCABULARY IS HARDCODED HERE, NOT READ FROM THE RECORD, and that is
       the whole point. The first draft compared the page against
       surface.pieces[].status — so renaming "not built" to "coming soon" in
       the record and letting the build carry it through PASSED. A deliberate
       break found it here and twice more on the sibling surface. A check whose
       expectation is edited by the same commit as the thing it checks is not a
       check; the gate is the law and the record is the data. */
    const MUST_SAY = ["not built", "built · superseded", "measured · once"];
    const NEVER_SAY = ["coming soon", "launching soon", "in progress", "on the roadmap",
        "shipping soon", "available soon", "under development", "work in progress", "beta soon"];
    const missing = MUST_SAY.filter((x) => !PHRASE(x));
    T("the honest-status vocabulary survives the redesign", missing.length === 0,
        missing.length ? `FLATTENED — the page no longer says: ${missing.map((s) => JSON.stringify(s)).join(", ")}` : MUST_SAY.join(" · "));
    const softened = NEVER_SAY.filter((x) => PHRASE(x));
    T("no unbuilt thing is described with a marketing tense", softened.length === 0,
        softened.length ? `SOFTENED: ${softened.join(", ")}` : `${NEVER_SAY.length} substitutes, none present`);
    const ALLOWED = new Set([...MUST_SAY, "real · upstream", "in the T&R image",
        "alpha · v0.7.0-alpha.5", "shipping", "in the image"]);
    const odd = surface.pieces.map((p) => p.status).filter((s) => !ALLOWED.has(s));
    T("every status in the record is drawn from the agreed vocabulary", odd.length === 0,
        odd.length ? `UNRECOGNISED: ${[...new Set(odd)].join(", ")}` : `${surface.pieces.length} pieces`);
    T("every piece in the record reaches the page",
        surface.pieces.every((p) => PHRASE(p.piece)), `${surface.pieces.length} pieces`);
}

/* ---------- 14. every path this page tells a reader to load resolves ---------- */
{
    const hrefs = [...new Set([...MARKUP.matchAll(/(?:href|src)="(\/[^"#?]*)"/g)].map((m) => m[1]))];
    const dead = hrefs.filter((h) => !existsSync("." + (h.endsWith("/") ? h + "index.html" : h)));
    T("every same-origin path the page links resolves in the tree", dead.length === 0,
        dead.length ? `DEAD: ${dead.join(", ")}` : `${hrefs.length} paths`);
}

/* ---------- 15. density ---------- */
T("the landing page stays small", landing.length < 46000, `${landing.length.toLocaleString()} bytes`);

/* ==========================================================================
   16. SHELL.md §8.5 — THE IDENTIFYING ANIMATION ASSERTS NOTHING

   gpscoord.com shipped a canvas globe whose vehicles were created by
   `for (let i = 0; i < 12; i++)`, and printed beside it, for months:

       12   Active Pathfinders

   A decoration's internal constant published as a live user metric. The checks
   below are that defect mechanised, and they read the page through
   visibleText() so a constant hiding in a comment cannot satisfy them either.

   WHEN THE SECOND CHECK FIRES, THE ANIMATION CHANGES — never the page.
   ========================================================================== */
{
    const marked = [...landing.matchAll(/<[a-z]+\b[^>]*\bdata-identity-animation\b[^>]*>/gi)];
    T("the landing page marks an element data-identity-animation", marked.length >= 1, `${marked.length} marked`);
    const firstSection = (landing.split("<section")[1] || "").split("</section>")[0];
    T("the identity animation is above the fold — inside the first section",
        firstSection.includes("data-identity-animation"));
    T("the h1 comes before the identity animation — the question comes first",
        landing.indexOf("<h1") > -1 && landing.indexOf("<h1") < landing.indexOf("data-identity-animation"));
}

const ANIM_NUMS = new Set();
const ANIM_STRS = new Set();
for (const m of anim.matchAll(/(?<![\w.$])\d+(?:\.\d+)?/g)) {
    const v = Number(m[0]);
    if (Math.abs(v) >= 2) ANIM_NUMS.add(String(v));
}
for (const m of anim.matchAll(/"([^"\\\n]{3,})"|'([^'\\\n]{3,})'/g)) ANIM_STRS.add(m[1] ?? m[2]);

{
    const texts = visibleText(landing);
    const shown = new Set();
    for (const t of texts) {
        shown.add(t);
        if (/^-?[\d,]*\d(?:\.\d+)?$/.test(t) && t.includes(",")) shown.add(t.replace(/,/g, ""));
    }
    const leaked = [...shown].filter((t) => ANIM_NUMS.has(t) || ANIM_STRS.has(t));
    T("no text on the landing page is a constant read from the animation", leaked.length === 0,
        leaked.length
            ? `LEAKED: ${leaked.map((l) => JSON.stringify(l)).join(", ")} — change src/derive.js, not the page`
            : `${ANIM_NUMS.size + ANIM_STRS.size} constants vs ${texts.length} text nodes, disjoint`);
}
{
    const recordText = ["surface", "tests"].map((f) => read(`./records/${f}.json`)).join("\n");
    const shared = [...ANIM_STRS].filter((s) => recordText.includes(s));
    T("the animation shares no string with a frozen record", shared.length === 0,
        shared.length ? `SHARED: ${shared.map((s) => JSON.stringify(s)).join(", ")}` : `${ANIM_STRS.size} strings, none in records`);
}
{
    const FORBIDDEN = ["innerHTML", "outerHTML", "textContent", "innerText", "insertAdjacentHTML",
        "document.write", "createElement", "createTextNode", "appendChild", "setAttribute",
        "getElementById", "getElementsBy", "localStorage", "sessionStorage", "XMLHttpRequest", "fetch("];
    const found = FORBIDDEN.filter((k) => anim.includes(k));
    T("the animation neither reads nor writes page content", found.length === 0,
        found.join(", ") || "no DOM content API used");
    const queries = [...anim.matchAll(/querySelector(?:All)?\(\s*([^)]*)\)/g)].map((m) => m[1]);
    T("the animation queries nothing but its own canvas",
        queries.length === 1 && queries[0].includes("data-identity-animation"), queries.join(" | ") || "none");
}
T("the animation honours prefers-reduced-motion", anim.includes("prefers-reduced-motion"));
T("the animation never uses IntersectionObserver", !anim.includes("IntersectionObserver"));
T("the animation stops when the tab is hidden", anim.includes("document.hidden"));
T("the animation caps its frame rate", /1000\s*\/\s*FPS/.test(anim));
T("the animation stays cheap enough for a phone", anim.length < 9000, `${anim.length.toLocaleString()} bytes`);

/* ==========================================================================
   17. CONTRAST — every declared text token, on the surface it sits on
   ========================================================================== */
const sheet = read("./src/shell.css");
const TOKENS = {};
for (const m of sheet
    .slice(sheet.indexOf("/* TOKENS-START"), sheet.indexOf("/* TOKENS-END"))
    .matchAll(/--([\w-]+)\s*:\s*([^;\n}]+)/g))
    TOKENS[m[1]] = m[2].trim();
if (!TOKENS.ink) throw new Error("launch-gate found no token block in src/shell.css");

function colour(v) {
    const raw = (TOKENS[String(v).replace(/^--/, "")] || String(v)).trim();
    let m = /^#([0-9a-f]{6})$/i.exec(raw);
    if (m) return [parseInt(m[1].slice(0, 2), 16), parseInt(m[1].slice(2, 4), 16), parseInt(m[1].slice(4, 6), 16), 1];
    m = /^rgba?\(([^)]+)\)$/i.exec(raw);
    if (m) {
        const p = m[1].split(",").map((x) => Number(x.trim()));
        return [p[0], p[1], p[2], p.length > 3 ? p[3] : 1];
    }
    throw new Error(`launch-gate cannot read the colour ${JSON.stringify(v)} -> ${raw}`);
}
const composite = (f, b) => [
    f[3] * f[0] + (1 - f[3]) * b[0],
    f[3] * f[1] + (1 - f[3]) * b[1],
    f[3] * f[2] + (1 - f[3]) * b[2],
    1,
];
function solid(spec) {
    const layers = Array.isArray(spec) ? spec : [spec];
    let base = colour(layers[0]);
    base = [base[0], base[1], base[2], 1];
    for (let i = 1; i < layers.length; i++) base = composite(colour(layers[i]), base);
    return base;
}
const chan = (c) => {
    c /= 255;
    return c <= 0.03928 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4);
};
const lum = (c) => 0.2126 * chan(c[0]) + 0.7152 * chan(c[1]) + 0.0722 * chan(c[2]);
function contrast(fgSpec, bgSpec) {
    const bg = solid(bgSpec);
    const fg = composite(colour(fgSpec), bg);
    const a = lum(fg),
        b = lum(bg);
    return (Math.max(a, b) + 0.05) / (Math.min(a, b) + 0.05);
}
const CONTRAST_PAIRS = [
    ["--fg", "--ink", "body copy"],
    ["--fg", "--ink2", "card headings, the band's bold word"],
    ["--fg", "--ink3", "the figure's note, table headers' raised surface"],
    ["--fg2", "--ink", "lede and prose"],
    ["--fg2", "--ink2", "status values, the band's .covers span, rung chip text"],
    ["--fg2", "--ink3", "raised-surface secondary text"],
    ["--fg3", "--ink", "form labels on the page"],
    ["--fg3", "--ink2", "every .status dt, .needs, the footer"],
    ["--fg3", "--ink3", "table column headers"],
    ["--acc", "--ink", "links in prose"],
    ["--acc", "--ink2", "CTA verbs, eyebrows, the logo on hover, the moved clause"],
    ["--acc", ["--ink2", "--acc-soft"], "a CTA card while hovered"],
    ["--data", "--ink2", "the identity string, the where-tag, measured statuses"],
    ["--data", ["--ink2", "--data-soft"], "the live_local chip on its own tint"],
    ["--warn", "--ink2", "the LIMIT row, the claim tag, the ? rung, unbacked statuses"],
    ["--warn", ["--ink2", "rgba(245,196,81,.06)"], "the claim tag on its own tint"],
    ["--acc-ink", "--acc", "the label inside a primary button"],
    ["#9aa4b2", "--ink2", "the spec rung chip"],
    ["#7aa2f7", "--ink2", "the in_tree rung chip"],
    ["#4ade80", "--ink2", "the live_deployed rung chip"],
    ["#c4a1ff", "--ink2", "the external rung chip"],
];
const MIN_RATIO = 4.5;
let worst = Infinity,
    worstName = "";
for (const [fg, bg, where] of CONTRAST_PAIRS) {
    const r = contrast(fg, bg);
    const name = `${fg} on ${Array.isArray(bg) ? bg.join(" + ") : bg}`;
    if (r < worst) {
        worst = r;
        worstName = name;
    }
    T(`contrast ${name} — ${where}`, r >= MIN_RATIO, `${r.toFixed(2)}:1`);
}
T("the least legible declared pair clears the 4.5:1 floor", worst >= MIN_RATIO,
    `${worstName} at ${worst.toFixed(2)}:1`);

/* ==========================================================================
   18. r8 — RESOLVE THE CASCADE OVER THE ARTIFACT

   A declared token is not a painted colour. `.top nav a` is (0,2,1) and `.btn`
   is (0,1,0), so an unscoped nav rule WINS and paints --fg2 on --acc: the
   header CTA shipped unreadable on nine surfaces while every contrast check
   above passed, because those read tokens and browsers paint computed values.

   `:not(.btn)` fixes today's instance. This fixes the CLASS: for every button
   on the emitted page, resolve which rule actually decides its `color` —
   specificity, then source order, with !important winning outright and @media
   blocks included — and refuse when the winner is not itself a button rule.
   ========================================================================== */
{
    /* --- the emitted stylesheet, rules in source order --- */
    const css = [...landing.matchAll(/<style[^>]*>([\s\S]*?)<\/style>/gi)].map((m) => m[1]).join("\n");
    const rules = [];
    (function collect(text, media) {
        let i = 0;
        while (i < text.length) {
            const open = text.indexOf("{", i);
            if (open < 0) break;
            const head = text.slice(i, open).trim();
            /* find the matching close brace, counting nesting */
            let depth = 1,
                j = open + 1;
            while (j < text.length && depth > 0) {
                if (text[j] === "{") depth++;
                else if (text[j] === "}") depth--;
                j++;
            }
            const body = text.slice(open + 1, j - 1);
            if (head.startsWith("@")) {
                if (/^@(media|supports)/.test(head)) collect(body, head);
                /* @keyframes and friends declare nothing that paints an element */
            } else if (head) {
                for (const sel of head.split(",")) {
                    const s = sel.trim();
                    if (s) rules.push({ sel: s, body, media, order: rules.length });
                }
            }
            i = j;
        }
    })(css, null);

    /* --- the elements that must resolve to a button colour --- */
    const OPEN = /<(a|button)\b([^>]*)>/gi;
    const stack = [];
    const buttons = [];
    const tagRe = /<\/?([a-zA-Z][\w-]*)\b([^>]*?)(\/?)>/g;
    let m;
    const html = MARKUP.replace(/<script[\s\S]*?<\/script>/gi, "").replace(/<style[\s\S]*?<\/style>/gi, "");
    const VOID = new Set(["meta", "link", "br", "hr", "img", "input", "source", "area", "base", "col", "embed", "param", "track", "wbr"]);
    while ((m = tagRe.exec(html))) {
        const closing = m[0][1] === "/";
        const tag = m[1].toLowerCase();
        const attrs = m[2] || "";
        if (closing) {
            for (let k = stack.length - 1; k >= 0; k--) {
                if (stack[k].tag === tag) {
                    stack.length = k;
                    break;
                }
            }
            continue;
        }
        const cls = ((/class="([^"]*)"/.exec(attrs) || [])[1] || "").trim().split(/\s+/).filter(Boolean);
        const node = { tag, cls, attrs };
        if (tag === "a" || tag === "button") {
            const isBtn = cls.includes("btn") || tag === "button";
            if (isBtn) buttons.push({ node, chain: stack.slice() });
        }
        if (!VOID.has(tag) && !m[3]) stack.push(node);
    }
    OPEN.lastIndex = 0;

    /* --- a selector matcher over that chain. Handles the shapes this shell
       actually emits: descendant combinators of type/class compounds, with
       :not(), attribute equality, and pseudo-classes treated as state. --- */
    function parseCompound(text) {
        const c = { tag: null, cls: [], not: [], pseudo: [], attr: [], id: null };
        const re = /([.#]?[\w-]+|\[[^\]]*\]|::?[\w-]+(?:\(([^)]*)\))?|\*)/g;
        let t;
        while ((t = re.exec(text))) {
            const s = t[0];
            if (s === "*") continue;
            else if (s.startsWith("::")) c.pseudo.push(s);
            else if (s.startsWith(":")) {
                if (s.startsWith(":not(")) c.not.push(parseCompound(t[2] || ""));
                else c.pseudo.push(s);
            } else if (s.startsWith(".")) c.cls.push(s.slice(1));
            else if (s.startsWith("#")) c.id = s.slice(1);
            else if (s.startsWith("[")) c.attr.push(s.slice(1, -1));
            else c.tag = s.toLowerCase();
        }
        return c;
    }
    function matchCompound(c, node) {
        if (c.tag && c.tag !== node.tag) return false;
        if (c.id && !new RegExp(`id="${c.id}"`).test(node.attrs)) return false;
        for (const k of c.cls) if (!node.cls.includes(k)) return false;
        for (const a of c.attr) {
            const [name, val] = a.split("=");
            if (!new RegExp(`\\b${name}=`).test(node.attrs)) return false;
            if (val && !node.attrs.includes(val.replace(/["']/g, ""))) return false;
        }
        for (const n of c.not) if (matchCompound(n, node)) return false;
        return true;
    }
    /* State pseudo-classes are not matched unconditionally: a `:hover` rule
       decides the hovered colour and says nothing about the resting one.
       Resolving both together made this gate disagree with the browser on the
       ghost button — it reported the hover ink as the resting ink. So the
       resolution runs once per state, and each state admits only its own. */
    const STATE = /^:(hover|focus|focus-visible|focus-within|active|visited|disabled|checked|invalid|placeholder|target)$/;
    /* The lookbehind here is `(?<!:)`, NOT `(?<!\w)`. The first draft used the
       latter and therefore never matched `.btn.ghost:hover` — the character
       before the colon is a word character — so every hover rule was treated
       as stateless and the gate reported the hover ink as the resting ink.
       Caught by disagreeing with the browser's own computed style, which is
       the only reason to cross-check a resolver against a real renderer. */
    function statesOf(sel) {
        return [...sel.matchAll(/(?<!:):([\w-]+)(?!\()/g)]
            .map((m) => ":" + m[1])
            .filter((p) => STATE.test(p));
    }
    function matches(sel, node, chain, state) {
        const want = statesOf(sel);
        if (state === undefined) {
            /* legacy call: parse-check only */
        } else if (state === null) {
            if (want.length) return false;
        } else if (!want.every((p) => p === state)) return false;
        /* Descendant/child combinators only — this shell uses no siblings. */
        const parts = sel.trim().split(/\s*>\s*|\s+/).filter(Boolean);
        const subject = parseCompound(parts[parts.length - 1]);
        if (!matchCompound(subject, node)) return false;
        let ci = chain.length - 1;
        for (let p = parts.length - 2; p >= 0; p--) {
            const c = parseCompound(parts[p]);
            let found = false;
            while (ci >= 0) {
                if (matchCompound(c, chain[ci])) {
                    found = true;
                    ci--;
                    break;
                }
                ci--;
            }
            if (!found) return false;
        }
        return true;
    }
    function specificity(sel) {
        let a = 0, b = 0, c = 0;
        for (const part of sel.trim().split(/\s*>\s*|\s+/).filter(Boolean)) {
            const re = /([.#]?[\w-]+|\[[^\]]*\]|::?[\w-]+(?:\(([^)]*)\))?|\*)/g;
            let t;
            while ((t = re.exec(part))) {
                const s = t[0];
                if (s === "*") continue;
                else if (s.startsWith("::")) c++;
                else if (s.startsWith(":not(")) {
                    const inner = specificity(t[2] || "");
                    a += inner[0]; b += inner[1]; c += inner[2];
                } else if (s.startsWith(":")) b++;
                else if (s.startsWith(".")) b++;
                else if (s.startsWith("#")) a++;
                else if (s.startsWith("[")) b++;
                else c++;
            }
        }
        return [a, b, c];
    }
    const cmp = (x, y) => x[0] - y[0] || x[1] - y[1] || x[2] - y[2];

    function decl(body, prop) {
        const re = new RegExp(`(?:^|;)\\s*${prop}\\s*:\\s*([^;]+)`, "i");
        const m2 = re.exec(body);
        if (!m2) return null;
        const raw = m2[1].trim();
        return { value: raw.replace(/!important/i, "").trim(), important: /!important/i.test(raw) };
    }

    /* A rule "belongs to a button" when the compound it is the subject of is
       itself a button — a `.btn` class or a <button> element. The r7 defect is
       exactly a rule whose subject was `a`, inheriting its weight from
       ancestors that have nothing to do with buttons. */
    function isButtonRule(sel) {
        const parts = sel.trim().split(/\s*>\s*|\s+/).filter(Boolean);
        const last = parts[parts.length - 1];
        return /\.btn(?![\w-])/.test(last) || /(^|[^\w-])button(?![\w-])/.test(last);
    }

    /* A rule inside @media only applies at widths where the query holds. The
       resolver is run at each width this surface is checked at, so a max-width
       rule cannot silently decide a colour at 1280 — and a rule that hijacks a
       button ONLY on a phone is still caught. */
    function mediaApplies(q, width) {
        if (!q) return true;
        if (/prefers-reduced-motion/.test(q)) return false;
        let ok = true;
        for (const m2 of q.matchAll(/\(\s*(min|max)-width\s*:\s*(\d+)px\s*\)/g)) {
            const n = Number(m2[2]);
            ok = ok && (m2[1] === "min" ? width >= n : width <= n);
        }
        return ok;
    }
    /* var(--x) is resolved against the token block so the verdict is a colour,
       not the word "var". Declared tokens are what the browser resolves too. */
    const deVar = (v) =>
        String(v).replace(/var\(\s*--([\w-]+)\s*(?:,[^)]*)?\)/g, (m2, name) => TOKENS[name] ?? m2);

    /* A selector this resolver cannot parse is a REFUSAL, not a skip. A gate
       that quietly ignores what it does not understand is the hole it was
       written to close. */
    const unparsed = rules.filter((r) => {
        try {
            matches(r.sel, { tag: "a", cls: ["btn"], attrs: "" }, []);
            return false;
        } catch {
            return true;
        }
    });
    T("the cascade resolver parses every selector in the emitted sheet", unparsed.length === 0,
        unparsed.length ? `UNPARSED: ${unparsed.map((r) => r.sel).join(", ")}` : `${rules.length} rules`);

    const WIDTHS = [390, 800, 1280, 1600];
    const STATES = [null, ":hover", ":focus-visible"];
    const verdicts = [];
    for (const width of WIDTHS) for (const state of STATES) {
        for (const { node, chain } of buttons) {
            for (const prop of ["color", "background", "background-color"]) {
                const hits = rules
                    .filter((r) => mediaApplies(r.media, width))
                    .map((r) => ({ r, d: decl(r.body, prop) }))
                    .filter((x) => x.d && matches(x.r.sel, node, chain, state));
                if (!hits.length) continue;
                hits.sort((x, y) => {
                    if (x.d.important !== y.d.important) return x.d.important ? 1 : -1;
                    const s = cmp(specificity(x.r.sel), specificity(y.r.sel));
                    return s !== 0 ? s : x.r.order - y.r.order;
                });
                const win = hits[hits.length - 1];
                verdicts.push({
                    width,
                    state: state || "rest",
                    what: `${node.tag}.${node.cls.join(".") || "(no class)"}`,
                    prop,
                    sel: win.r.sel,
                    value: deVar(win.d.value),
                    ok: isButtonRule(win.r.sel),
                });
            }
        }
    }

    T("the cascade resolver found the page's buttons", buttons.length > 0, `${buttons.length} buttons`);
    const hijacked = verdicts.filter((v) => !v.ok);
    T("every button's painted colour is decided by a button rule, at every width (r8)",
        hijacked.length === 0,
        hijacked.length
            ? [...new Set(hijacked.map((v) => `@${v.width}px ${v.state} ${v.what} ${v.prop} <- "${v.sel}" (${v.value})`))].join("; ")
            : [...new Set(verdicts.filter((v) => v.state === "rest").map((v) => `${v.what} ${v.prop}=${v.value}`))].join(" · "));
    /* And the resolved value must be the ink the .btn rule declares — the same
       question from the other end, so a button rule that wins with the wrong
       colour is caught as well as a non-button rule that wins at all. */
    const btnRule = rules.find((r) => r.sel === ".btn");
    const btnColour = btnRule && decl(btnRule.body, "color");
    const want = btnColour && deVar(btnColour.value);
    const wrongValue = verdicts.filter(
        (v) => v.prop === "color" && v.what === "a.btn" && v.state === "rest" && v.value !== want
    );
    T("every plain .btn resolves to the ink the .btn rule declares, at every width",
        !!btnColour && wrongValue.length === 0,
        want
            ? `${want}${wrongValue.length ? " — but " + [...new Set(wrongValue.map((v) => `@${v.width}px ${v.value}`))].join(", ") : ""}`
            : "no .btn colour declared");
}

/* ==========================================================================
   19. EVERY INTERACTIVE ELEMENT CAN BE SEEN TO BE INTERACTIVE
   ========================================================================== */
{
    const styles = [...landing.matchAll(/<style[^>]*>([\s\S]*?)<\/style>/gi)].map((m) => m[1]).join("\n");
    const hoverSel = [...styles.matchAll(/([^{}]*?):hover/g)].map((m) => m[1]).join(" , ");
    const handles = new Set();
    for (const el of MARKUP.matchAll(/<(a|button)\b([^>]*)>/gi)) {
        const cls = /class="([^"]*)"/.exec(el[2]);
        handles.add(cls ? "." + cls[1].trim().split(/\s+/)[0] : el[1].toLowerCase());
    }
    const naked = [...handles].filter((h) =>
        h.startsWith(".")
            ? !new RegExp(`\\${h}(?![\\w-])`).test(hoverSel)
            : !new RegExp(`(^|[\\s>+~,(])${h}(?=[\\s.:>+~,)]|$)`, "m").test(hoverSel)
    );
    T("/ every interactive element has a visible :hover", naked.length === 0,
        naked.length ? `no hover for: ${naked.join(", ")}` : `${handles.size} kinds, all covered`);
    T("/ declares a focus-visible ring", /:focus-visible\s*\{/.test(styles));
    /* r7 — the h1's ink must fit its line box, and the value that was measured
       to fit must still be the value declared. Node cannot render a font, so
       the measurement lives in the record with the browser and viewport that
       produced it, and this refuses when the CSS drifts away from it. A face
       swap without a re-measurement is exactly how a sibling shipped a clipped
       descender at 1.02. */
    const tm = surface.type_metrics;
    T("the h1's measured ink box fits its line box",
        !!tm && tm.h1_ink_px <= tm.h1_line_box_px,
        tm ? `${tm.h1_face} at ${tm.h1_px}px — ink ${tm.h1_ink_px}px in a ${tm.h1_line_box_px}px box, ${tm.headroom_px}px headroom` : "no measurement recorded");
    T("the stylesheet still declares the line-height that was measured",
        !!tm && new RegExp(`h1\\{[^}]*line-height:${tm.h1_line_height.replace(".", "\\.")}[;}]`).test(styles),
        tm ? `line-height:${tm.h1_line_height}` : "no measurement recorded");
    T("the stylesheet still declares the display face that was measured",
        !!tm && styles.includes(tm.h1_face.replace(/ \d+$/, "")),
        tm ? tm.h1_face : "no measurement recorded");
    T("/ the form's inputs have a hover and a focus state",
        /\.say input:hover/.test(styles) && /\.say input:focus/.test(styles));
}

console.log(`\n${pass} passed, ${fail} failed (publication gate)`);
if (fail) process.exit(1);
