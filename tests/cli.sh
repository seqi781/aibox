#!/usr/bin/env bash
# 非交互命令测试：在测试镜像中运行（由 tests/run.sh 调用），不需要 Docker 守护进程和网络
#   docker run --rm -v "$PWD":/src:ro aibox-test:bash3.2 bash /src/tests/cli.sh
# 每条命令检查返回码，并检查输出中是否出现解释器错误（unbound variable / syntax error 等）
set -u
W=/tmp/aibox-cli; rm -rf "$W"; mkdir -p "$W/home/code/app" "$W/home/docs" "$W/home/.ssh"
cp -r /src "$W/repo"; rm -rf "$W/repo/config" "$W/repo/.aibox"
cd "$W/repo"
export HOME="$W/home"
V=images/mihomo-gateway/validate-upstream.sh
echo "非交互命令（bash $BASH_VERSION）"

n=0; bad=0
run() {  # run 期望返回码(0|1) 命令...
  local want="$1" out rc; shift; n=$((n + 1))
  out="$("$@" 2>&1 </dev/null)"; rc=$?
  if printf '%s' "$out" | grep -qiE 'unbound variable|syntax error|bad substitution|command not found|not a valid identifier|invalid option|line [0-9]+:'; then
    bad=$((bad + 1)); echo "  ✘ [$*] 解释器错误:"; printf '%s\n' "$out" | sed 's/^/      /' | head -5
  elif { [ "$want" = 0 ] && [ "$rc" -ne 0 ]; } || { [ "$want" = 1 ] && [ "$rc" -eq 0 ]; }; then
    bad=$((bad + 1)); echo "  ✘ [$*] 返回码 $rc（期望 $want）:"; printf '%s\n' "$out" | sed 's/^/      /' | head -3
  fi
}
expect() {  # expect 描述 条件命令...
  n=$((n + 1)); if "${@:2}"; then :; else bad=$((bad + 1)); echo "  ✘ $1"; fi
}

# ---------- 运行环境检查 ----------
run 1 sh ./aibox help
run 1 zsh ./aibox help
run 0 bash ./aibox help

# ---------- 基本 ----------
run 0 ./aibox help
run 0 ./aibox
run 0 ./aibox help --all
expect "aibox 只列出给人用的命令" sh -c './aibox | grep -q "aibox tmux" && ! ./aibox | grep -qE "import|report|mounts"'
expect "help --all 列出全部命令" sh -c './aibox help --all | grep -q "import" && ./aibox help --all | grep -q "report"'
run 1 ./aibox no-such-cmd
run 1 ./aibox c
run 1 ./aibox tmux --bad
run 0 ./aibox init --defaults
run 0 ./aibox init --defaults
run 0 ./aibox config help
run 0 ./aibox guide

# ---------- 出口：一键导入（--no-check 跳过联网预检） ----------
VM="vmess://$(printf '%s' '{"v":"2","ps":"香港01","add":"1.2.3.4","port":"443","id":"x","net":"tcp"}' | base64 | tr -d '\n')"
VL='vless://uuid@5.6.7.8:443?type=tcp#日本01'
SS="ss://$(printf '%s' 'aes-256-gcm:pw' | base64 | tr -d '\n=')@9.9.9.9:8388#%E6%96%B0%E5%8A%A0%E5%9D%A1"
TJ='trojan://pw@tj.example.com:443?sni=tj.example.com#美国01'
run 0 ./aibox import "$VL"
run 0 ./aibox import "$VM" "$TJ" --filter '香港|美国'
expect "导入后 links.txt 有 2 条" [ "$(grep -c '://' config/mihomo/links.txt)" = 2 ]
run 0 bash -c "printf '%s\n%s\n%s\n' '$VM' '$VL' '$SS' | ./aibox import -"
run 0 bash -c "printf '%s\n%s\n' '$VM' '$SS' | base64 | tr -d '\n' | ./aibox import -"
run 0 ./aibox import "https://sub.example.com/x?token=1" --no-check
run 0 ./aibox import "https://sub.example.com/x" "$VL" --no-check
expect "订阅 + 链接混合时 upstream 有 sub1 和 links" grep -q 'links:' config/mihomo/upstream.yaml
run 0 ./aibox import "clash://install-config?url=https%3A%2F%2Fsub.example.com%2Fa%3Fb%3D1&name=x" --no-check
expect "clash:// 链接解析出订阅地址" grep -q 'https://sub.example.com/a?b=1' config/mihomo/upstream.yaml
expect "只有订阅时删除旧的 links.txt" [ ! -f config/mihomo/links.txt ]
run 0 ./aibox import "sing-box://import-remote-profile?url=https%3A%2F%2Fsub.example.com%2Fsb#n" --no-check
cp config/mihomo/upstream.yaml "$W/up.before"
run 1 ./aibox import 'vless://u@192.168.1.10:443#内网'
run 1 ./aibox import 'socks://dTpw@127.0.0.1:10808#v2rayN本地'
run 1 ./aibox import 'http://127.0.0.1:25500/sub?target=clash' --no-check
run 1 ./aibox import 'hello-world'
run 1 ./aibox import 'ftp://x'
run 1 bash -c "printf '[Interface]\nPrivateKey=x\n' | ./aibox import -"
expect "导入失败时不改动原配置" cmp -s "$W/up.before" config/mihomo/upstream.yaml
run 1 ./aibox import --bogus

# ---------- 出口：其它写法 ----------
run 1 ./aibox config proxy
run 1 ./aibox config proxy --sub
run 0 ./aibox config proxy --filter 'JP|日本'
run 0 ./aibox config proxy --filter ''
run 0 ./aibox config proxy --group url-test
run 1 ./aibox config proxy --group bogus
printf 'proxies:\n  - { name: 东京, type: ss, server: 1.2.3.4, port: 1, cipher: aes-128-gcm, password: p }\n' > "$W/n.yaml"
run 0 ./aibox config proxy --nodes "$W/n.yaml"
run 1 ./aibox config proxy --nodes "$W/missing.yaml"
run 0 bash -c "printf 'proxies:\n  - { name: a, type: socks5, server: 5.6.7.8, port: 1 }\n' | ./aibox config proxy --nodes -"
run 1 bash -c "printf 'proxies:\n  - { name: a, type: socks5, server: 127.0.0.1, port: 7890 }\n' | ./aibox config proxy --nodes -"
run 1 bash -c "printf 'proxies:\n  - { name: a, type: socks5, server: 1.2.3.4, port: 1 }\nproxies:\n  - { name: b, type: socks5, server: 1.2.3.5, port: 1 }\n' | ./aibox config proxy --nodes -"

# ---------- 授权目录 ----------
run 0 ./aibox mounts
run 0 ./aibox mounts add rw ~/code/app
run 0 ./aibox mounts add ro ~/docs '->' 参考资料
run 1 ./aibox mounts add rw ~/code/app
run 1 ./aibox mounts add rw ~
run 1 ./aibox mounts add rw /
run 1 ./aibox mounts add rw ~/.ssh
run 1 ./aibox mounts add rw "$W/repo"
run 1 ./aibox mounts add rw "$W"
run 1 ./aibox mounts add xx ~/docs
run 0 ./aibox mounts list
run 0 ./aibox projects
expect "projects 输出两个项目" [ "$(./aibox projects | wc -l | tr -d ' ')" = 2 ]

# ---------- 工具 / 端口 / 密钥 / 其它键 ----------
run 1 ./aibox config tools claude
run 0 ./aibox import "$VL" --no-test
run 1 ./aibox test
run 1 ./aibox report
run 0 ./aibox config set AIBOX_TZ Asia/Tokyo
run 0 ./aibox config set AIBOX_LANG ja_JP.UTF-8
run 0 ./aibox config ports 3000,8080:80
run 1 ./aibox config ports abc
run 0 ./aibox config ports ''
run 0 bash -c "printf %s sk-test-123 | ./aibox config key ANTHROPIC_API_KEY"
expect "密钥文件权限为 600" [ "$(stat -c %a config/workspace.env)" = 600 ]
run 1 ./aibox config key ANTHROPIC_API_KEY sk-in-argv
run 1 ./aibox config key bad-name
run 0 ./aibox config key ANTHROPIC_API_KEY --unset
run 0 ./aibox config set AIBOX_TZ Asia/Shanghai
run 1 ./aibox config set AIBOX_ALLOW_BROAD_MOUNT 1
run 1 ./aibox config set AIBOX_UPSTREAM_PROXY x
run 1 ./aibox config set AIBOX_GATEWAY bogus
run 1 ./aibox config set FOO bar
run 0 ./aibox config get AIBOX_TZ
run 0 ./aibox config show
run 0 ./aibox config check

# ---------- VPN ----------
printf '[Interface]\nPrivateKey = k\nAddress = 10.0.0.2, fd00::2\n[Peer]\nPublicKey = p\nEndpoint = vpn.example.com:51820\nAllowedIPs = 0.0.0.0/0\n' > "$W/wg.conf"
run 0 ./aibox config vpn --wireguard "$W/wg.conf"
expect "WireGuard 地址补上掩码" grep -q 'Address = 10.0.0.2/32,fd00::2/128' config/gluetun/wireguard/wg0.conf
run 0 ./aibox config check
sed 's/vpn.example.com/192.168.1.1/' "$W/wg.conf" > "$W/wg-lan.conf"
run 1 ./aibox config vpn --wireguard "$W/wg-lan.conf"
run 1 ./aibox config vpn --wireguard "$W/missing.conf"
run 1 ./aibox config vpn --provider mullvad
run 0 env WIREGUARD_PRIVATE_KEY=k ./aibox config vpn --provider mullvad --countries Japan
run 1 ./aibox config vpn --provider mullvad --type openvpn
run 0 env OPENVPN_USER=u OPENVPN_PASSWORD=p ./aibox config vpn --provider protonvpn --type openvpn
run 0 ./aibox config set AIBOX_GATEWAY mihomo
run 0 ./aibox config check

# ---------- 清理 / 补全 / 需要终端的命令 ----------
run 0 ./aibox mounts rm 参考资料
run 1 ./aibox mounts rm nothing
run 0 ./aibox completion bash
run 0 ./aibox completion zsh
run 1 ./aibox completion fish
run 0 bash -c 'eval "$(./aibox completion bash)" && complete -p aibox'
run 0 zsh -f -c 'eval "$(./aibox completion zsh)" && whence -w _aibox'
run 1 ./aibox config
run 1 ./aibox config network
run 1 ./aibox config mounts

# ---------- install（非终端：不提问） ----------
run 0 env PATH="$HOME/.local/bin:/usr/bin:/bin" ./aibox install
expect "install 只创建 aibox 链接" test -L "$HOME/.local/bin/aibox" -a ! -e "$HOME/.local/bin/ai"
run 0 env PATH="/usr/bin:/bin" SHELL=/bin/zsh ./aibox install
expect "PATH 里没有可写目录时装到 ~/.local/bin" [ -L "$HOME/.local/bin/aibox" ]

echo "  共 $n 项，失败 $bad 项"
[ "$bad" = 0 ]
