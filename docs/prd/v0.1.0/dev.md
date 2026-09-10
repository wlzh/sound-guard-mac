# v0.1.0 技术开发文档

## 当前架构

已检查原工程基线（仅需求文档）及两个参考工程的 Swift Package/AppKit/构建脚本。新增 Swift 5.10 Package，部署目标 macOS 14.2，零第三方包。GuardCore 为纯策略与可注入协调器；GuardPlatform 封装 Core Audio；SoundGuard 为 AppKit 菜单和窗口；SignalMeter 为 C11 原子信号摘要。

## 状态与资源

`IdlePolicy` 根据单调时间、设备身份、音量、播放、配置和睡眠状态计算截止点。暂停、未知设备、未选设备、不支持、音量 0、静音和睡眠取消截止点。播放恢复取消计时，用户改音量/设备/设置给予完整等待时间。

`GuardController` 主队列串行协调，代数 token 使旧任务无效；`DeadlineScheduler` 仅一个单次 Dispatch 定时器。到期重新读取状态；适配层写前再复核 UID、运行 ID、路由、音量、静音及播放；写入 API 只有 `writeZero`，没有增加音量或恢复接口。失败锁定提示，点击重新核对/切换配置或唤醒后从头核验，防止错误忙循环。

`SystemAudio` 保留系统默认设备/设备表/音频服务变化监听，以及当前输出控制/路由通知。音量 0、静音、暂停、未选或异常时撤掉播放对象监听与 Tap。零音量不是退出进程，因此仍有基础内存和必要事件唤醒。

## 播放活动模式

监听 `kAudioHardwarePropertyProcessObjectList`，为进程对象监听 `kAudioProcessPropertyIsRunningOutput` 及 output scope 的 `kAudioProcessPropertyDevices`。事件发生才重读列表，判断是否有进程正在向当前输出设备播放。麦克风单独输入不算播放。通知丢失不能完全排除，到期有最终复核；不以设备笼统的 RunningSomewhere 混淆输入/输出。

## 静音流模式

仅用户启用且当前输出可控、允许、非零、未静音时，创建私有 Core Audio Process Tap 与私有 Aggregate Device。Tap 指向当前 UID 的单个输出流，muteBehavior 为 unmuted，不劫持/重定向播放，不设置系统默认设备。

仅支持 Float32 本机 PCM 和单输出流设备。实时回调只扫描至第一个非零样本、更新 C11 原子时间戳，不分配音频数组、不日志、不执行 UI。严格定义静音为数字全零，因此即使极小非零声音也保留输出。主队列每 0.5 秒检查摘要与健康，回调缺失超过 2 秒报错；启动给予最多 3 秒回调等待。任何新非零时间戳都会取消当前空闲，即使主队列曾延迟处理。

音量 0、模式关闭、设备变化、暂停、睡眠、退出时先停止 IO、销毁 IOProc、Aggregate、Tap，再释放 meter。权限由 macOS 处理，Info.plist 含 NSAudioCaptureUsageDescription。无公开的可靠“全零一定源自真静音”的证明；驱动或权限异常若仍交付全零样本，与真实静音可能不可区分，严格模式必须实机验收并保持默认关闭。

## 设备与音量

白名单以稳定 UID + 路由（数据源、插孔状态、输出终端类型）保存，不按名称匹配。默认内建扬声器需 built-in transport 且明确 speaker 来源/终端、未插耳机；未知路由不自动加入。外部设备仅当前默认输出时参与。

优先 master scalar；缺失则要求全部输出声道都有可写 scalar，逐声道归零并复核。无任何完整可写方案明确不支持，不使用替代设备或静音位假装音量数值归零。多个声道写入不具备系统事务性，失败可能部分归零；不会通过调高音量回滚。设备/其他 App 的并发改动不能完全原子化，写前后均核对并报告失败。

## 存储、UI、运行

`Preferences` Codable 保存 UserDefaults `preferences.v1`：enabled、minutes、detectSilentStream、protectBuiltIn、selectedDevices。输入校验与损坏数据安全默认。无数据库，无 HTTP 接口。单实例用用户缓存目录 flock，退出释放锁；登录启动用 SMAppService，默认不注册。

`--diagnose` 只读输出能力、音量、播放状态，不输出 UID 或设备名称。`--status` 通过本机分布式通知请求运行中 App 导出一次缓存状态，检查响应时间新鲜度；无后台状态文件轮询或持续写盘。导出的 status.json 权限 0600，不包含 UID/设备名称。

`--probe-zero N` 在当前为 0 时测量协调器驻留，不修改音量，状态变化则中止测量。`--verify-auto-zero --confirm-zero` 是明确会归零的实机验证命令，仅接受已手动开启的内建扬声器，临时等待 1 分钟、观察 75 秒，不持久化配置、不恢复音量。`--self-test-ui` 验证窗口构造/释放，`--render-previews DIR` 额外生成本地视图图片，可能含设备名称，不应上传真实截图。

## 文件与构建

- 新增 `Sources/GuardCore/Policy.swift`、`Controller.swift`：策略/协调器。
- 新增 `Sources/GuardCore/SignalHealth.swift`：可测试的信号回调健康与静音状态。
- 新增 `Sources/GuardPlatform/HAL.swift`、`SystemAudio.swift`、`SignalTap.swift`：平台边界。
- 新增 `Sources/SignalMeter/SignalMeter.c` 及头文件：实时摘要。
- 新增 `Sources/SoundGuard/main.swift`、`Resources/Info.plist`：入口和 UI。
- 新增 `Tests/GuardCoreTests/GuardTests.swift`：独立回归执行器，不依赖 XCTest。
- 新增 build/test/package 脚本及 macOS CI，更新 README、文档、版本记录；无数据库变更和删除接口。

Universal 构建分别指定 arm64/x86_64 triple 后 lipo 合并，避免本机精简工具链缺失 xcbuild。发行包 ad-hoc 签名，无 Developer ID/公证。发布到私有 GitHub 仓库，预览 Release 附 ZIP 与 SHA256，不把 Git tag 当作资产验证。

## 参考

实现已查本机 SDK 的 AudioHardware.h、AudioHardwareBase.h、CATapDescription.h。Apple 官方资料：[Core Audio taps](https://developer.apple.com/documentation/coreaudio/capturing-system-audio-with-core-audio-taps)、[进程输出状态](https://developer.apple.com/documentation/coreaudio/audiohardwareprocess/isrunningoutput)。测试边界见 [测试报告](../../TESTING.md)。
