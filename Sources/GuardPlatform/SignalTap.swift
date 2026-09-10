import CoreAudio
import Foundation
import GuardCore
import SignalMeter

final class SignalTap {
    private var tap: AudioObjectID = 0
    private var aggregate: AudioObjectID = 0
    private var io: AudioDeviceIOProcID?
    private var meter: OpaquePointer?
    private var health = SignalHealth(started: 0)
    private var poll: DispatchSourceTimer?
    var aggregateID: AudioObjectID { aggregate }
    init(device: OutputDevice, changed: @escaping () -> Void) throws {
        guard let allocated = sg_create() else { throw GuardError("无法分配信号检测器") }
        meter = allocated
        do {
            let streams = try Property(device.id, kAudioDevicePropertyStreams, kAudioDevicePropertyScopeOutput).array()
            guard streams.count == 1 else { throw GuardError("静音流检测暂不支持多输出流设备") }
            let description = CATapDescription(excludingProcesses: [], deviceUID: device.uid, stream: 0)
            description.name = "Sound Guard signal observer"
            description.isPrivate = true
            description.muteBehavior = .unmuted
            try check(AudioHardwareCreateProcessTap(description, &tap), "创建系统音频检测；请检查系统音频录制权限")
            let format = try Property(tap, kAudioTapPropertyFormat).scalar(AudioStreamBasicDescription())
            guard format.mFormatID == kAudioFormatLinearPCM,
                  format.mFormatFlags & kAudioFormatFlagIsFloat != 0,
                  format.mFormatFlags & kAudioFormatFlagIsBigEndian == 0,
                  format.mBitsPerChannel == 32 else { throw GuardError("静音流检测只支持本机 Float32 PCM") }
            let uid = UUID().uuidString
            let properties: [String: Any] = [
                kAudioAggregateDeviceNameKey: "Sound Guard Observer",
                kAudioAggregateDeviceUIDKey: "uk.869hr.SoundGuard.observer." + uid,
                kAudioAggregateDeviceIsPrivateKey: true,
                kAudioAggregateDeviceTapAutoStartKey: true,
                kAudioAggregateDeviceTapListKey: [[kAudioSubTapUIDKey: description.uuid.uuidString,
                                                  kAudioSubTapDriftCompensationKey: true]]
            ]
            try check(AudioHardwareCreateAggregateDevice(properties as CFDictionary, &aggregate), "建立私有音频观察设备")
            try check(AudioDeviceCreateIOProcIDWithBlock(&io, aggregate, nil) { _, input, _, _, _ in
                let timestamp = sg_now()
                let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
                for buffer in buffers {
                    if let data = buffer.mData {
                        sg_consume(allocated, data.assumingMemoryBound(to: Float.self), Int(buffer.mDataByteSize) / 4, timestamp)
                    }
                }
            }, "建立信号回调")
            health = SignalHealth(started: sg_now())
            try check(AudioDeviceStart(aggregate, io), "启动信号检测")
            // Only strict mode has a low-frequency health/silence check. No audio leaves this process.
            let poll = DispatchSource.makeTimerSource(queue: .main)
            poll.schedule(deadline: .now() + 0.5, repeating: 0.5, leeway: .milliseconds(100))
            poll.setEventHandler(handler: changed); self.poll = poll; poll.resume()
        } catch { stop(); throw error }
    }
    func playback() throws -> Playback {
        guard let meter else { throw GuardError("信号检测已停止") }
        // Read callback timestamps before the clock to avoid a concurrent callback appearing to be in the future.
        let buffer = sg_last_buffer(meter), sound = sg_last_sound(meter), invalid = sg_invalid(meter) != 0
        return try health.evaluate(now: sg_now(), buffer: buffer, sound: sound, invalid: invalid)
    }
    func stop() {
        poll?.setEventHandler {}; poll?.cancel(); poll = nil
        if let io, aggregate != 0 {
            AudioDeviceStop(aggregate, io)
            AudioDeviceDestroyIOProcID(aggregate, io)
        }
        io = nil
        if aggregate != 0 { AudioHardwareDestroyAggregateDevice(aggregate); aggregate = 0 }
        if tap != 0 { AudioHardwareDestroyProcessTap(tap); tap = 0 }
        if let meter { sg_destroy(meter); self.meter = nil }
    }
    deinit { stop() }
}
