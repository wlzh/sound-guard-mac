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
    public private(set) var preferences: Preferences
    public private(set) var device: OutputDevice?
    public private(set) var state: GuardState = .unavailable
    public private(set) var lastAction = "尚未自动归零"
    public private(set) var monitorActive = false
    public private(set) var recoveryMonitoringActive = false
    public var recoveryPromptID: UUID? { recovery?.id }
    public var recoveryConfirmationActive: Bool { recovery?.candidateSince != nil }
    public private(set) var policy = IdlePolicy()
    private let audio: AudioService
    private let scheduler: GuardScheduler
    private let now: () -> TimeInterval
    private var sleeping = false
    private var running = false
    private var generation = 0
    private var writeFault: String?
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
        running = false; invalidate(); audio.onChange = nil; audio.stop(); monitorActive = false
        recoveryMonitoringActive = false; recovery = nil
    }
    public func configure(_ value: Preferences) {
        let detectionModeChanged = value.detectSilentStream != preferences.detectSilentStream
        let confirmationChanged = value.recoveryPlaybackConfirmationMilliseconds != preferences.recoveryPlaybackConfirmationMilliseconds
        preferences = value; writeFault = nil; policy.reset()
        if !value.enabled || !value.recoveryPromptEnabled || detectionModeChanged ||
           recovery.map({ !value.includes($0.zeroDevice) }) == true { recovery = nil }
        else if confirmationChanged { recovery?.candidateSince = nil }
        refresh()
    }
    public func setSleeping(_ value: Bool) {
        sleeping = value; policy.reset()
        if !value { retry() } else { refresh() }
    }
    public func retry() {
        writeFault = nil; policy.reset(); audio.stop(); monitorActive = false
        do { try audio.start(); refresh() } catch { fail(error) }
    }
    public func refresh() {
        guard running else { return }
        invalidate()
        do {
            device = try audio.currentDevice()
            if let writeFault { throw GuardError(writeFault) }
            let active = preferences.enabled && !sleeping && device.map {
                preferences.includes($0) && $0.controllable && $0.volume > 0 && !$0.muted
            } == true
            if let saved = recovery {
                if !preferences.enabled || !preferences.recoveryPromptEnabled || sleeping {
                    recovery = nil
                } else if let current = device {
                    if current.id != saved.zeroDevice.id || current.selectionID != saved.zeroDevice.selectionID ||
                       current.volume != 0 || current.muted != saved.zeroDevice.muted { recovery = nil }
                } else {
                    recovery = nil
                }
            }
            let recovering = !active && recovery != nil && device?.volume == 0
            do {
                try audio.setMonitoring(device: active || recovering ? device : nil,
                                        signal: (active || recovering) && preferences.detectSilentStream)
            } catch where recovering {
                recovery = nil
                try? audio.setMonitoring(device: nil, signal: false)
            }
            monitorActive = active
            recoveryMonitoringActive = recovering && recovery != nil
            let playback: Playback = active ? try audio.playback(for: device!, signal: preferences.detectSilentStream) : .unknown
            let due = policy.evaluate(device: device, playback: playback, preferences: preferences, sleeping: sleeping, now: now())
            state = policy.state
            if due, let device {
                // The adapter revalidates identity, route, volume and playback immediately before writing.
                let previousVolume: VolumeSnapshot
                do { previousVolume = try audio.zero(device) }
                catch { writeFault = error.localizedDescription; throw error }
                lastAction = "已自动归零 · " + DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .short)
                policy.reset()
                self.device = try audio.currentDevice()
                if preferences.recoveryPromptEnabled, let zeroDevice = self.device,
                   zeroDevice.id == device.id, zeroDevice.selectionID == device.selectionID,
                   zeroDevice.volume == 0, !zeroDevice.muted {
                    recovery = RecoveryContext(id: UUID(), zeroDevice: zeroDevice, originalVolume: previousVolume)
                    do {
                        // Strict mode must keep the existing tap so a persistent silent stream is
                        // distinguished from new audible samples after automatic zeroing.
                        try audio.setMonitoring(device: zeroDevice, signal: preferences.detectSilentStream)
                        recoveryMonitoringActive = true
                    } catch {
                        recovery = nil; recoveryMonitoringActive = false
                        try? audio.setMonitoring(device: nil, signal: false)
                    }
                } else {
                    recovery = nil; try audio.setMonitoring(device: nil, signal: false)
                    recoveryMonitoringActive = false
                }
                monitorActive = false; state = .zero
            } else if recovering, var saved = recovery, let current = self.device {
                let processes = (try? audio.playingProcesses(for: current)) ?? []
                let playing: Bool
                if preferences.detectSilentStream {
                    guard let strictPlayback = try? audio.playback(for: current, signal: true) else {
                        recovery = nil; recoveryMonitoringActive = false
                        try? audio.setMonitoring(device: nil, signal: false)
                        onUpdate?(); return
                    }
                    playing = strictPlayback == .playing
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
    public func restoreVolume(for promptID: UUID) throws {
        guard running, !sleeping, preferences.enabled, preferences.recoveryPromptEnabled,
              let saved = recovery, saved.id == promptID else { throw GuardError("恢复请求已失效") }
        let current = try audio.currentDevice()
        guard let current, current.id == saved.zeroDevice.id,
              current.selectionID == saved.zeroDevice.selectionID, current.volume == 0,
              current.muted == saved.zeroDevice.muted else { recovery = nil; throw GuardError("设备或音量已变化，未恢复音量") }
        try audio.restore(current, snapshot: saved.originalVolume)
        recovery = nil; recoveryMonitoringActive = false
        lastAction = "已确认恢复音量"
        policy.reset(); refresh()
    }
    public func keepSilent(for promptID: UUID) {
        guard running, let saved = recovery, saved.id == promptID else { return }
        recovery = nil; recoveryMonitoringActive = false
        try? audio.setMonitoring(device: nil, signal: false)
        lastAction = "已确认保持静音"
        policy.reset(); refresh()
    }
    private func invalidate() { generation += 1; scheduler.cancel() }
    private func fail(_ error: Error) {
        writeFault = error.localizedDescription
        invalidate(); policy.reset(); state = .fault(error.localizedDescription)
        try? audio.setMonitoring(device: nil, signal: false); monitorActive = false
        recoveryMonitoringActive = false; recovery = nil; onUpdate?()
    }
}

public struct GuardError: LocalizedError {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}
