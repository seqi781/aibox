#!/bin/sh
# 严格出口校验器测试（POSIX sh；宿主机和测试镜像里都能跑）
#   sh tests/validator.sh
cd "$(dirname "$0")/.." || exit 1
V=images/mihomo-gateway/validate-upstream.sh
T="${TMPDIR:-/tmp}/aibox-validator.$$"; mkdir -p "$T"; trap 'rm -rf "$T"' EXIT
n=0; bad=0
fail() { bad=$((bad + 1)); echo "  ✘ $*"; }
b64()  { printf '%s' "$1" | base64 | tr -d '\n'; }
b64u() { printf '%s' "$1" | base64 | tr -d '\n=' | tr '+/' '-_'; }
echo "严格出口校验器"

# ---------- upstream.yaml：应拒绝（f_）/ 应通过（p_） ----------
w() { printf '%b\n' "$2" > "$T/$1.yaml"; }
w f_empty      '# only comments'
w f_hostdocker 'proxies:\n  - { name: a, type: socks5, server: host.docker.internal, port: 7890 }'
w f_localhost  "proxies:\n  - { name: a, type: socks5, server: 'LocalHost', port: 7890 }"
w f_lan        'proxies:\n  - name: a\n    type: http\n    server: 192.168.1.5\n    port: 7890'
w f_docker172  'proxies:\n  - { name: a, type: ss, server: "172.20.0.1", port: 1, cipher: x, password: y }'
w f_cgnat      'proxies:\n  - { name: a, type: socks5, server: 100.101.1.2, port: 1 }'
w f_orb        'proxies:\n  - { name: a, type: socks5, server: host.orb.internal, port: 7890 }'
w f_v6ula      'proxies:\n  - { name: a, type: socks5, server: "fd00::1", port: 1 }'
w f_direct     'proxies:\n  - { name: a, type: direct }'
w f_rules      'proxies:\n  - { name: a, type: socks5, server: 1.2.3.4, port: 1 }\nrules:\n  - MATCH,DIRECT'
w f_mixed      'proxies:\n  - { name: ok, type: socks5, server: 1.2.3.4, port: 1 }\n  - { name: bad, type: socks5, server: 10.0.0.8, port: 1 }'
w f_dupkey     'proxies:\n  - { name: a, type: socks5, server: 1.2.3.4, port: 1 }\nproxies:\n  - { name: b, type: socks5, server: 1.2.3.5, port: 1 }'
w p_public     'proxies:\n  - { name: a, type: socks5, server: 203.0.113.10, port: 1080 }'
w p_domain_fd  'proxies:\n  - { name: a, type: trojan, server: fdn.example.com, port: 443, password: x, sni: 192.168.1.1 }'
w p_provider   'proxy-providers:\n  sub:\n    type: http\n    url: "https://example.com/sub?x=1"\n    path: ./p.yaml'
w p_comment    '# server: 127.0.0.1\nproxies:\n  - { name: a, type: ss, server: 8.8.8.8, port: 1, cipher: x, password: y }  # 旧: 10.0.0.1'
for f in "$T"/*.yaml; do
  n=$((n + 1)); name="$(basename "$f" .yaml)"
  sh "$V" "$f" >/dev/null 2>&1; rc=$?
  case "$name" in
    f_*) [ "$rc" -ne 0 ] || fail "应拒绝却通过: $name" ;;
    p_*) [ "$rc" -eq 0 ] || fail "应通过却拒绝: $name" ;;
  esac
done

# ---------- 分享链接：解析服务器地址 ----------
while IFS='|' read -r want link; do
  n=$((n + 1)); got="$(sh "$V" --host "$link")"
  [ "$got" = "$want" ] || fail "地址解析: 期望 $want，得到 '$got'  ($(printf '%s' "$link" | cut -c1-60))"
done <<EOF
1.2.3.4|vmess://$(b64 '{"v":"2","ps":"a","add":"1.2.3.4","port":"443","id":"x"}')
vm.example.com|vmess://$(b64u '{"add": "vm.example.com", "port": 443}')#x
host.example|vmess://uuid@host.example:443?type=ws#new-style
5.6.7.8|vless://uuid@5.6.7.8:443?security=reality&sni=a.com&pbk=x#名字
2001:db8::1|vless://uuid@[2001:db8::1]:443?type=tcp#v6
ss.example.com|ss://$(b64u 'aes-256-gcm:pass')@ss.example.com:8388#sip002
9.9.9.9|ss://$(b64 'chacha20-ietf-poly1305:p@ss')@9.9.9.9:8388/?plugin=obfs-local%3Bobfs%3Dhttp#plugin
8.8.4.4|ss://$(b64 'aes-128-gcm:pw@8.8.4.4:443')#legacy
2022.example|ss://2022-blake3-aes-128-gcm:cGFzcw==@2022.example:443#ss2022
ssr.example.net|ssr://$(b64u 'ssr.example.net:443:auth_aes128_md5:aes-256-cfb:tls1.2_ticket_auth:cGFzcw/?remarks=eA')
hy.example|hysteria2://auth@hy.example:443/?sni=hy.example&insecure=1#hy2
hy.example|hy2://hy.example:443?obfs=salamander#noauth
tuic.example|tuic://uuid:pw@tuic.example:443?congestion_control=bbr#tuic
3.3.3.3|trojan://p%40ss@3.3.3.3:443?sni=x#t
any.example|anytls://pw@any.example:443/?sni=any.example#a
127.0.0.1|socks://$(b64 'u:p')@127.0.0.1:7890#本机
localhost|socks5://localhost:1080
EOF

# ---------- 分享链接：严格检查 ----------
lk() { printf '%s\n' "$@" > "$T/links.txt"; sh "$V" --links "$T/links.txt" >/dev/null 2>&1; }
n=$((n + 1)); lk 'vless://u@5.6.7.8:443#a' 'trojan://p@t.example:443#b' || fail "合规链接被拒绝"
n=$((n + 1)); lk 'vless://u@5.6.7.8:443#a' 'vless://u@10.0.0.1:443#lan' && fail "含内网链接却通过"
n=$((n + 1)); lk 'socks://dTpw@127.0.0.1:10808#v2rayN' && fail "本机 socks 端口却通过"
n=$((n + 1)); lk 'ftp://x.example/a' && fail "不支持的协议却通过"
n=$((n + 1)); printf '%s\n' "$(b64 "$(printf 'vless://u@5.6.7.8:443#a\nss://YWVzLTI1Ni1nY206cHc@9.9.9.9:1#b')")" > "$T/b64.txt"
sh "$V" --links "$T/b64.txt" >/dev/null 2>&1 || fail "整段 Base64 的链接被拒绝"

# ---------- 订阅内容概括 ----------
ct() { sh "$V" --content "$1" 2>/dev/null; }
printf '%s\n' "$(b64 "$(printf 'vless://u@5.6.7.8:443#%%E6%%97%%A5%%E6%%9C%%AC\nss://YWVzLTI1Ni1nY206cHc@127.0.0.1:1#剩余流量\ntrojan://p@t.example:443#美国')")" > "$T/sub.txt"
out="$(ct "$T/sub.txt")"; n=$((n + 1))
printf '%s\n' "$out" | grep -qx 'format=base64' && printf '%s\n' "$out" | grep -qx 'total=3' && printf '%s\n' "$out" | grep -qx 'local=1' \
  || fail "Base64 订阅概括不对: $(printf '%s' "$out" | tr '\n' ' ')"
printf 'proxies:\n  - { name: "香港 01", type: vmess, server: hk.example, port: 443 }\n  - name: 日本\n    type: trojan\n    server: jp.example\nrules:\n  - MATCH,DIRECT\n' > "$T/clash.yaml"
out="$(ct "$T/clash.yaml")"; n=$((n + 1))
printf '%s\n' "$out" | grep -qx 'format=clash' && printf '%s\n' "$out" | grep -qx 'total=2' && printf '%s\n' "$out" | grep -q '香港 01' \
  || fail "Clash 订阅概括不对: $(printf '%s' "$out" | tr '\n' ' ')"
printf 'proxies:\n  - { name: x, type: ss, server: 127.0.0.1, port: 1 }\n' > "$T/alllocal.yaml"
n=$((n + 1)); ct "$T/alllocal.yaml" >/dev/null && fail "全部节点指向本机却通过"
printf 'hello\n' > "$T/junk.txt"
n=$((n + 1)); ct "$T/junk.txt" >/dev/null && fail "无法识别的内容却通过"

# ---------- --server ----------
for h in 10.1.1.1 192.168.0.1 127.0.0.1 localhost host.docker.internal fd12::1; do
  n=$((n + 1)); sh "$V" --server "$h" 2>/dev/null && fail "--server $h 应拒绝"
done
for h in 8.8.8.8 vpn.example.com 2001:db8::1; do
  n=$((n + 1)); sh "$V" --server "$h" 2>/dev/null || fail "--server $h 应通过"
done

echo "  共 $n 项，失败 $bad 项"
[ "$bad" = 0 ]
