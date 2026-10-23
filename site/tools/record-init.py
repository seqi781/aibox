#!/usr/bin/env python3
"""录制一次真实的 ./aibox init，生成网页终端回放数据（site/init/cast.js）。

用法（在仓库根目录运行；需要能访问 Docker）：
  python3 site/tools/record-init.py --sub-file ~/sub.txt
      sub.txt 每行一条订阅链接或分享链接，只用于录制时粘贴，不会写进网页
  python3 site/tools/record-init.py --remask raw.cast
      只对已有的原始录制重新脱敏、重新生成 cast.js

录制过程完全真实：脚本在伪终端里启动 bash，输入 ./aibox init，按向导的提示作答
（选项 1 → 粘贴链接 → 全部节点 → 授权两个目录 → 不安装命令 → 立即启动）。
注意：录制会真的写入 config/、构建镜像并启动容器，和手动运行 ./aibox init 一样。

生成网页数据前会脱敏：
  - 粘贴的链接在回显里替换成同样形状的占位链接；
  - 所有公网 IPv4 换成文档保留地址（203.0.113.x 等，同一网段保持一致），IPv6 换成 2001:db8::x；
  - 原始录制（未脱敏）只保存在 --raw 指定的位置，不要提交到仓库。
"""
import argparse, codecs, datetime, fcntl, ipaddress, json, os, pty, random, re, select
import shutil, signal, struct, subprocess, sys, termios, time

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
COLS, ROWS = 100, 32
ANSI = re.compile(r"\x1b\[[0-9;?]*[ -/]*[@-~]|\x1b\][^\x07\x1b]*(\x07|\x1b\\)|\x1b[@-Z\\-_]")


def strip(s):
    return ANSI.sub("", s)


# ---------------------------------------------------------------- 录制
class Recorder:
    def __init__(self, links, mounts, install):
        self.links, self.mounts, self.install = links, list(mounts), install
        self.events, self.markers, self.paste = [], [], None
        self.dec = codecs.getincrementaldecoder("utf-8")("replace")
        self.line = ""          # 当前行（去掉控制序列后），用来判断提示符
        self.t0 = None

    def spawn(self):
        env = {k: os.environ[k] for k in ("HOME", "USER", "PATH", "SHELL") if k in os.environ}
        env.update(TERM="xterm-256color", LANG="C.UTF-8", PS1="$ ", COLUMNS=str(COLS), LINES=str(ROWS))
        shell = ["bash", "--noprofile", "--norc", "-i"]
        if subprocess.run(["docker", "info"], capture_output=True).returncode != 0:
            # 当前进程还没有 docker 组权限（刚加入组、没重新登录）时，借 sg 拿到权限
            shell = ["sg", "docker", "-c", "exec bash --noprofile --norc -i"]
        pid, fd = pty.fork()
        if pid == 0:
            os.chdir(ROOT)
            os.execvpe(shell[0], shell, env)
        fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", ROWS, COLS, 0, 0))
        self.pid, self.fd = pid, fd

    def pump(self, timeout):
        r, _, _ = select.select([self.fd], [], [], timeout)
        if not r:
            return False
        try:
            b = os.read(self.fd, 65536)
        except OSError:
            raise EOFError
        if not b:
            raise EOFError
        s = self.dec.decode(b)
        if self.t0 is not None and s:
            self.events.append([time.monotonic() - self.t0, s])
        for ch in strip(s):
            if ch == "\n":
                self.line = ""
            elif ch == "\r":
                pass
            else:
                self.line += ch
        sys.stdout.write(s); sys.stdout.flush()
        return True

    def wait(self, pattern, timeout):
        """等当前行出现 pattern（提示符停在行尾），期间持续收输出。"""
        rx = re.compile(pattern)
        end = time.monotonic() + timeout
        while time.monotonic() < end:
            got = self.pump(0.2)
            if not got and rx.search(self.line):
                return True
        raise TimeoutError(f"等待超时: {pattern!r}；当前行: {self.line!r}")

    def settle(self, quiet=0.6, timeout=5):
        end = time.monotonic() + timeout
        last = time.monotonic()
        while time.monotonic() < end and time.monotonic() - last < quiet:
            if self.pump(0.1):
                last = time.monotonic()

    def type(self, text, pause=(0.5, 0.9)):
        time.sleep(random.uniform(*pause))
        for ch in text:
            os.write(self.fd, ch.encode())
            self.pump(0)
            time.sleep(0.03 if ch == "\n" else random.uniform(0.045, 0.11))

    def mark(self, label):
        self.markers.append([time.monotonic() - self.t0, label])

    def run(self):
        self.spawn()
        self.wait(r"\$ $", 20)
        self.t0 = time.monotonic()
        self.events.append([0.0, "$ "])
        self.mark("开始")
        self.type("./aibox init\n", pause=(0.4, 0.4))
        self.mark("环境检查")

        prompts = [
            (r"请选择 .*: $", "choose"),
            (r"最后再按一次回车结束：$", "paste"),
            (r"节点筛选 .*: $", "filter"),
            (r"重新输入？.*: $", "retry"),
            (r"保留以上授权？.*: $", "keep"),
            (r"添加目录（Tab 补全，直接回车结束）: $", "mount"),
            (r"权限 rw/ro .*: $", "mode"),
            (r"安装 aibox 命令.*: $", "install"),
            (r"不在 PATH 中，添加到.*: $", "yes"),
            (r"添加 Tab 补全到.*: $", "yes"),
            (r"现在启动？.*: $", "start"),
            (r"^\$ $", "done"),
        ]
        rx = [(re.compile(p), k) for p, k in prompts]
        mode = "rw"
        deadline = time.monotonic() + 40 * 60
        while time.monotonic() < deadline:
            if self.pump(0.3):
                continue
            kind = next((k for r, k in rx if r.search(self.line)), None)
            if kind is None:
                continue
            if kind == "choose":
                self.mark("网络出口"); self.type("1\n")
            elif kind == "paste":
                time.sleep(1.2)
                start = len(self.events)
                os.write(self.fd, ("\n".join(self.links) + "\n").encode())   # 粘贴是一次性到达的
                self.settle(0.4)
                self.type("\n", pause=(0.5, 0.7))
                end_t = time.monotonic() + 15
                while time.monotonic() < end_t and not any("正在识别" in e[1] for e in self.events[start:]):
                    self.pump(0.2)
                end = len(self.events)
                for i in range(start, end):           # 找到“正在识别”所在的事件，回显到它之前为止
                    if "正在识别" in self.events[i][1]:
                        end = i; break
                self.paste = [start, end]
                self.mark("导入并测试节点")
            elif kind == "filter":
                self.type("\n")
            elif kind == "retry":
                raise RuntimeError("节点测试没有通过，停止录制（请换一个可用的订阅）")
            elif kind == "keep":
                self.type("y\n")
            elif kind == "mount":
                if self.mounts:
                    if not any(m == "授权目录" for _, m in self.markers):
                        self.mark("授权目录")
                    mode, path = self.mounts.pop(0)
                    self.type(path + "\n")
                else:
                    self.type("\n")
            elif kind == "mode":
                self.type(mode + "\n")
            elif kind == "install":
                self.type(("y" if self.install else "n") + "\n")
            elif kind == "yes":
                self.type("y\n")
            elif kind == "start":
                self.type("y\n"); self.mark("构建并启动")
            elif kind == "done":
                if any(m == "构建并启动" for _, m in self.markers) or "下一步" in "".join(e[1] for e in self.events[-20:]):
                    break
        else:
            raise TimeoutError("录制超过 40 分钟")
        # 补上“环境检测报告”章节的位置
        for t, s in self.events:
            if "环境检测报告" in strip(s):
                self.markers.append([t, "环境检测报告"]); break
        self.markers.sort()
        self.duration = self.events[-1][0]
        os.kill(self.pid, signal.SIGHUP)


# ---------------------------------------------------------------- 脱敏
DOC_NETS = ["203.0.113", "198.51.100", "192.0.2"]


class Masker:
    """公网 IP → 文档保留地址。同一个 /24 网段映射到同一个保留网段，保持“出口 IP 与 ECS 网段一致”这类关系可读。"""
    def __init__(self):
        self.nets, self.v6 = {}, {}

    def v4(self, s, last):
        try:
            ip = ipaddress.IPv4Address(s)
        except ValueError:
            return s
        if not ip.is_global or ip.is_multicast:
            return s       # 127.0.0.1、容器内网、fake-ip 段等保留原样
        net = s.rsplit(".", 1)[0]
        i = self.nets.setdefault(net, len(self.nets))
        if i >= len(DOC_NETS):          # 超过 3 个网段时错开末位，避免撞号
            last = str((int(last) + 61 * (i // len(DOC_NETS))) % 254 + 1)
        return f"{DOC_NETS[i % len(DOC_NETS)]}.{last}"

    def v6addr(self, s):
        try:
            ip = ipaddress.IPv6Address(s)
        except ValueError:
            return s
        if not ip.is_global:
            return s
        return self.v6.setdefault(s, f"2001:db8::{len(self.v6) + 1:x}")

    def sub(self, mt):
        if mt.group(1):
            return self.v4(mt.group(0), mt.group(5))
        return self.v6addr(mt.group(0))


IP_RX = re.compile(r"(?<![\d.])((\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3}))(?![\d.])"
                   r"|(?<![0-9A-Za-z:])[0-9A-Fa-f]{0,4}(?::[0-9A-Fa-f]{0,4}){2,7}(?![0-9A-Za-z:])")


def link_host(link):
    h = re.sub(r"^[a-z0-9+.-]+://([^/?#]*@)?", "", link, flags=re.I)
    return re.split(r"[/?#:]", h, 1)[0]


def fake_link(link):
    """同样形状、不含任何真实信息的占位链接。"""
    m = re.match(r"([a-z0-9+.-]+)://", link, re.I)
    scheme = (m.group(1) if m else "https").lower()
    base = "https://sub.example.com/api/v1/client/subscribe?token=" if scheme in ("http", "https") else f"{scheme}://"
    return base + "•" * 24


def mask(raw, links):
    events = [list(e) for e in raw["events"]]
    if raw.get("paste"):          # 粘贴内容的回显整段换成占位链接
        a, b = raw["paste"]
        echo = "".join(fake_link(l) + "\r\n" for l in links) + "\r\n"
        events[a:b] = [[events[a][0], echo]]
    for e in events:              # 兜底：链接或它的域名若在别处出现（例如报错信息），也替换掉
        for l in links:
            e[1] = e[1].replace(l, fake_link(l))
            host = link_host(l)
            if len(host) > 3:
                e[1] = e[1].replace(host, "sub.example.com")
    # 在整段文本上替换 IP（IP 可能被切在两个事件之间），再按偏移把事件边界对齐回去
    text = "".join(e[1] for e in events)
    m = Masker()
    out, offs, n, i = [], [0] * (len(text) + 1), 0, 0
    for mt in IP_RX.finditer(text):
        a, b = mt.span()
        new = m.sub(mt)
        while i < a:
            offs[i] = n; out.append(text[i]); n += 1; i += 1
        for k in range(a, b):
            offs[k] = n
        out.append(new); n += len(new); i = b
    while i < len(text):
        offs[i] = n; out.append(text[i]); n += 1; i += 1
    offs[len(text)] = n
    text2 = "".join(out)
    result, pos, prev = [], 0, 0
    for t, s in events:
        pos += len(s)
        nb = offs[pos]
        if nb > prev:
            result.append([round(t, 3), text2[prev:nb]])
        prev = nb
    for l in links:               # 检查：链接里的域名和较长的片段（token、路径等）都不能出现在结果里
        parts = {link_host(l)} | set(re.findall(r"[A-Za-z0-9_%=+-]{8,}", l))
        leaked = [p for p in parts if p and p not in fake_link(l) and p in text2]
        if leaked:
            raise RuntimeError("脱敏失败：网页数据里仍有链接片段，未生成 cast.js")
    return result, m


def env_info():
    def sh(cmd):
        try:
            return subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=20).stdout.strip()
        except Exception:
            return ""
    d = sh("docker version -f '{{.Server.Version}}' 2>/dev/null || sg docker -c \"docker version -f '{{.Server.Version}}'\"")
    c = sh("docker compose version --short 2>/dev/null || sg docker -c 'docker compose version --short'")
    osn = sh(". /etc/os-release 2>/dev/null && echo \"$PRETTY_NAME\"") or sh("sw_vers -productName; sw_vers -productVersion | tr '\\n' ' '")
    return {"os": osn, "arch": os.uname().machine, "docker": d, "compose": c,
            "commit": sh(f"git -C '{ROOT}' rev-parse --short HEAD")}


def write_cast(raw, links, out):
    events, m = mask(raw, links)
    data = {
        "cols": raw["cols"], "rows": raw["rows"], "recorded": raw["recorded"], "env": raw["env"],
        "duration": round(events[-1][0], 3), "markers": [[round(t, 3), l] for t, l in raw["markers"]],
        "events": events,
    }
    os.makedirs(os.path.dirname(out), exist_ok=True)
    with open(out, "w", encoding="utf-8") as f:
        f.write("/* 由 site/tools/record-init.py 生成：真实录制的 ./aibox init，链接和 IP 已脱敏。不要手动编辑。 */\n")
        f.write("window.AIBOX_CAST = ")
        json.dump(data, f, ensure_ascii=False, separators=(",", ":"))
        f.write(";\n")
    print(f"\n已生成 {out}（{len(events)} 段输出，录制时长 {data['duration']:.0f} 秒）")
    if m.nets or m.v6:
        print(f"已替换 {len(m.nets)} 个 IPv4 网段、{len(m.v6)} 个 IPv6 地址")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--sub-file", help="每行一条订阅或分享链接")
    ap.add_argument("--remask", metavar="RAW", help="只重新脱敏已有的原始录制")
    ap.add_argument("--raw", default=os.path.join(ROOT, ".aibox", "init-raw.cast.json"), help="原始录制保存位置（未脱敏，勿提交）")
    ap.add_argument("--out", default=os.path.join(ROOT, "site", "init", "cast.js"))
    ap.add_argument("--mount", action="append", default=[], metavar="MODE:PATH",
                    help="向导里授权的目录，可重复；默认 rw:~/code/myapp 和 ro:~/code/specs")
    ap.add_argument("--install", action="store_true", help="向导询问时安装 aibox / ai 命令（会改 ~/.bashrc）")
    a = ap.parse_args()

    if a.remask:
        raw = json.load(open(a.remask, encoding="utf-8"))
        links = [l.strip() for l in open(a.sub_file, encoding="utf-8") if l.strip()] if a.sub_file else raw.get("links_hint", [])
        write_cast(raw, links, a.out)
        return
    if not a.sub_file:
        ap.error("需要 --sub-file")
    links = [l.strip() for l in open(os.path.expanduser(a.sub_file), encoding="utf-8") if l.strip()]
    mounts = [tuple(x.split(":", 1)) for x in a.mount] or [("rw", "~/code/myapp"), ("ro", "~/code/specs")]
    for _, p in mounts:
        p = os.path.expanduser(p)
        if not os.path.isdir(p):
            sys.exit(f"目录不存在: {p}（先创建它，或用 --mount 指定）")

    rec = Recorder(links, mounts, a.install)
    try:
        rec.run()
    finally:
        try:
            os.kill(rec.pid, signal.SIGHUP)
        except Exception:
            pass
    raw = {"cols": COLS, "rows": ROWS, "recorded": datetime.date.today().isoformat(), "env": env_info(),
           "events": rec.events, "markers": rec.markers, "paste": rec.paste}
    os.makedirs(os.path.dirname(a.raw), exist_ok=True)
    with open(a.raw, "w", encoding="utf-8") as f:
        json.dump(raw, f, ensure_ascii=False)
    os.chmod(a.raw, 0o600)
    print(f"\n原始录制（未脱敏）: {a.raw}")
    write_cast(raw, links, a.out)


if __name__ == "__main__":
    main()
