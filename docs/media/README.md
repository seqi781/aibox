# aibox init → aibox claude

真实交互录制，只输入两个命令：

1. `aibox init`：选择网络方式，粘贴节点，选择筛选条件和项目目录，确认读写权限，再确认启动。
2. `aibox claude`：首次自动安装 Claude Code，选择显示主题，停在官方首次登录选择页。

[![aibox init 配置完成与启动确认](cover.png)](aibox-init-claude.mp4)

| 文件 | 用途 |
|---|---|
| [MP4 视频](aibox-init-claude.mp4) | 1920 × 1080，H.264，无音轨，适合演示和宣传分享 |
| [循环 GIF](aibox-init-claude.gif) | 用于 GitHub README、文章和支持动图的页面 |
| [封面](cover.png) | 向导中的配置摘要与启动确认 |
| [配置截图](configuration.png) | 项目目录选择与读写权限确认 |
| [Claude Code 启动截图](claude-start.png) | 官方首次登录入口 |
| [脱敏录制数据](terminal-recording.json) | 两个命令及向导的真实输出、输入和相对时间 |

录制前已安装并启动 Docker，且 `aibox` 已在 PATH 中。向导与 Claude Code 均真实运行；节点粘贴区间已隐藏，公网 IP 使用文档示例地址替换，自动下载和启动等待经过加速。

目录配置使用新建的临时示例项目。为保护已有任务，演示采用独立的容器、数据卷和示例用户目录，没有改变向导、代理或防火墙逻辑。录制完成后清理演示环境。

没有登录个人账号或发起模型请求。Claude Code 主题页的代码预览来自官方 CLI。网络和风险提示保留在原始终端输出中；保护范围见 [架构与安全设计](../ARCHITECTURE.md)。
