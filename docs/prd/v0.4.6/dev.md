# v0.4.6 技术设计

## 弹窗内一键加入例外

`RecoveryPromptPresenter.show` 用 `PlaybackScreenLocator.appDescriptor(for:)` 按顺序解析 `prompt.processes` 中第一个可识别的 App 身份（bundleId/路径，或经 NSRunningApplication 解析外层 App），作为 `ignoreDescriptor`；副标题名称优先取该身份的名称，无法解析时回退既有 `appName(for:)` 且不显示链接。来源行改为水平栈：单行截断标签 + 弹性占位 + `UI.link("不再提醒")`（12pt 链接样式，高度与文字行一致），行宽上限 326pt（380 卡片宽 − 42 图标 − 12 间距），面板尺寸不变。

点击 `ignoreApp`：先关闭面板，再经 `onIgnoreApp` 回调携带 `(prompt, descriptor)`。AppDelegate 的 `ignoreRecoveryApp(_:)` 按身份去重后把描述符追加进 `preferences.ignoredRecoveryApps` 并 `save`：偏好落盘沿用既有字段格式，`configure` 走既有 ignoredAppsChanged 分支（作废当前提示资格、重置确认计时），该 App 后续播放命中 `recoveryPromptProcesses` 的“全部被忽略”路径（`playbackWasIgnoredOnly`），不再弹窗。控制器、守望与恢复写入路径零改动。

## 验证

原生 UI 自检新增：带 bundleId 的合成进程弹出时断言“Player 已开始播放”与“不再提醒”存在、面板仍 420×350；点击后回调携带正确身份、面板关闭且未触发恢复/保持静音；`ignoreRecoveryApp` 重复调用仅写入一条；无来源（pid 0 无身份）时不显示链接。核心回归不涉及控制器行为，维持 129 项 / 670 次断言。
