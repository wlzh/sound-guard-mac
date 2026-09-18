import Foundation
import GuardCore
import GuardPlatform
import Darwin

// Opt-in, bounded hardware check. Never writes volume or changes preferences.
func runSignalRetryProbe() -> Int32 {
    do { try FileManager.default.createDirectory(at: statusDirectory, withIntermediateDirectories: true) }
    catch { print("SIGNAL_RETRY_PROBE=ABORTED; cannot create lock directory"); return 1 }
    let lock = open(statusDirectory.appendingPathComponent("instance.lock").path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
    guard lock >= 0 else { return 1 }
    defer { close(lock) }
    guard flock(lock, LOCK_EX | LOCK_NB) == 0 else {
        print("SIGNAL_RETRY_PROBE=ABORTED; quit the running app first")
        return 1
    }
    let preferences = Preferences.decode(UserDefaults.standard.data(forKey: "preferences.v1"))
    guard preferences.detectSilentStream else {
        print("SIGNAL_RETRY_PROBE=ABORTED; enable strict detection explicitly first")
        return 1
    }
    let audio = SystemAudio()
    defer { audio.stop() }
    do {
        guard let initial = try audio.currentDevice(), initial.volume == 0, initial.controllable else {
            print("SIGNAL_RETRY_PROBE=ABORTED; requires zero volume; no volume was changed")
            return 1
        }
        for cycle in 1...3 {
            try audio.start()
            guard let device = try audio.currentDevice(), device.id == initial.id,
                  device.selectionID == initial.selectionID, device.volume == 0 else {
                throw GuardError("Device or volume changed")
            }
            try audio.setMonitoring(device: device, signal: true)
            RunLoop.main.run(until: Date().addingTimeInterval(5))
            let playback = try audio.playback(for: device, signal: true)
            guard audio.signalHasFreshSamples else { throw GuardError("No fresh signal samples") }
            print("SIGNAL_CYCLE=\(cycle); FRESH_SAMPLES=true; PLAYBACK=\(playback)")
            fflush(stdout)
            audio.stop()
            guard !audio.signalActive, audio.listenerCount == 0 else { throw GuardError("Resources not released") }
            if cycle < 3 { RunLoop.main.run(until: Date().addingTimeInterval(3)) }
        }
        guard try audio.currentDevice()?.volume == 0 else { throw GuardError("Volume changed during probe") }
        print("SIGNAL_RETRY_PROBE=PASS; CYCLES=3; VOLUME_WRITES=0")
        return 0
    } catch {
        print("SIGNAL_RETRY_PROBE=FAIL; \(error.localizedDescription)")
        return 1
    }
}
