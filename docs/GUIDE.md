# aibox 配置与使用指南

本指南给两类读者：
- **人**：跟着交互式向导走，回答几个问题就能用（第 1 节）。
- **AI agent**（例如你在宿主机上让 Claude Code / Codex 帮你配置 aibox）：使用非交互命令，不需要人值守（第 3 节）。仓库根目录的 `AGENTS.md` / `CLAUDE.md` 会被 agent 自动读取。

在终端里随时运行 `aibox guide` 查看本文。

---

## 1. 人：用配置向导

```bash
./aibox init          # 第一次使用
aibox config          # 之后修改任何配置，再次运行向导即可（已有配置作为默认值）
```

向导只有 3 步，只问必须由你决定的事，每一步回车都会采用 `[方括号]` 里的默认值：

| 步骤 | 问什么 | 说明 |
|---|---|---|
| 1 环境检查 | 不提问 | 检查 Docker / Compose 版本，Linux 上还检查 TUN 设备。Docker 没装好也可以先完成配置 |
| 2 网络出口 | 粘贴订阅或分享链接（也支持 Clash 节点 / WireGuard / 商业 VPN） | 自动识别格式，**立即测试**并汇报可用节点、延迟、出口 IP 和地区；测试不通过可以重新输入 |
| 3 选择项目文件夹 | 列出 `~/code`、`~/Projects` 等位置的 git 项目，输入编号选择；也可输入路径或把文件夹拖进终端。每个文件夹问一句"允许 AI 修改吗"（否 = 只读） | 只有这里选的文件夹对容器可见；不能选整个主目录。不扫描文稿/桌面/下载（macOS 会弹隐私授权）。检测到 SELinux 时多问一句 |

最后会问是否安装 `aibox` / `ai` 命令、是否立即启动。启动后自动输出**环境检测报告**（之后随时用 `aibox report` 重新检测）：

| 部分 | 内容 | 数据来源 |
|---|---|---|
| 本机 | 真实 IPv4 / IPv6、时区、本机 DNS 来源 | 本机直连 ipinfo.io、ipify、Google DNS |
| 出口 | 代理后的 IP、国家 / 地区、城市、运营商、IP 归属（ASN）、时区 | 经代理查询 ipinfo.io、proxycheck.io、ip-api.com |
| IP 类型与风险 | 机房 / 住宅 / 移动网络、proxycheck 风险评分、是否被标记为代理 / VPN / Tor、StopForumSpam 滥用记录 | 经代理查询 |
| DNS | 容器的 DNS 由谁解析、是否携带本机网段（泄漏检测） | 容器内查询 `o-o.myaddr.l.google.com` |
| 一致性 | 容器时区和语言是否与出口一致、网络隔离体检是否通过 | 容器内检测 + `aibox doctor` |
| 综合判定 | 汇总以上各项，用一句话判定高 / 中 / 低风险 | — |

判定规则：
- **高风险**（任一项）：出口与本机 IP 相同、DNS 或 IPv6 泄漏、隔离体检失败、风险评分 ≥ 67、Tor / 失陷主机、StopForumSpam 有高置信度记录、出口地区可能不受 AI 服务支持。
- **中风险**：机房 IP、被标记为代理 / VPN、风险评分 34–66、少量滥用记录、时区与出口不一致。
- **低风险**：以上都没有。

proxycheck.io 免费额度每天有限，查不到的项目会注明"未能检测"，不计入判定。

其余的都自动处理，不需要你选：
- **时区和语言**：按出口 IP 的地区自动设置（例如出口在日本，就是 `Asia/Tokyo` + `ja_JP.UTF-8`），每次 `aibox up` 都会重新检测。要固定的话，用 `aibox config set AIBOX_TZ …` / `AIBOX_LANG …`。
- **AI 工具**：不预装。第一次运行 `aibox claude` / `aibox codex`，或者在容器里直接输入 `claude` / `codex` 时自动安装，之后保存在持久化 home 卷里。
- **镜像下载、端口映射**：拉取镜像用的是你电脑本身的网络，aibox 不干预；开发服务器的端口在开发过程中按需处理（见第 2 节"高级"）。

### 一键导入出口（自动识别格式）

不管你平时用什么代理软件，把它的订阅链接或节点分享链接粘贴进来即可：

```bash
aibox import "https://机场给的订阅链接"            # 订阅：Clash / mihomo / v2rayN / Shadowrocket 格式都可以
aibox import "vless://…" "trojan://…"               # 一条或多条分享链接
pbpaste | aibox import -                            # macOS：从剪贴板读取（v2rayN 里“导出分享链接到剪贴板”后）
```

| 能识别的输入 | 例子 / 从哪里复制 |
|---|---|
| 订阅链接 | `https://…`。Clash Verge / ClashX：配置文件 → 复制链接；v2rayN：订阅分组设置里的地址；Shadowrocket：订阅的 URL |
| 分享链接 | `vmess://` `vless://` `ss://` `ssr://` `trojan://` `hysteria2://` `hy2://` `tuic://` `anytls://` `socks://` |
| 一键导入链接 | `clash://install-config?url=…`、`sing-box://import-remote-profile?url=…`（机场网页上“一键导入”按钮的链接） |
| 整段 Base64 | 订阅链接在浏览器里打开后看到的那一长串字符 |
| Clash YAML | 含 `proxies:` 的节点列表 |

导入时会先下载一次订阅：确认格式、统计可用节点、列出节点名（方便写筛选正则）。以下情况会直接报错，不会写入配置：订阅返回的是网页（过期或需要登录）、没有识别出节点、地址指向本机或局域网（例如本地 subconverter、v2rayN 的 `127.0.0.1:10808`）。订阅里指向 `127.0.0.1` 的"剩余流量 / 到期时间"之类的信息条目只会提示，它们连不上，也不会被选中。本机下载失败时只给警告并照常保存，网关启动时会再下载一次；加 `--no-check` 可以跳过这一步检查。

只改某一部分，可以直接进入对应步骤：

```bash
aibox config network     # 只改出口
aibox config mounts      # 只改授权目录
```

---

## 2. 命令速查

安装后 `ai` 与 `aibox` 完全等价（`aibox install` 安装，并可选添加 Tab 补全）。

### 日常

| 命令 | 简写 | 作用 |
|---|---|---|
| `aibox shell [项目]` | `ai` 或 `ai s` | 进入容器终端（就在你的系统终端里，提示符以 `[aibox]` 开头，`exit` 退出） |
| `aibox claude [项目]` | `ai c` | 启动 Claude Code（第一次自动安装） |
| `aibox codex [项目]` | `ai x` | 启动 Codex |
| `aibox exec <命令>` | | 在容器里执行一条命令，例如 `ai exec npm test` |
| `aibox sessions` | `ai ls` | 列出 `--tmux` 会话 |
| `aibox status` | `ai st` | 状态、出口 IP、会话 |
| `aibox up` / `aibox stop` | `ai u` / `ai q` | 启动 / 停止 |
| `aibox doctor [--full]` | `ai d` | 体检 |

用法规则：
- **就用你的系统终端**：aibox 不提供自己的终端窗口。`ai` / `ai claude` 把你当前的终端直接接进容器，滚动、复制粘贴、快捷键都和平常一样。
- **AI 工具独占终端**：在 `ai` 进入的容器终端里输入 `claude` / `codex`，工具会直接替换这个 shell 运行，退出后回到你的系统终端（再次进入用 `ai`）。工具运行时后面没有 bash 在等待，所以 Ctrl+C 只会交给工具本身，不会出现提示符和工具界面混在一起。也可以直接在系统终端里运行 `ai claude`，效果相同。确实想留在容器 shell 里时用 `command claude`。
- **按当前目录定位**：在 Mac 上 `cd` 到某个授权目录（或它的子目录）再运行，就进入容器里对应的位置，例如 `~/code/myapp/src` → `/workspace/myapp/src`。不在授权目录里时，可以写项目名（`ai claude myapp`），否则进入 `/workspace`。
- **`--tmux`（可选）**：需要关掉终端后任务继续运行时使用。每个"工具 + 项目"一个会话（如 `claude-myapp`），再次运行同一命令回到原会话；`--new` 再开一个；`Ctrl+b d` 离开。
- `--yolo`：跳过工具自身的逐条确认（Claude 的 `--dangerously-skip-permissions`，Codex 的 `--dangerously-bypass-approvals-and-sandbox`）。容器本身就是沙箱，agent 只能改动你授权为 rw 的目录。
- 其余参数原样传给工具，例如 `aibox claude myapp -c`（继续上次对话）、`aibox codex myapp resume --last`。
- 继续上次的对话不需要 tmux：`ai claude -c`（Claude Code）、`ai codex resume --last`（Codex）。

### 配置（非交互，人和 agent 都可以用）

| 命令 | 作用 |
|---|---|
| `aibox import "<订阅或分享链接>" [更多…] [--filter <正则>]` | 一键导入出口，自动识别格式（简写 `ai i`） |
| `printf %s "$LINKS" \| aibox import -` | 从标准输入导入（多条链接、整段 Base64） |
| `aibox config proxy --sub <订阅链接> [--sub <链接2>] [--filter <正则>]` | 用订阅作为出口（同样会预先检查） |
| `aibox config proxy --nodes <文件>` 或 `... --nodes -`（从标准输入读取） | 用 Clash YAML 节点作为出口 |
| `aibox config vpn --wireguard <wg0.conf>` | 自建 WireGuard |
| `WIREGUARD_PRIVATE_KEY=... aibox config vpn --provider mullvad [--countries Japan]` | 商业 VPN（密钥从环境变量读取） |
| `aibox mounts add [rw\|ro] <路径> [-> <名字>]` | 授权目录（默认 rw） |
| `aibox mounts rm <名字\|路径>` / `aibox mounts` | 取消授权 / 查看列表 |
| `aibox test` | 重新测试当前代理：可用节点、延迟、出口 IP、地区 |
| `aibox report` | 环境检测报告：本机 / 出口 IP、IP 类型与风险、DNS、一致性、综合判定（简写 `ai r`） |
| `printf %s "$KEY" \| aibox config key ANTHROPIC_API_KEY` | 保存 API Key（只从标准输入读取；用账号登录的不需要） |
| `aibox config key ANTHROPIC_API_KEY --unset` | 删除 API Key |
| `aibox config set AIBOX_TZ Asia/Shanghai` / `config get <键>` | 修改 / 读取其它选项 |
| `aibox config check` | 校验全部配置（不需要 Docker） |
| `aibox config show` | 查看当前配置（密钥脱敏） |

配置修改都要执行 `aibox up` 才会生效。

---

## 3. Agent：非交互配置流程

**约定：**
- 所有配置命令都不提问、不需要终端。成功返回 0，失败返回非 0，错误原因输出到 stderr。
- 写入失败（例如节点不合规）时，**原配置保持不变**，可以放心重试。
- 不要运行需要交互的命令：不带参数的 `aibox config`、不带 `--defaults` 的 `aibox init`、`aibox shell`、`aibox claude`、`aibox codex`。它们是给人在终端里用的。

**标准流程：**

```bash
# 1. 生成默认配置文件（不会覆盖已有配置）
./aibox init --defaults

# 2. 出口（必须问用户要订阅链接或分享链接，不能自己编造，也不能填本机代理地址）
#    用户给的内容原样从标准输入传入，aibox 会自动识别格式；不要自己转换
printf %s "$USER_INPUT" | ./aibox import - --filter '日本|JP'

# 3. 授权用户明确指定的目录
./aibox mounts add rw ~/code/my-app
./aibox mounts add ro ~/Documents/specs

# 4. 可选：用户要用 API Key 时（密钥只能从标准输入传入）
printf %s "$ANTHROPIC_API_KEY" | ./aibox config key ANTHROPIC_API_KEY

# 5. 校验 → 启动 → 体检（AI 工具不用配置，用户第一次运行 aibox claude 时自动安装）
./aibox config check      # 返回 0 才继续
./aibox up                # 首次 3～5 分钟；返回非 0 时读 stderr 和 aibox logs gateway
./aibox doctor --full     # 返回 0 表示网络隔离全部检查通过
```

**常见失败及处理：**

| 错误信息包含 | 原因 | 处理 |
|---|---|---|
| `没有 proxies: 或 proxy-providers:` | 还没配置出口 | 向用户要订阅链接或分享链接 |
| `返回的是网页而不是订阅内容` | 订阅已过期、需要登录，或下载被拦截 | 请用户到机场网站重新复制订阅链接 |
| `没有识别出任何节点` / `无法识别` | 给的不是订阅或分享链接 | 把支持的格式告诉用户（见第 1 节表格） |
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

---

## 4. 在容器里使用 Claude Code / Codex

### 首次登录（只需一次，凭据保存在持久化 home 卷）

```bash
aibox claude myapp     # 首次运行按提示登录：浏览器打开链接，把授权码粘贴回终端
aibox codex myapp      # 在 Codex 里选择登录；容器内没有浏览器，用设备码: codex login --device-auth
```

用 API Key 的话，`aibox config key ANTHROPIC_API_KEY` / `OPENAI_API_KEY` 保存后执行 `aibox up`，就不需要登录了。

### 推荐工作方式
- **多开**：在终端里多开几个标签页，分别 `cd` 到不同项目运行 `ai claude`，互不影响。
- **长任务放心离开**：用 `ai claude --tmux`，关掉终端甚至断开 SSH 都不影响，下次运行同一命令就回到原会话。
- **参考资料设为只读**：把文档、规范、其它仓库用 `ro` 授权，agent 能读不能改。
- **项目说明文件**：在项目根目录放 `CLAUDE.md`（Claude Code）或 `AGENTS.md`（Codex），写上构建、测试命令和约定，agent 会自动读取。
- **git 与 SSH**：建议在容器内单独生成密钥（`ssh-keygen`，保存在持久化 home 卷），只加到需要的仓库，而不是挂载 Mac 上的 `~/.ssh`。
- **安装依赖**：`npm i -g` 和 `pip install --user` 装在 home 卷里，会一直保留。`sudo apt install` 装的包在 `aibox rebuild` 后会消失，需要长期使用的写进 `AIBOX_EXTRA_PACKAGES`。
- **AI 工具**：第一次使用时自动安装。Claude Code 会自己更新；其它工具运行 `aibox setup --upgrade`。也支持 `gemini`、`opencode`（`aibox gemini <项目>`）。
- **从本机浏览器访问容器里的开发服务器**：网关防火墙默认不接受外部连接。需要时运行 `aibox config ports 3000`（多个用逗号分隔），服务监听 `0.0.0.0`，执行 `aibox up` 后访问 `http://127.0.0.1:3000`。

---

## 5. Linux 说明

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

---

## 6. 故障排查

| 现象 | 处理 |
|---|---|
| 装了 Docker 仍提示"未找到 docker" | 先打开 OrbStack / Docker Desktop，再**新开一个终端窗口**（安装程序改的 PATH 只对新终端生效）。aibox 也会自动到 `~/.orbstack/bin`、`~/.docker/bin` 等位置查找 |
| `aibox up` 报网关不健康 | 运行 `aibox logs gateway`。常见原因是订阅下载失败（检查链接）或节点全部不可用 |
| 进入容器后没有网络 | `aibox status` 查看网关健康状态；网关重启过的话，任意 `aibox` 命令都会自动重新接入 |
| 挂载目录里写不了文件 | `aibox doctor` 查看挂载权限；Linux 上检查宿主机目录的属主，SELinux 系统开启 `AIBOX_SELINUX_RELABEL` |
| 构建镜像很慢 | 构建用的是你电脑本身的网络。可以为 Docker 配置镜像加速，或在电脑上开启代理后再运行 `aibox up` |
| 时区 / 语言不对 | 它们跟随出口 IP 的地区；`aibox test` 查看检测结果。要固定：`aibox config set AIBOX_TZ Asia/Tokyo`、`aibox config set AIBOX_LANG ja_JP.UTF-8`，然后 `aibox up` |
| 想彻底重来 | `aibox destroy`（删除容器和 home 卷，项目文件不受影响），然后 `aibox init` |
