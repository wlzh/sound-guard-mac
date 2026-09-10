import AppKit
import ServiceManagement
import GuardCore
import GuardPlatform
import Darwin

let repository = "https://github.com/wlzh/sound-guard-mac"
let statusRequest = Notification.Name("uk.869hr.SoundGuard.requestStatus")
let statusDirectory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("uk.869hr.SoundGuard")

final class SettingsDocument: NSView { override var isFlipped: Bool { true } }

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSWindowDelegate {
    let audio = SystemAudio()
    let defaults = UserDefaults.standard
    lazy var controller = GuardController(audio: audio, scheduler: DeadlineScheduler(),
        preferences: Preferences.decode(defaults.data(forKey: "preferences.v1")))
    var status: NSStatusItem!
    var settings: NSWindow?
    var about: NSWindow?
    var minutesField: NSTextField?
    var deviceButtons: [NSButton: String] = [:]
    var deviceNames: [String: String] = [:]
    var observers: [NSObjectProtocol] = []
    var lockFD: Int32 = -1
    var statusObserver: NSObjectProtocol?
    var selectedSettingsPage = 0
    var settingsFeedback: NSTextField?
    var previewDevices: [OutputDevice]?
    var previewCurrent: OutputDevice?
    var previewState: GuardState?
    var displayDevice: OutputDevice? { previewCurrent ?? controller.device }
    var displayState: GuardState { previewState ?? controller.state }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("uk.869hr.SoundGuard")
        do { try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true) }
        catch { showError("无法建立单实例锁目录：" + error.localizedDescription); NSApp.terminate(nil); return }
        lockFD = open(directory.appendingPathComponent("instance.lock").path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard lockFD >= 0, flock(lockFD, LOCK_EX | LOCK_NB) == 0 else { NSApp.terminate(nil); return }
        NSApp.setActivationPolicy(.accessory)
        status = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        status.button?.image = BrandAssets.mark()
        status.button?.setAccessibilityLabel("声音守卫：声波盾牌")
        let menu = NSMenu(); menu.delegate = self; status.menu = menu
        controller.onUpdate = { [weak self] in self?.updateStatus() }
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            self?.controller.setSleeping(true)
        })
        observers.append(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.controller.setSleeping(false)
        })
        controller.start()
        statusObserver = DistributedNotificationCenter.default().addObserver(forName: statusRequest, object: nil, queue: .main) { [weak self] _ in
            self?.exportStatus()
        }
    }
    func applicationWillTerminate(_ notification: Notification) {
        controller.stop()
        observers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        if lockFD >= 0 { close(lockFD); lockFD = -1 }
        if let statusObserver { DistributedNotificationCenter.default().removeObserver(statusObserver) }
    }
    func exportStatus() {
        let snapshot: [String: Any] = ["pid": ProcessInfo.processInfo.processIdentifier,
            "updatedAt": Date().timeIntervalSince1970, "version": AppVersion.current,
            "state": String(describing: controller.state), "volume": controller.device.map { Double($0.volume) } ?? -1,
            "enabled": controller.preferences.enabled, "minutes": controller.preferences.minutes,
            "monitorActive": controller.monitorActive, "listeners": audio.listenerCount,
            "playbackListeners": audio.playbackListenerCount, "signalActive": audio.signalActive,
            "lastAction": controller.lastAction]
        do {
            let file = statusDirectory.appendingPathComponent("status.json")
            try JSONSerialization.data(withJSONObject: snapshot, options: [.sortedKeys, .prettyPrinted]).write(to: file, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        } catch { /* On-demand diagnostics must never affect protection. */ }
    }
    func updateStatus() { status?.button?.toolTip = "声音守卫：" + stateText }
    var stateText: String {
        switch controller.state {
        case .paused: return "保护已暂停"
        case .sleeping: return "睡眠中"
        case .unavailable: return "没有可用输出设备"
        case .excluded: return "当前设备未启用保护"
        case .unsupported: return "当前设备不支持软件音量控制"
        case .zero: return "音量为 0，检测已休眠"
        case .muted: return "系统已静音，检测已休眠"
        case .playing: return "有播放活动，保持当前音量"
        case .waiting(let deadline):
            return "播放空闲，约 \(max(1, Int(ceil((deadline - ProcessInfo.processInfo.systemUptime) / 60)))) 分钟后归零"
        case .fault(let message): return "保护异常：" + message
        }
    }
    func save(_ p: Preferences) {
        defaults.set(try? JSONEncoder().encode(p), forKey: "preferences.v1"); controller.configure(p)
    }
    @objc func toggleEnabled() { var p = controller.preferences; p.enabled.toggle(); save(p) }
    @objc func zeroNow() { controller.zeroNow() }
    @objc func retry() { controller.retry() }
    @objc func quit() { NSApp.terminate(nil) }
    @objc func openGuide() {
        if let resource = Bundle.main.resourceURL?.appendingPathComponent("docs/USER_GUIDE.md"),
           FileManager.default.fileExists(atPath: resource.path) { NSWorkspace.shared.open(resource) }
        else { NSWorkspace.shared.open(URL(string: repository + "/blob/main/docs/USER_GUIDE.md")!) }
    }
    func checkbox(_ title: String, on: Bool, action: Selector) -> NSButton {
        let button = NSButton(checkboxWithTitle: title, target: self, action: action)
        button.state = on ? .on : .off; return button
    }
    func window(_ title: String, width: CGFloat, height: CGFloat) -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = title; window.isReleasedWhenClosed = false; window.delegate = self; window.center(); return window
    }
    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        if window === settings { settings = nil; minutesField = nil; settingsFeedback = nil; deviceButtons.removeAll(); deviceNames.removeAll() }
        if window === about { about = nil }
    }
    func present(_ window: NSWindow) { NSApp.activate(ignoringOtherApps: true); window.makeKeyAndOrderFront(nil) }
    @objc func refreshSettings() { rebuildSettings() }
    @objc func changeEnabled(_ sender: NSSwitch) { var p = controller.preferences; p.enabled = sender.state == .on; save(p) }
    @objc func changeBuiltIn(_ sender: NSSwitch) { var p = controller.preferences; p.protectBuiltIn = sender.state == .on; save(p) }
    @objc func changeDevice(_ sender: NSButton) {
        guard let key = deviceButtons[sender] else { return }
        var p = controller.preferences
        p.selectedDevices[key] = sender.state == .on ? deviceNames[key] : nil
        save(p)
    }
    @objc func changeSignal(_ sender: NSSwitch) {
        if sender.state == .on {
            let alert = NSAlert(); alert.messageText = "开启静音流检测？"
            alert.informativeText = "会在受保护设备音量非零时读取系统音频信号，可能出现系统音频录制权限提示。不保存音频；开启后 CPU 开销会增加。权限拒绝或检测异常会暂停保护，可关闭此选项恢复默认模式。"
            alert.addButton(withTitle: "开启"); alert.addButton(withTitle: "取消")
            guard alert.runModal() == .alertFirstButtonReturn else { sender.state = .off; return }
        }
        var p = controller.preferences; p.detectSilentStream = sender.state == .on; save(p)
    }
    @objc func applyMinutes() {
        guard let raw = minutesField?.stringValue, let value = Int(raw), (1...120).contains(value) else {
            showError("请输入 1–120 的整数分钟数"); return
        }
        var p = controller.preferences; p.minutes = value; save(p)
        settingsFeedback?.stringValue = "已保存，空闲计时已重新开始。"
    }
    @objc func changeLogin(_ sender: NSSwitch) {
        do {
            if sender.state == .on { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
        } catch { showError("登录启动设置失败：" + error.localizedDescription) }
        rebuildSettings()
    }
    func showError(_ message: String) { let alert = NSAlert(); alert.messageText = message; alert.runModal() }
    @objc func openAuthor() { NSWorkspace.shared.open(URL(string: "https://x.com/wlzh")!) }
    @objc func openWebsite() { NSWorkspace.shared.open(URL(string: "https://869hr.uk")!) }
    @objc func openRepository() { NSWorkspace.shared.open(URL(string: repository)!) }
}

if CommandLine.arguments.contains("--status") {
    let since = Date().timeIntervalSince1970
    DistributedNotificationCenter.default().postNotificationName(statusRequest, object: nil, userInfo: nil, deliverImmediately: true)
    var received = false
    for _ in 0..<20 {
        if let data = try? Data(contentsOf: statusDirectory.appendingPathComponent("status.json")),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let updated = json["updatedAt"] as? Double, updated >= since {
            print(String(data: data, encoding: .utf8)!); received = true; break
        }
        Thread.sleep(forTimeInterval: 0.1)
    }
    if !received { fputs("No fresh response from the running app\n", stderr); exit(1) }
} else if CommandLine.arguments.contains("--verify-auto-zero"), CommandLine.arguments.contains("--confirm-zero") {
    let audio = SystemAudio()
    guard let device = try audio.currentDevice(), device.builtInSpeaker, device.controllable, device.volume > 0, !device.muted else {
        print("VERIFY_ABORTED: requires a manually enabled built-in speaker; no volume was changed")
        exit(1)
    }
    var preferences = Preferences(); preferences.minutes = 1
    let controller = GuardController(audio: audio, scheduler: DeadlineScheduler(), preferences: preferences)
    var previous: GuardState?
    controller.onUpdate = {
        if previous != controller.state {
            print("LIVE_STATE=\(controller.state) listeners=\(audio.listenerCount) playbackListeners=\(audio.playbackListenerCount)")
            fflush(stdout); previous = controller.state
        }
    }
    controller.start()
    RunLoop.main.run(until: Date().addingTimeInterval(75))
    let passed = controller.lastAction.hasPrefix("已自动归零") && controller.state == .zero && controller.device?.volume == 0 && audio.playbackListenerCount == 0 && !audio.signalActive
    controller.stop()
    print("AUTO_ZERO_HARDWARE=\(passed ? "PASS" : "NOT_PASSED")")
    exit(passed ? 0 : 1)
} else if let index = CommandLine.arguments.firstIndex(of: "--probe-zero"), CommandLine.arguments.count > index + 1,
   let seconds = Double(CommandLine.arguments[index + 1]), (1...3600).contains(seconds) {
    let audio = SystemAudio()
    let controller = GuardController(audio: audio, scheduler: DeadlineScheduler())
    var valid = true
    controller.onUpdate = {
        if controller.device?.volume != 0 || controller.state != .zero {
            print("PROBE_STATE=\(controller.state)")
            valid = false; controller.stop()
        }
    }
    var before = rusage(); getrusage(RUSAGE_SELF, &before)
    let start = ProcessInfo.processInfo.systemUptime
    controller.start()
    if valid { RunLoop.main.run(until: Date().addingTimeInterval(seconds)) }
    let elapsed = ProcessInfo.processInfo.systemUptime - start
    var after = rusage(); getrusage(RUSAGE_SELF, &after)
    func cpu(_ r: rusage) -> Double {
        Double(r.ru_utime.tv_sec + r.ru_stime.tv_sec) + Double(r.ru_utime.tv_usec + r.ru_stime.tv_usec) / 1_000_000
    }
    print("ZERO_PROBE=\(valid ? "PASS" : "ABORTED_NONZERO_OR_FAULT") elapsed=\(elapsed) cpuPercent=\((cpu(after) - cpu(before)) / elapsed * 100) peakRSSMiB=\(Double(after.ru_maxrss) / 1048576) baselineListeners=\(audio.listenerCount) playbackListeners=\(audio.playbackListenerCount) signal=\(audio.signalActive)")
    controller.stop(); exit(valid ? 0 : 1)
} else if CommandLine.arguments.contains("--diagnose") {
    let audio = SystemAudio()
    do {
        let current = try audio.currentDevice()
        let devices = try audio.devices()
        let data: [String: Any] = ["version": AppVersion.current, "build": AppVersion.build,
            "deviceCount": devices.count, "currentIsBuiltInSpeaker": current?.builtInSpeaker ?? false,
            "volume": current.map { Double($0.volume) } ?? -1, "muted": current?.muted ?? false,
            "controllable": current?.controllable ?? false, "listeners": audio.listenerCount,
            "playback": try current.map { String(describing: try audio.playback(for: $0, signal: false)) } ?? "unavailable"]
        print(String(data: try JSONSerialization.data(withJSONObject: data, options: [.prettyPrinted, .sortedKeys]), encoding: .utf8)!)
    } catch { fputs("\(error.localizedDescription)\n", stderr); exit(1) }
} else if CommandLine.arguments.contains("--self-test-ui") {
    let index = CommandLine.arguments.firstIndex(of: "--render-previews")
    let output = index.flatMap { CommandLine.arguments.count > $0 + 1 ? URL(fileURLWithPath: CommandLine.arguments[$0 + 1]) : nil }
    try runUIChecks(outputDirectory: output)
} else {
    let app = NSApplication.shared
    let delegate = AppDelegate(); app.delegate = delegate
    withExtendedLifetime(delegate) { app.run() }
}
