import Foundation

public protocol AudioService: AnyObject {
    var onChange: (() -> Void)? { get set }
    func start() throws
    func stop()
    func currentDevice() throws -> OutputDevice?
    func devices() throws -> [OutputDevice]
    func setMonitoring(device: OutputDevice?, signal: Bool) throws
    func playback(for device: OutputDevice, signal: Bool) throws -> Playback
    func playingProcesses(for device: OutputDevice) throws -> [PlaybackProcess]
    func zero(_ expected: OutputDevice) throws -> VolumeSnapshot
    func restore(_ expectedZero: OutputDevice, snapshot: VolumeSnapshot) throws
}

public protocol GuardScheduler: AnyObject {
    func schedule(at deadline: TimeInterval, action: @escaping () -> Void)
    func cancel()
}

/// Main-queue confined coordinator; the platform owns audio callbacks, never the policy.
public final class GuardController {
    public var onUpdate: (() -> Void)?
    public var onRecoveryPrompt: ((RecoveryPrompt) -> Void)?
    public var onDiagnostic: ((DiagnosticEvent) -> Void)?
    public private(set) var lastFault: DiagnosticEvent?
    public private(set) var automaticRetryCount = 0
    public private(set) var retryDeadline: TimeInterval?
    public private(set) var automaticRetryPending = false
    public private(set) var preferences: Preferences
    public private(set) var device: OutputDevice?
    public private(set) var state: GuardState = .unavailable
    public private(set) var lastAction = "尚未自动归零"
    public private(set) var monitorActive = false
    public private(set) var recoveryMonitoringActive = false
    public private(set) var recoveryEndReason: String?
    public var recoveryPromptID: UUID? { retryPending ? nil : recovery?.id }
    public var recoveryContextRetained: Bool { recovery != nil }
    public var recoveryConfirmationActive: Bool { recovery?.candidateSince != nil }
    public private(set) var policy = IdlePolicy()
    private let audio: AudioService
    private let scheduler: GuardScheduler
    private let now: () -> TimeInterval
    private var sleeping = false
    private var running = false
    private var retryPending = false
    private var generation = 0
    private var writeFault: String?
    private var detectionFault: String?
    private var healthySince: TimeInterval?
    private var awaitingHealthy = false
    private var phase = "start"
    private static let automaticDelays: [TimeInterval] = [3, 10, 30]
    private static let retryCooldown: TimeInterval = 3
    private struct RecoveryContext {
        let id: UUID
        let zeroDevice: OutputDevice
        let originalVolume: VolumeSnapshot
        var playbackWasActive = false
        var candidateSince: TimeInterval?
    }
    private var recovery: RecoveryContext?
    public init(audio: AudioService, scheduler: GuardScheduler, preferences: Preferences = .init(),
                now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.audio = audio; self.scheduler = scheduler; self.preferences = preferences; self.now = now
    }
    public func start() {
        guard !running else { return }
        running = true
        audio.onChange = { [weak self] in self?.refresh() }
        do { try audio.start(); refresh() } catch { fail(error) }
    }
    public func stop() {
        record("stop", "应用退出")
        running = false; retryPending = false; invalidate(); audio.onChange = nil; audio.stop(); monitorActive = false
        recoveryMonitoringActive = false; recovery = nil; retryDeadline = nil; automaticRetryPending = false
    }
    public func configure(_ value: Preferences) {
        let detectionModeChanged = value.detectSilentStream != preferences.detectSilentStream
        let confirmationChanged = value.recoveryPlaybackConfirmationMilliseconds != preferences.recoveryPlaybackConfirmationMilliseconds
        let changed = value != preferences
        let needsRestart = retryPending || detectionFault != nil
        preferences = value; policy.reset()
        if !value.enabled || !value.recoveryPromptEnabled || detectionModeChanged ||
           recovery.map({ !value.includes($0.zeroDevice) }) == true {
            if recovery != nil { recoveryEndReason = "保护或恢复设置已变更" }
            recovery = nil
        }
        else if confirmationChanged { recovery?.candidateSince = nil }
        if changed {
            record("settings", "设置变更，取消旧重试任务")
            automaticRetryCount = 0; healthySince = nil; detectionFault = nil
            if retryPending { retryPending = false; automaticRetryPending = false; retryDeadline = nil; invalidate() }
            if needsRestart && running && !sleeping {
                restartAudio(after: value.enabled ? Self.retryCooldown : 0, preservingRecovery: true); return
            }
        }
        refresh()
    }
    public func setSleeping(_ value: Bool) {
        sleeping = value; policy.reset()
        if value {
            record("sleep", "系统进入睡眠")
            recovery = nil; recoveryEndReason = "系统进入睡眠"
            retryPending = false; automaticRetryPending = false; retryDeadline = nil
            invalidate(); audio.stop(); monitorActive = false; recoveryMonitoringActive = false
            healthySince = nil; state = .sleeping; onUpdate?()
        } else {
            record("wake", "系统唤醒，重新建立监听")
            automaticRetryCount = 0; detectionFault = nil
            restartAudio(after: 0)
        }
    }
    public func retry() {
        guard running, !sleeping, !retryPending else { return }
        record("manualRetry", "用户重新核对；此前状态：\(String(describing: state))")
        automaticRetryCount = 0; writeFault = nil; detectionFault = nil; healthySince = nil
        restartAudio(after: Self.retryCooldown, preservingRecovery: true)
    }
    public func refresh() {
        guard running, !sleeping, !retryPending else { return }
        if let message = writeFault ?? detectionFault {
            state = .fault(message); onUpdate?(); return
        }
        invalidate()
        do {
            phase = "readDevice"
            device = try audio.currentDevice()
            let active = preferences.enabled && !sleeping && device.map {
                preferences.includes($0) && $0.controllable && $0.volume > 0 && !$0.muted
            } == true
            if let saved = recovery {
                if !preferences.enabled || !preferences.recoveryPromptEnabled || sleeping {
                    recoveryEndReason = "保护已关闭或系统进入睡眠"
                    recovery = nil
                } else if let current = device {
                    if current.id != saved.zeroDevice.id || current.selectionID != saved.zeroDevice.selectionID ||
                       current.volume != 0 || current.muted != saved.zeroDevice.muted ||
                       !current.controllable || !preferences.includes(current) {
                        recoveryEndReason = "输出设备、路由、音量或静音状态已变化"
                        recovery = nil
                    }
                } else {
                    recoveryEndReason = "输出设备已断开"
                    recovery = nil
                }
                if recovery == nil { record("recoveryInvalidated", recoveryEndReason ?? "恢复记录已失效") }
            }
            let recovering = !active && recovery != nil && device?.volume == 0
            phase = "monitor"
            do {
                try audio.setMonitoring(device: active || recovering ? device : nil,
                                        signal: (active || recovering) && preferences.detectSilentStream)
            } catch where recovering {
                if (error as? GuardError)?.retryable == true { fail(error); return }
                recordFault(error)
                recoveryEndReason = "恢复检测启动失败：" + error.localizedDescription
                recovery = nil
                try? audio.setMonitoring(device: nil, signal: false)
            }
            monitorActive = active
            recoveryMonitoringActive = recovering && recovery != nil
            phase = "playback"
            let playback: Playback = active ? try audio.playback(for: device!, signal: preferences.detectSilentStream) : .unknown
            let due = policy.evaluate(device: device, playback: playback, preferences: preferences, sleeping: sleeping, now: now())
            state = policy.state
            if case .fault(let message) = state { throw GuardError(message, retryable: playback == .unknown) }
            if due, let device {
                // The adapter revalidates identity, route, volume and playback immediately before writing.
                let previousVolume: VolumeSnapshot
                phase = "zero"
                do { previousVolume = try audio.zero(device) }
                catch { writeFault = error.localizedDescription; throw error }
                lastAction = "已自动归零 · " + DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .short)
                record("autoZero", "自动归零成功")
                policy.reset()
                // zero() has already verified its write. Keep the snapshot across a transient follow-up read failure.
                if preferences.recoveryPromptEnabled {
                    let expectedZero = OutputDevice(id: device.id, uid: device.uid, name: device.name,
                        route: device.route, builtInSpeaker: device.builtInSpeaker, volume: 0,
                        muted: device.muted, controllable: device.controllable)
                    recovery = RecoveryContext(id: UUID(), zeroDevice: expectedZero, originalVolume: previousVolume)
                }
                phase = "postZeroRead"
                self.device = try audio.currentDevice()
                if preferences.recoveryPromptEnabled, let zeroDevice = self.device,
                   zeroDevice.id == device.id, zeroDevice.selectionID == device.selectionID,
                   zeroDevice.volume == 0, !zeroDevice.muted {
                    recoveryEndReason = nil
                    do {
                        // Strict mode must keep the existing tap so a persistent silent stream is
                        // distinguished from new audible samples after automatic zeroing.
                        try audio.setMonitoring(device: zeroDevice, signal: preferences.detectSilentStream)
                        recoveryMonitoringActive = true
                    } catch {
                        phase = "recoveryMonitor"
                        if (error as? GuardError)?.retryable == true { fail(error); return }
                        recordFault(error)
                        recoveryEndReason = "恢复检测启动失败：" + error.localizedDescription
                        recovery = nil; recoveryMonitoringActive = false
                        try? audio.setMonitoring(device: nil, signal: false)
                    }
                } else {
                    recovery = nil; try audio.setMonitoring(device: nil, signal: false)
                    recoveryMonitoringActive = false
                }
                monitorActive = false; state = .zero
            } else if recovering, var saved = recovery, let current = self.device {
                phase = "recoveryPlayback"
                let processes = preferences.detectSilentStream
                    ? ((try? audio.playingProcesses(for: current)) ?? [])
                    : (try audio.playingProcesses(for: current))
                let playing: Bool
                if preferences.detectSilentStream {
                    do {
                        let signal = try audio.playback(for: current, signal: true)
                        if signal == .starting {
                            recovery?.candidateSince = nil
                            onUpdate?(); return
                        }
                        guard signal != .unknown else { throw GuardError("恢复播放状态未知") }
                        playing = signal == .playing
                    } catch {
                        if (error as? GuardError)?.retryable == true { fail(error); return }
                        recordFault(error)
                        recoveryEndReason = "恢复信号检测失败：" + error.localizedDescription
                        recovery = nil; recoveryMonitoringActive = false
                        try? audio.setMonitoring(device: nil, signal: false)
                        onUpdate?(); return
                    }
                } else {
                    playing = !processes.isEmpty
                }
                var prompt: RecoveryPrompt?
                if playing {
                    if !saved.playbackWasActive {
                        let instant = now()
                        if saved.candidateSince == nil { saved.candidateSince = instant }
                        let deadline = saved.candidateSince! + preferences.recoveryPlaybackConfirmation
                        if instant >= deadline {
                            saved.candidateSince = nil; saved.playbackWasActive = true
                            prompt = RecoveryPrompt(id: saved.id, deviceName: current.name,
                                volume: saved.originalVolume.displayVolume, processes: processes,
                                timeout: preferences.recoveryPromptTimeout)
                        } else {
                            let token = generation
                            scheduler.schedule(at: deadline) { [weak self] in
                                guard let self, self.running, self.generation == token else { return }
                                self.refresh()
                            }
                        }
                    }
                } else {
                    saved.candidateSince = nil; saved.playbackWasActive = false
                }
                recovery = saved
                if let prompt { onRecoveryPrompt?(prompt) }
            } else if let deadline = policy.deadline {
                let token = generation
                scheduler.schedule(at: deadline) { [weak self] in
                    guard let self, self.running, self.generation == token else { return }
                    self.refresh()
                }
            }
            if state != .checkingSignal { markHealthy() }
            onUpdate?()
        } catch { fail(error) }
    }
    public func zeroNow() {
        guard running, !sleeping else { return }
        do {
            guard let current = try audio.currentDevice(), preferences.includes(current), current.controllable else {
                throw GuardError("当前设备不在保护名单或不支持音量控制")
            }
            // Manual action may run during playback; temporarily stop detection, not audio output.
            try audio.setMonitoring(device: nil, signal: false)
            recovery = nil; recoveryMonitoringActive = false
            _ = try audio.zero(current)
            lastAction = "已手动归零"; policy.reset(); writeFault = nil; refresh()
        } catch { writeFault = error.localizedDescription; fail(error) }
    }
    public func restoreVolume(for promptID: UUID, targetPercent: Int? = nil) throws {
        guard running, !sleeping, !retryPending, preferences.enabled, preferences.recoveryPromptEnabled,
              let saved = recovery, saved.id == promptID else { throw GuardError("恢复请求已失效") }
        let snapshot = try saved.originalVolume.restoring(toPercent: targetPercent)
        let current: OutputDevice?
        do { current = try audio.currentDevice() }
        catch { phase = "restoreRead"; fail(error); throw error }
        guard let current, current.id == saved.zeroDevice.id,
              current.selectionID == saved.zeroDevice.selectionID, current.volume == 0,
              current.muted == saved.zeroDevice.muted, current.controllable,
              preferences.includes(current) else { recovery = nil; throw GuardError("设备或音量已变化，未恢复音量") }
        do { try audio.restore(current, snapshot: snapshot) }
        catch { phase = "restoreWrite"; writeFault = error.localizedDescription; fail(error); throw error }
        recovery = nil; recoveryMonitoringActive = false
        recoveryEndReason = "已确认恢复音量"
        lastAction = "已确认恢复音量"
        policy.reset(); refresh()
    }
    public func keepSilent(for promptID: UUID) {
        guard running, let saved = recovery, saved.id == promptID else { return }
        recovery = nil; recoveryMonitoringActive = false
        recoveryEndReason = "已确认保持静音"
        try? audio.setMonitoring(device: nil, signal: false)
        lastAction = "已确认保持静音"
        policy.reset(); refresh()
    }
    private func invalidate() { generation += 1; scheduler.cancel() }
    private func restartAudio(after delay: TimeInterval, preservingRecovery: Bool = false) {
        guard running else { return }
        retryPending = delay > 0
        retryDeadline = delay > 0 ? now() + delay : nil
        policy.reset(); invalidate(); audio.stop(); monitorActive = false
        recoveryMonitoringActive = false
        if preservingRecovery { recovery?.candidateSince = nil }
        else { recovery = nil }
        guard delay > 0 else {
            phase = "start"
            do { try audio.start(); refresh() } catch { fail(error) }
            return
        }
        state = .retrying; onUpdate?()
        let token = generation
        scheduler.schedule(at: now() + delay) { [weak self] in
            guard let self, self.running, self.retryPending, self.generation == token else { return }
            self.retryPending = false
            self.retryDeadline = nil; self.automaticRetryPending = false; self.phase = "start"
            do { try self.audio.start(); self.refresh() } catch { self.fail(error) }
        }
    }
    private func fail(_ error: Error) {
        recordFault(error)
        healthySince = nil
        if writeFault == nil, (error as? GuardError)?.retryable == true,
           running, !sleeping, preferences.enabled, automaticRetryCount < Self.automaticDelays.count {
            let delay = Self.automaticDelays[automaticRetryCount]
            automaticRetryCount += 1; automaticRetryPending = true; awaitingHealthy = true
            record("automaticRetry", "\(Int(delay)) 秒后自动重建检测")
            restartAudio(after: delay, preservingRecovery: true)
            return
        }
        if recovery != nil { recoveryEndReason = "检测重建或读取失败：" + error.localizedDescription }
        retryPending = false
        detectionFault = error.localizedDescription
        automaticRetryPending = false; retryDeadline = nil
        invalidate(); policy.reset(); state = .fault(error.localizedDescription)
        try? audio.setMonitoring(device: nil, signal: false); monitorActive = false
        recoveryMonitoringActive = false; recovery = nil; onUpdate?()
    }
    private func markHealthy() {
        if awaitingHealthy { record("recovered", "状态核验已完成；未自动恢复音量"); awaitingHealthy = false }
        if healthySince == nil { healthySince = now() }
        if now() - healthySince! >= 60 { automaticRetryCount = 0 }
    }
    private func recordFault(_ error: Error) {
        let event = DiagnosticEvent(kind: "fault", phase: phase, message: error.localizedDescription,
                                    attempt: automaticRetryCount)
        lastFault = event; onDiagnostic?(event)
    }
    private func record(_ kind: String, _ message: String) {
        onDiagnostic?(DiagnosticEvent(kind: kind, phase: phase, message: message, attempt: automaticRetryCount))
    }
}

public struct GuardError: LocalizedError {
    public let message: String
    public let retryable: Bool
    public init(_ message: String, retryable: Bool = false) { self.message = message; self.retryable = retryable }
    public var errorDescription: String? { message }
}
