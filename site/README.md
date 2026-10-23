# aibox 宣传站

aibox 的单页宣传网站：中文主页 + 英文版，纯静态，无构建步骤、无依赖、无追踪脚本，也不请求任何第三方资源（字体用系统字体）。

```
site/
├── index.html        中文主页
├── en/index.html     英文版
├── assets/site.css   样式（颜色都在 :root 里，深色/浅色跟随系统）
├── assets/site.js    顶栏、复制按钮、首屏终端演示
├── favicon.svg
├── og.svg            分享卡片图的源文件（需导出为 og.png，见下文）
├── robots.txt
└── nextjs/sync.sh    接入已有 Next.js 站点用的同步脚本
```

## 本地预览

任选其一，然后打开 http://localhost:8000/ ：

```bash
cd site && python3 -m http.server 8000
```

```bash
npx serve site -l 8000
```

直接双击 `index.html` 也能看，但复制按钮在 `file://` 下会改用兼容方式。

## 上线前要替换的占位符

| 占位符 | 位置 | 替换为 |
|---|---|---|
| `OWNER` | 两个页面里所有 `github.com/OWNER/aibox` 链接 | GitHub 用户名或组织名 |
| `SITE_DOMAIN` | canonical、hreflang、og:url | 网站域名（含子路径，例如 `owner.github.io/aibox`） |
| `LICENSE_NAME` | 页脚 | 协议名，例如 `MIT`；仓库里也需要补一个 `LICENSE` 文件 |

一次性替换（GNU sed；macOS 上把 `sed -i` 换成 `sed -i ''`）：

```bash
cd site
sed -i 's#OWNER#your-name#g; s#SITE_DOMAIN#aibox.example.com#g; s#LICENSE_NAME#MIT#g' index.html en/index.html
```

## 分享卡片图（og.png）

社交平台大多不支持 SVG 预览图。用任意工具把 `og.svg` 导出成 1200×630 的 `og.png` 放在 `site/` 下，再取消两个页面 `<head>` 里 `og:image` 和 `twitter:card` 两行的注释。例如：

```bash
rsvg-convert -w 1200 -h 630 site/og.svg -o site/og.png
```

## 部署

站点就是 `site/` 目录本身，任何静态托管都可以。

**GitHub Pages**：仓库 Settings → Pages → Source 选 “GitHub Actions”，添加 `.github/workflows/pages.yml`：

```yaml
name: pages
on:
  push:
    branches: [main]
    paths: [site/**]
  workflow_dispatch:
permissions:
  contents: read
  pages: write
  id-token: write
jobs:
  deploy:
    runs-on: ubuntu-latest
    environment: github-pages
    steps:
      - uses: actions/checkout@v4
      - uses: actions/upload-pages-artifact@v3
        with:
          path: site
      - uses: actions/deploy-pages@v4
```

**Cloudflare Pages**：连接仓库，构建命令留空，输出目录填 `site`。

**Vercel**：导入仓库，Framework 选 “Other”，Root Directory 填 `site`，构建命令留空。

**Netlify**：Base directory 填 `site`，Publish directory 填 `site`，构建命令留空。

## 接入已有的 Next.js 站点

页面以独立子页面的形式挂在 Next.js 站点下（默认 `/aibox` 和 `/aibox/en`）。它保持静态 HTML，自带 CSS 和 JS，不经过站点的 layout，所以不会受全局样式影响，也不会影响站点其他页面。

**1. 复制页面到 Next.js 项目**（在本仓库根目录运行；会覆盖 `public/aibox/`）：

```bash
bash site/nextjs/sync.sh /path/to/your-next-app
```

脚本把文件复制到 `public/aibox/`，并把页面里的相对路径改成 `/aibox/...`。想换路径用 `--base /tools/aibox`；想顺便填上域名用 `--domain example.com`。`site/` 本身不会被修改，以后改了内容重新运行一次即可。

**2. 在 `next.config.ts`（或 `.js` / `.mjs`）里加 rewrites：**

```ts
const nextConfig = {
  // ……原有配置
  async rewrites() {
    return {
      beforeFiles: [
        { source: '/aibox', destination: '/aibox/index.html' },
        { source: '/aibox/en', destination: '/aibox/en/index.html' },
      ],
    };
  },
};
```

如果原来已有 `rewrites()`：它返回数组时，那个数组相当于 `afterFiles`，改成 `{ beforeFiles: [上面两条], afterFiles: [原数组] }`；返回对象时，把两条加进 `beforeFiles`。

**3. 运行：**

```bash
cd /path/to/your-next-app
npm run dev
```

打开 http://localhost:3000/aibox 。

已在 Next.js 16.4 新项目里验证过：开发模式和 `next build && next start` 下中英文页面、语言切换、锚点跳转、样式和脚本都正常，没有 404 和脚本错误。

注意：

- 站点设置了 `basePath`（比如 `/blog`）时，用 `--base /blog/aibox` 运行脚本，rewrites 里仍写 `/aibox`。
- 站点有 middleware（比如做多语言跳转或登录拦截）时，要在 `matcher` 里排除 `/aibox`，否则页面可能被重定向。
- 站点用 `output: 'export'` 静态导出时，rewrites 不生效；导出目录里 `aibox/index.html` 由静态托管直接提供，访问 `/aibox/` 即可。
- 想在站点导航里加入口，用普通链接 `<a href="/aibox">`。它是静态页，不是 Next.js 路由，用 `next/link` 没有好处，只会多一次失败的客户端跳转。

## 修改内容时注意

- 两个页面结构相同，改一处时记得同步另一处。
- 页面上的事实以仓库 `README.md`、`docs/` 和 `AGENTS.md` 为准。未实测的环境（真实 Mac、SELinux、rootless Docker）不要写成“已验证”。
- 终端演示里的出口 IP 都是文档保留地址（203.0.113.x、198.51.100.x），换成真实录屏前先遮掉 IP 和订阅链接。
- 首屏终端动画的脚本在页面里的 `<script type="application/json" id="demo-script">`，`<pre id="demo">` 里是关闭动效或没有 JS 时显示的最终画面，两者要一致。
- 不要引入 Google Fonts、统计脚本等第三方资源；页脚写了“不请求第三方资源”。
