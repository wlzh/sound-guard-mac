# v0.4.0 技术设计

Preferences 新增 `ignoredRecoveryApps: [IgnoredRecoveryApp]`，使用 Bundle ID 优先、标准化 `.app` 路径回退的身份，不保存 PID。旧 preferences.v1 缺少字段时解码为空。

SystemAudio 在 Core Audio 进程 PID 可用时映射 NSRunningApplication，并沿 helper 的 `.app` 路径提升到 regular App。GuardController 在恢复阶段统一过滤：所有已识别进程都命中名单才抑制提示；混合、未知、严格模式无进程身份均保守提示。自动归零、Signal Tap、恢复写入复核和权限边界不变。

AppKit 设置页复用现有 UserDefaults/save/configure；当前进程添加使用播放进程快照，Applications 添加使用 NSOpenPanel。不新增权限或后台服务。
