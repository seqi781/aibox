#!/bin/sh
# 健康 = TUN 存在 + PROXY 组里有真实节点 + 经代理能访问测试地址
# （root 进程无 routing-mark，必然走 TUN → 代理）
ip link show "${TUN_DEVICE:-aibox0}" >/dev/null 2>&1 || exit 1
now="$(curl -fsS --max-time 3 --unix-socket /run/aibox/mihomo.sock http://mihomo/proxies/PROXY 2>/dev/null \
  | sed -n 's/.*"now":"\([^"]*\)".*/\1/p')"
case "$now" in ''|REJECT|REJECT-DROP|DIRECT|COMPATIBLE|PASS)
  echo "PROXY 组没有可用节点（now=${now:-?}）"; exit 1 ;; esac
exec curl -fsS -o /dev/null --max-time 10 "${TEST_URL:-https://www.gstatic.com/generate_204}"
