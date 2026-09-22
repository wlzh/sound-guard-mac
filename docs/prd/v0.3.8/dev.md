# v0.3.8 技术设计

VolumeSnapshot.restoring(toPercent:) 验证原始快照和目标范围。nil 返回精确快照；整数 1–100 将各通道按 value / maximum * target 缩放，保留零声道和比例。

GuardController.restoreVolume 新增可选 targetPercent 参数，默认 nil 兼容既有调用。设备、路由、音量、静音、可控性、名单和恢复上下文复核后，沿用 SystemAudio.restore 的逐通道写入、回读及失败归零。AudioService 协议未变化。

RecoveryPromptPresenter.onRestore 改为 (RecoveryPrompt, Int?)，主程序传递选择；弹窗关闭前捕获目标，关闭时释放控件和选择。RecoveryVolumeSlider 使用原生 mouseDown tracking，defer 结束暂停，UUID 检查阻止旧拖动污染新提示。单调时钟替代墙钟，计时测试注入 now；计时器仍每秒一次。选择不持久化，无偏好迁移、权限或采集变更。

接口影响：新增快照变换方法；修改恢复回调和控制器可选参数；无删除接口。核心测试覆盖比例、非法值、精度、上下文消费和外部变化；UI 测试覆盖边界、取整、重置、按钮、暂停与关闭。
