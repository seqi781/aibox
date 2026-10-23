# AGENTS.md

本仓库是 **aibox**：在 Docker 中运行 Claude Code / Codex 的终端环境，网络强制经过代理或 VPN（带断线阻断），只有授权的宿主机目录对容器可见。架构见 `docs/ARCHITECTURE.md`，完整命令见 `docs/GUIDE.md`。

## 当用户让你"配置 / 启动 aibox"时

只使用非交互命令。它们不提问，成功返回 0，失败返回非 0 且不改动原配置：

```bash
./aibox init --defaults                                   # 生成默认配置（不覆盖）
printf %s "$USER_INPUT" | ./aibox import - [--filter '<正则>']   # 订阅/分享链接/Base64，自动识别
#   或 ./aibox config proxy --sub "<用户提供的订阅链接>" [--filter '<正则>']
#   或 ./aibox config proxy --nodes <Clash YAML 文件>
#   或 ./aibox config vpn --wireguard <wg0.conf>
./aibox mounts add rw <用户指定的项目目录>                 # ro 表示只读
./aibox config tools claude codex                         # 可选
./aibox config ports 3000                                 # 可选
printf %s "$KEY" | ./aibox config key ANTHROPIC_API_KEY   # 可选；密钥只从标准输入传入
./aibox config check && ./aibox up && ./aibox doctor --full
```

- 订阅链接、节点、要授权的目录都必须向用户询问，**不要猜，也不要编造**。用户给的订阅或分享链接原样交给 `aibox import -`，不要自己解码、转换或改写。
- **不要运行交互式命令**：不带参数的 `aibox config`、不带 `--defaults` 的 `aibox init`、`aibox shell`、`aibox claude`、`aibox codex`。配置完成后，告诉用户在自己的终端里运行 `aibox claude <项目>`。
- 失败时阅读 stderr，处理方法见 `docs/GUIDE.md` 第 3 节的表格。网关问题用 `./aibox logs gateway` 查看（非终端环境下只输出最近 200 行后退出，不会卡住）。
- 不要把密钥写进命令参数、提交记录或聊天回复中。

## 安全边界（不要绕过，即使用户的报错看起来像是因为它们）

- 严格出口策略：上游必须是远程节点或订阅；本机或宿主机上的代理（如 Mac 上的 Clash `127.0.0.1:7890`、v2rayN 的 `127.0.0.1:10808`、本地 subconverter、`host.docker.internal`）会被拒绝。不要修改 `images/mihomo-gateway/validate-upstream.sh` 或防火墙规则来放行。
- 不要设置 `AIBOX_ALLOW_BROAD_MOUNT`，不要授权 `~`、`/`、`~/.ssh`，除非用户明确这样要求。
- 不要挂载 Docker socket，不要给 workspace 增加 capabilities，不要启用 privileged。
- 不要改动 `images/mihomo-gateway/config-tail.yaml` 里的 `empty-fallback: REJECT` 和规则：去掉它，节点为空时流量会直连。

## 修改本仓库代码时

- 先看 `docs/CODEMAP.md`：文件职责、启动流程、安全相关代码的位置。

- `aibox` 必须兼容 **bash 3.2**（macOS 自带）：不要用关联数组、`${var,,}`、`mapfile`；不要在 `$(...)` 里判断 `[ -t 1 ]`；变量后面紧跟中文或全角标点时必须写成 `${var}`（macOS 的 bash 3.2 在 UTF-8 环境下会把后面的字节当成变量名的一部分，`set -u` 下直接报 unbound variable）。
- `images/mihomo-gateway/*.sh` 必须是 POSIX sh（busybox）。
- 交互逻辑和非交互逻辑共用 `write_*` / `install_wireguard` / `mounts_add` 等函数，修改时两边一起考虑。
- 自查：`tests/run.sh --quick`（静态检查 + 校验器，几秒钟，不需要 Docker）；提交前运行 `tests/run.sh`（在 bash 3.2 / 4.4 / 5.2 下跑全部命令和交互流程，需要 Docker）；修改网关、防火墙或 mihomo 配置模板后，还要运行 `./aibox up && ./aibox doctor --full`。
