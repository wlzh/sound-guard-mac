import CoreAudio
import Foundation
import GuardCore

struct Property: Hashable {
    let object: AudioObjectID
    let selector: AudioObjectPropertySelector
    let scope: AudioObjectPropertyScope
    let element: AudioObjectPropertyElement
    init(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector,
         _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal, _ element: UInt32 = 0) {
        self.object = object; self.selector = selector; self.scope = scope; self.element = element
    }
    var address: AudioObjectPropertyAddress {
        .init(mSelector: selector, mScope: scope, mElement: element)
    }
    var exists: Bool { var a = address; return AudioObjectHasProperty(object, &a) }
    var settable: Bool {
        var a = address; var value: DarwinBoolean = false
        return AudioObjectIsPropertySettable(object, &a, &value) == noErr && value.boolValue
    }
    func scalar<T>(_ initial: T) throws -> T {
        var a = address; var value = initial; var size = UInt32(MemoryLayout<T>.size)
        let status = withUnsafeMutablePointer(to: &value) { AudioObjectGetPropertyData(object, &a, 0, nil, &size, $0) }
        try check(status, "读取音频属性")
        guard size == MemoryLayout<T>.size else { throw GuardError("音频属性长度异常") }
        return value
    }
    func string() throws -> String {
        var a = address; var value: CFString?; var size = UInt32(MemoryLayout<CFString?>.size)
        let status = withUnsafeMutablePointer(to: &value) { AudioObjectGetPropertyData(object, &a, 0, nil, &size, $0) }
        try check(status, "读取设备标识")
        guard let value else { throw GuardError("设备标识为空") }
        return value as String
    }
    func array() throws -> [UInt32] {
        var a = address; var size: UInt32 = 0
        try check(AudioObjectGetPropertyDataSize(object, &a, 0, nil, &size), "读取音频对象列表长度")
        guard size % 4 == 0 else { throw GuardError("音频对象列表格式异常") }
        if size == 0 { return [] }
        var result = [UInt32](repeating: 0, count: Int(size / 4))
        let capacity = size
        let status = result.withUnsafeMutableBytes { AudioObjectGetPropertyData(object, &a, 0, nil, &size, $0.baseAddress!) }
        try check(status, "读取音频对象列表")
        guard size <= capacity, size % 4 == 0 else { throw GuardError("音频对象列表发生变化") }
        return Array(result.prefix(Int(size / 4)))
    }
    func writeZero() throws {
        var a = address; var zero: Float32 = 0
        try check(AudioObjectSetPropertyData(object, &a, 0, nil, 4, &zero), "音量归零")
    }
}

func check(_ status: OSStatus, _ operation: String) throws {
    if status != noErr { throw GuardError("\(operation)失败 (OSStatus \(status))；请重新核对") }
}

final class Listeners {
    private var blocks: [Property: AudioObjectPropertyListenerBlock] = [:]
    var count: Int { blocks.count }
    func replace(_ properties: Set<Property>, changed: @escaping () -> Void) throws {
        for key in Set(blocks.keys).subtracting(properties) { remove(key) }
        for key in properties where blocks[key] == nil {
            let block: AudioObjectPropertyListenerBlock = { _, _ in changed() }
            var a = key.address
            try check(AudioObjectAddPropertyListenerBlock(key.object, &a, .main, block), "注册系统通知")
            blocks[key] = block
        }
    }
    private func remove(_ key: Property) {
        guard let block = blocks.removeValue(forKey: key) else { return }
        var a = key.address
        AudioObjectRemovePropertyListenerBlock(key.object, &a, .main, block)
    }
    func clear() { for key in Array(blocks.keys) { remove(key) } }
    deinit { clear() }
}

public final class DeadlineScheduler: GuardScheduler {
    private var timer: DispatchSourceTimer?
    public init() {}
    public func schedule(at deadline: TimeInterval, action: @escaping () -> Void) {
        cancel()
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + max(0, deadline - ProcessInfo.processInfo.systemUptime), leeway: .milliseconds(100))
        timer.setEventHandler(handler: action); self.timer = timer; timer.resume()
    }
    public func cancel() { timer?.setEventHandler {}; timer?.cancel(); timer = nil }
    deinit { cancel() }
}
