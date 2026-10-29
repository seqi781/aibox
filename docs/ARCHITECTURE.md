# aibox 架构说明

[文档目录](README.md) · [使用指南](GUIDE.md) · [代码地图](CODEMAP.md) · [第三方许可](THIRD_PARTY_NOTICES.md)

## 1. 目标

| 需求 | 落地方式 |
|---|---|
| 真实终端 | Debian 13 容器 + bash + tmux，`docker exec -it` 直连，没有 Web 终端或 SSH 中间层 |
| 独立网络 | 网关容器独占网络栈，工作区容器共享它的网络命名空间；断线即断网 |
| 本地文件 | 只 bind mount 授权目录，`ro` 由内核强制 |
| 轻量 | 不额外配置完整虚拟机；macOS 复用 Docker 的 Linux 环境，实际开销取决于运行时和任务 |
| 易用 | 一个 bash 脚本 `aibox`：init / up / shell / stop / doctor |
| 可扩展 | 网关可插拔（`gateways/*.yaml`）；同一套 compose 在 macOS / Linux / Windows(WSL2) 上通用 |

## 2. 方案对比

| 方案 | 问题 |
|---|---|
| 完整 Linux 虚拟机 (UTM/Multipass) | 太重，文件共享和网络都要自己配 |
| 单容器 + `HTTP_PROXY` 环境变量 | **不可靠**：不认环境变量的程序（Rust/Go 二进制、git+ssh、DNS）会直接走宿主机网络，代理断了也不会阻断 |
| 单容器里同时跑 VPN 和工具 | 容器需要 `NET_ADMIN`，AI agent（或被注入的指令）用 `sudo iptables -F` 就能拆掉防火墙 |
| 宿主机开全局 VPN | 会影响整台 Mac，不符合"不影响宿主机网络" |
| **双容器共享网络命名空间（采用）** | 网络能力和工作环境分开：工作区没有任何网络管理权限，只能走网关 |

这种"网关容器 + `network_mode: service:gateway`"的模式在社区里已经很成熟（gluetun 的标准用法）。aibox 没有自己实现 VPN 或代理协议，只做了编排和加固。

## 3. 组件

```
┌──────────────────────── macOS（宿主机网络不受影响）──────────────────────────┐
│  aibox CLI ── docker compose                                               │
│ ┌──────────── Docker 的 Linux VM（OrbStack / Docker Desktop / Colima）────┐ │
│ │  ┌─────────── 共享的网络命名空间 ───────────────────────────────────┐  │ │
│ │  │ gateway（NET_ADMIN）              workspace（无 NET_ADMIN/RAW）   │  │ │
│ │  │  ├ mihomo TUN 或 gluetun VPN         ├ bash / tmux / git / node   │  │ │
│ │  │  ├ iptables：默认 DROP               ├ claude / codex（在 home 卷）│  │ │
│ │  │  ├ DNS 127.0.0.1（经隧道解析）       ├ /workspace/* ← 授权目录    │  │ │
│ │  │  └ IPv6 全部禁用                     └ /home/dev   ← 持久化卷     │  │ │
│ │  └──────────────────────┬───────────────────────────────────────────┘  │ │
│ └─────────────────────────┼──────────────────────────────────────────────┘ │
└───────────────────────────┼────────────────────────────────────────────────┘
                            └─► 只有加密隧道 → 代理节点 / VPN 服务器 → 互联网
```

| 组件 | 来源 | aibox 做了什么 |
|---|---|---|
| gluetun（VPN 模式） | `qmcgaw/gluetun` 官方镜像 | 仅做编排，上游代码及许可独立保留 |
| mihomo（代理模式） | `metacubex/mihomo` 官方二进制 | 增加启动脚本（防火墙、配置生成、守护进程）与上游校验 |
| workspace | `node:24-trixie-slim` | 开发工具、UID 对齐、tmux 配置 |
| Claude Code / Codex | 官方安装器 / npm | 首次启动经隧道装进 home 卷，之后可以自动更新 |

## 4. 网络隔离（重点）

### 4.1 mihomo 网关的防火墙规则

```
OUTPUT 默认 DROP
  ├ -d 127.0.0.11      DROP     # Docker 内置 DNS 可能经宿主机转发，直接封掉
  ├ -o lo              ACCEPT   # 本地 DNS 127.0.0.1:53（mihomo）
  ├ ESTABLISHED        ACCEPT
  ├ -o aibox0 (TUN)    ACCEPT   # 应用流量 → mihomo → 代理
  ├ -d <宿主机IP>       DROP     # 网桥网关 / host.docker.internal
  └ mark 6666  → AIBOX_UPSTREAM  # 只有 mihomo 自己的出站（连接上游节点）
                 ├ -d 私有/回环/保留网段  DROP   # 禁止本地 Clash、局域网代理作为上游
                 └ ACCEPT                         # 只允许公网节点
IPv6：sysctl 关闭 + ip6tables 全部 DROP（两者都不成立时拒绝启动）
```

- **启动时就是 fail-closed**：先上防火墙，再启动 mihomo。
- **断线阻断**：mihomo 崩溃后 TUN 网卡消失，剩下的流量没有标记，全部被 DROP。entrypoint 会守护 mihomo，崩溃后 2 秒重启；整个过程中网络命名空间不变，工作区不用重启。
- **工作区伪造不了标记**：打 `SO_MARK` 需要 `NET_ADMIN`，而工作区里即使 sudo 成 root 也没有这个能力。
- **应用流量没有直连规则**：规则只有两条。`IN-TYPE,INNER,DIRECT` 只匹配 mihomo 自己发起的请求（下载订阅），应用流量都从 TUN 进入，匹配不到它；其余全部 `MATCH,PROXY`。PROXY 组只包含用户提供的节点，并用 `exclude-type` 硬性排除 Direct、Reject 等类型。上游文件里如果出现 `rules:` 等其它顶层键，网关会拒绝启动。
- **组内没有节点时断网**：mihomo 的默认行为是，组为空时（节点筛选没匹配到、订阅下载失败）回落到内置的 `COMPATIBLE`，而它等同于直连。aibox 设置了 `empty-fallback: REJECT`，并且健康检查会确认当前节点不是 REJECT/DIRECT/COMPATIBLE；所以此时网关不健康，`aibox up` 会报出原因，流量全部被拒绝。
- **分享链接**：`aibox import` 把 vmess/vless/ss/trojan 等分享链接写入 `config/mihomo/links.txt`，由 mihomo 的 file 提供者读取（mihomo 自己解析链接，aibox 不做协议转换）。CLI 和网关启动时都会用 `validate-upstream.sh --links` 解析每条链接的服务器地址，指向本机或局域网的直接拒绝。
- **导入时预检订阅**：`aibox import` 会在宿主机上下载一次订阅，用来识别格式、统计节点，并拒绝过期订阅（返回网页）和本地订阅转换地址。订阅里指向本机的"剩余流量"等信息条目只提示，运行时由防火墙兜底，它们连不上，也不会被选中。
- **订阅下载直连**：首次下载订阅时还没有节点可用，只能直接连接订阅服务器（和 Clash 的默认行为一样）。连接受防火墙限制，只能去公网地址；本地网络能看到你访问了订阅服务器的域名或 IP，但看不到其它任何流量。
- **上游必须是远程节点或订阅**：不支持把宿主机上的 Clash 等本地代理当上游，因为它的分流规则可能让流量直连。这条规则分两层执行：
  1. 配置校验（`validate-upstream.sh`，CLI 和网关共用）：至少要有一个节点或订阅；节点 `server` 不能是 localhost、`*.internal`、`*.local` 或私有/保留 IP；不允许 `type: direct`。
  2. 防火墙兜底：带标记的出站（也就是 mihomo 连接上游的流量）只能去公网地址；私有、回环、链路本地、CGNAT、保留网段，以及宿主机地址（网桥网关和 `host.docker.internal`）一律 DROP。订阅里的域名即使解析到宿主机，也连不上。
- **控制接口不对外**：mihomo API 只监听网关容器内的 unix socket，工作区访问不到，也就切不到 DIRECT。
- **DNS**：使用 fake-ip，域名交给代理远端解析；需要真实解析时走 DoH 并经隧道（`#PROXY`）。`AIBOX_PROXY_DNS` 里有不带 `#PROXY` 的服务器时网关拒绝启动。TUN 会劫持所有发往 53 端口的流量，程序硬编码 `8.8.8.8` 也会被拦截。只有"解析节点自身域名"的查询（`AIBOX_PROXY_SERVER_DNS`）必须直连。

### 4.2 gluetun 网关

gluetun 自带 kill switch（iptables 只放行到 VPN 服务器的连接）、DNS over TLS 和 IPv6 处理。aibox 额外用 sysctl 关闭了 IPv6。自建 WireGuard 的 `Endpoint` 同样执行严格出口策略：不能是本机、宿主机或局域网地址（`aibox config vpn`、`config check`、`up` 都会检查）。

### 4.3 威胁与对策

| 泄漏路径 | 对策 | doctor 是否验证 |
|---|---|---|
| 程序不认代理环境变量 | TUN / VPN 在 L3 层接管全部流量 | ✔ 出口 IP |
| 代理或 VPN 断线 | 防火墙默认 DROP | ✔ `--full` 模拟断线 |
| DNS 泄漏 | 本地 DNS + 劫持 53 端口 + 封禁 127.0.0.11 | ✔ fake-ip / 劫持 / ECS |
| IPv6 泄漏 | sysctl 关闭 + ip6tables DROP | ✔ |
| agent 用 sudo 改网络 | 工作区没有 NET_ADMIN、NET_RAW、SYS_ADMIN | ✔ 能力集检查 |
| agent 切换代理模式 | 控制接口只在网关内的 unix socket | ✔ |
| 上游是宿主机 Clash，其规则走直连 | 只接受远程节点或订阅；配置校验 + 防火墙禁止连接宿主机和私有网段 | ✔ 规则检查 |
| 节点组为空时回落直连 | `empty-fallback: REJECT` + 健康检查确认有真实节点 | ✔ 当前节点 |
| 越权读写宿主机文件 | 只挂授权目录，ro 由内核强制；拒绝挂载 `/`、`$HOME` 及其上级、凭据目录（`~/.ssh` 等）、`/var/run` 与 Docker socket | ✔ 挂载权限 |
| 经授权目录改动网关配置 | 拒绝挂载 aibox 自身目录，以及包含它的上级目录 | — |
| 逃逸到 Docker | 不挂载 docker.sock，非 privileged | — |

边界说明：镜像拉取和 `docker build` 使用 Docker 所在主机的网络，不在工作容器运行时隔离的范围内；会访问镜像仓库、Debian / Alpine 软件源等。AI 工具在运行时经网关安装。

## 5. 文件与持久化

- 授权目录 → `/workspace/<名称>`，也可以用 `-> /path` 指定容器内路径。
- 构建镜像时让容器内 `dev` 用户的 UID/GID 与宿主机一致，新建文件的归属就是正确的（macOS 通常是 501:20）。
- `/home/dev` 是命名卷：AI 工具本体、登录凭据、shell 历史、npm 全局包都在里面，`down` 或 `rebuild` 后都还在。
- 环境检测报告（`aibox report`）：查询出口 IP 信息（ipinfo.io、proxycheck.io、ip-api.com、StopForumSpam）的请求都在 workspace 里经代理发出，这些服务只看到出口 IP；“本机”一节从宿主机发起查询，已有代理可能影响结果，不能直接当作真实宽带出口。
- 构建时设置 `BUILDX_NO_DEFAULT_ATTESTATIONS=1`：provenance 证明带有构建时间，会让镜像 ID 每次都变，导致每次 `up` 都重建容器、中断 tmux 会话。
- AI 工具不打进镜像，也不预装：第一次使用时经网关安装到 home 卷。安装入口是 `/usr/local/bin` 下的同名脚本（排在 PATH 最后），装好后用 `exec` 替换成真正的程序，中间没有多余的进程。在交互式容器 shell 里输入工具名时，`/etc/aibox/bashrc` 会用 `exec` 让工具替换这个 shell：工具运行期间没有 bash 在等待，Ctrl+C 只交给工具，bash 不可能在工具界面里打印提示符；在 tmux 会话里则为工具新开一个 tmux 窗口，工具直接由 tmux 启动，退出后回到原来的窗口；`aibox claude` 同样是工具直接作为 `docker exec` 的进程。
- 时区和语言跟随出口 IP 的地区：`aibox up` 在 workspace 里经隧道查询 ipinfo.io（备用 ip-api.com），生成对应 locale，写入 `~/.config/aibox/locale.env`，由登录 shell 和 `aibox` 的 `docker exec -e` 生效。不写进容器环境变量，地区变化时不需要重建容器（不会中断 tmux 会话）。
- apt 安装的包写进 `AIBOX_EXTRA_PACKAGES`，执行 `rebuild` 后会固化到镜像里。

### 5.1 机器信息防护与实测对比

- `AIBOX_HIDE_HARDWARE=1`（默认，旧配置未写此项时也启用）：生成的 workspace 配置用只读空 tmpfs 遮住 `/sys`，减少 DMI / 设备编号和硬件拓扑的读取。它不会改变 `/proc/cpuinfo`、内核系统调用或 CPU 指令。`/proc/sys/kernel/random/boot_id` 仍可能暴露 Docker 所用 Linux 的开机标识；本次实测的 Docker/runc 拒绝在该路径挂载 tmpfs 或空文件，未绕过该限制。
- workspace 启动时用系统随机源生成 32 位十六进制 machine ID，保存在独立 home 的 `~/.config/aibox/machine-id`，然后安装到 `/etc/machine-id`；D-Bus 的同名文件引用它。保留 home 时标识稳定，不复制宿主机 ID，也不更改 AI 工具的账号标识。
- 电脑名使用 Docker 默认的容器名称标识，不沿用宿主机名。共享网关网络时 Docker 不支持设置 `hostname`，因此不额外伪造电脑名或绕过网络限制。
- `AIBOX_MOUNTS` 只包含容器内路径和读写方式。宿主机 bind 源路径只用于宿主机侧编排；容器自己的 mountinfo 仍可能暴露源路径，不能宣称删除环境变量就消除了路径关联。
- `aibox compare` 对宿主机和已运行容器执行同一只读探针。默认终端表格显示实际 IP、电脑名和系统参数，唯一 ID 只显示前 8 位；`--redact` 隐藏 IP / 电脑名 / ID，`--json` 保持脱敏。宿主机数据不传进容器，也不自动写报告文件。实际容器的挂载、权限和 tmpfs 与探针结果一起判定，未检测到、失败、未运行均不视为防护通过。它不调用启动流程，不中断已有任务。
- 默认联网步骤只向 `api.ipify.org` / `api6.ipify.org` 查询两端当前出口；`--offline` 跳过它们。它不会强行绕过宿主机已有代理寻找真实宽带 IP，也不读取 Claude 的凭据或联网请求工具服务。IP 相同不直接推断直连，IPv6 请求失败不直接推断阻断成功。
- 对比的是当前终端可访问的信息，不是 Claude 已采集或上传的内容；也不模拟平台风控。账号关联、浏览器登录网络、CPU 架构、可见内核和部分资源信息仍存在。Docker 使用共享内核的隔离机制，不能保证程序无法识别容器或无法用其它途径关联设备。

兼容性代价：需要 sysfs 的 GPU、设备发现、硬件监控和部分构建工具可能受影响，可设置 `AIBOX_HIDE_HARDWARE=0` 后重建 workspace；更改不要求扩大 capabilities，也不修改网关防火墙。已有工作容器必须在保存任务后重建才能应用，更新代码不代表正在运行的旧容器已受保护。

参考：[Docker 隔离机制](https://docs.docker.com/engine/security/)、[共享容器网络的限制](https://docs.docker.com/engine/network/#container-networks)、[Linux UTS 命名空间只隔离电脑名和域名](https://man7.org/linux/man-pages/man7/uts_namespaces.7.html)。

## 6. 跨平台

| 平台 | 状态 | 说明 |
|---|---|---|
| macOS (Apple Silicon / Intel) | 主要目标 | 推荐 OrbStack，Docker Desktop 和 Colima 也可以用；CLI 已在 bash 3.2 下测试 |
| Linux | 已实测（Ubuntu 24.04 arm64） | 原生 Docker；会检查 Docker/Compose 版本和 TUN 设备；支持 sudo 运行（按真实用户处理 `~` 和 UID）；SELinux 可选 `:z` 标签（未实测）；防火墙只作用于容器的命名空间，不影响宿主机 |
| Windows | 预留 | Docker Desktop + WSL2，在 WSL 里运行 `aibox` |

## 6.1 配置接口

| 使用者 | 方式 | 特点 |
|---|---|---|
| 人 | `aibox init` / `aibox config`（交互式向导） | 逐步提问，支持 Tab 补全路径，密钥输入不显示 |
| AI agent / 脚本 | `aibox import`、`aibox test`、`aibox config proxy/vpn/key/set/check`、`aibox mounts add/rm` | 不提问；返回码区分成败；失败时不改动原配置；密钥只从标准输入或环境变量读取 |

向导和非交互命令共用同一套写入和校验函数（`write_sub_upstream`、`install_wireguard`、`mounts_add`、`validate-upstream.sh` 等），两种方式的结果完全一致。`AGENTS.md` / `CLAUDE.md` 会被 Codex / Claude Code 自动读取，其中写明了 agent 的操作流程和安全边界。

## 7. 已知限制与后续计划

- 网关容器被单独重启后，工作区会先断网（这是 fail-closed 的表现），再执行启动或进入环境的命令会重新接入；`compare` 只读，不触发修复。
- 节点本身部署在局域网或 Tailscale（100.64/10）里时也会被拒绝。这是严格策略的代价，目前不提供例外开关。
- 计划：Windows PowerShell 包装脚本、多个工作区实例（`AIBOX_NAME`）、订阅作入口的链式代理、`aibox node` 节点查看与切换。
