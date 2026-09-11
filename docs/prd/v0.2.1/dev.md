# v0.2.1 技术设计

## 上下游影响

上游 GuardController 和 OutputDevice 提供状态、设备名与音量。MenuUI 拆分 detail/volume，故障隐藏音量，不可控或非有限值不转整数；Visuals.menuHeader 新增可选 volume 参数。所有调用方 MenuUI 和 UIChecks 同步。单行名称设置低水平抗压优先级，百分比保留宽度；提示与辅助功能标签保存原文。

下游菜单命令、计时、HAL、Tap、偏好 Codable、单实例及状态 CLI 结构不变，无权限或数据迁移。About 读取统一版本常量；Info.plist、VERSION、BUILD_NUMBER、文档和 ZIP 命名统一为 0.2.1 / 3。构建脚本继续打包资源与离线文档，CI 运行统一测试与 Universal 构建。

## 生命周期与验证

仅菜单打开时构造，关闭释放头部；没有新增轮询。UIChecks 覆盖明暗高度、对齐、长名称边界与提示。保留 50 项核心回归，18 次 UI 检查；人工硬件与长期性能缺口保持公开。
