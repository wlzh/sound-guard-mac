import CoreAudio
import Foundation
import GuardCore

public final class SystemAudio: AudioService {
    public var onChange: (() -> Void)?
    private let system = AudioObjectID(kAudioObjectSystemObject)
    private let baseline = Listeners()
    private let outputListeners = Listeners()
    private let processListeners = Listeners()
    private var tap: SignalTap?
    private var monitored: OutputDevice?
    private var pending = false
    private var active = false
    public var listenerCount: Int { baseline.count + outputListeners.count + processListeners.count }
    public var playbackListenerCount: Int { processListeners.count }
    public var signalActive: Bool { tap != nil }
    public init() {}
    private func changed() {
        guard active, !pending else { return }
        pending = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }; self.pending = false
            if self.active { self.onChange?() }
        }
    }
    public func start() throws {
        active = true
        try baseline.replace([
            Property(system, kAudioHardwarePropertyDefaultOutputDevice),
            Property(system, kAudioHardwarePropertyDevices),
            Property(system, kAudioHardwarePropertyServiceRestarted)
        ], changed: { [weak self] in self?.changed() })
    }
    public func stop() {
        active = false; tap = nil; monitored = nil
        processListeners.clear(); outputListeners.clear(); baseline.clear()
    }
    private func controls(_ id: UInt32) throws -> [Property] {
        let main = Property(id, kAudioDevicePropertyVolumeScalar, kAudioDevicePropertyScopeOutput)
        if main.exists && main.settable { return [main] }
        let streams = try Property(id, kAudioDevicePropertyStreams, kAudioDevicePropertyScopeOutput).array()
        var count: UInt32 = 0
        for stream in streams {
            let format = try Property(stream, kAudioStreamPropertyVirtualFormat).scalar(AudioStreamBasicDescription())
            count += format.mChannelsPerFrame
        }
        guard count > 0, count <= 64 else { return [] }
        let channels = (1...count).map { Property(id, kAudioDevicePropertyVolumeScalar, kAudioDevicePropertyScopeOutput, $0) }
        return channels.allSatisfy { $0.exists && $0.settable } ? channels : []
    }
    private func inspect(_ id: UInt32) throws -> OutputDevice {
        let uid = try Property(id, kAudioDevicePropertyDeviceUID).string()
        let name = try Property(id, kAudioObjectPropertyName).string()
        let transport = try Property(id, kAudioDevicePropertyTransportType).scalar(UInt32(0))
        let streams = try Property(id, kAudioDevicePropertyStreams, kAudioDevicePropertyScopeOutput).array()
        let terminals = try streams.map { try Property($0, kAudioStreamPropertyTerminalType).scalar(UInt32(0)) }
        let source = Property(id, kAudioDevicePropertyDataSource, kAudioDevicePropertyScopeOutput)
        let sourceValue: UInt32? = source.exists ? try source.scalar(UInt32(0)) : nil
        let jack = Property(id, kAudioDevicePropertyJackIsConnected, kAudioDevicePropertyScopeOutput)
        let jackConnected: Bool = jack.exists ? try jack.scalar(UInt32(0)) != 0 : false
        // Never infer built-in speakers from a localized device name alone.
        let internalSpeakerSource: UInt32 = 0x6973706b // 'ispk'
        let builtIn = transport == kAudioDeviceTransportTypeBuiltIn && !jackConnected &&
            (sourceValue == internalSpeakerSource || (sourceValue == nil && !terminals.isEmpty &&
              terminals.allSatisfy { $0 == kAudioStreamTerminalTypeSpeaker }))
        let route = "\(sourceValue.map(String.init) ?? "none"):\(jackConnected):" + terminals.map(String.init).joined(separator: ",")
        let controls = try controls(id)
        let volumes = try controls.map { try $0.scalar(Float32(0)) }
        guard volumes.allSatisfy({ $0.isFinite && (0...1).contains($0) }) else { throw GuardError("设备音量无效") }
        let mute = Property(id, kAudioDevicePropertyMute, kAudioDevicePropertyScopeOutput)
        let muted = mute.exists ? try mute.scalar(UInt32(0)) != 0 : false
        return OutputDevice(id: id, uid: uid, name: name, route: route, builtInSpeaker: builtIn,
                            volume: volumes.max() ?? 0, muted: muted, controllable: !controls.isEmpty)
    }
    public func devices() throws -> [OutputDevice] {
        let ids = try Property(system, kAudioHardwarePropertyDevices).array()
        return ids.compactMap { id in
            guard let streams = try? Property(id, kAudioDevicePropertyStreams, kAudioDevicePropertyScopeOutput).array(),
                  !streams.isEmpty, id != tap?.aggregateID else { return nil }
            if let device = try? inspect(id) { return device }
            return OutputDevice(id: id,
                uid: (try? Property(id, kAudioDevicePropertyDeviceUID).string()) ?? "unavailable:\(id)",
                name: ((try? Property(id, kAudioObjectPropertyName).string()) ?? "未知输出设备") + "（属性读取失败）",
                route: "unknown", builtInSpeaker: false, volume: 0, controllable: false)
        }
    }
    public func currentDevice() throws -> OutputDevice? {
        let id = try Property(system, kAudioHardwarePropertyDefaultOutputDevice).scalar(UInt32(0))
        guard id != 0 else { outputListeners.clear(); return nil }
        let device = try inspect(id)
        var watch = Set(try controls(id))
        for selector in [kAudioDevicePropertyMute, kAudioDevicePropertyDataSource,
                         kAudioDevicePropertyJackIsConnected, kAudioDevicePropertyStreams] {
            let p = Property(id, selector, kAudioDevicePropertyScopeOutput)
            if p.exists { watch.insert(p) }
        }
        for selector in [kAudioDevicePropertyDeviceIsAlive, kAudioObjectPropertyOwnedObjects] {
            let p = Property(id, selector); if p.exists { watch.insert(p) }
        }
        for stream in try Property(id, kAudioDevicePropertyStreams, kAudioDevicePropertyScopeOutput).array() {
            watch.insert(Property(stream, kAudioStreamPropertyVirtualFormat))
            watch.insert(Property(stream, kAudioStreamPropertyTerminalType))
        }
        if active { try outputListeners.replace(watch, changed: { [weak self] in self?.changed() }) }
        return device
    }
    public func setMonitoring(device: OutputDevice?, signal: Bool) throws {
        guard let device else { monitored = nil; processListeners.clear(); tap = nil; return }
        if monitored?.selectionID != device.selectionID || monitored?.id != device.id {
            tap = nil; processListeners.clear(); monitored = device
        }
        if signal {
            processListeners.clear()
            if tap == nil { tap = try SignalTap(device: device, changed: { [weak self] in self?.changed() }) }
        } else {
            tap = nil
            let processes = try Property(system, kAudioHardwarePropertyProcessObjectList).array()
            func attach(_ list: [UInt32]) throws {
                var properties: Set<Property> = [Property(system, kAudioHardwarePropertyProcessObjectList)]
                for process in list {
                    properties.insert(Property(process, kAudioProcessPropertyIsRunningOutput))
                    properties.insert(Property(process, kAudioProcessPropertyDevices, kAudioObjectPropertyScopeOutput))
                }
                try processListeners.replace(properties, changed: { [weak self] in self?.changed() })
            }
            do { try attach(processes) }
            catch {
                // A process may exit between enumeration and registration. Reconcile once, not a polling loop.
                let fresh = try Property(system, kAudioHardwarePropertyProcessObjectList).array()
                guard Set(fresh) != Set(processes) else { throw error }
                try attach(fresh)
            }
        }
    }
    public func playback(for device: OutputDevice, signal: Bool) throws -> Playback {
        if signal {
            guard let tap else { return .unknown }
            return try tap.playback()
        }
        for process in try Property(system, kAudioHardwarePropertyProcessObjectList).array() {
            do {
                let running = try Property(process, kAudioProcessPropertyIsRunningOutput).scalar(UInt32(0))
                if running != 0 {
                    let devices = try Property(process, kAudioProcessPropertyDevices, kAudioObjectPropertyScopeOutput).array()
                    if devices.contains(device.id) { return .playing }
                }
            } catch {
                let current = try Property(system, kAudioHardwarePropertyProcessObjectList).array()
                if current.contains(process) { throw error }
            }
        }
        return .idle
    }
    public func zero(_ expected: OutputDevice) throws {
        guard let current = try currentDevice(), current.id == expected.id,
              current.selectionID == expected.selectionID, current.volume == expected.volume,
              current.muted == expected.muted, current.controllable else {
            throw GuardError("设备或音量已变化，本次归零取消")
        }
        if monitored != nil {
            guard try playback(for: current, signal: tap != nil) == .idle else {
                throw GuardError("播放已恢复，本次归零取消")
            }
        }
        for control in try controls(current.id) { try control.writeZero() }
        guard let verified = try currentDevice(), verified.selectionID == current.selectionID, verified.volume == 0 else {
            throw GuardError("归零后复核失败；请检查实际系统音量")
        }
    }
}
