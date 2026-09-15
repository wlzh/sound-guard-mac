# v0.3.4 技术设计

## 上游与偏好

`Preferences.recoveryPlaybackConfirmationMilliseconds` 使用整数毫秒保存，默认 `2000`，有效范围 `500...30000`，解码时兼容旧版 JSON。计算属性转换为单调时钟使用的秒值。该字段只影响自动归零后恢复提示的播放候选，不影响空闲归零、弹窗停留或音量快照。

## 状态机

`RecoveryContext` 新增可选 `candidateSince`。发现播放且当前段尚未提示时记录单调时间；达到 `candidateSince + confirmation` 才创建 `RecoveryPrompt`。播放停止会同时清除候选并允许下一次播放重新确认。修改确认时长会保留恢复凭据和已提示状态，但取消未完成候选并从配置变更时重新计时。

默认模式依靠 Core Audio 进程事件启动候选，并通过已有 `GuardScheduler` 建立一个带 100 毫秒容差的单次截止任务。所有 `refresh` 都递增 generation 并取消旧任务，过期回调必须同时匹配 generation 才能执行。严格模式继续由现有 Signal Tap 每 0.5 秒触发刷新；短于 600 毫秒的静音由 `SignalHealth` 保持为播放，达到空闲后控制器清除候选。

## 下游与资源

确认完成后沿用 v0.3.3 的恢复浮层和互斥按钮语义。`recoveryConfirmationActive` 只读状态支持菜单提示和 `--status` 诊断。默认模式没有新增轮询，严格模式没有新增 Tap 或提高检查频率；额外常驻状态仅为一个可选时间戳。设备、音量、路由、睡眠、关闭功能、显式选择和故障仍按既有规则撤销上下文并释放资源。
