// 终端录制回放：把真实录制的终端输出（含 ANSI 控制序列）按时间重放成网页上的文字终端。
// 不是视频：文字可以选中、复制。无依赖，无追踪。数据由 site/tools/record-init.py 生成。
(function () {
  "use strict";

  // ---------- 字符宽度：中日韩等宽字符占两列 ----------
  function wide(c) {
    return (c >= 0x1100 && c <= 0x115f) || (c >= 0x2e80 && c <= 0x303e) || (c >= 0x3041 && c <= 0x33ff) ||
      (c >= 0x3400 && c <= 0x4dbf) || (c >= 0x4e00 && c <= 0x9fff) || (c >= 0xa000 && c <= 0xa4cf) ||
      (c >= 0xac00 && c <= 0xd7a3) || (c >= 0xf900 && c <= 0xfaff) || (c >= 0xfe30 && c <= 0xfe4f) ||
      (c >= 0xff00 && c <= 0xff60) || (c >= 0xffe0 && c <= 0xffe6) || (c >= 0x1f300 && c <= 0x1f64f) ||
      (c >= 0x1f900 && c <= 0x1f9ff) || (c >= 0x20000 && c <= 0x3fffd);
  }

  // ---------- 极简终端：只保留回放需要的部分 ----------
  // 屏幕是一组行，每行是若干单元格 [字符, 样式]；向下滚出屏幕的行保留为历史。
  function Term(cols, rows) {
    this.cols = cols; this.rows = rows;
    this.reset();
  }
  Term.prototype.reset = function () {
    this.lines = [[]]; this.r = 0; this.c = 0; this.wrap = false;
    this.st = { fg: null, bg: null, b: 0, d: 0, i: 0, u: 0 }; this.key = "";
    this.saved = null; this.pend = ""; this.dirty = { all: true };
  };
  Term.prototype.top = function () { return Math.max(0, this.lines.length - this.rows); };
  Term.prototype.line = function (r) { while (this.lines.length <= r) this.lines.push([]); return this.lines[r]; };
  Term.prototype.mark = function (r) { this.dirty[r] = true; };
  Term.prototype.styleKey = function () {
    var s = this.st, k = [];
    if (s.fg !== null) k.push("f" + s.fg);
    if (s.bg !== null) k.push("g" + s.bg);
    if (s.b) k.push("b"); if (s.d) k.push("d"); if (s.i) k.push("i"); if (s.u) k.push("u");
    this.key = k.join(" ");
  };
  Term.prototype.newline = function () {
    this.r++; this.line(this.r); this.wrap = false;
  };
  Term.prototype.put = function (ch) {
    var w = wide(ch.codePointAt(0)) ? 2 : 1;
    if (this.wrap || this.c + w > this.cols) { this.newline(); this.c = 0; }
    var L = this.line(this.r);
    while (L.length < this.c) L.push([" ", ""]);
    L[this.c] = [ch, this.key];
    if (w === 2) L[this.c + 1] = ["", this.key];
    // 覆盖了宽字符的后半格时，把前半格清掉
    if (L[this.c + w] && L[this.c + w][0] === "" && w === 1) L[this.c + w] = [" ", ""];
    this.c += w;
    if (this.c >= this.cols) { this.c = this.cols; this.wrap = true; }
    this.mark(this.r);
  };
  Term.prototype.eraseLine = function (mode) {
    var L = this.line(this.r);
    if (mode === 2) L.length = 0;
    else if (mode === 1) { for (var i = 0; i <= this.c && i < L.length; i++) L[i] = [" ", ""]; }
    else L.length = Math.min(L.length, this.c);
    this.mark(this.r);
  };
  Term.prototype.sgr = function (ps) {
    if (!ps.length) ps = [0];
    for (var i = 0; i < ps.length; i++) {
      var p = ps[i], s = this.st;
      if (p === 0) { s.fg = s.bg = null; s.b = s.d = s.i = s.u = 0; }
      else if (p === 1) s.b = 1; else if (p === 2) s.d = 1; else if (p === 3) s.i = 1; else if (p === 4) s.u = 1;
      else if (p === 22) s.b = s.d = 0; else if (p === 23) s.i = 0; else if (p === 24) s.u = 0;
      else if (p >= 30 && p <= 37) s.fg = p - 30; else if (p >= 90 && p <= 97) s.fg = p - 90 + 8; else if (p === 39) s.fg = null;
      else if (p >= 40 && p <= 47) s.bg = p - 40; else if (p >= 100 && p <= 107) s.bg = p - 100 + 8; else if (p === 49) s.bg = null;
      else if (p === 38 || p === 48) {   // 256 色 / 真彩色：归到最接近的基本色
        var n = null;
        if (ps[i + 1] === 5) { n = ps[i + 2]; i += 2; n = n < 16 ? n : null; }
        else if (ps[i + 1] === 2) { i += 4; }
        if (p === 38) s.fg = n; else s.bg = n;
      }
    }
    this.styleKey();
  };
  Term.prototype.csi = function (params, final, priv) {
    var ps = params ? params.split(";").map(function (x) { return x === "" ? 0 : parseInt(x, 10) || 0; }) : [];
    var n = ps[0] || 1, top = this.top();
    if (priv) return;   // ?25l、?2004h 等模式切换：回放里不需要
    switch (final) {
      case "m": this.sgr(ps); break;
      case "A": this.r = Math.max(top, this.r - n); this.wrap = false; break;
      case "B": this.r += n; this.line(this.r); this.wrap = false; break;
      case "C": this.c = Math.min(this.cols - 1, this.c + n); this.wrap = false; break;
      case "D": this.c = Math.max(0, Math.min(this.c, this.cols - 1) - n); this.wrap = false; break;
      case "E": this.r += n; this.line(this.r); this.c = 0; this.wrap = false; break;
      case "F": this.r = Math.max(top, this.r - n); this.c = 0; this.wrap = false; break;
      case "G": this.c = Math.min(this.cols - 1, (ps[0] || 1) - 1); this.wrap = false; break;
      case "H": case "f":
        this.r = top + Math.max(0, (ps[0] || 1) - 1); this.line(this.r);
        this.c = Math.min(this.cols - 1, (ps[1] || 1) - 1); this.wrap = false; break;
      case "K": this.eraseLine(ps[0] || 0); break;
      case "J":
        var m = ps[0] || 0;
        if (m === 0) { this.eraseLine(0); for (var r = this.r + 1; r < this.lines.length; r++) { this.lines[r] = []; this.mark(r); } }
        else if (m === 2 || m === 3) {   // 清屏：把当前屏幕推进历史，开一屏新的
          var keep = this.lines.length;
          for (var k = 0; k < this.rows; k++) this.lines.push([]);
          this.r = keep; this.c = 0; this.dirty.all = true;
        }
        break;
      case "s": this.saved = [this.r, this.c]; break;
      case "u": if (this.saved) { this.r = this.saved[0]; this.c = this.saved[1]; } break;
    }
  };
  Term.prototype.write = function (s) {
    s = this.pend + s; this.pend = "";
    var i = 0, n = s.length;
    while (i < n) {
      var ch = s[i];
      if (ch === "\x1b") {
        if (i + 1 >= n) { this.pend = s.slice(i); return; }
        var nx = s[i + 1];
        if (nx === "[") {
          var j = i + 2;
          while (j < n && !/[@-~]/.test(s[j])) j++;
          if (j >= n) { this.pend = s.slice(i); return; }
          var body = s.slice(i + 2, j), priv = /^[?>=!]/.test(body);
          this.csi(priv ? body.slice(1) : body.replace(/[ -\/]/g, ""), s[j], priv);
          i = j + 1; continue;
        }
        if (nx === "]" || nx === "P" || nx === "_") {   // OSC / DCS：跳到 BEL 或 ST
          var e = i + 2;
          while (e < n && s[e] !== "\x07" && !(s[e] === "\x1b" && s[e + 1] === "\\")) e++;
          if (e >= n) { this.pend = s.slice(i); return; }
          i = e + (s[e] === "\x07" ? 1 : 2); continue;
        }
        if (nx === "7") { this.saved = [this.r, this.c]; i += 2; continue; }
        if (nx === "8") { if (this.saved) { this.r = this.saved[0]; this.c = this.saved[1]; } i += 2; continue; }
        if (nx === "(" || nx === ")") { i += 3; continue; }
        i += 2; continue;
      }
      if (ch === "\r") { this.c = 0; this.wrap = false; }
      else if (ch === "\n") { this.newline(); }
      else if (ch === "\b") { this.c = Math.max(0, Math.min(this.c, this.cols) - 1); this.wrap = false; }
      else if (ch === "\t") { this.c = Math.min(this.cols - 1, (Math.floor(this.c / 8) + 1) * 8); }
      else if (ch === "\x07" || ch < " ") { /* 其它控制字符忽略 */ }
      else {
        var cp = s.codePointAt(i);
        var str = String.fromCodePoint(cp);
        this.put(str); i += str.length; continue;
      }
      i++;
    }
  };

  // ---------- 渲染 ----------
  function esc(t) { return t.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;"); }
  function lineHTML(L, cur) {   // cur：光标所在列（不在这一行时为 -1）
    var out = "", style = null, buf = "";
    function flush() {
      if (buf) out += style ? '<span class="' + cls(style) + '">' + esc(buf) + "</span>" : esc(buf);
      buf = "";
    }
    var end = L.length;   // 去掉行尾空白
    while (end > 0 && (L[end - 1][0] === " " || L[end - 1][0] === "") && !L[end - 1][1]) end--;
    for (var i = 0; i < end; i++) {
      var cell = L[i] || [" ", ""];
      if (cell[0] === "") continue;
      if (i === cur) { flush(); out += '<span class="cur">' + esc(cell[0]) + "</span>"; style = null; continue; }
      if (cell[1] !== style) { flush(); style = cell[1]; }
      buf += cell[0];
    }
    flush();
    if (cur >= end) out += new Array(cur - end + 1).join(" ") + '<span class="cur"> </span>';
    return out;
  }
  function cls(k) { return k.split(" ").map(function (x) { return "a-" + x; }).join(" "); }

  function fmt(t) {
    t = Math.max(0, Math.round(t));
    var m = Math.floor(t / 60), s = t % 60;
    return m + ":" + (s < 10 ? "0" : "") + s;
  }

  // ---------- 播放器 ----------
  function Player(root, data) {
    this.root = root; this.data = data;
    this.term = new Term(data.cols, data.rows);
    this.screen = root.querySelector(".cast-screen");
    this.screen.style.setProperty("--cols", data.cols);
    this.screen.style.setProperty("--rows", data.rows);
    this.els = [];
    this.btn = root.querySelector("[data-cast=play]");
    this.bar = root.querySelector("[data-cast=bar]");
    this.fill = root.querySelector("[data-cast=fill]");
    this.time = root.querySelector("[data-cast=time]");
    this.speedBtn = root.querySelector("[data-cast=speed]");
    this.speeds = [1, 2, 4]; this.speed = 1;
    // 回放时间轴：真实时间里超过 MAXGAP 秒的等待压缩成 MAXGAP 秒（构建镜像、下载等），
    // 状态栏同时显示真实经过的时间
    var MAXGAP = 1.6, t = 0, prev = 0;
    this.tl = data.events.map(function (e) {
      t += Math.min(e[0] - prev, MAXGAP); prev = e[0];
      return t;
    });
    this.total = t;
    this.idx = 0; this.pos = 0; this.playing = false; this.raf = 0;
    var self = this;
    this.btn.addEventListener("click", function () { self.playing ? self.pause() : self.play(); });
    if (this.speedBtn) this.speedBtn.addEventListener("click", function () {
      self.speed = self.speeds[(self.speeds.indexOf(self.speed) + 1) % self.speeds.length];
      self.speedBtn.textContent = self.speed + "×";
    });
    this.bar.addEventListener("click", function (ev) {
      var r = self.bar.getBoundingClientRect();
      self.seek(self.total * Math.min(1, Math.max(0, (ev.clientX - r.left) / r.width)));
    });
    this.bar.addEventListener("keydown", function (ev) {
      if (ev.key === "ArrowRight") { self.seek(self.pos + 5); ev.preventDefault(); }
      if (ev.key === "ArrowLeft") { self.seek(self.pos - 5); ev.preventDefault(); }
    });
    root.querySelectorAll("[data-cast-seek]").forEach(function (a) {
      a.addEventListener("click", function (ev) {
        ev.preventDefault();
        self.seekReal(parseFloat(a.getAttribute("data-cast-seek")));
        if (!self.playing) self.play();
      });
    });
  }
  // 真实时间 → 回放时间
  Player.prototype.toPlay = function (real) {
    var ev = this.data.events, i = 0;
    while (i < ev.length && ev[i][0] < real) i++;
    return i < ev.length ? this.tl[i] - 0.001 : this.total;
  };
  Player.prototype.seekReal = function (real) { this.seek(this.toPlay(real)); };
  Player.prototype.render = function () {
    var T = this.term, scr = this.screen, i;
    if (T.dirty.all) { scr.textContent = ""; this.els = []; }
    for (i = this.els.length; i < T.lines.length; i++) {
      var d = document.createElement("div"); d.className = "ln";
      scr.appendChild(d); this.els.push(d); T.dirty[i] = true;
    }
    if (this.curRow !== undefined && this.curRow !== T.r) T.dirty[this.curRow] = true;
    T.dirty[T.r] = true;
    for (var k in T.dirty) {
      if (k === "all") continue;
      var r = +k;
      if (this.els[r]) this.els[r].innerHTML = lineHTML(T.lines[r] || [], r === T.r ? Math.min(T.c, T.cols - 1) : -1);
    }
    T.dirty = {}; this.curRow = T.r;
    this.follow();
    var p = this.total ? this.pos / this.total : 0;
    this.fill.style.width = (p * 100).toFixed(2) + "%";
    this.bar.setAttribute("aria-valuenow", Math.round(p * 100));
    var real = this.idx > 0 ? this.data.events[this.idx - 1][0] : 0;
    this.time.textContent = "录制时间 " + fmt(real) + " / " + fmt(this.data.duration);
  };
  Player.prototype.follow = function () {
    var v = this.root.querySelector(".cast-view");
    if (!this.userScrolled) v.scrollTop = v.scrollHeight;
  };
  Player.prototype.advance = function (to) {
    var ev = this.data.events;
    while (this.idx < ev.length && this.tl[this.idx] <= to) { this.term.write(ev[this.idx][1]); this.idx++; }
    this.pos = to;
  };
  Player.prototype.seek = function (to) {
    to = Math.max(0, Math.min(this.total, to));
    if (to < this.pos) { this.term.reset(); this.idx = 0; }
    this.advance(to);
    this.userScrolled = false;
    this.render();
    if (this.pos >= this.total) this.done();
  };
  Player.prototype.play = function () {
    if (this.pos >= this.total) this.seek(0);
    this.playing = true; this.root.classList.add("playing");
    this.btn.textContent = "暂停"; this.btn.setAttribute("aria-label", "暂停");
    var self = this, last = performance.now();
    function tick(now) {
      if (!self.playing) return;
      var dt = Math.min(0.25, (now - last) / 1000) * self.speed; last = now;
      self.advance(self.pos + dt);
      self.render();
      if (self.pos >= self.total) { self.done(); return; }
      self.raf = requestAnimationFrame(tick);
    }
    this.raf = requestAnimationFrame(tick);
  };
  Player.prototype.pause = function () {
    this.playing = false; cancelAnimationFrame(this.raf); this.root.classList.remove("playing");
    this.btn.textContent = "播放"; this.btn.setAttribute("aria-label", "播放");
  };
  Player.prototype.done = function () {
    this.pause(); this.btn.textContent = "重播"; this.btn.setAttribute("aria-label", "重播");
  };

  // ---------- 启动 ----------
  var root = document.querySelector("[data-cast-root]");
  var data = window.AIBOX_CAST;
  if (!root || !data) return;
  // 章节和录制信息（来自录制数据）
  var ch = root.querySelector("[data-cast=chapters]");
  if (ch && data.markers) {
    data.markers.forEach(function (m) {
      var li = document.createElement("li"), b = document.createElement("button");
      b.type = "button"; b.setAttribute("data-cast-seek", m[0]);
      b.innerHTML = "<span>" + fmt(m[0]) + "</span>" + esc(m[1]);
      li.appendChild(b); ch.appendChild(li);
    });
  }
  var env = data.env || {};
  var meta = {
    recorded: data.recorded, os: env.os && (env.os + (env.arch ? " · " + env.arch : "")),
    docker: env.docker && ("Docker " + env.docker + (env.compose ? " · Compose " + env.compose : "")),
    commit: env.commit, duration: fmt(data.duration)
  };
  document.querySelectorAll("[data-cast-meta]").forEach(function (el) {
    var v = meta[el.getAttribute("data-cast-meta")]; if (v) el.textContent = v;
  });

  var p = new Player(root, data);
  root.castPlayer = p;   // 方便在控制台里调试
  var view = root.querySelector(".cast-view");
  // 用户往上翻看时不要强行滚到底；翻回底部后恢复跟随
  view.addEventListener("scroll", function () {
    p.userScrolled = view.scrollTop + view.clientHeight < view.scrollHeight - 8;
  }, { passive: true });

  var reduce = window.matchMedia && window.matchMedia("(prefers-reduced-motion: reduce)").matches;
  if (reduce) { p.seek(p.total); return; }   // 关闭动效时直接显示完整结果
  p.render();
  if ("IntersectionObserver" in window) {
    var io = new IntersectionObserver(function (es) {
      if (es[0].isIntersecting) { io.disconnect(); p.play(); }
    }, { threshold: 0.25 });
    io.observe(root);
  } else {
    p.play();
  }
})();
