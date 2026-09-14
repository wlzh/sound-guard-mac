# v0.3.0 技术设计

## 核心状态与安全契约

Preferences 新增 recoveryPromptEnabled=false 与 recoveryPromptSeconds=60，并自定义向后兼容解码，防止旧 JSON 因新增非可选字段整体回到默认值。VolumeSnapshot 保存每个输出控制通道原值；RecoveryContext 仅在内存保存 UUID、归零后的设备快照、音量快照和播放沿状态。

GuardController 仍由主队列约束。自动归零成功且开关开启后，切换到 signal=false 的进程事件监听；从无播放到有播放时发出 RecoveryPrompt。同一连续播放只触发一次。手动归零、睡眠、设备/路由/静音/音量改变、关闭设置或退出会清除上下文。restoreVolume 只接受当前 UUID，并在写入前二次复核。

恢复提醒是辅助能力：零音量监听注册或播放 PID 枚举失败不得把成功归零改为 fault。主保护的读取、监听、归零失败仍保持原有 fail-closed 行为。

## 平台实现

SystemAudio 使用 kAudioHardwarePropertyProcessObjectList、kAudioProcessPropertyIsRunningOutput、kAudioProcessPropertyDevices 和 kAudioProcessPropertyPID 返回当前默认设备的播放进程。PID 不可读时仍返回 pid=0 以触发通用提示。恢复逐通道写入并逐通道回读；中途或复核失败尽量全部写回 0。

RecoveryPromptPresenter 使用非激活 NSPanel 和单个 1 秒 Timer。关闭时释放 Timer、窗口和请求。PlaybackScreenLocator 仅在触发提示时查询 AX focused/main window；Helper bundle 尝试映射到最外层 .app 的普通运行实例。AX 坐标与 CGDisplayBounds 求交，定位失败按 NSEvent.mouseLocation 回退。

## 上游影响

- IdlePolicy 的空闲计时和两种检测语义不变。
- AudioService 协议新增 playingProcesses、返回 VolumeSnapshot 的 zero、显式 restore。
- OutputDevice 稳定 selectionID 继续由 UID 与 route 组成。
- 旧 preferences.v1 键保持不变，以兼容已有安装。

## 下游影响

- MenuUI 新增“播放时提示恢复”状态项，复用设置页启用确认流程。
- SettingsUI 新增开关、时长单位和辅助功能状态；关闭时不请求权限。
- main 状态导出新增 recoveryMonitoringActive，zero 提示区分休眠与等待播放。
- UIChecks 生成恢复面板明暗图和恢复设置图；About 自动读取 v0.3.0/build 5。
- 构建、签名和打包脚本接口不变；发行 ZIP 文件名随 VERSION 更新。

## 数据、权限和资源

只持久化开关与提示秒数。设备、PID、窗口位置、音量快照和提示 UUID 不写磁盘、不上传。辅助功能只用于屏幕定位，不用于控制其他 App；拒绝不影响自动归零。恢复事件模式不申请系统音频捕获，只有独立的“静音流也计时”会使用 Signal Tap。

## 验证

GuardTests 覆盖设置迁移、边界、播放沿、失效、故障隔离和明确恢复。UIChecks 覆盖开关关闭态、非激活面板、品牌视图、按钮、无默认键、取消、超时及旧请求释放。真实 AX、多屏、播放器和硬件音量恢复必须单独人工验收。
