import Foundation

public struct SignalHealth {
    private let started: UInt64
    private var observedSound: UInt64 = 0
    public init(started: UInt64) { self.started = started }
    public mutating func evaluate(now: UInt64, buffer: UInt64, sound: UInt64, invalid: Bool) throws -> Playback {
        guard !invalid else { throw GuardError("收到无效音频样本，已停止保护") }
        guard now >= started, now >= buffer, now >= sound else { throw GuardError("音频时钟异常，已停止保护") }
        if buffer == 0 && now - started < 3_000_000_000 { return .playing }
        guard buffer > 0, now - buffer < 2_000_000_000 else {
            throw GuardError("系统音频没有有效回调，请检查录制权限后重新核对")
        }
        let lastSound = max(started, sound)
        if lastSound != observedSound { observedSound = lastSound; return .playing }
        return now - lastSound < 600_000_000 ? .playing : .idle
    }
}
