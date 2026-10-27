#!/usr/bin/env bash
# 工作镜像隐私与兼容性实测。先构建测试镜像：
# docker build --build-arg USER_UID=1000 --build-arg USER_GID=1000 -t aibox/workspace:privacy-check images/workspace
# bash tests/workspace-privacy.sh [镜像名]
# 使用自己的无网络容器和临时 home，不使用现有工作环境或真实项目。
set -euo pipefail
cd "$(dirname "$0")/.."
image="${1:-aibox/workspace:privacy-check}"
test_name="aibox-privacy-check-$$"
test_home="${test_name}-home"
test_home_other="${test_name}-other"
cleanup() {
  docker rm -f "$test_name" >/dev/null 2>&1 || true
  docker volume rm "$test_home" "$test_home_other" >/dev/null 2>&1 || true
}
trap cleanup EXIT
trap 'exit 130' INT TERM
docker volume create "$test_home" >/dev/null
docker volume create "$test_home_other" >/dev/null
start() {
  docker run -d --name "$test_name" --network none \
    --cap-drop NET_ADMIN --cap-drop NET_RAW --cap-drop SYS_ADMIN --cap-drop SYS_MODULE \
    --tmpfs /sys:ro,nosuid,nodev,noexec,size=65536 \
    -v "$1:/home/dev" "$image" >/dev/null
  local i=0
  until docker exec "$test_name" test -s /etc/machine-id >/dev/null 2>&1; do
    i=$((i + 1)); [ "$i" -lt 20 ] || { echo "机器标识初始化失败" >&2; docker logs "$test_name"; exit 1; }
    sleep 0.2
  done
}
start "$test_home"
docker exec "$test_name" bash -ec '
  test ! -e /sys/devices
  test ! -r /sys/devices/virtual/dmi/id/product_uuid
  test ! -r /sys/class/dmi/id/product_uuid
  test ! -r /proc/1/root/sys/devices/virtual/dmi/id/product_uuid
  ! sudo touch /sys/aibox-write-test 2>/dev/null
  ! sudo mount -t sysfs sysfs /sys 2>/dev/null
  grep -qxE "[0-9a-f]{32}" /etc/machine-id
  cmp -s /etc/machine-id /var/lib/dbus/machine-id
  cmp -s /etc/machine-id "$HOME/.config/aibox/machine-id"
  test "$(stat -c %a "$HOME/.config/aibox/machine-id")" = 600
  node -e '\''const os = require("os"); if (!os.cpus().length || !os.availableParallelism()) process.exit(1); require("crypto").randomBytes(32);'\''
  python3 -c "import multiprocessing, secrets, socket; assert multiprocessing.cpu_count() > 0; secrets.token_bytes(32)"
  git --version >/dev/null
  tmux -V >/dev/null
  mkdir -p /tmp/privacy-check
  printf "int main(void) { return 0; }\n" > /tmp/privacy-check/test.c
  cc /tmp/privacy-check/test.c -o /tmp/privacy-check/test
  /tmp/privacy-check/test
'
echo "  ✔ 硬件目录遮挡，sudo 不能重新挂载 sysfs（未隐藏开机标识）"
echo "  ✔ Node、Python、Git、tmux、C 编译与随机数功能"
(
  set -- help
  . ./aibox >/dev/null
  WS="$test_name"
  cmd_compare --offline --json
) | python3 -c '
import json, sys
data = json.load(sys.stdin)
rows = {item["id"]: item for item in data["rows"]}
assert data["workspace_running"] and data["workspace_probe_ok"]
assert rows["hardware_ids"]["result"] == "improved"
assert rows["permissions"]["result"] == "improved"
assert rows["boot_id"]["result"] in ("warning", "unknown")
print("  ✔ compare 根据新容器的真实配置与读取结果判定，未宣称开机标识已隐藏")
'
first="$(docker exec "$test_name" cat /etc/machine-id)"
docker rm -f "$test_name" >/dev/null
start "$test_home"
second="$(docker exec "$test_name" cat /etc/machine-id)"
[ "$first" = "$second" ]
echo "  ✔ 重建容器后，同一 home 的机器标识不变"
docker rm -f "$test_name" >/dev/null
start "$test_home_other"
third="$(docker exec "$test_name" cat /etc/machine-id)"
[ "$first" != "$third" ]
echo "  ✔ 不同 home 的机器标识独立（具体值未输出）"
