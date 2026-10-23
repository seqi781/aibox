#!/bin/sh
# 校验 mihomo 上游配置（宿主机 CLI 与网关容器共用，POSIX sh）
# 严格出口策略：必须提供真实的代理节点或订阅；禁止把本机/宿主机/局域网上的代理
# （如 Mac 上的 Clash）当作上游，因为其出口由宿主机规则决定，可能走直连。
#   用法: validate-upstream.sh <upstream.yaml>
#         validate-upstream.sh --server <主机名或IP>   只检查一个服务器地址（WireGuard Endpoint 等）
#         validate-upstream.sh --links <文件>         严格检查分享链接（vmess:// vless:// ss:// ...）
#         validate-upstream.sh --normalize <文件>     输出分享链接（自动解码整段 Base64）
#         validate-upstream.sh --content <文件>       概括订阅内容（格式、节点数、类型、名称、本地条目数）
set -f   # 链接里可能有 * ? 等字符，关闭通配符展开
err() { echo "upstream 配置错误: $*" >&2; exit 1; }

is_local_server() {  # 本机/宿主机/局域网/保留地址 → 返回 0
  case "$(printf '%s' "$1" | tr 'A-Z' 'a-z')" in
    localhost|*.localhost|*.local|*.internal|*.orb.local|host.docker.internal|gateway.docker.internal|\
    0.*|10.*|127.*|169.254.*|192.168.*|172.1[6-9].*|172.2[0-9].*|172.3[0-1].*|\
    100.6[4-9].*|100.[7-9][0-9].*|100.1[0-1][0-9].*|100.12[0-7].*|198.1[89].*|::1|fe80:*|fc*:*|fd*:*) return 0 ;;
  esac
  return 1
}

LINK_SCHEMES="vmess vless ss ssr trojan hysteria hysteria2 hy2 tuic anytls socks socks5 socks5h"

b64d() {  # 解码 Base64（兼容 URL 安全字符和缺失的 =；macOS / GNU / busybox / openssl）
  b_s="$(printf '%s' "$1" | tr -d '\r\n ' | tr '_-' '/+')"
  case $(( ${#b_s} % 4 )) in 2) b_s="${b_s}==" ;; 3) b_s="${b_s}=" ;; esac
  for b_c in "base64 -D" "base64 -d" "openssl base64 -d -A"; do
    b_o="$(printf '%s' "$b_s" | $b_c 2>/dev/null)" && [ -n "$b_o" ] && { printf '%s' "$b_o"; return 0; }
  done
  return 1
}

is_link() {  # 是否为支持的分享链接
  case "$1" in *://*) ;; *) return 1 ;; esac
  case " $LINK_SCHEMES " in *" $(printf '%s' "${1%%://*}" | tr 'A-Z' 'a-z') "*) return 0 ;; esac
  return 1
}

link_host() {  # 从分享链接中取出服务器地址
  l_scheme="$(printf '%s' "${1%%://*}" | tr 'A-Z' 'a-z')"; l_rest="${1#*://}"; l_rest="${l_rest%%#*}"; l_x=""
  case "$l_scheme" in
    vmess)  # vmess://Base64(JSON)；也兼容 vmess://uuid@host:port 写法
      if l_dec="$(b64d "${l_rest%%\?*}")" && printf '%s' "$l_dec" | grep -q '"add"'; then
        printf '%s' "$l_dec" | tr -d '\n' | sed -n 's/.*"add"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p'; return 0
      fi ;;
    ssr)    # ssr://Base64(host:port:protocol:method:obfs:...)
      l_dec="$(b64d "$l_rest")" || return 1; printf '%s' "${l_dec%%:*}"; return 0 ;;
    ss)     # ss://Base64(method:pass)@host:port 或 ss://Base64(method:pass@host:port)
      l_x="${l_rest%%\?*}"; l_x="${l_x%/}"
      case "$l_x" in *@*) ;; *) l_x="$(b64d "$l_x")" || return 1 ;; esac ;;
  esac
  [ -n "$l_x" ] || l_x="${l_rest%%\?*}"
  l_hp="${l_x##*@}"; l_hp="${l_hp%%/*}"
  case "$l_hp" in \[*) l_h="${l_hp#\[}"; l_h="${l_h%%\]*}" ;; *:*) l_h="${l_hp%:*}" ;; *) l_h="$l_hp" ;; esac
  printf '%s' "$l_h"
}

link_name() {  # 节点名称（未做 URL 解码）
  case "$1" in
    vmess://*) b64d "$(printf '%s' "${1#vmess://}" | sed 's/[?#].*//')" 2>/dev/null | tr -d '\n' \
                 | sed -n 's/.*"ps"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' ;;
    *'#'*) printf '%s' "${1##*#}" ;;
  esac
}

normalize() {  # 文件 → 每行一个分享链接；整段 Base64 自动解码
  n_raw="$(tr -d '\r' < "$1")"
  if ! printf '%s\n' "$n_raw" | grep -q '://'; then
    n_dec="$(b64d "$n_raw")" && printf '%s\n' "$n_dec" | grep -q '://' && n_raw="$n_dec"
  fi
  printf '%s\n' "$n_raw" | tr -d '\r' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' | grep -vE '^(#|$)' || true
}

if [ "${1:-}" = "--host" ]; then link_host "${2:-}"; echo; exit 0; fi   # 调试用：输出分享链接的服务器地址
if [ "${1:-}" = "--normalize" ]; then normalize "${2:-/dev/null}"; exit 0; fi

if [ "${1:-}" = "--links" ]; then
  [ -s "${2:-}" ] || err "缺少分享链接文件"
  n_ok=0
  for l in $(normalize "$2"); do
    is_link "$l" || err "无法识别的分享链接: $(printf '%s' "$l" | cut -c1-40)…（支持: ${LINK_SCHEMES}）"
    h="$(link_host "$l")"
    [ -n "$h" ] || err "分享链接中找不到服务器地址: $(printf '%s' "$l" | cut -c1-40)…"
    if is_local_server "$h"; then
      echo "upstream 配置错误: 分享链接的服务器 $h 是本机/宿主机/局域网地址。" >&2
      echo "  不允许把本地代理软件（如 v2rayN、Clash）作为上游，请使用远程节点或订阅链接。" >&2
      exit 1
    fi
    n_ok=$((n_ok + 1))
  done
  [ "$n_ok" -gt 0 ] || err "没有分享链接"
  exit 0
fi

if [ "${1:-}" = "--content" ]; then
  # 输出 KEY=VALUE：format total local types names；无可用节点时返回 1
  c_f="${2:-}"; [ -s "$c_f" ] || { echo "format=empty"; exit 1; }
  c_total=0; c_local=0; c_types=""; c_names=""
  if grep -qE '^proxies:' "$c_f"; then
    echo "format=clash"
    c_body="$(sed -n '/^proxies:/,/^[A-Za-z]/p' "$c_f")"
    c_total="$(printf '%s\n' "$c_body" | grep -cE '^[[:space:]]*-[[:space:]]*(\{[[:space:]]*)?name:' || true)"
    c_local="$(printf '%s\n' "$c_body" | grep -oE '(^|[[:space:],{])server:[[:space:]]*["'"'"']?[^"'"'"',}[:space:]]+' \
      | sed -E 's/.*server:[[:space:]]*["'"'"']?//' | while IFS= read -r s; do is_local_server "$s" && echo x; done | grep -c x || true)"
    c_types="$(printf '%s\n' "$c_body" | grep -oE '(^|[[:space:],{])type:[[:space:]]*[A-Za-z0-9-]+' | sed -E 's/.*type:[[:space:]]*//' | sort | uniq -c | awk '{printf "%s:%s ", $2, $1}')"
    c_names="$(printf '%s\n' "$c_body" | grep -oE '(-|\{)[[:space:]]*(\{[[:space:]]*)?name:[[:space:]]*("[^"]*"|'"'"'[^'"'"']*'"'"'|[^,}]*)' \
      | sed -E 's/.*name:[[:space:]]*//; s/^["'"'"']//; s/["'"'"']$//' | head -500 | tr '\n' '\t')"
  else
    c_links="$(normalize "$c_f")"
    if printf '%s' "$(tr -d '\r' < "$c_f")" | grep -q '://'; then echo "format=links"; else echo "format=base64"; fi
    for l in $c_links; do
      is_link "$l" || continue
      c_total=$((c_total + 1))
      h="$(link_host "$l")"; if [ -z "$h" ] || is_local_server "$h"; then c_local=$((c_local + 1)); fi
      c_types="$c_types $(printf '%s' "${l%%://*}" | tr 'A-Z' 'a-z')"
      [ "$c_total" -le 500 ] && c_names="$c_names$(link_name "$l")	"
    done
    c_types="$(printf '%s\n' $c_types | grep . | sort | uniq -c | awk '{printf "%s:%s ", $2, $1}')"
  fi
  echo "total=$c_total"; echo "local=$c_local"; echo "types=$c_types"; echo "names=$c_names"
  [ "$c_total" -gt "$c_local" ] || exit 1
  exit 0
fi

if [ "${1:-}" = "--server" ]; then
  if is_local_server "${2:-}"; then
    echo "出口配置错误: 服务器 ${2:-} 是本机/宿主机/局域网地址，严格出口策略只允许远程服务器" >&2; exit 1
  fi
  exit 0
fi

f="${1:-}"

[ -n "$f" ] && [ -s "$f" ] || err "缺少 config/mihomo/upstream.yaml（必须填写代理节点 proxies: 或订阅 proxy-providers:）"
grep -qE '^(proxies|proxy-providers):' "$f" || \
  err "upstream.yaml 中没有 proxies: 或 proxy-providers:，必须填写代理节点或订阅后才能使用"

bad="$(grep -E '^[A-Za-z][A-Za-z0-9_-]*:' "$f" | grep -vE '^(proxies|proxy-providers):' | tr '\n' ' ')"
[ -z "$bad" ] || err "只能包含 proxies: / proxy-providers: 两个顶层键（不要粘贴完整 Clash 配置），发现: $bad"

dup="$(grep -oE '^(proxies|proxy-providers):' "$f" | sort | uniq -d | tr '\n' ' ')"
[ -z "$dup" ] || err "顶层键重复: ${dup}（所有节点请写在同一个 proxies: 下）"

# 去掉注释后再检查
body="$(sed 's/[[:space:]]#.*$//; /^[[:space:]]*#/d' "$f")"

if printf '%s\n' "$body" | grep -iqE '(^|[[:space:],{])type:[[:space:]]*["'"'"']?direct([[:space:],}"'"'"']|$)'; then
  err "不允许 type: direct 的节点（会绕过代理直连）"
fi

printf '%s\n' "$body" | grep -oE '(^|[[:space:],{])server:[[:space:]]*["'"'"']?[^"'"'"',}[:space:]]+' \
  | sed -E 's/.*server:[[:space:]]*["'"'"']?//' | while IFS= read -r s; do
  if is_local_server "$s"; then
      echo "upstream 配置错误: 节点 server: $s 指向本机/宿主机/局域网地址。" >&2
      echo "  不允许把本地代理软件（如 Mac 上的 Clash）作为上游，请直接填写该软件所用的远程节点或订阅链接。" >&2
      exit 1
  fi
done || exit 1
exit 0
