# v0.4.5 技术设计

## 动态帮助标签

`StatusTooltipProvider`（`NSViewToolTipOwner`）在启动时对状态栏按钮执行一次 `addToolTip(bounds, owner:, userData:)`；标签将显示时系统回调 `view(_:stringForToolTip:point:userData:)`，实时返回“声音守卫：”+ `stateText`。属性式 `button.toolTip` 从此不再赋值：AppKit 对该属性的赋值会移除并重挂帮助标签注册，若发生在标签显示中（30 秒心跳、系统音频事件、恢复确认计时都会触发 `updateStatus`），标签失去“离开即消失”的归属并跟随光标——这是本轮修复的根因。`NSStatusItem.button` 为只读、无法替换子类，故采用 owner 回调方案；provider 对 AppDelegate 持弱引用，无保留环。

`updateStatus` 改为 `setAccessibilityHelp`，保证 AXHelp（原由 toolTip 属性间接提供）继续随状态同步；该调用不经过帮助标签管理器，无同类风险。

## 验证

原生 UI 自检构造真实 `NSStatusItem` 走同一 `attachStatusTooltip` 路径，断言：属性式 toolTip 始终为 nil、回调文本等于“声音守卫：+stateText”、AXHelp 同步、连续两次 updateStatus 不回退；自检结束移除状态栏项。核心回归不涉及 UI 层，维持 129 项 / 670 次断言。
