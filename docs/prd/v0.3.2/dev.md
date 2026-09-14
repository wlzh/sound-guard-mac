# v0.3.2 技术设计

`BrandAssets.icon` 从随包 `AppIcon.svg` 加载彩色图标。App 启动时设置 `NSApp.applicationIconImage`，`UI.alert` 为每个 `NSAlert` 显式设置 64pt 品牌图标。菜单栏仍使用 `BrandMark.svg` 的 template 渲染，不受此次调整影响。

`RecoveryPromptPresenter` 仍是非激活 `NSPanel`，只调整尺寸与约束。两个按钮通过共享工厂取得相同对齐尺寸；测试使用 `alignmentRect(forFrame:)` 验证 AppKit 去除 bezel 外扩后的真实布局尺寸，避免把系统阴影边界误当作按钮不等宽。

上游 `RecoveryPrompt` 数据、播放 App 定位和倒计时输入不变；下游恢复回调、设备复核、取消、关闭、超时及资源释放不变。没有新增权限、定时器、音频访问或持久化字段。

UI 门禁检查品牌 Alert 图标、420×264pt 面板、标题层级、App 来源、倒计时、185×34pt 双按钮和无默认键，并生成明暗预览。真实 VoiceOver、缩放显示和多屏视觉仍单独验收。
