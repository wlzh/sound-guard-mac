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

    func applicationDidFinishLaunching(_ notification: Notification) {
        let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("uk.869hr.SoundGuard")
        do { try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true) }
        catch { showError("无法建立单实例锁目录：" + error.localizedDescription); NSApp.terminate(nil); return }
        lockFD = open(directory.appendingPathComponent("instance.lock").path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard lockFD >= 0, flock(lockFD, LOCK_EX | LOCK_NB) == 0 else { NSApp.terminate(nil); return }
        NSApp.setActivationPolicy(.accessory)
        status = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        status.button?.image = NSImage(systemSymbolName: "speaker.badge.shield.checkmark", accessibilityDescription: "声音守卫")
            ?? NSImage(systemSymbolName: "speaker.wave.2", accessibilityDescription: "声音守卫")
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
    func menuWillOpen(_ menu: NSMenu) {
        menu.removeAllItems()
        label("声音守卫 · " + AppVersion.current, in: menu)
        label(stateText, in: menu)
        if let device = controller.device {
            label(device.name + (device.controllable ? " · 音量 \(Int(device.volume * 100))%" : " · 不可调节"), in: menu)
        }
        label(controller.lastAction, in: menu)
        menu.addItem(.separator())
        item(controller.preferences.enabled ? "暂停保护" : "恢复保护", #selector(toggleEnabled), in: menu)
        let zero = item("立即将当前受保护设备归零", #selector(zeroNow), in: menu)
        zero.isEnabled = controller.device.map { controller.preferences.includes($0) && $0.controllable } ?? false
        item("重新核对 / 重试", #selector(retry), in: menu)
        item("设置与设备选择…", #selector(showSettings), in: menu, key: ",")
        menu.addItem(.separator())
        item("关于声音守卫…", #selector(showAbout), in: menu)
        item("使用说明", #selector(openGuide), in: menu)
        item("退出声音守卫", #selector(quit), in: menu, key: "q")
    }
    func label(_ text: String, in menu: NSMenu) {
        let entry = NSMenuItem(title: text, action: nil, keyEquivalent: ""); entry.isEnabled = false; menu.addItem(entry)
    }
    @discardableResult func item(_ title: String, _ action: Selector, in menu: NSMenu, key: String = "") -> NSMenuItem {
        let entry = NSMenuItem(title: title, action: action, keyEquivalent: key); entry.target = self; menu.addItem(entry); return entry
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
    func text(_ value: String, bold: Bool = false) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: value)
        label.font = bold ? .boldSystemFont(ofSize: 14) : .systemFont(ofSize: 12)
        label.maximumNumberOfLines = 0; return label
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
        if window === settings { settings = nil; minutesField = nil; deviceButtons.removeAll(); deviceNames.removeAll() }
        if window === about { about = nil }
    }
    func present(_ window: NSWindow) { NSApp.activate(ignoringOtherApps: true); window.makeKeyAndOrderFront(nil) }
    @objc func showSettings() {
        if settings == nil { settings = window("声音守卫 · 设置", width: 540, height: 630) }
        rebuildSettings(); present(settings!)
    }
    func rebuildSettings() {
        guard let window = settings else { return }
        deviceButtons.removeAll(); deviceNames.removeAll()
        let stack = NSStackView(); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 14
        stack.edgeInsets = NSEdgeInsets(top: 22, left: 24, bottom: 22, right: 24)
        stack.addArrangedSubview(text("仅自动关小，不自动打开", bold: true))
        stack.addArrangedSubview(text("当前状态：" + stateText))
        stack.addArrangedSubview(checkbox("启用自动归零保护", on: controller.preferences.enabled, action: #selector(changeEnabled(_:))))
        let row = NSStackView(); row.orientation = .horizontal; row.spacing = 8
        row.addArrangedSubview(text("连续空闲"))
        let field = NSTextField(string: String(controller.preferences.minutes)); field.widthAnchor.constraint(equalToConstant: 55).isActive = true
        minutesField = field; row.addArrangedSubview(field); row.addArrangedSubview(text("分钟后归零（1–120）"))
        row.addArrangedSubview(NSButton(title: "应用", target: self, action: #selector(applyMinutes)))
        stack.addArrangedSubview(row)
        stack.addArrangedSubview(checkbox("静音流也计时（进阶检测）", on: controller.preferences.detectSilentStream, action: #selector(changeSignal(_:))))
        stack.addArrangedSubview(text("默认关闭。两种模式都会在非零音量时检测播放。开启后额外读取系统音频信号，仅全零样本算静音；不使用麦克风、不录音、不上传。"))
        stack.addArrangedSubview(text("保护设备", bold: true))
        stack.addArrangedSubview(checkbox("系统内建扬声器", on: controller.preferences.protectBuiltIn, action: #selector(changeBuiltIn(_:))))
        stack.addArrangedSubview(text("其他设备默认不保护。勾选后，仅当它成为系统默认输出时生效；不修改闲置设备音量。插孔或设备身份变化需要重新选择。"))
        var seen = Set<String>()
        do {
            for device in try audio.devices() where !device.builtInSpeaker {
                seen.insert(device.selectionID); deviceNames[device.selectionID] = device.name
                let button = checkbox(device.name + (device.controllable ? "" : "（不支持音量控制）"),
                    on: controller.preferences.selectedDevices[device.selectionID] != nil, action: #selector(changeDevice(_:)))
                button.isEnabled = device.controllable || controller.preferences.selectedDevices[device.selectionID] != nil
                deviceButtons[button] = device.selectionID; stack.addArrangedSubview(button)
            }
            for (key, name) in controller.preferences.selectedDevices.sorted(by: { $0.value < $1.value }) where !seen.contains(key) {
                deviceNames[key] = name
                let button = checkbox(name + "（离线 / 路由变化，取消勾选可移除）", on: true, action: #selector(changeDevice(_:)))
                deviceButtons[button] = key; stack.addArrangedSubview(button)
            }
        } catch { stack.addArrangedSubview(text("设备列表读取失败：" + error.localizedDescription)) }
        stack.addArrangedSubview(NSButton(title: "刷新设备列表", target: self, action: #selector(refreshSettings)))
        let login = SMAppService.mainApp.status
        stack.addArrangedSubview(checkbox("登录时启动", on: login == .enabled, action: #selector(changeLogin(_:))))
        if login == .requiresApproval { stack.addArrangedSubview(text("登录启动待批准，请前往系统设置 → 通用 → 登录项。")) }
        let scroll = NSScrollView(frame: window.contentView!.bounds); scroll.hasVerticalScroller = true
        scroll.autoresizingMask = [.width, .height]; scroll.drawsBackground = true
        scroll.backgroundColor = .windowBackgroundColor
        let document = SettingsDocument(frame: scroll.contentView.bounds)
        stack.translatesAutoresizingMaskIntoConstraints = false; document.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: document.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: document.trailingAnchor),
            stack.topAnchor.constraint(equalTo: document.topAnchor)
        ])
        scroll.documentView = document
        document.layoutSubtreeIfNeeded()
        document.setFrameSize(NSSize(width: scroll.contentSize.width, height: max(scroll.contentSize.height, stack.fittingSize.height)))
        window.contentView = scroll
    }
    @objc func refreshSettings() { controller.retry(); rebuildSettings() }
    @objc func changeEnabled(_ sender: NSButton) { var p = controller.preferences; p.enabled = sender.state == .on; save(p) }
    @objc func changeBuiltIn(_ sender: NSButton) { var p = controller.preferences; p.protectBuiltIn = sender.state == .on; save(p) }
    @objc func changeDevice(_ sender: NSButton) {
        guard let key = deviceButtons[sender] else { return }
        var p = controller.preferences
        p.selectedDevices[key] = sender.state == .on ? deviceNames[key] : nil
        save(p)
    }
    @objc func changeSignal(_ sender: NSButton) {
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
    }
    @objc func changeLogin(_ sender: NSButton) {
        do {
            if sender.state == .on { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
        } catch { showError("登录启动设置失败：" + error.localizedDescription) }
        rebuildSettings()
    }
    func showError(_ message: String) { let alert = NSAlert(); alert.messageText = message; alert.runModal() }
    @objc func showAbout() {
        if about == nil {
            about = window("关于声音守卫", width: 540, height: 450)
            let stack = NSStackView(); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 12
            stack.edgeInsets = NSEdgeInsets(top: 24, left: 24, bottom: 24, right: 24)
            stack.addArrangedSubview(text("Sound Guard · 声音守卫", bold: true))
            stack.addArrangedSubview(text("版本 \(AppVersion.current)（build \(AppVersion.build)） · 开发预览"))
            stack.addArrangedSubview(text("只负责将空闲输出归零，绝不自动恢复音量。\nCopyright © 2026 wlzh · MIT License"))
            let row = NSStackView(); row.orientation = .horizontal
            for (title, action) in [("作者", #selector(openAuthor)), ("网站", #selector(openWebsite)),
                                    ("GitHub", #selector(openRepository)), ("文档", #selector(openGuide))] {
                row.addArrangedSubview(NSButton(title: title, target: self, action: action))
            }
            stack.addArrangedSubview(row)
            let licenseURL = Bundle.main.resourceURL?.appendingPathComponent("LICENSE")
            let license = licenseURL.flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? "MIT License · Copyright (c) 2026 wlzh\n完整许可证见源码 LICENSE。"
            let scroll = NSScrollView(); scroll.hasVerticalScroller = true; scroll.borderType = .bezelBorder
            let view = NSTextView(); view.isEditable = false; view.string = license
            view.font = .monospacedSystemFont(ofSize: 10, weight: .regular); view.textContainerInset = NSSize(width: 8, height: 8)
            view.isVerticallyResizable = true; view.isHorizontallyResizable = false
            view.autoresizingMask = [.width]; view.textContainer?.widthTracksTextView = true
            scroll.documentView = view; stack.addArrangedSubview(scroll)
            scroll.heightAnchor.constraint(equalToConstant: 220).isActive = true
            scroll.widthAnchor.constraint(equalToConstant: 492).isActive = true
            stack.frame = about!.contentView!.bounds; stack.autoresizingMask = [.width, .height]; about!.contentView = stack
        }
        present(about!)
    }
    @objc func openAuthor() { NSWorkspace.shared.open(URL(string: "https://github.com/wlzh")!) }
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
    _ = NSApplication.shared
    NSApp.appearance = NSAppearance(named: .aqua)
    let delegate = AppDelegate()
    delegate.settings = delegate.window("Settings test", width: 540, height: 630)
    delegate.rebuildSettings()
    precondition(delegate.minutesField?.stringValue == String(delegate.controller.preferences.minutes))
    delegate.showAbout()
    precondition(delegate.about?.contentView?.subviews.isEmpty == false)
    if let index = CommandLine.arguments.firstIndex(of: "--render-previews"), CommandLine.arguments.count > index + 1 {
        let directory = URL(fileURLWithPath: CommandLine.arguments[index + 1])
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for (name, window) in [("settings", delegate.settings), ("about", delegate.about)] {
            if let view = window?.contentView {
                view.wantsLayer = true
                view.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
                view.layoutSubtreeIfNeeded()
                if let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                    view.cacheDisplay(in: view.bounds, to: bitmap)
                    try bitmap.representation(using: .png, properties: [:])?.write(to: directory.appendingPathComponent(name + ".png"))
                }
            }
        }
    }
    delegate.about?.close(); delegate.settings?.close()
    precondition(delegate.about == nil && delegate.settings == nil)
    print("UI_CONSTRUCTION=PASS; VISIBLE_LAYOUT=MANUAL_CHECK_REQUIRED")
} else {
    let app = NSApplication.shared
    let delegate = AppDelegate(); app.delegate = delegate
    withExtendedLifetime(delegate) { app.run() }
}
