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

final class RecoveryVolumeSlider: NSSlider {
    var onTracking: ((Bool) -> Void)?
    override func mouseDown(with event: NSEvent) {
        onTracking?(true)
        defer { onTracking?(false) }
        super.mouseDown(with: event)
    }
}

final class RecoveryPromptPresenter: NSObject, NSWindowDelegate {
    private var panel: NSPanel?
    private var timer: Timer?
    private var deadline = 0.0
    private var trackingStarted: TimeInterval?
    private var selectedPercent: Int?
    private var slider: RecoveryVolumeSlider?
    private var volumeLabel: NSTextField?
    private var restoreButton: NSButton?
    private var resetButton: NSButton?
    var now: () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }
    private var originalVolumeText: String {
        let percent = (prompt?.volume ?? 0) * 100
        return percent < 1 ? "<1%" : "\(Int(percent.rounded()))%"
    }
    private var prompt: RecoveryPrompt?
    private var countdown: NSTextField?
    var onRestore: ((RecoveryPrompt, Int?) -> Void)?
    var onKeepSilent: ((RecoveryPrompt) -> Void)?
    var currentPanel: NSPanel? { panel }
    var currentPromptID: UUID? { prompt?.id }

    func show(_ prompt: RecoveryPrompt) {
        close()
        self.prompt = prompt; deadline = now() + prompt.timeout
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 420, height: 350),
            styleMask: [.titled, .closable, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered, defer: false)
        panel.title = "声音守卫"; panel.titleVisibility = .hidden; panel.titlebarAppearsTransparent = true
        panel.isFloatingPanel = true; panel.becomesKeyOnlyIfNeeded = true; panel.level = .floating
        panel.collectionBehavior = [.moveToActiveSpace, .transient]
        panel.isReleasedWhenClosed = false; panel.delegate = self
        if let closeButton = panel.standardWindowButton(.closeButton) {
            closeButton.toolTip = "暂时关闭；下次播放仍会提醒"
            closeButton.setAccessibilityLabel("暂时关闭恢复提示；下次播放仍会提醒")
        }

        let appName = PlaybackScreenLocator.appName(for: prompt.processes)
        let eyebrow = UI.label("声音守卫 · 播放保护", size: 11, weight: .medium, color: .secondaryLabelColor)
        let heading = UI.stack([
            UI.image(BrandAssets.icon(size: 42), size: 42),
            UI.stack([eyebrow, UI.label("要恢复声音吗？", size: 17, weight: .semibold),
                      UI.label("\(appName) 已开始播放", size: 12, color: .secondaryLabelColor)], spacing: 3)
        ], vertical: false, spacing: 12)
        let originalPercent = Int((prompt.volume * 100).rounded())
        let volume = UI.label(originalVolumeText, size: 24, weight: .semibold)
        self.volumeLabel = volume
        volume.font = .monospacedDigitSystemFont(ofSize: 24, weight: .semibold)
        volume.alignment = .right
        let summary = UI.row(title: "恢复音量", detail: prompt.deviceName, control: volume)
        let slider = RecoveryVolumeSlider(value: Double(max(1, originalPercent)), minValue: 1, maxValue: 100,
                                          target: self, action: #selector(volumeChanged(_:)))
        slider.isContinuous = true
        slider.setAccessibilityLabel("待恢复音量，百分比；确认后生效")
        slider.onTracking = { [weak self] tracking in
            guard let self, self.prompt?.id == prompt.id else { return }
            self.setTracking(tracking)
        }
        self.slider = slider
        let reset = NSButton(title: "还原", target: self, action: #selector(resetVolume))
        reset.bezelStyle = .inline; reset.isEnabled = false
        reset.setAccessibilityLabel("选择归零前的原始音量，不立即出声")
        self.resetButton = reset
        let endpoints = UI.stack([UI.label("1%", size: 11, color: .secondaryLabelColor), NSView(),
                                  UI.label("100%", size: 11, color: .secondaryLabelColor)], vertical: false)
        let original = UI.stack([UI.label("归零前 \(originalVolumeText)", size: 11, color: .secondaryLabelColor),
                                 NSView(), reset], vertical: false)
        let controls = UI.stack([slider, endpoints, original], spacing: 3)
        for row in [endpoints, original] { row.widthAnchor.constraint(equalTo: controls.widthAnchor).isActive = true }
        slider.widthAnchor.constraint(equalTo: controls.widthAnchor).isActive = true
        let card = UI.group([summary, controls], width: 380)
        let countdown = UI.label("", size: 12, weight: .medium, color: .secondaryLabelColor)
        self.countdown = countdown
        let keep = UI.actionButton("保持静音，不再提醒", target: self, action: #selector(keepSilent), width: 185)
        keep.setAccessibilityLabel("保持静音，并且不再提醒本次自动归零")
        let restore = UI.actionButton("恢复到 \(originalVolumeText)", target: self,
                                      action: #selector(restore), primary: true, width: 185)
        restore.setAccessibilityLabel("确认恢复系统音量至 \(originalVolumeText)")
        self.restoreButton = restore
        let actions = UI.stack([keep, restore], vertical: false, spacing: 10)
        let hint = UI.label("滑动仅选择音量，确认后才会出声。", size: 11, color: .secondaryLabelColor)
        let body = UI.stack([heading, card, hint, countdown, actions], spacing: 10)
        actions.alignment = .centerY
        body.translatesAutoresizingMaskIntoConstraints = false
        let root = NativeSurface(); panel.contentView = root; root.addSubview(body)
        NSLayoutConstraint.activate([
            body.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 20),
            body.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -20),
            body.topAnchor.constraint(equalTo: root.topAnchor, constant: 24),
            body.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -18),
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

    @objc func updateCountdown() {
        let remaining = max(0, Int(ceil(deadline - (trackingStarted ?? now()))))
        countdown?.stringValue = "还剩 \(remaining) 秒 · 超时后关闭，下次播放仍提醒"
        if remaining == 0 && trackingStarted == nil { close() }
    }
    func setTracking(_ tracking: Bool) {
        let now = now()
        if tracking { if trackingStarted == nil { trackingStarted = now } }
        else if let started = trackingStarted { deadline += now - started; trackingStarted = nil }
        updateCountdown()
    }
    @objc private func volumeChanged(_ sender: NSSlider) {
        guard prompt != nil, sender === slider else { return }
        selectedPercent = max(1, min(100, Int(sender.doubleValue.rounded())))
        sender.integerValue = selectedPercent!
        updateSelection()
    }
    @objc private func resetVolume() {
        selectedPercent = nil
        slider?.integerValue = max(1, Int(((prompt?.volume ?? 0) * 100).rounded()))
        updateSelection()
    }
    private func updateSelection() {
        let text = selectedPercent.map { "\($0)%" } ?? originalVolumeText
        volumeLabel?.stringValue = text
        restoreButton?.title = "恢复到 \(text)"
        restoreButton?.setAccessibilityLabel("确认恢复系统音量至 \(text)")
        resetButton?.isEnabled = selectedPercent != nil
    }
    func expireForTesting() { deadline = 0; updateCountdown() }
    @objc private func keepSilent() {
        guard let prompt else { close(); return }
        close(); onKeepSilent?(prompt)
    }
    @objc private func restore() {
        guard let prompt else { close(); return }
        let target = selectedPercent
        close(); onRestore?(prompt, target)
    }
    func close() {
        timer?.invalidate(); timer = nil; panel?.orderOut(nil); panel?.close(); panel = nil
        clearSelection()
    }
    func windowWillClose(_ notification: Notification) {
        timer?.invalidate(); timer = nil; panel = nil; clearSelection()
    }
    private func clearSelection() {
        prompt = nil; countdown = nil; trackingStarted = nil; selectedPercent = nil
        slider = nil; volumeLabel = nil; restoreButton = nil; resetButton = nil
    }
}
