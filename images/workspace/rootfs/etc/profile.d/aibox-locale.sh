# 时区和语言：由 aibox 按代理/VPN 出口 IP 的地区写入 ~/.config/aibox/locale.env（每次 aibox up 更新）
# 登录 shell（tmux 新窗口、aibox claude / codex）读取它；对应的 locale 不存在时保持 C.UTF-8
if [ -r "$HOME/.config/aibox/locale.env" ]; then
  while IFS='=' read -r __k __v; do
    case "$__k" in
      TZ) [ -n "$__v" ] && export TZ="$__v" ;;
      LANG) if [ -n "$__v" ] && locale -a 2>/dev/null | grep -qix "${__v%%.*}.utf8"; then export LANG="$__v" LC_ALL="$__v"; fi ;;
    esac
  done < "$HOME/.config/aibox/locale.env"
  unset __k __v
fi
