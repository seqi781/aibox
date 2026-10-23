# aibox

在 Docker 里运行 Claude Code、Codex 等 AI 编程工具的轻量 Linux 终端，支持 **macOS 和 Linux**（Windows 可在 WSL2 中使用）：

- **完整终端**：直接用你的系统终端进入，bash、git、node、python、编译工具链；需要后台常驻时可选 tmux
- **独立出口**：所有流量强制走代理或 VPN，有 DNS、IPv4、IPv6 泄漏防护和断线阻断，不改动宿主机网络
- **文件授权**：只有你列出的目录对容器可见，每个目录单独设置只读或读写
- **两种配置方式**：人用交互式向导；AI agent 用非交互命令（见 [AGENTS.md](AGENTS.md)）

文档：[配置与使用指南](docs/GUIDE.md)（终端里运行 `aibox guide`）· [架构与安全设计](docs/ARCHITECTURE.md) · [代码地图](docs/CODEMAP.md)

## 安装

**1. 安装 Docker**

| 系统 | 命令 |
|---|---|
| macOS | `brew install orbstack`（或 Docker Desktop），然后启动它 |
| Linux | `curl -fsSL https://get.docker.com \| sudo sh && sudo usermod -aG docker $USER`，然后重新登录 |
| Windows | 安装 Docker Desktop 并开启 WSL2 集成，之后在 WSL 终端里操作 |

**2. 获取 aibox 并运行配置向导**

```bash
git clone <仓库地址> ~/aibox     # 或直接复制整个目录
cd ~/aibox
./aibox init                      # 向导只有 3 步：环境检查 → 粘贴订阅或分享链接（自动识别并测试）→ 授权目录
```

向导里会问是否安装 `aibox` / `ai` 命令和 Tab 补全，选"是"以后就能在任意目录使用。

## 日常使用

就在你平时用的终端（Terminal、iTerm 等）里操作，进入项目目录后在命令前加 `ai`：

```bash
cd ~/code/myapp
ai                  # 进入容器终端，直接位于 /workspace/myapp（提示符以 [aibox] 开头，exit 退出）
ai claude           # 在这个项目里启动 Claude Code（第一次自动安装）；也可以 ai c
ai codex            # 启动 Codex；也可以 ai x
ai claude --yolo    # 跳过逐条确认（容器即沙箱）
ai claude --tmux    # 放进 tmux：关掉终端也继续运行，再次运行同一命令回来
ai st               # 状态和出口 IP
ai r                # 环境检测报告：出口 IP 类型与风险、DNS、时区一致性，判定高 / 中 / 低风险
ai q                # 停止
```

- 不在项目目录时也可以写项目名：`ai claude myapp`。
- 首次运行 `claude` / `codex` 时按提示登录一次，凭据会持久保存。
- 更多用法见 `aibox help` 和 [指南第 2 节](docs/GUIDE.md#2-命令速查)。

## 修改配置

```bash
aibox config                          # 重新运行向导（已有配置作为默认值）
aibox config network | mounts | tools # 只改其中一项
aibox mounts add ro ~/Documents/specs # 直接授权一个只读目录
aibox config check                    # 校验配置
aibox up                              # 改完后执行，使配置生效
```

让 AI agent 帮你配置时，它会读取 [AGENTS.md](AGENTS.md)，只使用非交互命令。

## 常见问题

- **我用的是 v2rayN / Shadowrocket / sing-box，能用吗？** 能。把订阅链接或节点分享链接直接粘贴进来，格式会自动识别：`aibox import "<链接>"`，或者 `pbpaste | aibox import -`（macOS，从剪贴板读取）。
- **能不能直接用电脑上正在运行的 Clash？** 不能，这是有意的设计。Clash 的分流规则可能让部分流量直连，出口就不受控了。请把 Clash 里的订阅链接填进来。指向本机或局域网的节点会被拒绝。
- **`aibox up` 报网关不健康**：节点连不上，或订阅下载失败。运行 `aibox logs gateway` 查看原因。
- **AI 工具怎么装？** 不用装。第一次运行 `ai c` / `ai x`，或者在容器里输入 `claude` / `codex` 时自动安装。
- **时区和语言？** 自动按代理出口 IP 的地区设置，和出口保持一致；要固定见 [指南](docs/GUIDE.md#6-故障排查)。
- **Linux 上提示无权访问 Docker**：`sudo usermod -aG docker $USER` 后重新登录；临时也可以用 `sudo aibox ...`，文件归属会自动处理。
- **验证网络隔离**：`aibox doctor --full`，全部打 ✔ 即正常。
