# aibox

在 Docker 里运行 Claude Code、Codex 等 AI 编程工具的轻量 Linux 终端，支持 **macOS 和 Linux**（Windows 可在 WSL2 中使用）：

- **完整终端**：直接用你的系统终端进入，bash、git、node、python、编译工具链都有；长任务可以放进可恢复的会话
- **独立出口**：所有流量强制走代理或 VPN，有 DNS、IPv4、IPv6 泄漏防护和断线阻断，不改动你电脑的网络
- **文件授权**：只有你选的项目文件夹对容器可见，每个文件夹单独设置能否修改
- **人和 AI 都能配置**：人用交互式向导；AI agent 用非交互命令（见 [AGENTS.md](AGENTS.md)）

文档：[使用指南](docs/GUIDE.md)（终端里运行 `aibox guide`）· [架构与安全设计](docs/ARCHITECTURE.md) · [代码地图](docs/CODEMAP.md)

## 安装

**1. 安装 Docker**

| 系统 | 命令 |
|---|---|
| macOS | `brew install orbstack`（或 Docker Desktop），然后启动它 |
| Linux | `curl -fsSL https://get.docker.com \| sudo sh && sudo usermod -aG docker $USER`，然后重新登录 |
| Windows | 安装 Docker Desktop 并开启 WSL2 集成，之后在 WSL 终端里操作 |

**2. 获取 aibox 并运行配置向导**

```bash
git clone <仓库地址> ~/aibox
cd ~/aibox
./aibox init      # 3 步：环境检查 → 粘贴订阅或分享链接（自动识别并测试）→ 选择项目文件夹
```

向导里会问是否安装 `aibox` 命令，选"是"以后就能在任意目录使用。

## 使用

只需要这 10 个命令（只输入 `aibox` 也会显示）：

| 命令 | 作用 |
|---|---|
| `aibox init` | 第一次使用：配置向导 |
| `aibox claude [项目]` | 启动 Claude Code（第一次运行时自动安装） |
| `aibox codex [项目]` | 启动 Codex |
| `aibox shell [项目]` | 进入容器终端（`exit` 退出） |
| `aibox tmux [项目]` | 进入可恢复的会话：关掉终端窗口，里面的程序也继续运行 |
| `aibox status` | 查看运行状态和出口 IP |
| `aibox stop` | 停止（数据保留） |
| `aibox restart` | 重启；修改配置后用它让配置生效 |
| `aibox doctor` | 检查网络、断网保护和环境风险 |
| `aibox config` | 修改配置（网络出口、项目文件夹） |

```bash
cd ~/code/myapp
aibox claude        # 在这个项目里启动 Claude Code
aibox tmux          # 长任务：进入会话后运行 claude；Ctrl+b 再按 d 离开，再次运行 aibox tmux 回来
```

- 先 `cd` 到项目文件夹再运行，就进入容器里对应的位置；也可以写项目名：`aibox claude myapp`。
- 第一次运行 `claude` / `codex` 时按提示登录一次，登录状态会一直保存。
- 更多说明见 [使用指南](docs/GUIDE.md)。

## 常见问题

- **我用的是 v2rayN / Shadowrocket / Clash Verge，能用吗？** 能。运行 `aibox config`，把订阅链接或节点分享链接粘贴进来，格式会自动识别。
- **能不能直接用电脑上正在运行的 Clash？** 不能，这是有意的设计：Clash 的分流规则可能让部分流量直连，出口就不受控了。请把 Clash 里的订阅链接粘贴进来。
- **启动时报网关不健康**：节点连不上，或订阅失效。运行 `aibox doctor` 查看原因。
- **AI 工具怎么装？** 不用装，第一次运行 `aibox claude` / `aibox codex` 时自动安装。
- **时区和语言？** 自动按代理出口 IP 的地区设置，和出口保持一致。
- **怎么确认网络是安全的？** 运行 `aibox doctor`，它会检查断网保护、DNS 和 IPv6 泄漏，并给出出口 IP 的风险判定。
