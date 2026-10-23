# /etc/profile 会重置 PATH：把持久化 home 中的工具目录加回去（Claude Code 原生版、npm 全局包）
for d in "$HOME/.npm-global/bin" "$HOME/.local/bin"; do
  case ":$PATH:" in *":$d:"*) ;; *) PATH="$d:$PATH" ;; esac
done
export PATH
