# v0.3.1 技术设计

## 根因

严格模式使用 Signal Tap 将全零样本判为空闲，但 v0.3.0 在归零后统一切换到 `kAudioProcessPropertyIsRunningOutput`。进程状态不能表达信号是否为全零，导致同一静音流被当作新的播放沿。

## 修正

`GuardController` 在恢复等待阶段按用户检测模式选择数据源。默认模式继续使用 `playingProcesses`；严格模式保持 `signal=true` 并以 `playback(..., signal: true)` 的静音到有声沿触发。提示时仍单独枚举 PID 用于最佳努力的窗口定位，PID 不参与是否有声的判断。

已有 `SystemAudio.setMonitoring` 在设备不变且 Signal Tap 已存在时不会重建 Tap，因此归零前后的信号健康状态连续，也不会产生新的启动宽限误报。严格检测异常时撤销只存在内存中的恢复上下文并释放监听，音量保持 0，主保护的归零成功不改为 fault。

## 上下游

上游仍是 Core Audio Process Tap、输出进程属性和设备属性。下游恢复面板、辅助功能窗口定位、逐通道恢复、状态导出和设置结构均不变。性能文档区分默认零音量事件监听与用户主动开启的严格信号监听。

## 测试

注入测试覆盖“静音进程持续存在但信号 idle”“随后信号 playing”和“恢复阶段信号读取失败”。统一测试、Universal 构建、签名、CI 与发布附件需重新验证；真实系统音频权限及播放器端到端保留为人工验收。
