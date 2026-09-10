# 安装与卸载

v0.1.0 / build 1，开发预览；macOS 14.2+，Universal arm64/x86_64。当前本机验证平台 macOS 15.6 / Apple Silicon，其他平台需实机验证。

## 安装

从获授权的 [私有 Release](https://github.com/wlzh/sound-guard-mac/releases) 下载 `SoundGuard-v0.1.0-macos-universal.zip` 和 SHA256.txt，在同一目录执行 `shasum -a 256 -c SHA256.txt`。解压后把 Sound Guard.app 放入 `/Applications` 或 `~/Applications` 再打开。

当前 ad-hoc 签名，没有 Apple Developer ID 和公证。若 macOS 拦截，在确认来源和校验和后按系统“隐私与安全性”提供的允许打开流程操作；不建议全局关闭 Gatekeeper。升级前退出旧实例，再替换 App，不同时运行两份。

源码构建：在项目根运行 `zsh scripts/test-all.sh` 和 `zsh scripts/build-app.sh`，产物位于 `dist/Sound Guard.app`。默认模式无需录音权限；严格模式在非零音量启用后才会访问系统音频。

## 卸载

先在 App 设置中关闭登录启动，再从菜单退出，删除 App。偏好位于 macOS 用户偏好域 `uk.869hr.SoundGuard`，如需彻底清除可执行 `defaults delete uk.869hr.SoundGuard`。可删除 `~/Library/Caches/uk.869hr.SoundGuard` 的单实例锁目录。应用退出后锁自动释放，文件残留不代表后台仍在运行。

卸载不修改系统当前音量，不会恢复被归零前的数值。
