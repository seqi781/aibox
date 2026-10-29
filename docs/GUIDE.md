# aibox 使用指南

[文档目录](README.md) · [对比说明](COMPARE.md) · [使用许可](LICENSING.md)

本文按“日常使用”和“自动配置 / 完整参考”分开。

个人用户可按 [LICENSE](../LICENSE) 直接下载安装并本地使用；超出个人许可范围的行为需另行授权。

- **第一部分（第 1–4 节）给人看**：日常使用和本机对比。
- **第二部分（第 5–8 节）给 AI agent 和脚本看**：非交互配置流程和完整命令参考，人不需要读。仓库根目录的 `AGENTS.md` / `CLAUDE.md` 会被 agent 自动读取。

## 目录

[1. 首次配置](#setup) · [2. 日常操作](#daily) · [3. 使用 AI 工具](#tools) · [4. 常见问题](#faq)

[5. 非交互配置](#automation) · [6. 完整命令](#reference) · [7. Linux](#linux) · [8. 排查与重置](#troubleshooting)

---

# 第一部分：给人看

<a id="setup"></a>

## 1. 第一次使用

```bash
cd ~/aibox
./aibox init
```

向导只有 3 步，每一步回车都会采用 `[方括号]` 里的默认值：

| 步骤 | 问什么 | 说明 |
|---|---|---|
| 1 环境检查 | 不提问 | 检查 Docker。Docker 没装好也可以先完成配置 |
| 2 网络出口 | 粘贴订阅链接或节点分享链接（也支持 Clash 节点、WireGuard、VPN 服务商），可选输入节点关键词（如 `美国\|US`）只用部分节点 | 自动识别 Clash、v2rayN、Shadowrocket 等格式，**立即测试**并显示可用节点、延迟、出口 IP 和地区。测试不通过，或出口在 AI 服务不支持的地区（中国大陆、香港等）时，可以重新输入 |
| 3 选择项目文件夹 | 列出 `~/code`、`~/Projects` 等位置的 git 项目，输入编号选择；也可以输入路径或把文件夹拖进终端。每个文件夹问一句"允许 AI 修改吗"（否 = 只读） | 只有这里选的文件夹对容器可见，不能选整个主目录 |

最后会问是否安装 `aibox` 命令（以后在任意目录都能用）、是否立即启动。启动后自动输出**环境检测报告**：本机和出口 IP、出口 IP 的类型与风险、DNS 是否泄漏、时区是否一致，最后一句话判定高 / 中 / 低风险。之后随时运行 `aibox doctor` 可以重新检测。

时区、语言、AI 工具都不用配置：时区和语言按出口 IP 的地区自动设置，Claude Code / Codex 第一次运行时自动安装。

<a id="daily"></a>

## 2. 常用命令

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
| `aibox compare` | 对比本机和 aibox，看看哪些信息暴露得更少、哪些仍然可见 |
| `aibox config` | 修改配置（网络出口、项目文件夹） |

只输入 `aibox` 会显示这张表。

**看本机与 aibox 的差异：** 运行 `aibox compare`，用实际数据和 `✓ / ⚠ / —` 并排显示。截图分享加 `--redact`，不查询 IP 加 `--offline`。[字段、选项和结果含义](COMPARE.md)。

<a id="hardware-privacy"></a>

**硬件信息防护：** 默认遮住硬件目录；GPU、设备发现等工具可能受影响。旧容器需要在保存任务后重建，单纯更新脚本或执行对比不会应用防护。[生效步骤与兼容性](COMPARE.md#hardware-privacy)。

**怎么指定项目：** 先在终端里 `cd` 到项目文件夹，再运行命令，就会进入容器里对应的位置，例如 `~/code/myapp/src` → `/workspace/myapp/src`。不在项目文件夹里时，可以在命令后面写项目名：`aibox claude myapp`。

**就用你自己的终端：** aibox 不提供自己的终端窗口，`aibox claude`、`aibox shell` 直接接进你正在用的终端（Terminal、iTerm 等），滚动、复制粘贴、快捷键都和平常一样。

**在容器终端里输入 `claude` / `codex`：** 工具会直接替换这个 shell 运行，退出后回到你的系统终端。这样工具运行时后面没有 shell 在等待，Ctrl+C 只交给工具本身，不会出现提示符混进工具界面的情况。

**`aibox tmux`：** 适合长时间运行的任务。
- 每个项目一个会话。在会话里运行 `claude` 或 `codex`，工具会在新窗口里打开，退出后回到原来的窗口。
- 按 `Ctrl+b` 再按 `d` 离开，里面的程序继续运行；关掉终端窗口也一样。电脑和 Docker 需要保持运行，休眠或停止容器后不能保证任务继续。
- 再次运行 `aibox tmux` 回到原处。
- 按 `Ctrl+b` 再按数字切换窗口。底部状态栏一直显示这些按键提示。

**继续上次的对话：** 参数会原样传给工具，例如 `aibox claude -c`（Claude Code）、`aibox codex resume --last`（Codex）。

<a id="tools"></a>

## 3. 使用 Claude Code / Codex

**首次登录**（登录信息会保存在独立 home 中，过期后可能需要重新登录）：
- `aibox claude`：按提示在浏览器打开链接，把授权码粘贴回终端。
- `aibox codex`：容器里没有浏览器，选择设备码登录。

**建议：**
- **多开**：在终端里多开几个标签页，分别 `cd` 到不同项目运行 `aibox claude`，互不影响。
- **参考资料设为只读**：在 `aibox config` 里添加文档、其它仓库等文件夹时选"不允许修改"，AI 能读不能改。
- **项目说明文件**：在项目根目录放 `CLAUDE.md`（Claude Code）或 `AGENTS.md`（Codex），写上构建、测试命令和约定，AI 会自动读取。
- **git 与 SSH**：在容器里单独生成密钥（`ssh-keygen`，会一直保存），只加到需要的仓库，不要把 Mac 上的 `~/.ssh` 交给容器。
- **安装依赖**：在容器里 `npm i -g`、`pip install --user` 装的东西会一直保留。

<a id="faq"></a>

## 4. 常见问题

| 问题 | 处理 |
|---|---|
| 我用的是 v2rayN / Shadowrocket / Clash Verge，能用吗？ | 能。运行 `aibox config`，在网络出口这一步粘贴订阅链接或节点分享链接，格式会自动识别 |
| 能直接用电脑上正在运行的 Clash 吗？ | 不能，这是有意的设计：Clash 的分流规则可能让部分流量直连。请把 Clash 里的订阅链接粘贴进来 |
| 装了 Docker 仍提示"未找到 docker" | 先打开 OrbStack / Docker Desktop，再**新开一个终端窗口** |
| 启动时报网关不健康，或容器里没有网络 | 节点连不上或订阅失效。运行 `aibox doctor` 查看原因，必要时 `aibox config` 换一个订阅 |
| 修改了配置但没生效 | 运行 `aibox restart` |
| 想检查网络是否安全、出口 IP 风险高不高 | 运行 `aibox doctor` |
| 想重新配置 | 换节点或目录用 `aibox config`；清除登录和工具会删除数据，先确认范围并备份，见[排查与重置](#troubleshooting) |

---

# 第二部分：给 AI agent 和脚本（人不需要读）

<a id="automation"></a>

## 5. 非交互配置流程

**约定：**
- 所有配置命令都不提问、不需要终端。成功返回 0，失败返回非 0，错误原因输出到 stderr。
- 写入失败（例如节点不合规）时，**原配置保持不变**，可以放心重试。
- 不要运行需要交互的命令：不带参数的 `aibox config`、不带 `--defaults` 的 `aibox init`、`aibox shell`、`aibox tmux`、`aibox claude`、`aibox codex`。它们是给人在终端里用的。
- 向用户转述时只提第 2 节的常用命令（包括用户明确要求的 `compare`）；其它命令由你来运行。

**标准流程：**

```bash
# 1. 生成默认配置文件（不会覆盖已有配置）
./aibox init --defaults

# 2. 出口（必须问用户要订阅链接或分享链接，不能自己编造，也不能填本机代理地址）
#    用户给的内容原样从标准输入传入，aibox 会自动识别格式；不要自己转换
printf %s "$USER_INPUT" | ./aibox import -
# 仅当用户明确指定筛选条件时，才追加 --filter "$USER_FILTER"

# 3. 授权用户明确指定的目录
./aibox mounts add rw ~/code/my-app
./aibox mounts add ro ~/Documents/specs

# 4. 可选：用户要用 API Key 时（密钥只能从标准输入传入）
printf %s "$ANTHROPIC_API_KEY" | ./aibox config key ANTHROPIC_API_KEY

# 5. 校验 → 启动 → 体检（AI 工具不用配置，用户第一次运行 aibox claude 时自动安装）
./aibox config check      # 返回 0 才继续
./aibox up                # 首次 3～5 分钟；返回非 0 时读 stderr 和 aibox logs gateway
./aibox doctor --full     # 返回 0 表示网络隔离全部检查通过；同时输出环境检测报告
```

**常见失败及处理：**

| 错误信息包含 | 原因 | 处理 |
|---|---|---|
| `没有 proxies: 或 proxy-providers:` | 还没配置出口 | 向用户要订阅链接或分享链接 |
| `返回的是网页而不是订阅内容` | 订阅已过期、需要登录，或下载被拦截 | 请用户到机场网站重新复制订阅链接 |
| `没有识别出任何节点` / `无法识别` | 给的不是订阅或分享链接 | 把支持的格式告诉用户（见第 6 节"一键导入"） |
| `订阅 … 的地址 … 是本机/局域网地址` | 用户给的是本地 subconverter 或代理软件转换后的订阅 | 请用户提供机场的原始订阅链接 |
| `分享链接的服务器 … 是本机/宿主机/局域网地址` | 例如 v2rayN 本地端口 `socks://…@127.0.0.1:10808` | 请用户导出远程节点的分享链接或订阅 |
| `指向本机/宿主机/局域网地址` | 用户给的是本机 Clash 的地址（如 127.0.0.1:7890） | 请用户提供 Clash 里的订阅链接 |
| `节点解析到了本机/宿主机/局域网地址` | 订阅里的节点域名解析到了内网地址 | 换一个订阅或节点 |
| `测试没有通过，已恢复原来的配置` | 节点都连不上、订阅下载失败，或筛选没匹配到 | 把测试输出告诉用户；用户确认节点没问题时可以加 `--no-test` |
| `没有可用节点，网关已断网` | 节点筛选没匹配到任何节点，或订阅下载失败 | 告诉用户；取消筛选用 `aibox config proxy --filter ''`，订阅问题看 `aibox logs gateway` |
| `网关不健康` | 节点连不上 | 运行 `aibox logs gateway`，把原因告诉用户 |
| `服务器 … 是本机/宿主机/局域网地址` | WireGuard 的 Endpoint 指向本地网络 | 请用户提供远程 VPN 服务器的配置 |
| `拒绝挂载整个 /、用户主目录或其上级目录` | 授权范围过大 | 只授权具体的项目目录 |
| `它包含 aibox 自身目录` | 要授权的目录里包含 aibox（否则 AI 能改网关配置） | 只授权其中具体的项目子目录，或请用户把 aibox 移到别处 |
| `拒绝挂载凭据目录` / `Docker socket` | 授权了 `~/.ssh`、`/var/run` 等 | 不要授权；需要 SSH 时在容器内单独生成密钥 |
| `当前用户无权访问 Docker` | Linux 上用户不在 docker 组 | 告诉用户执行 `sudo usermod -aG docker $USER` 并重新登录 |

**禁止事项**（这些是安全边界，不是程序缺陷）：
- 不要尝试绕过严格出口策略：不要修改 `validate-upstream.sh`、网关的防火墙规则，也不要把本地代理地址写进配置。
- 不要设置 `AIBOX_ALLOW_BROAD_MOUNT`，不要授权 `~`、`/` 或 `~/.ssh`，除非用户明确要求。
- 不要挂载 Docker socket，不要给 workspace 增加 `NET_ADMIN` 等权限。

<a id="reference"></a>

## 6. 完整命令参考

`aibox help --all` 输出同样的列表。

### 一键导入出口（自动识别格式）

```bash
aibox import "https://机场给的订阅链接"            # 订阅：Clash / mihomo / v2rayN / Shadowrocket 格式都可以
aibox import "vless://…" "trojan://…"               # 一条或多条分享链接
printf %s "$LINKS" | aibox import -                 # 从标准输入读取（多条链接、整段 Base64）
```

| 能识别的输入 | 例子 / 从哪里复制 |
|---|---|
| 订阅链接 | `https://…`。Clash Verge / ClashX：配置文件 → 复制链接；v2rayN：订阅分组设置里的地址；Shadowrocket：订阅的 URL |
| 分享链接 | `vmess://` `vless://` `ss://` `ssr://` `trojan://` `hysteria2://` `hy2://` `tuic://` `anytls://` `socks://` |
| 一键导入链接 | `clash://install-config?url=…`、`sing-box://import-remote-profile?url=…`（机场网页上"一键导入"按钮的链接） |
| 整段 Base64 | 订阅链接在浏览器里打开后看到的那一长串字符 |
| Clash YAML | 含 `proxies:` 的节点列表 |

导入时会先下载一次订阅：确认格式、统计可用节点、列出节点名。以下情况会直接报错，不会写入配置：订阅返回的是网页（过期或需要登录）、没有识别出节点、地址指向本机或局域网（例如本地 subconverter、v2rayN 的 `127.0.0.1:10808`）。订阅里指向 `127.0.0.1` 的"剩余流量 / 到期时间"之类的信息条目只会提示，它们连不上，也不会被选中。本机下载失败时只给警告并照常保存，网关启动时会再下载一次；加 `--no-check` 跳过这一步检查。导入后会实际测试节点，测试不通过时恢复原配置（`--no-test` 跳过测试）。

### 配置

| 命令 | 作用 |
|---|---|
| `aibox init --defaults` | 生成默认配置，不提问、不覆盖 |
| `aibox config proxy --sub <订阅链接> [--sub <链接2>] [--filter <正则>]` | 用订阅作为出口（同样会预先检查） |
| `aibox config proxy --nodes <文件>` 或 `... --nodes -`（从标准输入读取） | 用 Clash YAML 节点作为出口 |
| `aibox config vpn --wireguard <wg0.conf>` | 自建 WireGuard |
| `WIREGUARD_PRIVATE_KEY=... aibox config vpn --provider mullvad [--countries Japan]` | VPN 服务商（密钥从环境变量读取） |
| `aibox mounts add [rw\|ro] <路径> [-> <名字>]` | 授权目录（默认 rw） |
| `aibox mounts rm <名字\|路径>` / `aibox mounts` | 取消授权 / 查看列表 |
| `printf %s "$KEY" \| aibox config key ANTHROPIC_API_KEY` | 保存 API Key（只从标准输入读取；用账号登录的不需要）；`--unset` 删除 |
| `aibox config set AIBOX_<键> <值>` / `config get <键>` | 修改 / 读取其它选项，例如 `AIBOX_TZ`、`AIBOX_LANG`（固定时区和语言）、`AIBOX_PORTS`（发布开发端口到 `127.0.0.1`）、`AIBOX_EXTRA_PACKAGES`（构建时额外安装的 apt 包） |
| `aibox config check` | 校验全部配置（不需要 Docker） |
| `aibox config show` | 查看当前配置（密钥脱敏） |
| `aibox config network` / `aibox config mounts` | 只运行向导的某一步（交互式，给人用） |

配置修改后执行 `aibox up`（或 `aibox restart`）生效。

### 运行与检测

| 命令 | 作用 |
|---|---|
| `aibox up` | 启动（首次构建镜像，约 3–5 分钟） |
| `aibox test` | 重新测试当前代理：可用节点、延迟、出口 IP、地区 |
| `aibox report` | 只输出环境检测报告（`aibox doctor` 末尾也会输出） |
| `aibox compare [--offline] [--redact] [--json]` | 本机与容器的实际数据对比表；`--redact` 隐藏 IP 等信息，`--json` 保持脱敏。返回 2 表示检测不完整 |
| `aibox doctor [--full]` | 网络与挂载体检；`--full` 含断线阻断测试。设置 `AIBOX_DOCTOR_NO_REPORT=1` 时不附带报告 |
| `aibox exec <命令>` | 在容器里执行一条命令（按当前目录定位） |
| `aibox claude\|codex [项目] --yolo` | 跳过工具自身的逐条确认（Claude 的 `--dangerously-skip-permissions`，Codex 的 `--dangerously-bypass-approvals-and-sandbox`） |
| `aibox claude\|codex [项目] --tmux [--new]` | 直接在 tmux 会话里启动工具（每个"工具 + 项目"一个会话） |
| `aibox sessions` | 列出 tmux 会话 |
| `aibox gemini` / `aibox opencode` | 启动 Gemini CLI / OpenCode |
| `aibox logs [gateway\|workspace]` | 日志（非终端环境下只输出最近 200 行后退出） |

### 维护

| 命令 | 作用 |
|---|---|
| `aibox install` | 把 `aibox` 链接到 PATH，并可选添加 Tab 补全 |
| `aibox setup <工具…>` / `aibox setup --upgrade` | 手动安装 / 升级 AI 工具 |
| `aibox rebuild` | 拉取最新基础镜像并重建（home 卷保留） |
| `aibox down` | 删除容器（home 卷和配置保留） |
| `aibox destroy` | 删除容器、镜像和 home 卷（需要输入 yes；项目文件和 `config/` 不受影响） |
| `aibox guide` | 显示本文 |

**环境检测报告的内容：**

| 部分 | 内容 | 数据来源 |
|---|---|---|
| 本机 | 当前终端查到的 IPv4 / IPv6、时区、本机 DNS 来源 | 从本机查询 ipinfo.io、ipify、Google DNS；已有代理可能影响结果 |
| 出口 | 代理后的 IP、国家 / 地区、城市、运营商、IP 归属（ASN）、时区 | 经代理查询 ipinfo.io、proxycheck.io、ip-api.com |
| IP 类型与风险 | 机房 / 住宅 / 移动网络、proxycheck 风险评分、是否被标记为代理 / VPN / Tor、StopForumSpam 滥用记录 | 经代理查询 |
| DNS | 容器的 DNS 由谁解析、是否携带本机网段（泄漏检测） | 容器内查询 `o-o.myaddr.l.google.com` |
| 一致性 | 容器时区和语言是否与出口一致、网络隔离体检是否通过 | 容器内检测 + `aibox doctor` |
| 综合判定 | 汇总以上各项，用一句话判定高 / 中 / 低风险 | — |

判定规则：
- **高风险**（任一项）：出口与本机 IP 相同、DNS 或 IPv6 泄漏、隔离体检失败、风险评分 ≥ 67、Tor / 失陷主机、StopForumSpam 有高置信度记录、出口地区可能不受 AI 服务支持。
- **中风险**：机房 IP、被标记为代理 / VPN、风险评分 34–66、少量滥用记录、时区与出口不一致。
- **低风险**：以上都没有。

第三方查询有额度和可用性限制，查不到的项目会注明“未能检测”，不计入判定；因此“低风险”不代表全部项目已验证，也不是封号概率。

当前综合报告会把“本机与容器出口相同”列为高风险。本机已开代理时也会出现相同出口，不能据此确认直连泄漏；`aibox compare` 会显示这一不确定性。IPv6 查询失败也不单独证明阻断生效，断线保护应结合实际体检。

<a id="linux"></a>

## 7. Linux 说明

| 项目 | 说明 |
|---|---|
| 安装 Docker | `curl -fsSL https://get.docker.com \| sudo sh`，然后 `sudo usermod -aG docker $USER` 并重新登录 |
| 版本要求 | Docker Engine ≥ 25，Compose ≥ 2.24。发行版自带的旧版本会被检测出来，并提示升级方法 |
| TUN 设备 | 缺少 `/dev/net/tun` 时会提示执行 `sudo modprobe tun` |
| 用 sudo 运行 | 支持。`~` 按真实用户展开，生成的文件归还给真实用户，容器内使用真实用户的 UID |
| 用 root 登录直接运行 | 可以，但容器内用户的 UID 是 1000 |
| SELinux（Fedora / RHEL） | 向导检测到 Enforcing 时会询问，开启后挂载目录带 `:z` 标签。**未实测** |
| rootless Docker | 会给出警告，**未测试** |
| 已实测环境 | Ubuntu 24.04 arm64、Docker 29、Compose 2.40 |

宿主机网络不受影响：所有防火墙规则只作用于网关容器自己的网络命名空间。

<a id="troubleshooting"></a>

## 8. 故障排查

| 现象 | 处理 |
|---|---|
| 装了 Docker 仍提示"未找到 docker" | 请用户先打开 OrbStack / Docker Desktop，再新开一个终端窗口。aibox 也会自动到 `~/.orbstack/bin`、`~/.docker/bin` 等位置查找 |
| `aibox up` 报网关不健康 | `aibox logs gateway`。常见原因是订阅下载失败（检查链接）或节点全部不可用 |
| 进入容器后没有网络 | `aibox status` 查看网关健康状态；网关重启后，启动或进入环境会重新接入；`compare` 只读，不会修复网络 |
| 挂载目录里写不了文件 | `aibox doctor` 查看挂载权限；Linux 上检查宿主机目录的属主，SELinux 系统开启 `AIBOX_SELINUX_RELABEL` |
| 构建镜像很慢 | 构建用的是电脑本身的网络。可以为 Docker 配置镜像加速，或在电脑上开启代理后再运行 `aibox up` |
| 时区 / 语言不对 | 它们跟随出口 IP 的地区；`aibox test` 查看检测结果。要固定：`aibox config set AIBOX_TZ Asia/Tokyo`、`aibox config set AIBOX_LANG ja_JP.UTF-8`，然后 `aibox up` |
| 仅重新配置 | 使用配置命令调整网络或目录，保留 home 中的工具和登录信息 |
| 只删除容器 | `aibox down` 保留 home 和配置；执行前确认没有仍需运行的任务 |
| 清除工具和登录 | 明确确认删除范围并备份后再用 `aibox destroy`；它会删除 home，挂载的项目目录不在此命令的删除范围内 |
| 同时清除配置 | 配置包含节点和密钥，`.aibox/` 也可能有备份及独立测试实例。不要直接整体删除；先核对、备份并逐项确认 |
