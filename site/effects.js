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

/* ============================================================
   reveal and count-up.

   Two rules from the house style decide the shape of this:
   a screen is never faded in, it slides or scales, and a number
   that carries a page counts up to itself rather than being
   printed already finished. Both are driven by one observer, so
   a block reveals and its numbers start counting in the same
   frame, and nothing animates twice.

   The value is read from data-to and the FINAL string from
   data-show, so a number that ends in a unit or a percent lands
   on exactly the text the build wrote. Nothing here invents a
   number: it only walks to the one already in the page.
   ============================================================ */
(function () {
  var reduce = window.matchMedia &&
    window.matchMedia("(prefers-reduced-motion: reduce)").matches;

  // every block worth revealing, marked here rather than in the templates so a
  // new section on any page gets it without anyone remembering to
  var blocks = document.querySelectorAll(
    ".stats, .proof, .term, .law, .pair > div, .day, .tbl, details, .cta, .intro > h1, section > h2"
  );
  for (var i = 0; i < blocks.length; i++) blocks[i].setAttribute("data-reveal", "");

  if (reduce || !("IntersectionObserver" in window)) {
    for (var j = 0; j < blocks.length; j++) blocks[j].classList.add("in");
    countAll(document);
    return;
  }

  function ease(t) { return 1 - Math.pow(1 - t, 3); }

  function count(el) {
    if (el.dataset.counted) return;
    el.dataset.counted = "1";
    var to = parseFloat(el.getAttribute("data-to"));
    var show = el.getAttribute("data-show") || el.textContent;
    if (!isFinite(to)) return;
    // the shape of the finished string, so the walk keeps its own formatting:
    // thousands separators, a decimal place, a trailing unit
    var m = show.match(/^([^0-9-]*)(-?[\d,]*\.?\d+)(.*)$/);
    if (!m) return;
    var pre = m[1], post = m[3];
    var dec = (m[2].split(".")[1] || "").length;
    var grouped = m[2].indexOf(",") >= 0;
    var dur = 900, t0 = 0;
    function fmt(v) {
      var s = dec ? v.toFixed(dec) : String(Math.round(v));
      if (grouped) {
        var parts = s.split(".");
        parts[0] = parts[0].replace(/\B(?=(\d{3})+(?!\d))/g, ",");
        s = parts.join(".");
      }
      return pre + s + post;
    }
    function frame(ts) {
      if (!t0) t0 = ts;
      var p = Math.min(1, (ts - t0) / dur);
      el.textContent = p < 1 ? fmt(to * ease(p)) : show;
      if (p < 1) requestAnimationFrame(frame);
    }
    el.textContent = fmt(0);
    requestAnimationFrame(frame);
  }

  function countAll(root) {
    var ns = root.querySelectorAll("[data-to]");
    for (var k = 0; k < ns.length; k++) count(ns[k]);
  }

  var io = new IntersectionObserver(function (entries) {
    for (var e = 0; e < entries.length; e++) {
      if (!entries[e].isIntersecting) continue;
      var el = entries[e].target;
      // a stagger, so a column of five numbers arrives as a column and not as
      // one block landing at once
      var sibs = el.parentNode ? el.parentNode.children : [el];
      var idx = Array.prototype.indexOf.call(sibs, el);
      setTimeout(function (node) {
        return function () { node.classList.add("in"); countAll(node); };
      }(el), Math.min(idx, 6) * 55);
      io.unobserve(el);
    }
  }, { rootMargin: "0px 0px -8% 0px", threshold: 0.08 });

  for (var n = 0; n < blocks.length; n++) io.observe(blocks[n]);

  // anything already on screen at load counts immediately, so the hero is not
  // sitting at zero while the reader looks at it
  requestAnimationFrame(function () {
    for (var q = 0; q < blocks.length; q++) {
      var r = blocks[q].getBoundingClientRect();
      if (r.top < window.innerHeight && r.bottom > 0) {
        blocks[q].classList.add("in");
        countAll(blocks[q]);
        io.unobserve(blocks[q]);
      }
    }
  });
})();
