#!/usr/bin/env bash
# aibox 兼容性测试入口
#   tests/run.sh                 静态检查 + 校验器 + 在 bash 3.2 / 4.4 / 5.2 下跑命令和交互流程（需要 Docker）
#   tests/run.sh --quick         只跑静态检查和校验器（不需要 Docker，几秒钟）
#   tests/run.sh --bash "3.2"    只测指定的 bash 版本
# 不包含 aibox up / doctor 的端到端测试（需要真实节点）；修改网关或防火墙后请另外运行 ./aibox doctor --full
set -u
cd "$(dirname "$0")/.."
VERSIONS="3.2 4.4 5.2"; QUICK=0
while [ $# -gt 0 ]; do
  case "$1" in
    --quick) QUICK=1 ;;
    --bash) VERSIONS="${2:?--bash 需要版本号，如 \"3.2 5.2\"}"; shift ;;
    -h|--help) sed -n '2,7p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "未知参数: $1" >&2; exit 2 ;;
  esac; shift
done

results=""; fail=0
step() {  # step 名称 命令...
  local name="$1"; shift
  if "$@"; then results="$results  ✔ $name
"; else results="$results  ✘ $name
"; fail=1; fi
  echo
}

step "静态检查" bash tests/lint.sh
step "严格出口校验器" sh tests/validator.sh

if [ "$QUICK" = 0 ]; then
  docker info >/dev/null 2>&1 || { echo "Docker 不可用：用 --quick 只跑静态检查，或先启动 Docker" >&2; exit 2; }
  for v in $VERSIONS; do
    img="aibox-test:bash$v"
    echo "== 构建测试镜像 $img"
    docker build -q --build-arg BASH_TAG="$v" -t "$img" tests/ >/dev/null || { results="$results  ✘ 构建 $img
"; fail=1; continue; }
    step "bash $v：非交互命令" docker run --rm -v "$PWD":/src:ro "$img" bash /src/tests/cli.sh
    step "bash $v：交互式流程" docker run --rm -v "$PWD":/src:ro "$img" python3 /src/tests/interactive.py
  done
fi

echo "== 结果"; printf '%s' "$results"
[ "$fail" = 0 ] && echo "全部通过" || echo "有失败项"
exit "$fail"
