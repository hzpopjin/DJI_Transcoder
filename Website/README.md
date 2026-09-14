# Pocket Helper 静态介绍与隐私政策

`index.html` 是完整页面，`app-icon.png` 是本地图片。无 JavaScript、外部字体、统计组件或构建依赖；两份文件一起放在静态网站目录即可访问。页面可直接从本地打开。

用户确认的信息：

- 公司：吉尔利斯文化传媒（杭州）有限公司
- 支持与隐私邮箱：service@randomdance.cn
- 公开网址：暂留空，尚未部署

## 预览

在项目根目录执行：

```sh
python3 -m http.server 8765 --bind 127.0.0.1 --directory Website
```

浏览器打开 `http://127.0.0.1:8765/`。使用 `#privacy` 直达隐私政策，`#support` 直达使用帮助。

## App 内离线政策

政策正文以本页为唯一编辑源。修改后，在项目根目录运行：

```sh
python3 Website/sync_privacy.py
```

脚本生成 `Pocket Helper/{en,zh-Hans,zh-Hant}.lproj/PrivacyPolicy.html`，保留相同政策、排版与联系信息，移除介绍部分和图片依赖。App 的“设置 → 关于 → 隐私政策”离线显示此文件。

## 部署时

只需发布 `index.html` 和 `app-icon.png`，不需要上传同步脚本或 App 文件。使用公开可访问的 HTTPS 静态托管，不要求访客登录。

取得实际网址后，再填写 App Store Connect 的隐私政策 URL 与支持 URL，并核对托管方实际日志及保留方式与“本网页”条款一致。当前页面没有伪造域名或 App Store 下载链接，也未对外发布。

页面已检查桌面和 390px 手机布局、图片载入和内部锚点。App 构建、测试记录见项目开发文档和上架检查报告。
