# Qrcode — 二维码生成器桌面应用

基于 Native SDK 构建的 Windows 桌面应用，使用 Zig 编写，WebView2 渲染。

## 依赖

- [Zig 0.16.0](https://ziglang.org/download/) — 编译器
- [@native-sdk/cli](https://www.npmjs.com/package/@native-sdk/cli) — Native SDK（构建时需要作为 Zig 依赖）

## 安装

```sh
# 安装 Native SDK（全局）
npm install -g @native-sdk/cli

# 创建 _sdk 链接（项目根目录执行）
New-Item -ItemType Junction -Path _sdk -Target (Get-Item (Get-Command native).Source).Directory.Parent.FullName -Force
```

## 编译

```sh
zig build
```

输出在 `.native/build/zig-out/bin/qrcode.exe`

## 推送

仅允许 HTTPS，使用 Personal Access Token：

```sh
git remote set-url origin https://<token>@github.com/doubleyeh/qrcode.git
git push
```

## 构建说明（CI）

CI 流程（.github/workflows/build.yml）：
1. `actions/checkout@v4`
2. `mlugg/setup-zig@v1` — 安装 Zig 0.16.0
3. `npm install @native-sdk/cli`
4. 创建 `_sdk` junction
5. `zig build`（在 `.native/build/` 目录）
6. 上传 `zig-out/bin/` 为构建产物
