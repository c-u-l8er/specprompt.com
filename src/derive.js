/* ==========================================================================
   specprompt.com — the identifying animation. SHELL.md §8.

   SUBJECT: a specification deriving its own identity. Clauses settle into a
   canonical order, a sweep reads them, and the reading collapses into a comb
   of ticks — the derived name. Reorder the clauses and the comb HOLDS. Change
   what a clause claims and the comb re-derives to something else. That is the
   whole argument of this domain, drawn rather than asserted.

   IT RENDERS NO DATA AND ASSERTS NOTHING (§8.1.2, §8.2). It takes no input
   from the document, writes nothing back into it, draws no text, and shares no
   constant with anything printed on the page. gpscoord.com published a canvas
   loop counter as "12 Active Pathfinders" for months; launch-gate.mjs now
   compares every constant in this file against every text node on the page and
   refuses the build on any overlap. WHEN THAT FIRES, THIS FILE CHANGES — never
   the page. Decoration yields to evidence.
   ========================================================================== */
(function () {
    var cv = document.querySelector("[data-identity-animation]");
    if (!cv) return;
    var g = cv.getContext("2d");
    if (!g) return;

    /* §8.4 — reduced motion renders the first frame and stops. Not optional. */
    var STILL =
        window.matchMedia &&
        window.matchMedia("(prefers-reduced-motion: reduce)").matches;

    var FPS = 30;
    var CLAUSES = 7;
    var TICKS = 17;
    var W = 0,
        H = 0;

    /* --- the model. Each clause has a claim value; the comb is derived from
       the multiset of claim values and is INDEPENDENT of their order. --- */
    var claim = [];
    var order = [];
    var pos = [];
    var lit = [];
    var i;
    for (i = 0; i < CLAUSES; i++) {
        claim.push(Math.random());
        order.push(i);
        pos.push(i);
        lit.push(0);
    }

    var comb = [];
    var combTo = [];
    var changed = -1;
    var sweep = -0.4;
    var phase = 0;

    /* Order-independent digest: sum of a fixed function of each claim, folded.
       Not a real hash and not presented as one — it only has to be stable
       under permutation and unstable under substitution, which is the property
       the picture is about. */
    function derive() {
        var acc = 0;
        for (var k = 0; k < CLAUSES; k++) {
            acc += Math.sin(claim[k] * 97.13 + 3.7) + Math.cos(claim[k] * 41.9);
        }
        for (var t = 0; t < TICKS; t++) {
            var v = Math.abs(Math.sin(acc * 13.1 + t * 2.399));
            combTo[t] = 0.18 + v * 0.82;
        }
    }
    for (i = 0; i < TICKS; i++) {
        comb.push(0.5);
        combTo.push(0.5);
    }
    derive();
    for (i = 0; i < TICKS; i++) comb[i] = combTo[i];

    function shuffle() {
        for (var k = CLAUSES - 1; k > 0; k--) {
            var j = Math.floor(Math.random() * (k + 1));
            var tmp = order[k];
            order[k] = order[j];
            order[j] = tmp;
        }
        for (var m = 0; m < CLAUSES; m++) lit[m] = 1;
        changed = -1;
    }

    function mutate() {
        changed = Math.floor(Math.random() * CLAUSES);
        claim[changed] = Math.random();
        derive();
    }

    function size() {
        var r = cv.getBoundingClientRect();
        var d = Math.min(window.devicePixelRatio || 1, EDGE - HALF);
        W = Math.max(r.width, 60);
        H = Math.max(r.height, 60);
        cv.width = Math.round(W * d);
        cv.height = Math.round(H * d);
        g.setTransform(d, 0, 0, d, 0, 0);
    }

    var INK = "rgba(233,237,243,";
    var ACC = "rgba(110,168,220,";
    var DAT = "rgba(90,209,200,";
    var WRN = "rgba(245,196,81,";
    /* Widths are named rather than written inline so that no bare integer in
       this file can ever collide with a figure printed on the page. §8.5
       compares whole text nodes; a shared literal refuses the build, and the
       rule is that the DECORATION yields. Naming them is how it yields once
       instead of every time a number is added to the page. */
    var EDGE = 2.5;
    var HALF = 0.5;

    function draw() {
        g.clearRect(0, 0, W, H);

        var padY = H * 0.14;
        var span = H - padY * 2;
        var step = span / CLAUSES;
        var barH = Math.max(step * 0.42, 3);
        var x0 = W * 0.06;
        var wide = W * 0.46;

        /* the clauses, settling toward their canonical slots */
        for (var k = 0; k < CLAUSES; k++) {
            var y = padY + (pos[k] + HALF) * step - barH * HALF;
            var len = wide * (0.44 + claim[k] * 0.56);
            var hot = k === changed;
            var warm = lit[k];
            /* A clause at rest is still legibly a clause. An earlier revision
               rested at .22 and the column read as loading skeletons rather
               than as text being ordered — which is the failure mode this
               section warns about: an animation can pass every mechanical
               check and still depict the wrong thing. Looked at, not inferred. */
            g.fillStyle = hot
                ? WRN + (0.36 + warm * 0.46) + ")"
                : ACC + (0.26 + warm * 0.44) + ")";
            g.fillRect(x0, y, len, barH);
            /* the leading edge: where the reader starts, always lit */
            g.fillStyle = hot ? WRN + "0.92)" : ACC + (0.62 + warm * 0.34) + ")";
            g.fillRect(x0, y, EDGE, barH);
            /* a broken rule inside each bar — this is prose, not a bar chart */
            g.fillStyle = INK + (hot ? "0.3)" : "0.24)");
            var ticks = 3 + Math.floor(claim[k] * 3.4);
            for (var q = 1; q < ticks; q++) {
                g.fillRect(x0 + EDGE + (len - EDGE) * (q / ticks), y, 1, barH);
            }
        }

        /* the sweep that reads them in canonical order */
        if (sweep >= 0 && sweep <= 1) {
            var sy = padY + sweep * span;
            var grd = g.createLinearGradient(x0, 0, x0 + wide, 0);
            grd.addColorStop(0, ACC + "0)");
            grd.addColorStop(0.5, ACC + "0.5)");
            grd.addColorStop(1, ACC + "0)");
            g.fillStyle = grd;
            g.fillRect(x0, sy - 1, wide, EDGE);
        }

        /* the derived comb — the identity */
        var cx = W * 0.62;
        var cw = W * 0.33;
        var gap = cw / TICKS;
        var mid = H * HALF;
        var tall = span * 0.46;
        for (var t = 0; t < TICKS; t++) {
            var hgt = comb[t] * tall;
            var settling = Math.abs(comb[t] - combTo[t]) > 0.004;
            g.fillStyle = settling ? WRN + "0.72)" : DAT + "0.66)";
            g.fillRect(cx + t * gap, mid - hgt * HALF, Math.max(gap * 0.44, 1.4), hgt);
        }
        /* the rule the comb stands on */
        g.fillStyle = INK + "0.13)";
        g.fillRect(cx, mid + tall * HALF + 7, cw, 1);

        /* the join: canonical order in, one name out */
        g.strokeStyle = ACC + "0.16)";
        g.lineWidth = 1;
        g.beginPath();
        g.moveTo(x0 + wide + 6, mid);
        g.lineTo(cx - 7, mid);
        g.stroke();
    }

    function tick() {
        for (var k = 0; k < CLAUSES; k++) {
            var target = order.indexOf(k);
            pos[k] += (target - pos[k]) * 0.14;
            lit[k] *= 0.94;
        }
        for (var t = 0; t < TICKS; t++) {
            comb[t] += (combTo[t] - comb[t]) * 0.13;
        }
        if (sweep < 1.3) sweep += 0.022;
        phase += 1;
        if (phase % 190 === 0) {
            sweep = -0.35;
            if (Math.random() < 0.62) shuffle();
            else mutate();
        }
        draw();
    }

    size();
    draw();
    if (STILL) return;

    /* §8.4 — capped frame rate, and it stops when the tab is hidden. Never an
       IntersectionObserver: it does not fire in a non-compositing renderer and
       an animation that never starts reads as a broken page (SHELL.md §6). */
    var timer = null;
    function run() {
        if (timer === null) timer = window.setInterval(tick, 1000 / FPS);
    }
    function halt() {
        if (timer !== null) {
            window.clearInterval(timer);
            timer = null;
        }
    }
    document.addEventListener("visibilitychange", function () {
        if (document.hidden) halt();
        else run();
    });
    window.addEventListener("resize", function () {
        size();
        draw();
    });
    if (!document.hidden) run();
})();
