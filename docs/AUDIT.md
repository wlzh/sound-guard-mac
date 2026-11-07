# 全链路审计记录

v0.4.7 / build 23，2026-11-07。工作区起点为干净 main（v0.4.6 / build 22 已发），原基线 129 项测试 / 670 次断言通过。本轮由用户实机截图反馈驱动：v0.4.6 运行中的恢复提示仍显示“某个 App 已开始播放”且无“不再提醒”链接。

## 实机证据与根因

截图证据（v0.4.6 运行时）：提示为“某个 App 已开始播放”、无链接。代码证据：`SystemAudio.playbackProcess(pid:)` 仅经 NSRunningApplication/LaunchServices 解析；无 bundle 的进程（命令行工具、后台守护、特殊 helper）解析失败返回裸 PID，提示端 `appDescriptor` 因无身份而隐藏链接、回退通用文案。用户偏好例外名单已含 MuMu、WeChat、Arc 等 bundle App，剩余触发源即 bundle 外进程——v0.4.6 的能力对该场景不可见。

## 范围与结果

| 链路 | 审查与处理 |
| --- | --- |
| 进程解析 | 两级：LaunchServices bundle 身份（不变）→ proc_pidpath 可执行路径回退；名称分别为 localizedName/bundle 名/路径末段 |
| 身份匹配 | 路径身份走既有 `path:<标准化路径>` 与 `bundlePath == candidate` 分支，PID 不参与身份，重启仍匹配 |
| 提示端 | 零改动：v0.4.6 的 appDescriptor 在有路径时即显示名称与“不再提醒”链接 |
| 例外链路 | 复用 ignoredRecoveryApps 去重、展示与移除；路径型条目以进程名显示 |
| 安全回退 | PID 非正、进程退出、proc_pidpath 失败均回退裸 PID（“某个 App”，无链接），不崩溃不误报 |
| 隐私 | 诊断事件不含进程路径或名称；`--status` 字段不变 |
| 文档 → 版本 | 同步 0.4.7 / build 23 全套入口；构建与安装分离 |

## 自动化证据

新增 1 项裸进程身份回归（MeterTests 套件，以测试进程自身 PID 验证解析与路径身份匹配），合计 130 项 / 674 次断言通过；原生 UI 自检新增路径型来源（/usr/bin/afplay 合成数据）提示检查并通过。实机以 `afplay`（无 bundle 裸进程）触发提示并截屏核对。最终完整门禁和发行验证结果记录在[测试报告](TESTING.md)。

## 保留边界

- 路径例外按可执行文件匹配：升级、搬移后路径变化需重新加入（与 bundlePath 身份既有边界一致）。
- proc_pidpath 对已退出进程返回空，维持“某个 App”回退；此时仍可走设置入口。
- 用户截图的具体触发源待复现确认（A27）：需该源再次播放时核对名称显示。
- 本地构建、安装、Git 提交、远端 CI 和公开 Release 是独立交付门禁，不相互推导；无 Developer ID/公证。
