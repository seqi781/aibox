#!/usr/bin/env python3
"""交互式测试：用伪终端驱动配置向导和 install 的各个分支（由 tests/run.sh 在测试镜像中调用）。

每个流程按顺序等待提示（去掉颜色码后用正则匹配）并输入回答；
检查是否出现解释器错误、是否卡住、返回码是否为 0。不需要网络和 Docker。
"""
import base64, functools, os, pty, re, select, shutil, signal, sys, time

print = functools.partial(print, flush=True)
W = '/tmp/aibox-tty'
ANSI = re.compile(rb'\x1b\[[0-9;?]*[A-Za-z]')
ERR = re.compile(r'unbound variable|syntax error|bad substitution|command not found|line \d+:')
failed = 0


def setup():
    shutil.rmtree(W, ignore_errors=True)
    shutil.copytree('/src', W + '/repo', ignore=shutil.ignore_patterns('config', '.aibox', '.git'))
    for d in ('home/code/app/.git', 'home/projects/site/.git', 'home/docs', 'home/My Dir'):
        os.makedirs(f'{W}/{d}')
    os.utime(f'{W}/home/projects/site/.git', (1e9, 1e9))   # 较旧的项目排在后面
    open(W + '/wg.conf', 'w').write('[Interface]\nPrivateKey = k\nAddress = 10.0.0.2\n[Peer]\n'
                                    'PublicKey = p\nEndpoint = 203.0.113.5:51820\nAllowedIPs = 0.0.0.0/0\n')


def drive(name, args, steps, env=None, timeout=15):
    """steps: [(提示正则, 回答)]；回答里的 \\n 会作为多次回车发送"""
    global failed
    pid, fd = pty.fork()
    if pid == 0:
        os.chdir(W + '/repo')
        e = dict(HOME=W + '/home', LANG='en_US.UTF-8', LC_ALL='en_US.UTF-8', TERM='xterm',
                 PATH='/usr/local/bin:/usr/bin:/bin', SHELL='/bin/bash')
        e.update(env or {})
        os.execvpe('./aibox', ['./aibox'] + args, e)
    buf, log, ok, why = b'', b'', True, ''

    def pump(t):
        nonlocal buf, log
        if select.select([fd], [], [], t)[0]:
            try:
                d = os.read(fd, 4096)
            except OSError:
                return False
            if not d:
                return False
            buf += d
            log += d
        return True

    for pat, ans in steps:
        end = time.time() + timeout
        while not re.search(pat.encode(), ANSI.sub(b'', buf)):
            if time.time() > end or not pump(0.2):
                ok, why = False, f'等不到提示 /{pat}/'
                break
        if not ok:
            break
        buf = b''
        os.write(fd, (ans.replace('\n', '\r') + '\r').encode())
    end = time.time() + 5
    while time.time() < end and pump(0.3):
        pass
    for _ in range(20):
        w, st = os.waitpid(pid, os.WNOHANG)
        if w:
            break
        time.sleep(0.25)
    else:
        os.kill(pid, signal.SIGKILL)
        _, st = os.waitpid(pid, 0)
        ok, why = False, why or '进程没有结束（仍在等待输入）'
    text = ANSI.sub(b'', log).decode('utf-8', 'replace').replace('\r', '')
    errs = [l for l in text.splitlines() if ERR.search(l)]
    rc = os.waitstatus_to_exitcode(st)
    if errs:
        ok, why = False, '解释器错误: ' + errs[0]
    if ok and rc != 0:
        ok, why = False, f'返回码 {rc}'
    print(f"  {'✔' if ok else '✘'} {name}" + ('' if ok else f'：{why}'))
    if not ok:
        failed += 1
        print('\n'.join('      ' + l for l in text.splitlines()[-15:]))
    return text


def check(desc, cond):
    global failed
    if not cond:
        failed += 1
        print(f'  ✘ {desc}')


def conf(path):
    try:
        return open(f'{W}/repo/config/{path}', encoding='utf-8').read()
    except FileNotFoundError:
        return ''


setup()
BASH_V = os.popen("bash -c 'echo $BASH_VERSION'").read().strip()
print(f'交互式流程（bash {BASH_V}）')
VL = 'vless://uuid@5.6.7.8:443?type=tcp#日本01'
TJ = 'trojan://pw@tj.example.com:443?sni=tj.example.com#美国01'

t = drive('init：粘贴无法识别的内容 → 重新粘贴两条分享链接 → 筛选 → 按编号/路径/拖入授权目录', ['init'], [
    (r'请选择 \[1\]: ', '1'),
    (r'（空行）结束：', 'hello-world\n'),
    (r'重新输入？.*\[Y/n\]: ', ''),
    (r'（空行）结束：', f'{VL}\n{TJ}\n'),
    (r'节点关键词.*: ', '德国'), (r'没有节点名包含「德国」[\s\S]*节点关键词.*: ', '日本|美国'),
    (r'1\) ~/code/app\s+2\) ~/projects/site[\s\S]*编号或路径.*: ', '1 2'),
    (r'允许 AI 修改 ~/code/app .*\[Y/n\]: ', ''), (r'允许 AI 修改 ~/projects/site .*\[Y/n\]: ', 'n'),
    (r'继续添加.*: ', f"'{W}/home/docs'"), (r'允许 AI 修改 ~/docs .*: ', 'n'),
    (r'继续添加.*: ', '~'),
    (r'不能|拒绝[\s\S]*继续添加.*: ', W + '/home/My\\ Dir '), (r'允许 AI 修改 ~/My Dir .*: ', 'y'),
    (r'继续添加.*: ', ''),
    (r'安装 aibox 命令.*\[Y/n\]: ', 'n'),
])
check('第一次配置不显示“保持当前出口不变”', '保持当前出口不变' not in t)
check('摘要显示出口和项目权限', '代理：分享链接 2 条，只用名称含「日本|美国」的节点' in t and '~/code/app（可修改）→ 容器里 /workspace/app' in t)
check('init 写入 2 条分享链接', conf('mihomo/links.txt').count('://') == 2)
check('init 写入节点筛选', 'AIBOX_NODE_FILTER=日本|美国' in conf('aibox.env'))
m = conf('mounts.conf')
check('init 授权 4 个目录（~ 被拒绝）', m.count('\nrw') + m.count('\nro') == 4)
check('init 授权的读写权限正确', 'rw  ~/code/app' in m and 'ro  ~/projects/site' in m and 'ro  ~/docs' in m and 'rw  ~/My Dir' in m)
check('init 不再询问工具、端口、时区、镜像源', 'AIBOX_TOOLS' not in conf('aibox.env') and 'AIBOX_APT_MIRROR' not in conf('aibox.env'))

drive('config：全部回车使用默认值', ['config'], [
    (r'请选择 \[5\]: ', ''), (r'保留以上授权？ \[Y/n\]: ', ''), (r'继续添加.*: ', 'n'),
    (r'安装 aibox 命令.*: ', 'n'),
])
check('默认值不改变分享链接', conf('mihomo/links.txt').count('://') == 2)

drive('config network：粘贴 Clash YAML（本机节点被拒 → 重新粘贴）', ['config', 'network'], [
    (r'请选择 \[5\]: ', '2'),
    (r'单独一行 END 回车：', '  - { name: 本机, type: socks5, server: 127.0.0.1, port: 7890 }\nEND'),
    (r'重新粘贴？.*\[Y/n\]: ', 'y'),
    (r'单独一行 END 回车：', 'proxies:\n  - { name: 东京01, type: ss, server: 9.9.9.9, port: 8388, cipher: aes-256-gcm, password: x }\nEND'),
    (r'节点关键词.*: ', ''),
])
check('粘贴 YAML 后删除旧的分享链接', conf('mihomo/links.txt') == '')

drive('config network：WireGuard 文件（先给错误路径）', ['config', 'network'], [
    (r'请选择 \[\d\]: ', '3'), (r'WireGuard 配置文件.*: ', W + '/nope.conf'), (r'WireGuard 配置文件.*: ', f"'{W}/wg.conf'"),
])
check('WireGuard 切换到 gluetun', 'AIBOX_GATEWAY=gluetun' in conf('aibox.env'))

drive('config network：商业 VPN（WireGuard，私钥隐藏输入）', ['config', 'network'], [
    (r'请选择 \[\d\]: ', '4'), (r'服务商.*: ', 'Mullvad'), (r'请选择 \[1\]: ', ''),
    (r'私钥 PrivateKey.*: ', 'secret-key'), (r'地址 Address.*: ', '10.64.0.1/32'), (r'出口国家.*: ', 'Japan'),
])
check('服务商名称自动转小写', 'VPN_SERVICE_PROVIDER=mullvad' in conf('gluetun.env'))
drive('config network：商业 VPN（OpenVPN）', ['config', 'network'], [
    (r'请选择 \[\d\]: ', '4'), (r'服务商.*: ', 'protonvpn'), (r'请选择 \[1\]: ', '2'),
    (r'OpenVPN 用户名.*: ', 'user'), (r'OpenVPN 密码.*: ', 'pass'), (r'出口国家.*: ', ''),
])
check('OpenVPN 写入 gluetun.env', 'OPENVPN_USER=user' in conf('gluetun.env'))

drive('config mounts：清空后重新添加', ['config', 'mounts'], [
    (r'保留以上授权？ \[Y/n\]: ', 'n'), (r'编号或路径.*: ', '~/code/app'), (r'允许 AI 修改.*: ', 'n'), (r'继续添加.*: ', ''),
])
drive('config key：终端里隐藏输入', ['config', 'key', 'OPENAI_API_KEY'], [(r'OPENAI_API_KEY（输入不显示）: ', 'sk-openai')])
check('隐藏输入的密钥已保存', 'OPENAI_API_KEY=sk-openai' in conf('workspace.env'))

# install：PATH 里没有可写目录（模拟 Apple Silicon Mac 上 /usr/local/bin 不存在），zsh
drive('install：zsh，装到 ~/.local/bin 并加入 PATH、添加补全', ['install'], [
    (r'不在 PATH 中，添加到 .*\.zshrc？ \[Y/n\]: ', ''), (r'添加 Tab 补全到 .*\.zshrc？ \[Y/n\]: ', ''),
], env=dict(SHELL='/bin/zsh', PATH='/usr/bin:/bin'))
zshrc = open(W + '/home/.zshrc', encoding='utf-8').read() if os.path.exists(W + '/home/.zshrc') else ''
check('.zshrc 加入 PATH 和补全', '.local/bin' in zshrc and 'aibox completion zsh' in zshrc)
rc = os.system(f"HOME={W}/home zsh -f -c 'source ~/.zshrc && whence -w _aibox' >/dev/null 2>&1")
check('没有初始化补全系统的 zsh 也能加载补全', rc == 0)

print(f'  失败 {failed} 项')
sys.exit(1 if failed else 0)
