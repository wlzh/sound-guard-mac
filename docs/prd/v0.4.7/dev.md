# v0.4.7 技术设计

## 裸进程身份解析

`SystemAudio.playbackProcess(pid:)` 改为两级解析：先走既有 NSRunningApplication + 外层 App 解析，仅当应用有 bundleId 或 bundleURL 时采用（名称缺失回退 bundle 末段名）；否则用 `proc_pidpath` 读可执行文件真实路径（标准化后）作为 `bundlePath`，取路径末段为名称。两级都失败（PID 非正、进程已退出、路径读取失败）时维持裸 PID。方法改为 public，供回归测试以自身进程（SPM 裸可执行）验证解析与 `IgnoredRecoveryApp.matches` 的路径身份匹配。

路径身份走既有机制：`PlaybackProcess.identities` 生成 `path:<标准化路径>`，`IgnoredRecoveryApp.matches` 的 `bundlePath == candidate` 分支直接命中；例外去重、设置展示与移除复用 ignoredRecoveryApps 全链路。PID 从不参与身份，重启后 PID 变化不影响匹配；可执行文件路径变化（升级/搬移）后不再匹配，与 bundlePath 身份的既有边界一致。

提示端无改动：v0.4.6 的 `appDescriptor(for:)` 在 `bundlePath != nil` 时即构造描述符，因此路径型来源自动获得名称显示与“不再提醒”链接。

## 验证

新增 GuardTests 回归（MeterTests 套件）：以测试进程自身 PID 调用 `playbackProcess`，断言身份与名称非空、bundleId 缺失时路径身份可匹配。原生 UI 自检新增合成路径型来源（`/usr/bin/afplay`）的提示检查：显示“afplay 已开始播放”且链接存在。实机验证用 `afplay` 播放本机音频（无 bundle 裸进程）触发提示并截屏核对。
