// aibox 宣传站：顶栏、复制按钮、首屏终端演示。无依赖，无追踪。
(function () {
  "use strict";

  var reduce = window.matchMedia && window.matchMedia("(prefers-reduced-motion: reduce)").matches;
  var lang = document.documentElement.lang.indexOf("zh") === 0 ? "zh" : "en";
  var T = {
    zh: { copy: "复制", done: "已复制", fail: "复制失败" },
    en: { copy: "Copy", done: "Copied", fail: "Failed" }
  }[lang];

  // 顶栏：滚动后出现底色
  var hdr = document.querySelector(".hdr");
  if (hdr) {
    var onScroll = function () { hdr.classList.toggle("solid", window.scrollY > 8); };
    window.addEventListener("scroll", onScroll, { passive: true });
    onScroll();
  }

  // 复制按钮：复制目标 <pre> 的纯文本（代码块里没有提示符，复制即可运行）
  function copyText(text) {
    if (navigator.clipboard && window.isSecureContext) return navigator.clipboard.writeText(text);
    return new Promise(function (ok, fail) {
      var ta = document.createElement("textarea");
      ta.value = text; ta.setAttribute("readonly", ""); ta.style.position = "fixed"; ta.style.opacity = "0";
      document.body.appendChild(ta); ta.select();
      try { document.execCommand("copy") ? ok() : fail(); } catch (e) { fail(e); }
      document.body.removeChild(ta);
    });
  }
  document.querySelectorAll("button.copy").forEach(function (btn) {
    btn.textContent = T.copy;
    btn.addEventListener("click", function () {
      var pre = document.getElementById(btn.getAttribute("data-target"));
      if (!pre) return;
      var text = pre.innerText.replace(/\s+$/, "") + "\n";
      copyText(text).then(function () {
        btn.textContent = T.done; btn.setAttribute("data-done", "");
      }, function () { btn.textContent = T.fail; }).then(function () {
        setTimeout(function () { btn.textContent = T.copy; btn.removeAttribute("data-done"); }, 1600);
      });
    });
  });

  // 首屏终端：按脚本逐行播放。脚本放在页面的 <script type="application/json" id="demo-script">。
  // 关闭动效或没有 JS 时，<pre> 里已有完整的最终画面。
  var pre = document.getElementById("demo");
  var src = document.getElementById("demo-script");
  var replay = document.getElementById("demo-replay");
  if (!pre || !src) return;
  var steps;
  try { steps = JSON.parse(src.textContent); } catch (e) { return; }
  var finalHTML = pre.innerHTML;
  if (reduce) { if (replay) replay.hidden = true; return; }

  function esc(s) { return s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;"); }
  var timer = null, running = false;

  function play() {
    clearTimeout(timer);
    running = true;
    pre.innerHTML = "";
    var i = 0;
    var caret = document.createElement("span");
    caret.className = "caret";
    caret.setAttribute("aria-hidden", "true");

    function next() {
      if (i >= steps.length) { running = false; pre.appendChild(caret); return; }
      var s = steps[i++];
      if (s.cmd !== undefined) {
        var line = document.createElement("span");
        line.innerHTML = '<span class="ps">$ </span>';
        var cm = document.createElement("span");
        cm.className = "cm";
        line.appendChild(cm);
        pre.appendChild(line);
        line.appendChild(caret);
        var k = 0;
        (function type() {
          if (k < s.cmd.length) {
            cm.textContent += s.cmd.charAt(k++);
            timer = setTimeout(type, 38 + Math.random() * 40);
          } else {
            line.removeChild(caret);
            pre.appendChild(document.createTextNode("\n"));
            timer = setTimeout(next, 380);
          }
        })();
      } else {
        var out = document.createElement("span");
        if (s.cls) out.className = s.cls;
        out.innerHTML = esc(s.out);
        pre.appendChild(out);
        pre.appendChild(document.createTextNode("\n"));
        timer = setTimeout(next, s.wait || 140);
      }
    }
    next();
  }

  if (replay) replay.addEventListener("click", play);

  // 进入视口时播放一次
  if ("IntersectionObserver" in window) {
    var played = false;
    var io = new IntersectionObserver(function (es) {
      es.forEach(function (e) {
        if (e.isIntersecting && !played) { played = true; play(); io.disconnect(); }
      });
    }, { threshold: 0.3 });
    io.observe(pre);
  } else {
    pre.innerHTML = finalHTML;
  }
})();
