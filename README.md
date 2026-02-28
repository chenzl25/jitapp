# FanyiApp (macOS)

一个可全局使用的划词翻译菜单栏应用，支持 OpenAI 兼容 Chat 接口（可直接填 DeepSeek key）。

## 功能

- 全局热键翻译，默认 `Option + D`
- 热键可配置（修饰键 + 单个字母/数字）
- 划词后按热键触发翻译
- 配置项：`Base URL / API Key / Model / 目标语言`
- 菜单栏开关开机自启

## 本地开发运行

```bash
swift run
```

## 打包为可双击安装的 .app / .dmg

```bash
./scripts/release.sh
```

产物位置：

- `dist/Fanyi.app`
- `dist/Fanyi.dmg`

也可分步执行：

```bash
./scripts/build_app.sh
./scripts/package_dmg.sh
```

## 签名

默认使用 ad-hoc 签名（本机可运行）。

如果你有开发者证书，可在构建时指定：

```bash
SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" ./scripts/build_app.sh
```

## 首次使用

1. 双击打开 `dist/Fanyi.app`
2. 菜单栏点 `译 -> 设置` 填入 API 参数
3. 在任意应用中选中文字
4. 按热键（默认 `Option + D`）翻译

## 权限与系统设置

为了全局读取选中文本，请在 macOS 开启：

- `系统设置 -> 隐私与安全性 -> 辅助功能`

为了开机自启生效，若菜单显示“等待系统批准”，请前往：

- `系统设置 -> 通用 -> 登录项`

## 脚本说明

- `scripts/generate_icon.swift`: 生成 1024 PNG 图标
- `scripts/make_icon.sh`: 生成 `.icns`
- `scripts/build_app.sh`: 构建并组装 `.app`
- `scripts/sign_app.sh`: 签名与校验
- `scripts/package_dmg.sh`: 打包 `.dmg`
- `scripts/release.sh`: 一键构建 + 打包
