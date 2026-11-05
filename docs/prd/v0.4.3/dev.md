# v0.4.3 技术设计

## 故障分类与竞态重读

`AudioErrorClassification` 新增 `staleObjectError`（'who?'，0x77686F3F）：HAL 对已消失对象（典型为设备切换瞬间过期的默认设备 ID）的应答，与既有 BadObject/NotReady 同列临时错误。`SystemAudio.currentDevice` 在检查默认设备抛出可重试错误时重读一次 `DefaultOutputDevice`，ID 变化则检查新设备并注册监听；重读失败或错误不可重试时原样上抛。诊断日志三次实机故障均为该竞态，重读在多数情况下就地恢复，不进入故障态。

## 心跳与看门狗

控制器新增自持 `DispatchSourceTimer`（主队列，30 秒周期，1 秒余量），不复用单槽 `GuardScheduler`，因此永不取消或推迟空闲截止、恢复确认或重建冷却等既有调度。心跳回调按序检查：未运行、睡眠、暂停、写入故障锁或冷却中直接返回；存在检测故障锁时执行看门狗重建（记录 watchdogRetry、清检测故障与重试预算、`restartAudio(after: 0)`，等效自动"重新核对"）；否则执行一次 `refresh()` 周期复核。

周期复核与事件驱动复核走同一路径，保持设备身份、路由、静音、零音量与播放状态的全部安全复核；空闲截止按绝对时间由策略保留，恢复确认候选与截止同样保留，不重复弹窗。通知静默丢失（监听失效、无回调）时，音量回升、播放停止等变化最迟 30 秒被发现。

写入故障锁不参与自动恢复：写后错误、恢复写入错误仍要求人工核对，心跳在此期间为无操作。`start`/`stop` 启停心跳，`deinit` 兜底释放。

## 诊断节流与可观测性

看门狗首次重建某故障消息时记录 watchdogRetry；同一消息持续时每 20 次重建留一条轨迹，期间 `fail` 的重复 fault 与 automaticRetry 记录改为仅静默刷新 `lastFault`，不冲刷 64 条事件历史。故障消息变化或 `markHealthy`（连续健康）后恢复完整记录。`exportStatus` 新增 `sustainedFault` 与 `automaticRecoveryArmed`；菜单故障详情与工具提示追加"将自动重试"。

## 上下游影响

偏好 Codable 格式、设备名单、恢复提示模型、CLI 参数与权限声明不变。心跳周期复核只读设备属性与播放状态，不写音量；严格检测 Tap 的启停仍由 `setMonitoring` 决定。其他 `AudioService` 实现无需变更；心跳行为由注入时钟与直接调用 `heartbeat()` 的回归覆盖。
