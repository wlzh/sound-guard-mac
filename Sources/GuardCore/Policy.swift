import Foundation

public enum AppVersion {
    public static let current = "0.2.1"
    public static let build = "3"
}

public struct Preferences: Codable, Equatable {
    public var enabled = true
    public var minutes = 5
    public var detectSilentStream = false
    public var protectBuiltIn = true
    public var selectedDevices: [String: String] = [:]
    public init() {}
    public var timeout: TimeInterval { Double((1...120).contains(minutes) ? minutes : 5) * 60 }
    public func includes(_ device: OutputDevice) -> Bool {
        device.builtInSpeaker ? protectBuiltIn : selectedDevices[device.selectionID] != nil
    }
    public static func decode(_ data: Data?) -> Preferences {
        guard let data, var value = try? JSONDecoder().decode(Self.self, from: data) else { return .init() }
        if !(1...120).contains(value.minutes) { value.minutes = 5 }
        return value
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

public enum Playback: Equatable { case idle, playing, unknown }
public enum GuardState: Equatable {
    case paused, sleeping, unavailable, excluded, unsupported, zero, muted, playing, waiting(TimeInterval), fault(String)
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
