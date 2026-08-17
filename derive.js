(function () {
var cv = document.querySelector("[data-identity-animation]");
if (!cv) return;
var g = cv.getContext("2d");
if (!g) return;
var STILL =
window.matchMedia &&
window.matchMedia("(prefers-reduced-motion: reduce)").matches;
var FPS = 30;
var CLAUSES = 7;
var TICKS = 17;
var W = 0,
H = 0;
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
for (var k = 0; k < CLAUSES; k++) {
var y = padY + (pos[k] + HALF) * step - barH * HALF;
var len = wide * (0.44 + claim[k] * 0.56);
var hot = k === changed;
var warm = lit[k];
g.fillStyle = hot
? WRN + (0.36 + warm * 0.46) + ")"
: ACC + (0.26 + warm * 0.44) + ")";
g.fillRect(x0, y, len, barH);
g.fillStyle = hot ? WRN + "0.92)" : ACC + (0.62 + warm * 0.34) + ")";
g.fillRect(x0, y, EDGE, barH);
g.fillStyle = INK + (hot ? "0.3)" : "0.24)");
var ticks = 3 + Math.floor(claim[k] * 3.4);
for (var q = 1; q < ticks; q++) {
g.fillRect(x0 + EDGE + (len - EDGE) * (q / ticks), y, 1, barH);
}
}
if (sweep >= 0 && sweep <= 1) {
var sy = padY + sweep * span;
var grd = g.createLinearGradient(x0, 0, x0 + wide, 0);
grd.addColorStop(0, ACC + "0)");
grd.addColorStop(0.5, ACC + "0.5)");
grd.addColorStop(1, ACC + "0)");
g.fillStyle = grd;
g.fillRect(x0, sy - 1, wide, EDGE);
}
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
g.fillStyle = INK + "0.13)";
g.fillRect(cx, mid + tall * HALF + 7, cw, 1);
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
