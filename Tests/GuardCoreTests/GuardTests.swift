import Foundation
import GuardCore
import GuardPlatform
import SignalMeter

private var failures = 0
private var assertions = 0
class XCTestCase {
    func setUp() {}
    func tearDown() {}
}
func XCTAssertTrue(_ value: @autoclosure () -> Bool, file: StaticString = #file, line: UInt = #line) {
    assertions += 1
    if !value() { failures += 1; print("FAIL \(file):\(line)") }
}
func XCTAssertFalse(_ value: @autoclosure () -> Bool, file: StaticString = #file, line: UInt = #line) {
    XCTAssertTrue(!value(), file: file, line: line)
}
func XCTAssertEqual<T: Equatable>(_ lhs: T, _ rhs: T, file: StaticString = #file, line: UInt = #line) {
    assertions += 1
    if lhs != rhs { failures += 1; print("FAIL \(file):\(line) \(lhs) != \(rhs)") }
}
func XCTAssertNil<T>(_ value: @autoclosure () -> T?, file: StaticString = #file, line: UInt = #line) {
    XCTAssertTrue(value() == nil, file: file, line: line)
}
func XCTAssertNotNil<T>(_ value: @autoclosure () -> T?, file: StaticString = #file, line: UInt = #line) {
    XCTAssertTrue(value() != nil, file: file, line: line)
}

private func speaker(_ volume: Float = 0.4, id: UInt32 = 1, uid: String = "speaker", route: String = "speaker",
                     builtIn: Bool = true, muted: Bool = false, controllable: Bool = true) -> OutputDevice {
    OutputDevice(id: id, uid: uid, name: "Synthetic output", route: route, builtInSpeaker: builtIn,
                 volume: volume, muted: muted, controllable: controllable)
}

final class PolicyTests: XCTestCase {
    func testDefaultSettings() {
        let p = Preferences(); XCTAssertEqual(p.timeout, 300); XCTAssertTrue(p.enabled)
        XCTAssertTrue(p.protectBuiltIn); XCTAssertFalse(p.detectSilentStream); XCTAssertTrue(p.selectedDevices.isEmpty)
    }
    func testTimeoutValidation() {
        for (minutes, seconds) in [(1, 60), (120, 7200), (0, 300), (-1, 300), (121, 300)] {
            var p = Preferences(); p.minutes = minutes; XCTAssertEqual(p.timeout, Double(seconds))
        }
    }
    func testPreferencesRoundTrip() throws {
        var p = Preferences(); p.minutes = 17; p.detectSilentStream = true; p.selectedDevices["uid|route"] = "Speaker"
        XCTAssertEqual(Preferences.decode(try JSONEncoder().encode(p)), p)
    }
    func testCorruptPreferencesUseDefaults() { XCTAssertEqual(Preferences.decode(Data("bad".utf8)), Preferences()) }
    func testInvalidPersistedTimeoutSanitized() throws {
        var p = Preferences(); p.minutes = -5
        XCTAssertEqual(Preferences.decode(try JSONEncoder().encode(p)).minutes, 5)
    }
    func testDefaultOnlyBuiltIn() {
        let p = Preferences(); XCTAssertTrue(p.includes(speaker())); XCTAssertFalse(p.includes(speaker(builtIn: false)))
    }
    func testDeviceIdentityNotName() {
        var p = Preferences(); let external = speaker(uid: "external", builtIn: false)
        p.selectedDevices[external.selectionID] = external.name
        XCTAssertTrue(p.includes(external)); XCTAssertFalse(p.includes(speaker(uid: "replacement", builtIn: false)))
        XCTAssertFalse(p.includes(speaker(uid: "external", route: "headphone", builtIn: false)))
    }
    func testBuiltInCanBeDisabled() { var p = Preferences(); p.protectBuiltIn = false; XCTAssertFalse(p.includes(speaker())) }
    func testInitialGraceAndExactDeadline() {
        var policy = IdlePolicy(); let p = Preferences()
        XCTAssertFalse(policy.evaluate(device: speaker(), playback: .idle, preferences: p, sleeping: false, now: 10))
        XCTAssertEqual(policy.deadline, 310)
        XCTAssertFalse(policy.evaluate(device: speaker(), playback: .idle, preferences: p, sleeping: false, now: 309.99))
        XCTAssertTrue(policy.evaluate(device: speaker(), playback: .idle, preferences: p, sleeping: false, now: 310))
    }
    func testPlayingNeverHasDeadline() {
        var policy = IdlePolicy()
        for now in [0.0, 301, 10000] {
            XCTAssertFalse(policy.evaluate(device: speaker(), playback: .playing, preferences: .init(), sleeping: false, now: now))
            XCTAssertNil(policy.deadline)
        }
    }
    func testPlaybackResetsDeadline() {
        var policy = IdlePolicy()
        _ = policy.evaluate(device: speaker(), playback: .idle, preferences: .init(), sleeping: false, now: 0)
        _ = policy.evaluate(device: speaker(), playback: .playing, preferences: .init(), sleeping: false, now: 290)
        _ = policy.evaluate(device: speaker(), playback: .idle, preferences: .init(), sleeping: false, now: 299)
        XCTAssertEqual(policy.deadline, 599)
    }
    func testZeroCancelsAndPlaybackDoesNotRestore() {
        var policy = IdlePolicy()
        _ = policy.evaluate(device: speaker(), playback: .idle, preferences: .init(), sleeping: false, now: 0)
        XCTAssertFalse(policy.evaluate(device: speaker(0), playback: .playing, preferences: .init(), sleeping: false, now: 500))
        XCTAssertEqual(policy.state, .zero); XCTAssertNil(policy.deadline)
    }
    func testManualVolumeChangeRestarts() {
        var policy = IdlePolicy()
        _ = policy.evaluate(device: speaker(), playback: .idle, preferences: .init(), sleeping: false, now: 0)
        XCTAssertFalse(policy.evaluate(device: speaker(0.6), playback: .idle, preferences: .init(), sleeping: false, now: 299))
        XCTAssertEqual(policy.deadline, 599)
    }
    func testDeviceChangeRestarts() {
        var policy = IdlePolicy()
        _ = policy.evaluate(device: speaker(), playback: .idle, preferences: .init(), sleeping: false, now: 0)
        _ = policy.evaluate(device: speaker(id: 2), playback: .idle, preferences: .init(), sleeping: false, now: 299)
        XCTAssertEqual(policy.deadline, 599)
    }
    func testRouteChangeRestarts() {
        var policy = IdlePolicy()
        _ = policy.evaluate(device: speaker(), playback: .idle, preferences: .init(), sleeping: false, now: 0)
        _ = policy.evaluate(device: speaker(route: "other"), playback: .idle, preferences: .init(), sleeping: false, now: 299)
        XCTAssertEqual(policy.deadline, 599)
    }
    func testBlockedStatesDiscardDeadline() {
        var disabled = Preferences(); disabled.enabled = false
        let scenarios: [(OutputDevice?, Playback, Preferences, Bool, GuardState)] = [
            (speaker(), .idle, disabled, false, .paused), (speaker(), .idle, .init(), true, .sleeping),
            (nil, .idle, .init(), false, .unavailable), (speaker(builtIn: false), .idle, .init(), false, .excluded),
            (speaker(controllable: false), .idle, .init(), false, .unsupported),
            (speaker(muted: true), .idle, .init(), false, .muted),
            (speaker(), .unknown, .init(), false, .fault("播放状态未知"))]
        for (device, playback, preferences, sleeping, state) in scenarios {
            var policy = IdlePolicy()
            _ = policy.evaluate(device: speaker(), playback: .idle, preferences: .init(), sleeping: false, now: 0)
            XCTAssertFalse(policy.evaluate(device: device, playback: playback, preferences: preferences, sleeping: sleeping, now: 999))
            XCTAssertEqual(policy.state, state); XCTAssertNil(policy.deadline)
        }
    }
    func testInvalidVolumeCannotTrigger() {
        for volume: Float in [.nan, .infinity, -0.1, 1.1] {
            var policy = IdlePolicy()
            XCTAssertFalse(policy.evaluate(device: speaker(volume), playback: .idle, preferences: .init(), sleeping: false, now: 1000))
            XCTAssertEqual(policy.state, .fault("音量读数无效"))
        }
    }
}

private final class FakeAudio: AudioService {
    var onChange: (() -> Void)?
    var device: OutputDevice? = speaker()
    var activity: Playback = .idle
    var monitored: OutputDevice?
    var signal = false
    var writes = 0
    var reads = 0
    var failRead = false, failMonitor = false, failWrite = false, failStart = false
    var starts = 0, stops = 0
    func start() throws { starts += 1; if failStart { throw GuardError("start") } }
    func stop() { stops += 1; monitored = nil }
    func currentDevice() throws -> OutputDevice? {
        reads += 1; if failRead { throw GuardError("read") }; return device
    }
    func devices() throws -> [OutputDevice] { device.map { [$0] } ?? [] }
    func setMonitoring(device: OutputDevice?, signal: Bool) throws {
        if failMonitor && device != nil { throw GuardError("monitor") }; monitored = device; self.signal = signal
    }
    func playback(for device: OutputDevice, signal: Bool) throws -> Playback { activity }
    func zero(_ expected: OutputDevice) throws {
        if failWrite { throw GuardError("write") }
        guard device == expected else { throw GuardError("changed") }
        writes += 1; device = speaker(0, id: expected.id, uid: expected.uid, route: expected.route, builtIn: expected.builtInSpeaker)
    }
}
private final class FakeScheduler: GuardScheduler {
    var action: (() -> Void)?
    var deadline: TimeInterval?
    func schedule(at deadline: TimeInterval, action: @escaping () -> Void) { self.deadline = deadline; self.action = action }
    func cancel() { action = nil; deadline = nil }
}

final class ControllerTests: XCTestCase {
    private var audio: FakeAudio!, scheduler: FakeScheduler!, controller: GuardController!
    private var time = 0.0
    override func setUp() {
        audio = FakeAudio(); scheduler = FakeScheduler(); time = 0
        controller = GuardController(audio: audio, scheduler: scheduler, now: { [unowned self] in self.time })
    }
    override func tearDown() { controller.stop(); controller = nil }
    func testAutoZeroAndRelease() {
        controller.start(); XCTAssertNotNil(audio.monitored); time = 300; scheduler.action?()
        XCTAssertEqual(audio.writes, 1); XCTAssertNil(audio.monitored); XCTAssertNil(scheduler.action)
        XCTAssertEqual(controller.state, .zero)
    }
    func testZeroDoesNotMonitor() {
        audio.device = speaker(0); controller.start()
        XCTAssertNil(audio.monitored); XCTAssertNil(scheduler.action); XCTAssertFalse(controller.monitorActive)
    }
    func testMutedDoesNotMonitor() {
        audio.device = speaker(muted: true); controller.start(); XCTAssertNil(audio.monitored)
        XCTAssertEqual(controller.state, .muted)
    }
    func testExcludedDoesNotMonitor() {
        audio.device = speaker(builtIn: false); controller.start(); XCTAssertNil(audio.monitored)
        XCTAssertEqual(controller.state, .excluded)
    }
    func testStaleTimerIgnoredOnPlayback() {
        controller.start(); let old = scheduler.action
        audio.activity = .playing; audio.onChange?(); time = 300; old?()
        XCTAssertEqual(audio.writes, 0); XCTAssertNil(scheduler.action)
    }
    func testStaleTimerIgnoredAfterStop() {
        controller.start(); let old = scheduler.action; controller.stop(); time = 300; old?()
        XCTAssertEqual(audio.writes, 0); XCTAssertNil(audio.onChange)
    }
    func testDeadlineRechecksPlayback() {
        controller.start(); audio.activity = .playing; time = 300; scheduler.action?()
        XCTAssertEqual(audio.writes, 0); XCTAssertEqual(controller.state, .playing)
    }
    func testDeadlineRechecksDevice() {
        controller.start(); audio.device = speaker(id: 2); time = 300; scheduler.action?()
        XCTAssertEqual(audio.writes, 0); XCTAssertEqual(scheduler.deadline, 600)
    }
    func testWakeRestartsGrace() {
        controller.start(); controller.setSleeping(true); time = 2000
        XCTAssertNil(audio.monitored); controller.setSleeping(false)
        XCTAssertEqual(scheduler.deadline, 2300); XCTAssertEqual(audio.writes, 0)
    }
    func testPreferenceChangeRestartsGrace() {
        controller.start(); time = 250; var p = Preferences(); p.minutes = 1; controller.configure(p)
        XCTAssertEqual(scheduler.deadline, 310)
    }
    func testPauseAndResume() {
        controller.start(); var p = Preferences(); p.enabled = false; controller.configure(p)
        XCTAssertNil(audio.monitored); XCTAssertNil(scheduler.action)
        time = 1000; p.enabled = true; controller.configure(p); XCTAssertEqual(scheduler.deadline, 1300)
    }
    func testSignalSwitchPassedToAdapter() {
        controller.start(); var p = Preferences(); p.detectSilentStream = true; controller.configure(p)
        XCTAssertTrue(audio.signal); p.detectSilentStream = false; controller.configure(p); XCTAssertFalse(audio.signal)
    }
    func testWriteFailureLatchesWithoutRetryLoop() {
        controller.start(); audio.failWrite = true; time = 300; scheduler.action?()
        XCTAssertEqual(controller.state, .fault("write")); XCTAssertNil(scheduler.action); XCTAssertNil(audio.monitored)
        audio.onChange?(); XCTAssertEqual(audio.writes, 0); XCTAssertNil(audio.monitored)
        audio.failWrite = false; controller.retry(); XCTAssertEqual(scheduler.deadline, 600)
    }
    func testReadFailureDoesNotMute() {
        controller.start(); audio.failRead = true; time = 300; scheduler.action?()
        XCTAssertEqual(audio.writes, 0); XCTAssertEqual(controller.state, .fault("read"))
    }
    func testListenerFailureDoesNotMute() {
        audio.failMonitor = true; controller.start(); XCTAssertNil(scheduler.action)
        XCTAssertEqual(controller.state, .fault("monitor")); XCTAssertEqual(audio.writes, 0)
    }
    func testStartFailureVisible() {
        audio.failStart = true; controller.start(); XCTAssertEqual(controller.state, .fault("start"))
    }
    func testManualZeroAllowedDuringPlayback() {
        audio.activity = .playing; controller.start(); controller.zeroNow()
        XCTAssertEqual(audio.writes, 1); XCTAssertEqual(controller.state, .zero)
    }
    func testManualZeroRejectsExcluded() {
        audio.device = speaker(builtIn: false); controller.start(); controller.zeroNow(); XCTAssertEqual(audio.writes, 0)
    }
    func testRestorePlaybackNeverWritesNonzero() {
        audio.device = speaker(0); controller.start(); audio.activity = .playing; audio.onChange?()
        XCTAssertEqual(audio.writes, 0); XCTAssertEqual(audio.device?.volume, 0)
    }
    func testSelectedExternalGetsProtectionAndUnselectStops() {
        let external = speaker(uid: "usb", builtIn: false); audio.device = external; controller.start()
        var p = Preferences(); p.selectedDevices[external.selectionID] = external.name; controller.configure(p)
        XCTAssertNotNil(audio.monitored); p.selectedDevices = [:]; controller.configure(p); XCTAssertNil(audio.monitored)
    }
    func testUnknownPlaybackCancels() {
        controller.start(); audio.activity = .unknown; audio.onChange?()
        XCTAssertNil(scheduler.action); XCTAssertEqual(audio.writes, 0)
    }
}

final class MeterTests: XCTestCase {
    func testTapConfigurationDoesNotMuteOrCaptureMicrophone() {
        let description = TapConfiguration.description(deviceUID: "synthetic-output-uid")
        XCTAssertEqual(description.deviceUID, "synthetic-output-uid")
        XCTAssertTrue(description.isExclusive); XCTAssertTrue(description.isPrivate)
        XCTAssertTrue(description.processes.isEmpty)
        XCTAssertEqual(description.muteBehavior, .unmuted)
    }
    func testSignalStartupGrace() throws {
        var health = SignalHealth(started: 1)
        XCTAssertEqual(try health.evaluate(now: 100, buffer: 0, sound: 0, invalid: false), .playing)
    }
    func testSignalMissingCallbacksFail() {
        var health = SignalHealth(started: 1)
        do { _ = try health.evaluate(now: 4_000_000_000, buffer: 0, sound: 0, invalid: false); XCTAssertTrue(false) }
        catch { XCTAssertTrue(true) }
    }
    func testSignalStaleCallbacksFail() {
        var health = SignalHealth(started: 1)
        do { _ = try health.evaluate(now: 4_000_000_000, buffer: 1_000_000_000, sound: 0, invalid: false); XCTAssertTrue(false) }
        catch { XCTAssertTrue(true) }
    }
    func testSignalDigitalSilenceTransitions() throws {
        var health = SignalHealth(started: 1)
        XCTAssertEqual(try health.evaluate(now: 100, buffer: 50, sound: 0, invalid: false), .playing)
        XCTAssertEqual(try health.evaluate(now: 1_000_000_000, buffer: 999_000_000, sound: 0, invalid: false), .idle)
    }
    func testSignalShortSoundRetainedAcrossDelayedPoll() throws {
        var health = SignalHealth(started: 1)
        _ = try health.evaluate(now: 100, buffer: 50, sound: 0, invalid: false)
        XCTAssertEqual(try health.evaluate(now: 3_000_000_000, buffer: 2_990_000_000, sound: 1_000_000_000, invalid: false), .playing)
        XCTAssertEqual(try health.evaluate(now: 3_500_000_000, buffer: 3_490_000_000, sound: 1_000_000_000, invalid: false), .idle)
    }
    func testSignalInvalidClockAndSamplesFail() {
        for (now, buffer, invalid): (UInt64, UInt64, Bool) in [(2, 3, false), (2, 1, true)] {
            var health = SignalHealth(started: 1)
            do { _ = try health.evaluate(now: now, buffer: buffer, sound: 0, invalid: invalid); XCTAssertTrue(false) }
            catch { XCTAssertTrue(true) }
        }
    }
    func testDigitalSilence() {
        let meter = sg_create()!; defer { sg_destroy(meter) }
        let samples: [Float] = [0, -0, 0]; samples.withUnsafeBufferPointer { sg_consume(meter, $0.baseAddress, $0.count, 100) }
        XCTAssertEqual(sg_last_buffer(meter), 100); XCTAssertEqual(sg_last_sound(meter), 0)
    }
    func testQuietSoundIsNotSilence() {
        let meter = sg_create()!; defer { sg_destroy(meter) }
        let samples: [Float] = [0, Float.leastNonzeroMagnitude]
        samples.withUnsafeBufferPointer { sg_consume(meter, $0.baseAddress, $0.count, 200) }
        XCTAssertEqual(sg_last_sound(meter), 200)
    }
    func testInvalidSamples() {
        let meter = sg_create()!; defer { sg_destroy(meter) }
        let samples: [Float] = [.nan]; samples.withUnsafeBufferPointer { sg_consume(meter, $0.baseAddress, $0.count, 300) }
        XCTAssertEqual(sg_invalid(meter), 1)
    }
    func testMissingBufferIsNotSilenceEvidence() {
        let meter = sg_create()!; defer { sg_destroy(meter) }
        sg_consume(meter, nil, 0, 300); XCTAssertEqual(sg_last_buffer(meter), 0)
    }
}

let policyTests = PolicyTests()
let controllerTests = ControllerTests()
let meterTests = MeterTests()
let suites: [(XCTestCase, [(String, () throws -> Void)])] = [
    (policyTests, [
        ("defaults", policyTests.testDefaultSettings), ("timeout bounds", policyTests.testTimeoutValidation),
        ("preferences persistence", policyTests.testPreferencesRoundTrip), ("corrupt preferences", policyTests.testCorruptPreferencesUseDefaults),
        ("invalid saved timeout", policyTests.testInvalidPersistedTimeoutSanitized), ("built-in default", policyTests.testDefaultOnlyBuiltIn),
        ("stable identity", policyTests.testDeviceIdentityNotName), ("disable built-in", policyTests.testBuiltInCanBeDisabled),
        ("exact deadline", policyTests.testInitialGraceAndExactDeadline), ("continuous playback", policyTests.testPlayingNeverHasDeadline),
        ("playback reset", policyTests.testPlaybackResetsDeadline), ("zero state", policyTests.testZeroCancelsAndPlaybackDoesNotRestore),
        ("volume change", policyTests.testManualVolumeChangeRestarts), ("device change", policyTests.testDeviceChangeRestarts),
        ("route change", policyTests.testRouteChangeRestarts), ("blocked states", policyTests.testBlockedStatesDiscardDeadline),
        ("invalid volume", policyTests.testInvalidVolumeCannotTrigger)
    ]),
    (controllerTests, [
        ("auto zero cleanup", controllerTests.testAutoZeroAndRelease), ("zero no monitor", controllerTests.testZeroDoesNotMonitor),
        ("mute no monitor", controllerTests.testMutedDoesNotMonitor), ("excluded no monitor", controllerTests.testExcludedDoesNotMonitor),
        ("stale timer playback", controllerTests.testStaleTimerIgnoredOnPlayback), ("stale timer exit", controllerTests.testStaleTimerIgnoredAfterStop),
        ("deadline playback check", controllerTests.testDeadlineRechecksPlayback), ("deadline device check", controllerTests.testDeadlineRechecksDevice),
        ("wake grace", controllerTests.testWakeRestartsGrace), ("setting grace", controllerTests.testPreferenceChangeRestartsGrace),
        ("pause resume", controllerTests.testPauseAndResume), ("signal switch", controllerTests.testSignalSwitchPassedToAdapter),
        ("write failure latch", controllerTests.testWriteFailureLatchesWithoutRetryLoop), ("read failure", controllerTests.testReadFailureDoesNotMute),
        ("listener failure", controllerTests.testListenerFailureDoesNotMute), ("start failure", controllerTests.testStartFailureVisible),
        ("manual zero", controllerTests.testManualZeroAllowedDuringPlayback), ("manual excluded", controllerTests.testManualZeroRejectsExcluded),
        ("never restore", controllerTests.testRestorePlaybackNeverWritesNonzero), ("external selection", controllerTests.testSelectedExternalGetsProtectionAndUnselectStops),
        ("unknown playback", controllerTests.testUnknownPlaybackCancels)
    ]),
    (meterTests, [("tap configuration", meterTests.testTapConfigurationDoesNotMuteOrCaptureMicrophone),
                  ("signal startup", meterTests.testSignalStartupGrace), ("signal absent", meterTests.testSignalMissingCallbacksFail),
                  ("signal stale", meterTests.testSignalStaleCallbacksFail), ("signal silence", meterTests.testSignalDigitalSilenceTransitions),
                  ("signal delayed poll", meterTests.testSignalShortSoundRetainedAcrossDelayedPoll), ("signal corrupt", meterTests.testSignalInvalidClockAndSamplesFail),
                  ("digital silence", meterTests.testDigitalSilence), ("quiet sound", meterTests.testQuietSoundIsNotSilence),
                  ("invalid samples", meterTests.testInvalidSamples), ("missing callback", meterTests.testMissingBufferIsNotSilenceEvidence)])
]
var count = 0
for (suite, tests) in suites {
    for (name, test) in tests {
        count += 1; suite.setUp(); let before = failures
        do { try test() } catch { failures += 1; print("FAIL \(name): \(error)") }
        suite.tearDown(); print("\(failures == before ? "PASS" : "FAIL") \(name)")
    }
}
print("TESTS=\(count); ASSERTIONS=\(assertions); FAILURES=\(failures)")
exit(failures == 0 ? 0 : 1)
