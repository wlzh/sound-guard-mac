# v0.4.4 技术设计

## 零音量守望状态机

`GuardController.refresh` 在恢复记录失效复核之后新增两步：`maintainZeroWatch` 与 `armImplicitRecovery`。守望条件：恢复记录为空、保护与恢复提醒开启、当前设备在名单、可控、未静音、音量为 0，且未被抑制。满足即构造隐式 `RecoveryContext`（`implicit: true`），与自动归零凭据共用同一恢复链路：`recovering` 分支的播放进程/信号检测、有声确认计时、例外名单过滤、同段去重、`onRecoveryPrompt` 弹窗与 `restoreVolume` 写前复核完全一致，不新增任何写入路径。恢复提醒关闭时守望完全不启用，与既有行为一致。

守望凭据与自动归零凭据使用同一套失效复核：设备、路由、非零音量、静音、可控性或名单变化即作废；区别仅在来源与建议音量，不再有“作废后停在音量 0 即永久休眠”的路径。睡眠唤醒、看门狗重建、写入故障恢复与应用重启后，下一个 `refresh`（事件或 30 秒心跳驱动）按同样条件重新武装。

## 建议音量与抑制

`AudioService` 新增只读 `volumeSnapshot(for:)`（逐声道标量读取）。`refresh` 在音量大于 0 时按设备 UID 记忆最近快照（`try?`，失败静默跳过），路由变化不丢失记忆。隐式凭据优先使用记忆快照；缺失时以 `Preferences.implicitWatchRestoreVolume`（0.25）按快照通道数构造建议值，弹窗经 `RecoveryPrompt.originalVolumeKnown` 标注“未记录”。

抑制标记按 `selectionID` 记录：`keepSilent` 与 `zeroNow` 成功后设置；`refresh` 发现该设备音量离开 0、静音或设备变化即清除。抑制只在内存中，不写入偏好，不跨设备传播；“重新核对”不恢复已确认的保持静音。键盘调回 0 与记录失效不可区分，按新守望处理。

## 可观测性

每次隐式武装记录一条 `implicitWatch` 诊断（`implicitWatchLogged` 标记保证同一轮守望只记一条，避免持续启动失败冲刷 64 条历史）；事件不含设备标识、应用名或音量数值。`exportStatus` 新增 `recoveryImplicit` 与 `zeroWatchSuppressed`；菜单零音量子状态文案相应三分。`IdlePolicy`、偏好 Codable 格式、CLI 参数与权限声明不变；其他 `AudioService` 实现只需补齐快照读取。
