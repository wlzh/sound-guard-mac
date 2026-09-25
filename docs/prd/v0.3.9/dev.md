# v0.3.9 技术设计

GuardError 增加 retryable（默认 false）；HAL 对 bad-object/device/stream、not-running、not-ready、unspecified 分类为可重试，其余错误保守拒绝。SignalHealth 无回调/陈旧回调允许重试，错误时钟和无效样本不可重试。

GuardController 分离 writeFault 与 detectionFault。仅无写入故障且明确 retryable 时复用单个 GuardScheduler 调度 3/10/30 秒重建；pending 和 generation 阻止旧回调提前/重复启动。连续健康观察 60 秒后清预算，非每次 start 成功即清。睡眠停止音频服务，设置变化取消旧任务，人工 retry 清锁并记录此前状态；唤醒不会自动清除写入故障。

保留合法 RecoveryContext、原始快照和 playbackWasActive，清 candidateSince；refresh 完整核验身份、路由及状态。zero 成功即创建候选恢复快照，后续读取的临时失败不会丢掉已验证原值；最终仍须复核才能恢复。恢复写入异常进入安全锁定且不再次写入。

DiagnosticEvent Codable 记录 timestamp/kind/phase/message/attempt，消息限制 512 字符。DiagnosticJournal 主队列事件驱动，最多 64 条，载入超过 128 KiB 的文件忽略，原子写入后 chmod 0600，持久化失败吞掉但保留内存记录。无设备/进程标识或音频。main 在 controller.start 前接入 onDiagnostic；status 导出最近故障及重试状态，--diagnostics 只读缓存。UI 自测继续使用独立 UserDefaults。

接口新增：onDiagnostic、lastFault、automaticRetryCount/Pending、retryDeadline、DiagnosticJournal、AudioErrorClassification；修改 GuardError 构造器新增默认参数，无 AudioService 协议删除、偏好迁移或音频权限变化。上下游涉及 HAL/SignalHealth、Controller、AppDelegate、菜单和测试。

边界：同步 HAL API 不具备本版本实现的硬超时，退避不能中断阻塞的系统调用；禁止把本次修复等同于解决旧版实机探针阻塞。
