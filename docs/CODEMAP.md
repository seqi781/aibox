# aibox 代码地图

[文档目录](README.md) · [使用指南](GUIDE.md) · [架构](ARCHITECTURE.md) · [许可说明](LICENSING.md)

给想修改 aibox 的人和 agent：每个文件做什么、`aibox up` 时发生了什么、改某样东西该去哪里。
设计原因和威胁模型见 [ARCHITECTURE.md](ARCHITECTURE.md)，命令用法见 [GUIDE.md](GUIDE.md)。

## 1. 目录结构

```
aibox                          唯一的命令行入口（bash 3.2 兼容）
lib/
  compare.sh                   本机与容器的信息暴露对比（bash 3.2；只读、不调用启动流程）
  compare-display.sh           紧凑实际数据表；--redact 隐藏 IP、电脑名与 ID
  compare-table.awk            UTF-8 中文列宽、对齐与安全截断（不依赖 Python）
  environment-probe.sh         两端共用的只读探针（POSIX sh；原始标识只供宿主机内存比较）
compose.yaml                   workspace 容器（无网卡，共享网关的网络命名空间）
gateways/
  mihomo.yaml                  代理网关的 compose 片段
  gluetun.yaml                 VPN 网关的 compose 片段
images/
  mihomo-gateway/              代理网关镜像（alpine + mihomo + iptables）
    Dockerfile
    entrypoint.sh              防火墙 → 校验上游 → 生成配置 → 守护 mihomo
    validate-upstream.sh       严格出口校验（CLI 和网关共用，POSIX sh）
    config-head.yaml           TUN / DNS / routing-mark 模板
    config-tail.yaml           PROXY 组、empty-fallback、规则
    healthcheck.sh             TUN 存在 + 组内有真实节点 + 能经代理上网
  workspace/                   工作容器镜像（Debian 13 + Node 24 + 开发工具）
    Dockerfile
    rootfs/usr/local/bin/aibox-entrypoint   修正 home 卷归属，生成独立且随 home 保留的机器标识
    rootfs/usr/local/bin/aibox-setup        安装 claude / codex / gemini / opencode（第一次使用时调用）
    rootfs/usr/local/lib/aibox/tool-shim    /usr/local/bin/{claude,codex,...} 指向它：首次运行时安装，然后 exec 成真正的程序
    rootfs/etc/aibox/prompt.sh              [aibox] 提示符（~/.bashrc 末尾也会加载，避免被覆盖）
    rootfs/etc/profile.d/aibox-locale.sh    按出口地区设置时区和语言（读取 ~/.config/aibox/locale.env）
    rootfs/etc/aibox/bashrc                 提示符、欢迎信息；claude/codex 等以 exec 替换 shell 运行，在 tmux 里则开新窗口运行（Ctrl+C 不会让 bash 抢回终端）
    rootfs/etc/profile.d/aibox-path.sh      登录 shell 的 PATH（/etc/profile 会重置）
    rootfs/etc/tmux.conf                    tmux 配置（鼠标、OSC52 剪贴板、状态栏按键提示）
config.example/                配置模板；init 时复制到 config/（config/ 不进 git）
  aibox.env                    主配置（KEY=VALUE，由 aibox 自行解析，不会被 source）
  mounts.conf                  授权目录：<rw|ro> <路径> [-> <容器路径>]
  workspace.env                注入 workspace 的环境变量（API Key）
  mihomo/upstream.yaml         节点或订阅（只允许 proxies: / proxy-providers:）
  mihomo/links.txt             导入的分享链接（由 upstream.yaml 中的 links 文件提供者引用）
  gluetun.env, gluetun/        VPN 配置
docs/
  README.md                    文档总目录，按用户 / 自动配置 / 维护 / 许可导航
  GUIDE.md                     使用指南（aibox guide）
  COMPARE.md                   实际数据对比、选项、未验证项和硬件防护生效
  ARCHITECTURE.md              架构、威胁模型、已知限制
  CODEMAP.md                   本文件
  LICENSING.md                 运行、复制、转载、分发及商用的授权说明
  THIRD_PARTY_NOTICES.md        上游组件与各自许可，不受项目专有条款重新授权
  media/                       README 终端动画、MP4、截图及脱敏后的录制数据
LICENSE                        允许个人下载使用，限制改作、再分发和售卖
AGENTS.md / CLAUDE.md          agent 自动读取的操作规则与安全边界
tests/                         兼容性测试（tests/run.sh；见第 6 节）
（宣传站已迁出，本仓库只维护终端工具及其文档）
```

本文是技术操作说明，不授予修改或分发代码的版权许可；相应操作应已获授权。第三方内容继续适用其原有条款。

运行时生成、不进 git 的目录：`config/`（用户配置）、`.aibox/compose.generated.yaml`（挂载与端口）、`.aibox/geo.env`（最近一次检测到的出口地区）。

## 2. `aibox up` 时发生了什么

```
config/aibox.env ───────────── load_env（导出 AIBOX_*）
config/mounts.conf ─────────── gen_override → .aibox/compose.generated.yaml（挂载、端口）
config/mihomo/upstream.yaml ── validate-upstream.sh（不合规直接退出）
                                 │
docker compose -f compose.yaml -f gateways/<网关>.yaml -f .aibox/compose.generated.yaml \
               up -d --build --wait
  │
  ├─ gateway 容器（entrypoint.sh）
  │    ① setup_firewall：默认 DROP，只放行 TUN 和带 routing-mark 的公网连接
  │    ② build_upstream：容器内再校验一次 upstream.yaml
  │    ③ build_config：config-head + upstream + config-tail → /run/aibox/config.yaml
  │    ④ 守护循环：mihomo 退出后 2 秒重启，期间防火墙保持阻断
  │    healthcheck.sh 通过后才算 healthy
  │
  └─ workspace 容器（network_mode: service:gateway，去掉 NET_ADMIN/NET_RAW/SYS_ADMIN）
       依赖 gateway healthy 才启动
  │
fix_netns（网关重启过则重启 workspace，重新加入网络命名空间）
geo_apply（经隧道查询出口 IP 的地区 → 生成 locale，写入 ~/.config/aibox/locale.env）
（AI 工具不在这里安装：容器里 /usr/local/bin/claude 等同名脚本（tool-shim）在第一次运行时安装，然后 exec 成真正的程序）
```

## 3. `aibox` 脚本的结构

按文件中出现的顺序排列。用 `grep -n '^函数名()' aibox` 定位。

| 区块 | 主要函数 | 说明 |
|---|---|---|
| 定位与工具函数 | `info` `warn` `die` `trim` `yq` | 支持软链接到 PATH；`yq` 做 YAML 双引号转义 |
| 宿主机识别 | `fix_owner` | 识别 macOS / Linux / WSL；sudo 运行时按真实用户处理 `~`、UID、GID |
| Docker 环境检查 | `need_docker` `ver_ge` | 版本、权限、TUN 设备，给出各平台修复命令 |
| 配置读写 | `get_kv` `set_kv` `del_kv` `copy_examples` `load_env` `compose` | 纯 bash 实现，不依赖 `sed -i` 的平台差异 |
| 授权目录 | `canon_host_path` `mount_guard` `parse_mount_line` `gen_override` `mounts_add` `mounts_rm` | `mount_guard` 是挂载黑名单 |
| 容器状态 | `is_running` `health` `dexec` `fix_netns` | `TTY_FLAG` 必须在顶层判断 |
| 向导提问 | `ask` `ask_path` `ask_secret` `yesno` `choose` | |
| 进度显示 | `run_step` `step_detail` `fmt_secs` | 长操作在后台运行，前台显示已用时间、预计时间和当前步骤；日志在 `.aibox/logs/` |
| **一键导入出口** | `classify_proxy_input` `probe_subscription` `import_proxy` `write_import_upstream` `show_probe_names` | 识别订阅 / 分享链接 / 一键导入链接 / Base64 / YAML，预先下载订阅检查，再写入 upstream.yaml 和 links.txt |
| **写配置的共用函数** | `write_sub_upstream` `write_nodes_upstream` `install_wireguard` `write_provider_vpn` `check_wg_endpoint` `check_ports` | 向导和非交互命令共用；失败时恢复原文件 |
| 出口测试与地区 | `proxy_test` `geo_query` `geo_apply` `geo_args` `country_locale` `cmd_test` `snap_save/restore` | 用临时网关容器 aibox-gwtest 测节点，不影响正在运行的环境；失败时恢复配置 |
| 环境检测报告 | `cmd_report` `REPORT_COLLECT` `report_parse` `host_dns_resolver` `ai_unsupported_region` | 出口相关查询在 workspace 里经代理执行（用容器的 jq 解析）；本机部分直连；最后汇总为高 / 中 / 低风险 |
| 信息暴露对比 | `lib/compare.sh` 的 `cmd_compare`，`lib/environment-probe.sh` | 只检查实际运行环境；默认实际数据表，--redact / --json 脱敏；不落盘、不传入对方环境；未知不当成通过 |
| 向导（3 步） | `wizard_network` `wizard_test` `wizard_mounts` `cmd_wizard` | 第 3 步：`find_projects` 找 git 项目，`clean_input_path` 处理拖入的路径，`wizard_add_dir` 先校验再问是否可修改 |
| 非交互配置 | `cmd_init` `cmd_config` `config_usage` `list_mounts_raw` | 供 agent / 脚本使用，不提问 |
| 启动与进入 | `cmd_up` `ensure_up` `resolve_project` `cmd_shell` `cmd_tmux` `cmd_agent` | `cmd_tmux`：每个项目一个可恢复的 tmux 会话；`cmd_agent` 启动 claude / codex（`--tmux` 时放进"工具 + 项目"会话） |
| 管理命令 | `cmd_stop` `cmd_down` `cmd_logs` `cmd_setup` `cmd_rebuild` `cmd_status` `cmd_mounts` `cmd_destroy` `cmd_install` `cmd_completion` `cmd_guide` | |
| 体检 | `cmd_doctor`（`ok` / `bad` 计数） | `--full` 会模拟断线 |
| 帮助与分发 | `usage`（常用命令，含用户要求的 compare）、`usage_all`（`help --all`，给 agent）、文件末尾的 `case "$cmd"` | 没有简写命令；给人看的命令加到 `usage`、补全、README 和 GUIDE 第一部分，其它命令只写进 `usage_all` 和 GUIDE 第二部分 |

## 4. 安全相关的关键位置

| 机制 | 位置 |
|---|---|
| 防火墙与 kill switch | `entrypoint.sh` 的 `setup_firewall` |
| 上游只能是公网节点 | `validate-upstream.sh` 的 `is_local_server` 和 entrypoint 的 `NON_PUBLIC_NETS`（两处要保持一致） |
| 节点组为空时断网，不回落直连 | `config-tail.yaml` 的 `empty-fallback: REJECT`；`healthcheck.sh` 检查当前节点 |
| 应用流量全部走代理 | `config-tail.yaml` 的 `rules`（`IN-TYPE,INNER,DIRECT` 只匹配 mihomo 自己下载订阅的请求） |
| DNS 必须经隧道 | `config-head.yaml` 的 `dns:`；entrypoint 的 `build_config` 检查 `#PROXY` 后缀 |
| 控制接口不对 workspace 开放 | `config-head.yaml` 的 `external-controller-unix` |
| workspace 无网络权限 | `compose.yaml` 的 `network_mode` 和 `cap_drop` |
| 挂载限制 | `aibox` 的 `canon_host_path` 和 `mount_guard` |
| 硬件信息目录遮挡 | `aibox` 的 `gen_override`（只读 tmpfs），`load_env` / `cmd_config` 校验 `AIBOX_HIDE_HARDWARE` |
| 独立机器标识 | workspace 的 `aibox-entrypoint` 与 Dockerfile；不改变 AI 工具登录标识 |
| 分享链接的服务器地址检查 | `validate-upstream.sh --links`（`link_host` 解析各协议的地址；CLI 和网关启动时都会执行） |
| WireGuard 服务器地址检查 | `aibox` 的 `check_wg_endpoint`（调用 `validate-upstream.sh --server`） |

修改这些位置之后，必须运行 `./aibox doctor --full`。

## 5. 想改某样东西时去哪里

| 要改的 | 位置 |
|---|---|
| 节点选择策略、健康检查地址 | `config-tail.yaml`，对应的配置项在 `gateways/mihomo.yaml` 的 `environment` |
| 支持新的分享链接协议 | `validate-upstream.sh` 的 `LINK_SCHEMES` 和 `link_host`（mihomo 本身要支持该协议的链接） |
| 新增一个 AI 工具 | `aibox` 的 `KNOWN_TOOLS`；`aibox-setup` 的 `case`；`cmd_agent` 的 `--yolo` 映射；`cmd_completion` 和 `usage_all` |
| 容器里预装的软件 | `images/workspace/Dockerfile`（用户临时增加用 `AIBOX_EXTRA_PACKAGES`） |
| 新的配置项 | `config.example/aibox.env` 加默认值和注释，再在 `compose.yaml` 或 `gateways/*.yaml` 传给容器 |
| 新的非交互配置命令 | `cmd_config` 加子命令，写入逻辑放进共用函数，并更新 `config_usage`、`docs/GUIDE.md`、`AGENTS.md` |
| 新的体检项 | `cmd_doctor`，用 `ok` / `bad` 记录 |
| 新的报错及处理方法 | 报错文字写在代码里，处理方法写进 `docs/GUIDE.md` 第 3 节的表格 |
| shell 提示符、欢迎信息、AI 工具以 exec 运行 | `images/workspace/rootfs/etc/aibox/bashrc` |

## 6. 约束与自查

- `aibox` 必须兼容 bash 3.2：不用关联数组、`${var,,}`、`mapfile`；不要在 `$(...)` 里判断 `[ -t 1 ]`；变量后面紧跟中文或全角标点时必须写成 `${var}`（macOS 的 bash 3.2 在 UTF-8 环境下会把后面的字节当成变量名的一部分，`set -u` 下直接报 unbound variable）。
- `images/mihomo-gateway/*.sh` 必须是 POSIX sh（busybox）。
- 交互逻辑和非交互逻辑共用写入函数，修改时两边一起考虑。

```bash
tests/run.sh --quick     # 静态检查 + 校验器（几秒钟，不需要 Docker）
tests/run.sh             # 另外在 bash 3.2 / 4.4 / 5.2 下跑全部非交互命令和交互流程（需要 Docker）
./aibox up && ./aibox doctor --full   # 修改网关、防火墙或 mihomo 配置模板后
```

| 测试文件 | 内容 |
|---|---|
| `tests/lint.sh` | 语法、bash 4+ 专有语法、变量紧跟中文、在 `$(...)` 里判断终端、GNU 专有选项 |
| `tests/validator.sh` | 严格出口校验器：YAML 样例、各协议分享链接的地址解析、订阅内容概括、`--server` |
| `tests/cli.sh` | 约 100 条非交互命令的返回码、输出和生成的文件 |
| `tests/compare.py` | 对比的脱敏、只读、失败/旧环境、实际权限与挂载判定；由 cli.sh 在各 bash 版本下执行 |
| `tests/workspace-privacy.sh` | 用独立测试镜像、无网络临时容器验证 sysfs 遮挡、机器标识稳定性及 Node/Python/Git/tmux/C 兼容；不使用真实项目或 home |
| `tests/interactive.py` | 用伪终端驱动向导各分支和 `install` |
| `tests/Dockerfile` | 测试镜像：指定版本的 bash，并换成非 GNU 的 awk / sed / grep，接近 macOS |

新增命令或修改报错时，在 `tests/cli.sh` 或 `tests/interactive.py` 里补上对应的用例。
