import Foundation

public enum GuardPresentation {
    public static func headline(_ state: GuardState, now: TimeInterval) -> String {
        switch state {
        case .zero: return "音量已归零"
        case .muted: return "系统已静音"
        case .playing: return "正在播放，保持音量"
        case .waiting(let deadline): return "空闲中，约 \(max(1, Int(ceil((deadline - now) / 60)))) 分钟后归零"
        case .paused: return "自动保护已暂停"
        case .sleeping: return "睡眠中，等待唤醒"
        case .unavailable: return "未发现输出设备"
        case .excluded: return "当前设备未加入保护"
        case .unsupported: return "当前设备无法调节音量"
        case .fault: return "保护需要检查"
        }
    }
}
