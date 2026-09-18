# v0.3.7 技术设计

## 上游与状态

手动 retry 调用 `restartAudio(preservingRecovery: true)`；保留 RecoveryContext 的设备、原音量、ID 和 playbackWasActive，只清除 candidateSince。唤醒不是手动重试，仍采用清空路径。pending 阶段 `recoveryPromptID` 对外为 nil，关闭旧浮层；实际内存记录由 `recoveryContextRetained` 诊断，不额外持久化。

## 安全与下游

冷却结束通过既有 refresh 核验 ID、UID/路由、零音量、静音、可控性及保护名单后建立监听。restoreVolume 增加 pending 拒绝条件。关闭功能、切换检测模式、睡眠、退出和故障继续撤销记录。generation 取消旧确认任务，同段播放去重位保留，避免重试重复提示。

`Playback.starting` 表示没有首批样本。非零保护映射到 `checkingSignal` 而不计时；恢复分支取消候选但不改变同段去重位。首次有效数字静音立即为 idle，非零样本仍使用原有摘要与 600 ms 防抖。新增状态仅影响纯判断与展示，不改变 Tap 配置、权限、调度频率或偏好 JSON。

## 验证

新增 13 项测试覆盖保留/恢复、严格启动、候选重置、同段去重、已消费及手动零、设备/音量/路由/静音/名单/可控性/断开、配置/退出/睡眠及启动/监听/读取故障矩阵。实机结果和未覆盖项见测试报告，不将注入服务等同 HAL 硬件验收。
