#!/usr/bin/env bash
# 静态检查（不需要 Docker）：语法、bash 4+ 专有语法、变量紧跟中文、宿主机脚本的 POSIX 语法
# 用法: tests/lint.sh
set -u
cd "$(dirname "$0")/.."
fail=0
ok()  { echo "  ✔ $*"; }
bad() { echo "  ✘ $*"; fail=1; }

echo "静态检查"
HOST_BASH="aibox tests/cli.sh tests/lint.sh tests/run.sh"
POSIX_SH="images/mihomo-gateway/entrypoint.sh images/mihomo-gateway/healthcheck.sh images/mihomo-gateway/validate-upstream.sh"

for f in $HOST_BASH; do bash -n "$f" || bad "bash 语法错误: $f"; done
for f in $POSIX_SH; do sh -n "$f" || bad "sh 语法错误: $f"; done
[ "$fail" = 0 ] && ok "语法"

# bash 4+ 才有的语法（aibox 必须兼容 macOS 自带的 bash 3.2）
pat='declare -[Anlu]|local -[An]|mapfile|readarray|\$\{[A-Za-z_]+(,,|\^\^)\}|;;&|\|&|&>>|coproc|\[\[ -v |@[QEPAa]\}|\[-1\]\}|wait -n|globstar|EPOCHSECONDS|read -[a-z]*i|\{[a-z0-9]+\.\.[a-z0-9]+\.\.|exec \{[a-z]'
if hits="$(grep -nE "$pat" aibox)"; then bad "使用了 bash 4+ 语法:"; echo "$hits" | sed 's/^/      /'; else ok "没有 bash 4+ 专有语法"; fi

# macOS 的 bash 3.2 在 UTF-8 环境下会把 $var 后面紧跟的中文字节当成变量名的一部分
hits="$(perl -ne 'print "$ARGV:$.: $_" if /\$[A-Za-z_][A-Za-z0-9_]*[\x80-\xff]/' $HOST_BASH $POSIX_SH images/workspace/rootfs/usr/local/bin/* 2>/dev/null)"
if [ -n "$hits" ]; then bad "变量后紧跟中文/全角字符（应写成 \${var}）:"; echo "$hits" | sed 's/^/      /'; else ok "没有变量紧跟中文字符"; fi

# 在 $(...) 里判断终端永远为假（stdout 是管道）
if hits="$(grep -nE '\$\([^)]*\[ -t [012] \]' aibox)"; then bad "在 \$(...) 里判断 [ -t ]:"; echo "$hits" | sed 's/^/      /'; else ok "没有在 \$(...) 里判断终端"; fi

# GNU 专有的命令行选项（macOS 的 BSD 工具不支持）
if hits="$(grep -nE '(^|[[:space:];&|(])(sed -i|readlink -f|stat -c|date -d|grep -P|base64 -w|xargs -r|sort -V|head -n -|timeout [0-9])' aibox | grep -vE '^[0-9]+:[[:space:]]*#')"; then bad "使用了 GNU 专有选项:"; echo "$hits" | sed 's/^/      /'; else ok "没有 GNU 专有选项"; fi

# report 会运行 doctor，doctor 末尾又会运行 report：必须带 AIBOX_IN_REPORT，否则两者无限互相调用（卡在"等待网络隔离体检"）
if grep -q '( AIBOX_IN_REPORT=1; cmd_doctor )' aibox && grep -q 'AIBOX_IN_REPORT:-' aibox; then ok "report 与 doctor 不会互相无限调用"; else bad "cmd_report 调用 cmd_doctor 时缺少 AIBOX_IN_REPORT 保护"; fi

if command -v shellcheck >/dev/null 2>&1; then
  shellcheck -S error aibox $POSIX_SH && ok "shellcheck（error 级别）" || bad "shellcheck 报错"
else
  echo "  - 未安装 shellcheck，跳过"
fi
exit "$fail"
