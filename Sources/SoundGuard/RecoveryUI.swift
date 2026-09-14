import AppKit
import ApplicationServices
import GuardCore

enum PlaybackScreenLocator {
    static var trusted: Bool { AXIsProcessTrusted() }

    static func requestPermission() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    static func screen(for processes: [PlaybackProcess]) -> NSScreen {
        screen(for: processes, accessibilityTrusted: trusted)
    }

    static func screen(for processes: [PlaybackProcess], accessibilityTrusted: Bool) -> NSScreen {
        if accessibilityTrusted {
            for process in processes {
                let pid = owningApplication(for: process.pid)?.processIdentifier ?? process.pid
                guard let bounds = windowBounds(pid: pid) else { continue }
                if let screen = NSScreen.screens.max(by: {
                    intersectionArea($0, bounds) < intersectionArea($1, bounds)
                }), intersectionArea(screen, bounds) > 0 { return screen }
            }
        }
        let pointer = NSEvent.mouseLocation
        return NSScreen.screens.first(where: { $0.frame.contains(pointer) }) ?? NSScreen.main ?? NSScreen.screens[0]
    }

    static func appName(for processes: [PlaybackProcess]) -> String {
        for process in processes {
            if let app = owningApplication(for: process.pid),
               let name = app.localizedName, !name.isEmpty { return name }
        }
        return "某个 App"
    }

    private static func owningApplication(for pid: pid_t) -> NSRunningApplication? {
        guard pid > 0, let direct = NSRunningApplication(processIdentifier: pid) else { return nil }
        if direct.activationPolicy == .regular { return direct }
        guard let path = direct.bundleURL?.standardizedFileURL.path else { return direct }
        let parts = URL(fileURLWithPath: path).pathComponents
        guard let appIndex = parts.firstIndex(where: { $0.hasSuffix(".app") }) else { return direct }
        let outerPath = NSString.path(withComponents: Array(parts.prefix(through: appIndex)))
        return NSWorkspace.shared.runningApplications.first {
            $0.activationPolicy == .regular && $0.bundleURL?.standardizedFileURL.path == outerPath
        } ?? direct
    }

    private static func windowBounds(pid: pid_t) -> CGRect? {
        let app = AXUIElementCreateApplication(pid)
        for attribute in [kAXFocusedWindowAttribute, kAXMainWindowAttribute] {
            var raw: CFTypeRef?
            guard AXUIElementCopyAttributeValue(app, attribute as CFString, &raw) == .success,
                  let raw, CFGetTypeID(raw) == AXUIElementGetTypeID() else { continue }
            let window = unsafeBitCast(raw, to: AXUIElement.self)
            var positionRaw: CFTypeRef?, sizeRaw: CFTypeRef?
            guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &positionRaw) == .success,
                  AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeRaw) == .success,
                  let positionRaw, let sizeRaw,
                  CFGetTypeID(positionRaw) == AXValueGetTypeID(), CFGetTypeID(sizeRaw) == AXValueGetTypeID() else { continue }
            var position = CGPoint.zero, size = CGSize.zero
            guard AXValueGetValue(unsafeBitCast(positionRaw, to: AXValue.self), .cgPoint, &position),
                  AXValueGetValue(unsafeBitCast(sizeRaw, to: AXValue.self), .cgSize, &size) else { continue }
            return CGRect(origin: position, size: size)
        }
        return nil
    }

    private static func intersectionArea(_ screen: NSScreen, _ window: CGRect) -> CGFloat {
        guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else { return 0 }
        let intersection = CGDisplayBounds(number).intersection(window)
        return intersection.isNull ? 0 : intersection.width * intersection.height
    }
}

final class RecoveryPromptPresenter: NSObject, NSWindowDelegate {
    private var panel: NSPanel?
    private var timer: Timer?
    private var deadline = Date()
    private var prompt: RecoveryPrompt?
    private var countdown: NSTextField?
    var onRestore: ((RecoveryPrompt) -> Void)?
    var currentPanel: NSPanel? { panel }
    var currentPromptID: UUID? { prompt?.id }

    func show(_ prompt: RecoveryPrompt) {
        close()
        self.prompt = prompt; deadline = Date().addingTimeInterval(prompt.timeout)
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 400, height: 224),
            styleMask: [.titled, .closable, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered, defer: false)
        panel.title = "声音守卫"; panel.titleVisibility = .hidden; panel.titlebarAppearsTransparent = true
        panel.isFloatingPanel = true; panel.becomesKeyOnlyIfNeeded = true; panel.level = .floating
        panel.collectionBehavior = [.moveToActiveSpace, .transient]
        panel.isReleasedWhenClosed = false; panel.delegate = self

        let appName = PlaybackScreenLocator.appName(for: prompt.processes)
        let heading = UI.stack([
            UI.image(BrandAssets.icon(size: 32), size: 32),
            UI.stack([UI.label("检测到新的播放", size: 15, weight: .semibold),
                      UI.label(appName, size: 12, color: .secondaryLabelColor)], spacing: 2)
        ], vertical: false, spacing: 10)
        let volume = UI.label("\(Int(prompt.volume * 100))%", size: 18, weight: .semibold)
        let summary = UI.row(title: "恢复系统音量", detail: prompt.deviceName, control: volume)
        let card = UI.group([summary], width: 360)
        let countdown = UI.label("", size: 11, color: .secondaryLabelColor)
        self.countdown = countdown
        let keep = NSButton(title: "保持静音", target: self, action: #selector(dismiss))
        let restore = NSButton(title: "恢复至 \(Int(prompt.volume * 100))%", target: self, action: #selector(restore))
        restore.keyEquivalent = ""; keep.keyEquivalent = ""
        restore.setAccessibilityLabel("确认恢复系统音量至 \(Int(prompt.volume * 100))%")
        let spacer = NSView(); spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let actions = UI.stack([spacer, keep, restore], vertical: false, spacing: 8)
        let body = UI.stack([heading, card, countdown, actions], spacing: 10)
        actions.alignment = .centerY
        body.translatesAutoresizingMaskIntoConstraints = false
        let root = NativeSurface(); panel.contentView = root; root.addSubview(body)
        NSLayoutConstraint.activate([
            body.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 20),
            body.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -20),
            body.topAnchor.constraint(equalTo: root.topAnchor, constant: 26),
            body.bottomAnchor.constraint(lessThanOrEqualTo: root.bottomAnchor, constant: -18),
            actions.trailingAnchor.constraint(equalTo: body.trailingAnchor)
        ])
        self.panel = panel; updateCountdown()
        let screen = PlaybackScreenLocator.screen(for: prompt.processes)
        let visible = screen.visibleFrame
        panel.setFrameOrigin(NSPoint(x: visible.maxX - panel.frame.width - 18,
                                     y: visible.maxY - panel.frame.height - 18))
        panel.orderFrontRegardless()
        timer = Timer.scheduledTimer(timeInterval: 1, target: self, selector: #selector(updateCountdown),
                                     userInfo: nil, repeats: true)
        RunLoop.main.add(timer!, forMode: .common)
    }

    @objc private func updateCountdown() {
        let remaining = max(0, Int(ceil(deadline.timeIntervalSinceNow)))
        countdown?.stringValue = "\(remaining) 秒后关闭并保持静音"
        if remaining == 0 { close() }
    }
    func expireForTesting() { deadline = .distantPast; updateCountdown() }
    @objc private func dismiss() { close() }
    @objc private func restore() {
        guard let prompt else { close(); return }
        close(); onRestore?(prompt)
    }
    func close() {
        timer?.invalidate(); timer = nil; panel?.orderOut(nil); panel?.close(); panel = nil
        prompt = nil; countdown = nil
    }
    func windowWillClose(_ notification: Notification) {
        timer?.invalidate(); timer = nil; panel = nil; prompt = nil; countdown = nil
    }
}
