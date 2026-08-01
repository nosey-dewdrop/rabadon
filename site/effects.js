/* rabadon, the two effects carried over from noseydewdrop.com and one typer.
   Same construction as the portfolio: a field of small glyphs that twinkle, and
   a trail of coloured pieces that falls out of the cursor. Denser here, and
   nothing fires on click: a burst under the pointer reads as a streak and gets
   in the way of the thing being clicked. */

/* ---------- starfield ---------- */
(function () {
  var sf = document.getElementById("stars");
  if (!sf) return;
  var G = ["*", "+", "·", ".", "-"];
  var C = ["--pink", "--purple", "--green", "--yellow", "--blue"];
  var frag = document.createDocumentFragment();
  for (var i = 0; i < 300; i++) {
    var s = document.createElement("span");
    s.className = "star";
    s.textContent = G[i % 5];
    s.style.fontSize = (9 + (i % 3) * 3) + "px";
    if (i % 3 === 0) s.style.color = "var(" + C[i % 5] + ")";
    s.style.left = Math.random() * 100 + "vw";
    s.style.top = Math.random() * 100 + "vh";
    s.style.animationDelay = (Math.random() * 3.4) + "s";
    frag.appendChild(s);
  }
  sf.appendChild(frag);
})();

/* ---------- sprinkle: trail on move, burst on click ---------- */
(function () {
  var G = ["*", "+", "·"];
  var C = ["--pink", "--purple", "--green", "--yellow", "--blue"];
  var last = 0;
  function piece(x, y, vx) {
    var c = document.createElement("span");
    c.className = "cf";
    c.textContent = G[Math.floor(Math.random() * G.length)];
    c.style.left = (x + vx) + "px";
    c.style.top = y + "px";
    c.style.color = "var(" + C[Math.floor(Math.random() * C.length)] + ")";
    document.body.appendChild(c);
    setTimeout(function () { c.remove(); }, 1100);
  }
  function trail(x, y) {
    for (var i = 0; i < 3; i++) piece(x, y, (Math.random() - 0.5) * 28);
  }
  addEventListener("mousemove", function (e) {
    var t = Date.now();
    if (t - last > 34) { last = t; trail(e.clientX, e.clientY); }
  });
  addEventListener("touchmove", function (e) {
    var t = Date.now();
    if (t - last > 34) {
      last = t;
      var p = e.touches[0];
      if (p) trail(p.clientX, p.clientY);
    }
  }, { passive: true });
})();

/* ---------- the terminal types itself, verbatim from a real run ---------- */
(function () {
  var el = document.getElementById("typed");
  if (!el) return;
  var SEG = [
    ["$ ", "p"], ["./native/precision_test.sh\n\n", "c"],
    ["== rabadon gate precision ==\n\n", "o"],
    ["cases: 34\n", "o"],
    ["correct block: 11    wrong block: ", "o"], ["0\n", "g"],
    ["missed: ", "o"], ["0", "g"], ["    correct allow: 23\n\n", "o"],
    ["precision ", "o"], ["100.0%", "b"], ["\n", "o"],
    ["  a refusal is the right refusal\n  this often\n\n", "o"],
    ["recall    ", "o"], ["100.0%", "b"], ["\n", "o"],
    ["  real harm the gate actually stops\n\n", "o"],
    ["PASS", "g"]
  ];
  var si = 0, ci = 0, done = "";
  function step() {
    if (si >= SEG.length) { el.innerHTML = done + '<span class="cur">█</span>'; return; }
    var text = SEG[si][0], cls = SEG[si][1];
    ci++;
    if (ci > text.length) {
      done += '<span class="' + cls + '">' + text + '</span>';
      si++; ci = 0;
      setTimeout(step, 0);
      return;
    }
    el.innerHTML = done + '<span class="' + cls + '">' + text.slice(0, ci) +
      '</span><span class="cur">█</span>';
    setTimeout(step, text.charAt(ci - 1) === "\n" ? 105 : 18);
  }
  step();
})();
