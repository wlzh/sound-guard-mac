import Foundation

public protocol AudioService: AnyObject {
    var onChange: (() -> Void)? { get set }
    func start() throws
    func stop()
    func currentDevice() throws -> OutputDevice?
    func devices() throws -> [OutputDevice]
    func setMonitoring(device: OutputDevice?, signal: Bool) throws
    func playback(for device: OutputDevice, signal: Bool) throws -> Playback
    func zero(_ expected: OutputDevice) throws
}

public protocol GuardScheduler: AnyObject {
    func schedule(at deadline: TimeInterval, action: @escaping () -> Void)
    func cancel()
}

/// Main-queue confined coordinator; the platform owns audio callbacks, never the policy.
public final class GuardController {
    public var onUpdate: (() -> Void)?
    public private(set) var preferences: Preferences
    public private(set) var device: OutputDevice?
    public private(set) var state: GuardState = .unavailable
    public private(set) var lastAction = "尚未自动归零"
    public private(set) var monitorActive = false
    public private(set) var policy = IdlePolicy()
    private let audio: AudioService
    private let scheduler: GuardScheduler
    private let now: () -> TimeInterval
    private var sleeping = false
    private var running = false
    private var generation = 0
    private var writeFault: String?
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
    }
    public func configure(_ value: Preferences) {
        preferences = value; writeFault = nil; policy.reset(); refresh()
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
            try audio.setMonitoring(device: active ? device : nil, signal: preferences.detectSilentStream)
            monitorActive = active
            let playback: Playback = active ? try audio.playback(for: device!, signal: preferences.detectSilentStream) : .unknown
            let due = policy.evaluate(device: device, playback: playback, preferences: preferences, sleeping: sleeping, now: now())
            state = policy.state
            if due, let device {
                // The adapter revalidates identity, route, volume and playback immediately before writing.
                do { try audio.zero(device) }
                catch { writeFault = error.localizedDescription; throw error }
                lastAction = "已自动归零 · " + DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .short)
                policy.reset()
                self.device = try audio.currentDevice()
                try audio.setMonitoring(device: nil, signal: false)
                monitorActive = false; state = .zero
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
            try audio.zero(current)
            lastAction = "已手动归零"; policy.reset(); writeFault = nil; refresh()
        } catch { writeFault = error.localizedDescription; fail(error) }
    }
    private func invalidate() { generation += 1; scheduler.cancel() }
    private func fail(_ error: Error) {
        writeFault = error.localizedDescription
        invalidate(); policy.reset(); state = .fault(error.localizedDescription)
        try? audio.setMonitoring(device: nil, signal: false); monitorActive = false; onUpdate?()
    }
}

public struct GuardError: LocalizedError {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}
