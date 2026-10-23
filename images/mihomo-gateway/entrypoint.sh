#!/bin/sh
# aibox 代理网关入口
#   1. 先上防火墙（默认全部 DROP），再启动 mihomo —— 从第一秒起就是 fail-closed
#   2. 只有两类出站被放行：mihomo 自己带 routing-mark 的连接、进入 TUN 的流量
#   3. mihomo 崩溃时 TUN 消失，其余流量只剩物理网卡且无标记 → 全部被丢弃（断线阻断）
set -eu

MARK="${ROUTING_MARK:-6666}"
TUN="${TUN_DEVICE:-aibox0}"
CONF_DIR=/config
RUN_DIR=/run/aibox
DATA_DIR=/data
mkdir -p "$RUN_DIR" "$DATA_DIR"

log() { echo "[aibox-gateway] $*"; }
die() { echo "[aibox-gateway] 错误: $*" >&2; exit 1; }

# ---------- iptables 后端探测（nft 优先，回退 legacy） ----------
IPT=iptables; IP6T=ip6tables
if ! iptables -S >/dev/null 2>&1; then
  if iptables-legacy -S >/dev/null 2>&1; then IPT=iptables-legacy; IP6T=ip6tables-legacy
  else die "iptables 不可用（容器需要 NET_ADMIN 权限）"; fi
fi

DEV_IF="$(ip -4 route show default 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="dev"){print $(i+1); exit}}')"
[ -n "$DEV_IF" ] || die "找不到默认网卡"
DEV_NET="$(ip -4 route show dev "$DEV_IF" scope link 2>/dev/null | awk 'NR==1{print $1}')"
NON_PUBLIC_NETS="0.0.0.0/8 10.0.0.0/8 100.64.0.0/10 127.0.0.0/8 169.254.0.0/16 172.16.0.0/12 192.0.0.0/24 192.168.0.0/16 198.18.0.0/15 224.0.0.0/4 240.0.0.0/4"

host_from_hosts_file() {  # 只查 /etc/hosts（例如 host.docker.internal），绝不发 DNS
  awk -v h="$1" '$1 !~ /^#/ && $1 !~ /:/ {for(i=2;i<=NF;i++) if($i==h){print $1; exit}}' /etc/hosts
}
# 宿主机地址：Docker 网桥网关 + host.docker.internal（OrbStack/Docker Desktop/Colima 各不相同）
HOST_IPS="$(ip -4 route show default | awk '{print $3; exit}') $(host_from_hosts_file host.docker.internal)"

setup_firewall() {
  # 先把策略改成 DROP，再清空规则，避免出现放行窗口
  $IPT -P INPUT DROP; $IPT -P FORWARD DROP; $IPT -P OUTPUT DROP
  $IPT -F; $IPT -X 2>/dev/null || true

  # 禁止访问 Docker 内置 DNS(127.0.0.11)：它可能经宿主机转发查询，造成 DNS 泄漏
  $IPT -A OUTPUT -d 127.0.0.11 -j DROP
  $IPT -A INPUT  -i lo -j ACCEPT
  $IPT -A OUTPUT -o lo -j ACCEPT
  $IPT -A INPUT  -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
  $IPT -A OUTPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
  # 宿主机地址一律禁止新建连接（无论是否带标记、是否在允许直连网段内）
  for ip in $HOST_IPS; do $IPT -A OUTPUT -d "$ip" -j DROP; done
  # TUN 内部流量（由 mihomo 接管并转发到代理）
  $IPT -A INPUT  -i "$TUN" -j ACCEPT
  $IPT -A OUTPUT -o "$TUN" -j ACCEPT
  # 只有 mihomo 自身（带 routing-mark）能从物理网卡出站，连接上游代理服务器；
  # 且上游只能是公网地址：本机/宿主机/局域网上的代理（如 Mac 的 Clash）一律禁止，
  # 即使订阅里的域名解析到这些地址也连不上
  $IPT -N AIBOX_UPSTREAM
  for net in $NON_PUBLIC_NETS; do $IPT -A AIBOX_UPSTREAM -d "$net" -j DROP; done
  $IPT -A AIBOX_UPSTREAM -j ACCEPT
  $IPT -A OUTPUT -m mark --mark "$MARK" -j AIBOX_UPSTREAM

  # 可选：允许直连的网段（例如局域网服务），默认无
  for cidr in $(echo "${ALLOW_DIRECT_CIDRS:-}" | tr ',' ' '); do
    log "警告: 允许直连(不经代理) $cidr"
    $IPT -A OUTPUT -d "$cidr" -j ACCEPT
  done
  # 可选：入站端口（aibox 发布到宿主机 127.0.0.1 的开发端口）
  for p in $(echo "${INPUT_PORTS:-}" | tr ',' ' '); do
    $IPT -A INPUT -i "$DEV_IF" -p tcp --dport "$p" -j ACCEPT
  done

  # IPv6：全部阻断。即使 ip6tables 不可用，也必须确认 IPv6 已被 sysctl 关闭
  if $IP6T -P INPUT DROP 2>/dev/null; then
    $IP6T -P FORWARD DROP; $IP6T -P OUTPUT DROP
    $IP6T -F; $IP6T -X 2>/dev/null || true
    $IP6T -A INPUT -i lo -j ACCEPT; $IP6T -A OUTPUT -o lo -j ACCEPT
  elif [ "$(cat /proc/sys/net/ipv6/conf/all/disable_ipv6 2>/dev/null || echo 1)" != "1" ]; then
    die "ip6tables 不可用且 IPv6 未禁用，拒绝启动以防 IPv6 泄漏"
  fi
  log "防火墙已就绪 (后端=$IPT, 网卡=$DEV_IF, 子网=${DEV_NET:-?}, 已封禁宿主机: $(echo $HOST_IPS))"
}

# ---------- 上游配置 ----------

# 严格出口：只接受 upstream.yaml 中的远程节点/订阅（不支持把宿主机 Clash 等本地代理当上游）
build_upstream() {
  validate-upstream.sh "$CONF_DIR/upstream.yaml" || die "上游配置不合规，拒绝启动"
  cp "$CONF_DIR/upstream.yaml" "$RUN_DIR/upstream.yaml"
  if [ -f "$CONF_DIR/links.txt" ]; then
    validate-upstream.sh --links "$CONF_DIR/links.txt" || die "分享链接不合规，拒绝启动"
    validate-upstream.sh --normalize "$CONF_DIR/links.txt" > "$DATA_DIR/links.txt"
    log "上游: config/mihomo/upstream.yaml + links.txt（$(grep -c '://' "$DATA_DIR/links.txt") 条分享链接）"
  else
    rm -f "$DATA_DIR/links.txt"
    log "上游: config/mihomo/upstream.yaml"
  fi
}

quote_list() {  # "a, b" -> "a", "b"
  echo "$1" | tr ',' '\n' | sed 's/^ *//; s/ *$//' | grep -v '^$' | sed 's/.*/"&"/' | paste -sd, - | sed 's/,/, /g'
}

render() {  # 用 ENVIRON 替换 __KEY__，避免 sed 特殊字符问题
  awk 'BEGIN{n=split("LOG_LEVEL MARK TUN DNS PROXY_SERVER_DNS GROUP_TYPE TEST_URL FILTER_LINE",k," ")}
  { line=$0
    for(i=1;i<=n;i++){ key="__" k[i] "__"; v=ENVIRON["R_" k[i]]
      while((p=index(line,key))>0) line=substr(line,1,p-1) v substr(line,p+length(key)) }
    print line }' "$1"
}

build_config() {
  # 严格出口：应用的 DNS 查询必须经隧道（#PROXY），否则会从本地网络直接发出
  for ns in $(echo "${PROXY_DNS:-}" | tr ',' ' '); do
    case "$ns" in *'#PROXY') ;; *) die "AIBOX_PROXY_DNS 中的 $ns 没有 #PROXY 后缀，会绕过代理直连查询（DNS 泄漏），拒绝启动" ;; esac
  done
  export R_LOG_LEVEL="${LOG_LEVEL:-warning}" R_MARK="$MARK" R_TUN="$TUN"
  export R_DNS="$(quote_list "${PROXY_DNS:-https://1.1.1.1/dns-query#PROXY, https://8.8.8.8/dns-query#PROXY}")"
  export R_PROXY_SERVER_DNS="$(quote_list "${PROXY_SERVER_DNS:-https://223.5.5.5/dns-query, https://1.1.1.1/dns-query}")"
  export R_GROUP_TYPE="${GROUP_TYPE:-fallback}" R_TEST_URL="${TEST_URL:-https://www.gstatic.com/generate_204}"
  if [ -n "${NODE_FILTER:-}" ]; then
    export R_FILTER_LINE="    filter: '$(printf '%s' "$NODE_FILTER" | sed "s/'/''/g")'"
  else export R_FILTER_LINE=""; fi
  cfg="$RUN_DIR/config.yaml"
  render /etc/aibox/config-head.yaml > "$cfg"
  # 回包到 Docker 子网（宿主机端口转发）和允许直连的网段不进 TUN；iptables 仍禁止主动新建连接
  excl="$(quote_list "${DEV_NET:+$DEV_NET,}${ALLOW_DIRECT_CIDRS:-}")"
  if [ -n "$excl" ]; then
    sed -i "/^  strict-route: true/a\\  route-exclude-address: [$excl]" "$cfg"
  fi
  echo >> "$cfg"
  cat "$RUN_DIR/upstream.yaml" >> "$cfg"
  render /etc/aibox/config-tail.yaml >> "$cfg"
  mihomo -t -d "$DATA_DIR" -f "$cfg" >/dev/null 2>&1 || { mihomo -t -d "$DATA_DIR" -f "$cfg" || true; die "mihomo 配置校验失败"; }
}

setup_firewall
# DNS 指向 mihomo（127.0.0.1:53）；workspace 共享此网络命名空间与 resolv.conf
printf 'nameserver 127.0.0.1\noptions ndots:0 timeout:2 attempts:2\n' > /etc/resolv.conf
build_upstream
build_config

# ---------- 守护 mihomo：进程退出时不退出容器（保持网络命名空间与防火墙不变） ----------
child=""
stopping=0
on_term() { stopping=1; [ -n "$child" ] && kill "$child" 2>/dev/null; }
trap on_term TERM INT
log "启动 mihomo $(mihomo -v | head -1 | awk '{print $3}')"
while :; do
  if [ -f "$RUN_DIR/hold" ]; then sleep 1; continue; fi   # doctor 断线测试用
  mihomo -d "$DATA_DIR" -f "$RUN_DIR/config.yaml" &
  child=$!
  wait "$child" || true
  [ "$stopping" = 1 ] && exit 0
  log "mihomo 已退出，防火墙保持阻断，2 秒后重启"
  sleep 2
done
