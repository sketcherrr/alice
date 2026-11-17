# Alice 项目介绍页

奶油白与浅海蓝的静态介绍页，复用应用原始角色及动画图集，包含摸摸/喝茶/睡眠预览、三种性格示例、功能与平台状态、Mac 测试版入口和常见问题。网页不收集 Key，不调用 AI，不上传数据。

## 本地预览

```sh
python3 website/build.py
python3 -m http.server 8080 --directory dist/site
```

打开 `http://localhost:8080`。页面不依赖 npm、CDN、第三方字体或服务端；也可以直接打开 `dist/site/index.html`。

## GitHub Pages

仓库 Settings → Pages → Build and deployment → Source 选择 **GitHub Actions**。这是仓库首次开启 Pages 时的一次性设置。

`.github/workflows/pages.yml` 会构建页面，只上传 `dist/site`，然后发布到 GitHub Pages。之后修改 `website/` 或角色素材并提交到 `main`，页面会自动更新。也可在 Actions → Alice website 手动运行。

预期地址：`https://sketcherrr.github.io/alice/`。只有部署成功并验证 HTTP 响应后才能认为已上线。

角色动画遵循系统减少动态效果的设置，支持手动暂停，滚出视口或切到后台后停止动画计时。加载失败时保留原始立绘；关闭 JavaScript 时介绍内容、下载链接、FAQ 仍可使用。相处小剧场与首页互动均明确标注为预设示例。

Mac 下载入口指向构建列表，避免硬编码 14 天后过期的 artifact。平台进度和 FAQ 随产品实现更新。
