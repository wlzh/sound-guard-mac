import Foundation

public enum AppVersion {
    public static let current = "0.4.0"
    public static let build = "16"
}

public struct Preferences: Codable, Equatable {
    public var enabled = true
    public var minutes = 5
    public var detectSilentStream = false
    public var protectBuiltIn = true
    public var selectedDevices: [String: String] = [:]
    public var recoveryPromptEnabled = false
    public var recoveryPromptSeconds = 60
    public var recoveryPlaybackConfirmationMilliseconds = 2_000
    public var ignoredRecoveryApps: [IgnoredRecoveryApp] = []
    public init() {}
    public var ignoredRecoveryAppIdentities: Set<String> {
        Set(ignoredRecoveryApps.flatMap { $0.identities })
    }
    public func isIgnoredRecoveryApp(_ process: PlaybackProcess) -> Bool {
        guard !process.identities.isEmpty else { return false }
        return ignoredRecoveryApps.contains { $0.matches(process) }
    }
    public func recoveryPromptProcesses(from processes: [PlaybackProcess]) -> [PlaybackProcess]? {
        guard !processes.isEmpty else { return [] }
        let ignoredOnly = processes.allSatisfy { isIgnoredRecoveryApp($0) }
        return ignoredOnly ? nil : processes.filter { !isIgnoredRecoveryApp($0) }
    }
    public var timeout: TimeInterval { Double((1...120).contains(minutes) ? minutes : 5) * 60 }
    public var recoveryPromptTimeout: TimeInterval { Double((5...600).contains(recoveryPromptSeconds) ? recoveryPromptSeconds : 60) }
    public var recoveryPlaybackConfirmation: TimeInterval {
        Double((500...30_000).contains(recoveryPlaybackConfirmationMilliseconds) ? recoveryPlaybackConfirmationMilliseconds : 2_000) / 1_000
    }
    public func includes(_ device: OutputDevice) -> Bool {
        device.builtInSpeaker ? protectBuiltIn : selectedDevices[device.selectionID] != nil
    }
    public static func decode(_ data: Data?) -> Preferences {
        guard let data, var value = try? JSONDecoder().decode(Self.self, from: data) else { return .init() }
        if !(1...120).contains(value.minutes) { value.minutes = 5 }
        if !(5...600).contains(value.recoveryPromptSeconds) { value.recoveryPromptSeconds = 60 }
        if !(500...30_000).contains(value.recoveryPlaybackConfirmationMilliseconds) {
            value.recoveryPlaybackConfirmationMilliseconds = 2_000
        }
        value.ignoredRecoveryApps = Array(Set(value.ignoredRecoveryApps.filter { !$0.name.isEmpty && !$0.identities.isEmpty }))
        return value
    }
    private enum CodingKeys: String, CodingKey {
        case enabled, minutes, detectSilentStream, protectBuiltIn, selectedDevices
        case recoveryPromptEnabled, recoveryPromptSeconds, recoveryPlaybackConfirmationMilliseconds
        case ignoredRecoveryApps
    }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try values.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        minutes = try values.decodeIfPresent(Int.self, forKey: .minutes) ?? 5
        detectSilentStream = try values.decodeIfPresent(Bool.self, forKey: .detectSilentStream) ?? false
        protectBuiltIn = try values.decodeIfPresent(Bool.self, forKey: .protectBuiltIn) ?? true
        selectedDevices = try values.decodeIfPresent([String: String].self, forKey: .selectedDevices) ?? [:]
        recoveryPromptEnabled = try values.decodeIfPresent(Bool.self, forKey: .recoveryPromptEnabled) ?? false
        recoveryPromptSeconds = try values.decodeIfPresent(Int.self, forKey: .recoveryPromptSeconds) ?? 60
        recoveryPlaybackConfirmationMilliseconds = try values.decodeIfPresent(
            Int.self, forKey: .recoveryPlaybackConfirmationMilliseconds) ?? 2_000
        ignoredRecoveryApps = try values.decodeIfPresent([IgnoredRecoveryApp].self, forKey: .ignoredRecoveryApps) ?? []
    }
}

public struct IgnoredRecoveryApp: Codable, Equatable, Hashable {
    public let bundleIdentifier: String?
    public let bundlePath: String?
    public let name: String
    public init(bundleIdentifier: String? = nil, bundlePath: String? = nil, name: String) {
        self.bundleIdentifier = bundleIdentifier?.isEmpty == true ? nil : bundleIdentifier
        self.bundlePath = bundlePath?.isEmpty == true ? nil : bundlePath
        self.name = name
    }
    public var identities: [String] {
        [bundleIdentifier.map { "bundle:\($0)" }, bundlePath.map { "path:\($0)" }].compactMap { $0 }
    }
    public var identity: String? { identities.first }
    public func matches(_ process: PlaybackProcess) -> Bool {
        if let bundleIdentifier, let processIdentifier = process.bundleIdentifier {
            return bundleIdentifier == processIdentifier
        }
        guard bundleIdentifier == nil, let bundlePath, let processPath = process.bundlePath else { return false }
        return bundlePath == processPath
    }
}

public struct OutputDevice: Equatable {
    public let id: UInt32
    public let uid: String
    public let name: String
    public let route: String
    public let builtInSpeaker: Bool
    public let volume: Float
    public let muted: Bool
    public let controllable: Bool
    public var selectionID: String { uid + "|" + route }
    public init(id: UInt32, uid: String, name: String, route: String = "default", builtInSpeaker: Bool,
                volume: Float, muted: Bool = false, controllable: Bool = true) {
        self.id = id; self.uid = uid; self.name = name; self.route = route
        self.builtInSpeaker = builtInSpeaker; self.volume = volume
        self.muted = muted; self.controllable = controllable
    }
}

public enum Playback: Equatable { case idle, playing, starting, unknown }
public struct PlaybackProcess: Equatable {
    public let pid: Int32
    public let bundleIdentifier: String?
    public let bundlePath: String?
    public let name: String?
    public init(pid: Int32, bundleIdentifier: String? = nil, bundlePath: String? = nil, name: String? = nil) {
        self.pid = pid; self.bundleIdentifier = bundleIdentifier; self.bundlePath = bundlePath; self.name = name
    }
    public var identities: [String] {
        [bundleIdentifier.map { "bundle:\($0)" }, bundlePath.map { "path:\($0)" }].compactMap { $0 }
    }
    public var applicationIdentity: String? { identities.first }
}
public struct VolumeSnapshot: Equatable {
    public let values: [Float]
    public var displayVolume: Float { values.max() ?? 0 }
    public init(values: [Float]) { self.values = values }
    public func restoring(toPercent percent: Int?) throws -> VolumeSnapshot {
        guard !values.isEmpty, values.allSatisfy({ $0.isFinite && (0...1).contains($0) }),
              displayVolume > 0 else { throw GuardError("原音量记录无效") }
        guard let percent else { return self }
        guard (1...100).contains(percent) else { throw GuardError("恢复音量必须为 1–100%") }
        let target = Float(percent) / 100
        return VolumeSnapshot(values: values.map { ($0 / displayVolume) * target })
    }
}
public struct RecoveryPrompt: Equatable {
    public let id: UUID
    public let deviceName: String
    public let volume: Float
    public let processes: [PlaybackProcess]
    public let timeout: TimeInterval
    public init(id: UUID, deviceName: String, volume: Float, processes: [PlaybackProcess], timeout: TimeInterval) {
        self.id = id; self.deviceName = deviceName; self.volume = volume
        self.processes = processes; self.timeout = timeout
    }
}
public enum GuardState: Equatable {
    case paused, sleeping, retrying, checkingSignal, unavailable, excluded, unsupported, zero, muted, playing, waiting(TimeInterval), fault(String)
}

/// Pure policy. Time is monotonic, and every invalidation discards the previous deadline.
public struct IdlePolicy {
    public private(set) var state: GuardState = .unavailable
    public private(set) var deadline: TimeInterval?
    private var identity: String?
    private var volume: Float?
    public init() {}
    public mutating func reset() { deadline = nil; identity = nil; volume = nil }
    public mutating func evaluate(device: OutputDevice?, playback: Playback, preferences: Preferences,
                                  sleeping: Bool, now: TimeInterval) -> Bool {
        guard preferences.enabled else { return stop(.paused) }
        guard !sleeping else { return stop(.sleeping) }
        guard let device else { return stop(.unavailable) }
        guard preferences.includes(device) else { return stop(.excluded) }
        guard device.controllable else { return stop(.unsupported) }
        guard device.volume.isFinite, (0...1).contains(device.volume) else { return stop(.fault("音量读数无效")) }
        guard device.volume > 0 else { return stop(.zero) }
        guard !device.muted else { return stop(.muted) }
        guard playback != .unknown else { return stop(.fault("播放状态未知")) }
        guard playback != .starting else { return stop(.checkingSignal) }
        let key = "\(device.id)|\(device.selectionID)"
        if identity != key || volume != device.volume { deadline = nil }
        identity = key; volume = device.volume
        guard playback == .idle else { deadline = nil; state = .playing; return false }
        if deadline == nil { deadline = now + preferences.timeout }
        state = .waiting(deadline!)
        return now >= deadline!
    }
    @discardableResult private mutating func stop(_ next: GuardState) -> Bool {
        reset(); state = next; return false
    }
}
