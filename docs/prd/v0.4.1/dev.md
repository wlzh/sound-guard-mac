# v0.4.1 技术设计

`IgnoredRecoveryApp.matches` 先进行 Bundle ID 精确匹配，再比较标准化包路径。除精确路径外，仅当播放进程的 App 路径位于已保存父 `.app/Contents/` 边界内且自身以 `.app` 结尾时视为嵌套匹配。该规则复用 v0.4.0 已保存的 `bundlePath`，无需新增字段或偏好迁移；PID 和显示名称仍不参与持久身份判断。

`PlaybackScreenLocator` 从 `NSWorkspace.runningApplications` 生成稳定描述，排除当前进程、已终止和无可识别包身份的项目，按身份去重并按本地化名称排序。设置页复用既有选择弹窗和合并去重逻辑，不新增权限、轮询或后台服务。Core Audio 枚举、自动归零、Signal Tap、混合播放安全默认和恢复写入复核均不变。

测试新增 MuMu 形式的父/子 Bundle 样本，同时验证相似路径和非 `.app` helper 不会误匹配；原生 UI 自测验证新增入口存在且偏好隔离保持不变。
