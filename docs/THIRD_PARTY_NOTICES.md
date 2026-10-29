# 第三方软件与许可

[文档目录](README.md) · [aibox 许可](../LICENSE) · [架构](ARCHITECTURE.md)

aibox 的权利保留声明只覆盖著作权人拥有权利的原创内容，不对第三方代码、软件包、镜像、商标或界面重新授权。主要上游如下；表中链接指向各项目自身的许可或说明。

| 组件 | 本项目中的关系 | 上游许可 / 说明 |
|---|---|---|
| mihomo | 代理网关镜像中使用上游可执行程序，Dockerfile 当前默认 v1.19.33 | [GNU GPL v3 文本](https://github.com/MetaCubeX/mihomo/blob/v1.19.33/LICENSE) |
| Gluetun | VPN 模式使用上游镜像，配置默认 v3.41.3 | [MIT](https://github.com/qdm12/gluetun/blob/v3.41.3/LICENSE) |
| Node.js 24 | workspace 基础镜像中的运行时 | [Node.js 许可及其依赖声明](https://github.com/nodejs/node/blob/v24.x/LICENSE) |
| Debian 与系统软件包 | workspace 系统、开发工具和它们的依赖 | 各包分别授权，见 [Debian 许可资料](https://www.debian.org/legal/licenses/) 和镜像内各包的 copyright 文件 |
| Alpine 与系统软件包 | 代理网关系统及网络工具 | 各包分别授权，见 [Alpine 包信息](https://pkgs.alpinelinux.org/) 和对应包的上游声明 |
| Claude Code | 用户首次使用时由上游安装器下载，不预装进工作镜像 | [上游许可声明](https://github.com/anthropics/claude-code/blob/main/LICENSE.md)及适用的 Anthropic 服务条款 |
| Codex CLI | 用户首次使用时下载上游 CLI | [Apache-2.0](https://github.com/openai/codex/blob/main/LICENSE)；账号服务另受服务方条款约束 |

这份表是主要组件的导航，不代替镜像里所有软件包的完整许可证清单。Docker、Compose、终端、VPN 服务和 AI 账号等外部产品，也继续受各自的许可与服务条款约束。

## 使用或分发时

- 取得 aibox 的授权，不会替代第三方要求；第三方的开放许可也不会自动授权复制 aibox 的原创部分。
- 如另行获准分发包含第三方程序的镜像或安装包，应保留相应版权、许可文本，并履行该组件适用的源代码提供等义务。
- 不得删除或用本项目的专有许可替换上游许可证。可分离的第三方软件仍保留其原有权利。
- 演示中出现的 Claude Code 界面、品牌和其他第三方内容，不因截图或录屏转为 aibox 所有；aibox 不代表这些服务方，也不提供其账号、授权或承诺。

其他可选工具及依赖以实际安装版本和上游随附条款为准。
