/* ==========================================================================
   The correction form's progressive upgrade. SHELL.md r9.

   THE FORM ALREADY WORKS WITHOUT THIS FILE. It is a real
   <form action="https://formspree.io/f/xaewoadr" method="POST" novalidate>,
   so with scripting off the browser posts it and Formspree answers. All this
   script does is keep the visitor on the page instead of handing them to
   somebody else's thank-you screen.

   Success is printed ONLY on an actual 2xx from the endpoint. A control that
   says "sent" without asking the network is the same defect as a button that
   does nothing — you find out later, after spending the effort. Shape copied
   from computedriven.com, which is where the endpoint is ruled.
   ========================================================================== */
(function () {
    var form = document.querySelector("form.say");
    if (!form) return;
    var btn = form.querySelector("button[type=submit]");
    var msg = form.querySelector(".say-msg");
    if (!btn || !msg) return;

    function say(text, kind) {
        msg.className = "say-msg" + (kind ? " " + kind : "");
        /* textContent is the one DOM write on this page, and it is here rather
           than in the identity animation on purpose: the animation is required
           to be inert, this is a control that has to answer. */
        msg.textContent = text;
    }

    form.addEventListener("submit", function (e) {
        /* novalidate is on the form so the message appears in the page's own
           voice; the browser's bubbles are styled by the browser, not by us. */
        if (!form.checkValidity()) {
            e.preventDefault();
            var bad = form.querySelector(":invalid");
            say(
                bad && bad.name === "email"
                    ? "That email address will not parse."
                    : "Both fields are needed.",
                "bad"
            );
            if (bad) bad.focus();
            return;
        }
        e.preventDefault();
        btn.disabled = true;
        say("sending…");

        fetch(form.action, {
            method: "POST",
            body: new FormData(form),
            headers: { Accept: "application/json" },
        })
            .then(function (res) {
                return res.json().then(
                    function (data) {
                        return { ok: res.ok, status: res.status, data: data };
                    },
                    function () {
                        return { ok: res.ok, status: res.status, data: null };
                    }
                );
            })
            .then(function (r) {
                if (r.ok) {
                    form.reset();
                    say("Sent. A person reads these; give it a day or two.", "ok");
                    btn.disabled = false;
                    return;
                }
                /* Report what the endpoint actually said. The reason is usually
                   actionable and a generic apology never is. */
                var why =
                    (r.data &&
                        (r.data.error ||
                            (r.data.errors &&
                                r.data.errors
                                    .map(function (x) {
                                        return x.message;
                                    })
                                    .join("; ")))) ||
                    "HTTP " + r.status;
                say("Not sent — " + why, "bad");
                btn.disabled = false;
            })
            .catch(function () {
                say(
                    "Not sent — the request never completed. Check the connection, or anything blocking formspree.io.",
                    "bad"
                );
                btn.disabled = false;
            });
    });
})();
