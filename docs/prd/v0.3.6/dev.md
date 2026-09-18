# v0.3.6 技术设计

## 根因与上游

Apple SDK `AudioHardware.h` 定义 `kAudioAggregateDeviceTapAutoStartKey` 非零表示等待第一个 Tap 收到音频才启动。旧配置 true 与无播放仍需判断空闲的需求冲突，3 秒 `SignalHealth` 启动宽限到期后锁存故障。v0.3.5 的回收竞争推断不成立，延迟重建不能修正这个配置。

参考 [Apple 聚合设备配置](https://developer.apple.com/documentation/coreaudio/kaudioaggregatedevicetapautostartkey)。`TapConfiguration.aggregateProperties` 统一生成 private、单 Tap、AutoStart=false 配置，便于无硬件回归测试锁定行为。

## 下游与诊断

`recoveryEndReason` 记录检测失败、配置变化、设备变化或用户确认等退出原因；它不重新建立已撤销凭据，不绕过恢复前安全复核。此前未记录原因的退出不能事后推断为信号故障。

SignalHealth、IdlePolicy、写前复核、恢复提示及偏好协议保持不变。`signalHasFreshSamples` 只读最近有效缓冲时间与无效样本标记，要求小于 2 秒，未收到样本或检测已释放时为 false。`signalActive` 仍仅表示对象存在。

`--probe-signal-retry` 使用 App 单实例锁，要求已开启严格检测且音量为 0，重复三次启动检测、等待 5 秒、验证样本、释放所有监听，轮次间等待 3 秒。它不调用任何音量写入，不修改偏好，异常退出仍释放资源。此探针验证真实适配层，控制器冷却与取消语义另由注入测试覆盖。
