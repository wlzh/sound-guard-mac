import AppKit
import GuardCore

func runUIChecks(outputDirectory: URL?) throws {
    _ = NSApplication.shared; NSApp.appearance = NSAppearance(named: .aqua)
    let delegate = AppDelegate()
    let builtIn = OutputDevice(id: 1, uid: "demo-speaker", name: "内建扬声器", builtInSpeaker: true, volume: 0)
    let headphones = OutputDevice(id: 2, uid: "demo-headphones", name: "Studio Headphones", builtInSpeaker: false, volume: 0.3)
    delegate.previewDevices = [builtIn, headphones,
        OutputDevice(id: 3, uid: "demo-usb", name: "USB Audio", builtInSpeaker: false, volume: 0.4),
        OutputDevice(id: 4, uid: "demo-display", name: "Display Audio", builtInSpeaker: false, volume: 0, controllable: false)]
    delegate.previewCurrent = builtIn; delegate.previewState = .zero
    var p = Preferences(); p.selectedDevices[headphones.selectionID] = headphones.name
    delegate.controller.configure(p)
    precondition(BrandAssets.mark()?.isTemplate == true && BrandAssets.icon() != nil)
    precondition(UI.alert(message: "品牌检查").icon != nil)
    delegate.settings = delegate.window("声音守卫设置", width: 580, height: 650)
    delegate.rebuildSettings()
    precondition(delegate.minutesField?.stringValue == "5")
    delegate.showAbout(); precondition(delegate.about?.contentView?.subviews.isEmpty == false)
    let menu = NSMenu(); delegate.menuWillOpen(menu)
    precondition(menu.items.contains { $0.title == "自动保护" && $0.state == .on })
    precondition(menu.items.contains { $0.title == "静音流也计时" && $0.state == .off })
    precondition(menu.items.contains { $0.title == "播放时提示恢复" && $0.state == .off })
    precondition(menu.items.contains { $0.title == "立即归零" && !$0.isEnabled })
    precondition(menu.items.contains { $0.title == "保护设备…" && $0.action == #selector(AppDelegate.showDeviceSettings) })
    precondition(menu.items.first?.view != nil)
    func render(_ view: NSView?, name: String) throws {
        guard let directory = outputDirectory, let view else { return }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        view.layoutSubtreeIfNeeded()
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { throw GuardError("Cannot render \(name)") }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        try bitmap.representation(using: .png, properties: [:])!.write(to: directory.appendingPathComponent(name + ".png"))
    }
    try render(delegate.settings?.contentView, name: "settings-general")
    func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
    let generalViews = descendants(delegate.settings!.contentView!)
    precondition(generalViews.compactMap { $0 as? NSSwitch }.contains { $0.accessibilityLabel() == "播放时提示恢复" })
    precondition(delegate.recoveryDurationField?.stringValue == "1" && delegate.recoveryUnitPopup?.titleOfSelectedItem == "分钟")
    precondition(generalViews.compactMap { $0 as? NSButton }.contains { $0.title == "权限设置…" && !$0.isEnabled })
    if let scroll = generalViews.compactMap({ $0 as? NSScrollView }).first,
       let document = scroll.documentView {
        scroll.contentView.scroll(to: NSPoint(x: 0, y: max(0, document.frame.height - scroll.contentView.bounds.height)))
        scroll.reflectScrolledClipView(scroll.contentView)
        try render(delegate.settings?.contentView, name: "settings-recovery")
    }
    try render(delegate.about?.contentView, name: "about")
    let preview = NativeSurface(frame: NSRect(x: 0, y: 0, width: 316, height: 366))
    let rows = NSStackView(); rows.orientation = .vertical; rows.alignment = .leading; rows.spacing = 2
    for entry in menu.items {
        if entry.view != nil {
            let view = UI.menuHeader(headline: "音量已归零", detail: "内建扬声器", volume: "0%")
            view.translatesAutoresizingMaskIntoConstraints = false
            rows.addArrangedSubview(view)
        }
        else if entry.isSeparatorItem {
            let line = NSBox(); line.boxType = .separator; line.widthAnchor.constraint(equalToConstant: 288).isActive = true; rows.addArrangedSubview(line)
        } else {
            let label = UI.label(entry.title, size: 13, color: entry.isEnabled ? .labelColor : .disabledControlTextColor)
            let row = NSView(); row.addSubview(label); label.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([row.widthAnchor.constraint(equalToConstant: 316), row.heightAnchor.constraint(equalToConstant: 23),
                label.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 26), label.centerYAnchor.constraint(equalTo: row.centerYAnchor)])
            rows.addArrangedSubview(row)
        }
    }
    rows.translatesAutoresizingMaskIntoConstraints = false; preview.addSubview(rows)
    NSLayoutConstraint.activate([rows.topAnchor.constraint(equalTo: preview.topAnchor, constant: 4), rows.leadingAnchor.constraint(equalTo: preview.leadingAnchor)])
    try render(preview, name: "menu-structure")
    for (appearance, suffix) in [(NSAppearance.Name.aqua, "light"), (.darkAqua, "dark")] {
        let surface = NativeSurface(frame: NSRect(x: 0, y: 0, width: 316, height: 72))
        surface.appearance = NSAppearance(named: appearance)
        let header = UI.menuHeader(headline: "音量已归零", detail: "MacBook Pro扬声器", volume: "0%")
        UI.pin(header, in: surface, padding: 0); surface.layoutSubtreeIfNeeded()
        let brand = header.subviews.compactMap { $0 as? NSStackView }.first!
        let brandText = brand.arrangedSubviews.compactMap { $0 as? NSTextField }.first!
        precondition(header.frame.height == 72 && !brandText.isHidden && brandText.frame.width > 40)
        let fields = header.subviews.compactMap { $0 as? NSTextField }
        let deviceLabel = fields.first { $0.stringValue == "MacBook Pro扬声器" }!
        let bottomGap = deviceLabel.alignmentRect(forFrame: deviceLabel.frame).minY
        precondition(bottomGap >= 0 && bottomGap <= 8)
        precondition(fields.contains { $0.stringValue == "0%" && $0.alignment == .right && abs($0.alignmentRect(forFrame: $0.frame).maxX - 302) < 1 })
        try render(surface, name: "menu-header-" + suffix)
    }
    let longName = String(repeating: "很长的输出设备名称", count: 12)
    let compact = UI.menuHeader(headline: "保护需要检查", detail: longName)
    let host = NativeSurface(frame: NSRect(x: 0, y: 0, width: 316, height: 72))
    UI.pin(compact, in: host, padding: 0); host.layoutSubtreeIfNeeded()
    let details = compact.subviews.compactMap { $0 as? NSTextField }.first { $0.stringValue == longName }!
    precondition(details.toolTip == longName && details.maximumNumberOfLines == 1)
    precondition(compact.frame.width == 316 && details.alignmentRect(forFrame: details.frame).maxX <= 302)
    precondition(NSScreen.screens.contains(PlaybackScreenLocator.screen(for: [PlaybackProcess(pid: 0)], accessibilityTrusted: false)))
    let recoveryPrompt = RecoveryPrompt(id: UUID(), deviceName: "内建扬声器", volume: 0.25,
        processes: [PlaybackProcess(pid: 0)], timeout: 60)
    var restored = false; delegate.recoveryPresenter.onRestore = { _ in restored = true }
    delegate.recoveryPresenter.show(recoveryPrompt)
    let recoveryPanel = delegate.recoveryPresenter.currentPanel!
    recoveryPanel.appearance = NSAppearance(named: .aqua); recoveryPanel.contentView?.layoutSubtreeIfNeeded()
    precondition(recoveryPanel.styleMask.contains(.nonactivatingPanel) && recoveryPanel.level == .floating)
    precondition(recoveryPanel.frame.size == NSSize(width: 420, height: 264))
    let recoveryViews = descendants(recoveryPanel.contentView!)
    precondition(recoveryViews.compactMap { $0 as? NSImageView }.contains { $0.image != nil })
    let recoveryLabels = recoveryViews.compactMap { $0 as? NSTextField }.map(\.stringValue)
    precondition(recoveryLabels.contains("声音守卫 · 播放保护") && recoveryLabels.contains("要恢复声音吗？") && recoveryLabels.contains("某个 App 已开始播放"))
    let recoveryButtons = recoveryViews.compactMap { $0 as? NSButton }.filter { ["继续静音", "恢复到 25%"].contains($0.title) }
    precondition(recoveryButtons.count == 2)
    let buttonRects = recoveryButtons.map { $0.alignmentRect(forFrame: $0.frame) }
    precondition(buttonRects.allSatisfy { abs($0.width - 185) < 0.5 && abs($0.height - 34) < 0.5 })
    precondition(recoveryButtons.first { $0.title == "恢复到 25%" }?.isBordered == false)
    precondition(recoveryButtons.allSatisfy { $0.keyEquivalent.isEmpty })
    precondition(recoveryLabels.contains { $0.contains("还剩 60 秒") })
    try render(recoveryPanel.contentView, name: "recovery-prompt-light")
    recoveryPanel.appearance = NSAppearance(named: .darkAqua); recoveryPanel.contentView?.layoutSubtreeIfNeeded()
    try render(recoveryPanel.contentView, name: "recovery-prompt-dark")
    recoveryButtons.first { $0.title == "恢复到 25%" }!.performClick(nil)
    precondition(restored && delegate.recoveryPresenter.currentPanel == nil)
    restored = false; delegate.recoveryPresenter.show(recoveryPrompt)
    let keepViews = descendants(delegate.recoveryPresenter.currentPanel!.contentView!)
    keepViews.compactMap { $0 as? NSButton }.first { $0.title == "继续静音" }!.performClick(nil)
    precondition(!restored && delegate.recoveryPresenter.currentPanel == nil)
    delegate.recoveryPresenter.show(recoveryPrompt); delegate.recoveryPresenter.expireForTesting()
    precondition(!restored && delegate.recoveryPresenter.currentPanel == nil)
    delegate.recoveryPresenter.show(recoveryPrompt); delegate.updateStatus()
    precondition(delegate.recoveryPresenter.currentPanel == nil)
    delegate.selectedSettingsPage = 1; delegate.rebuildSettings()
    precondition(delegate.minutesField == nil && delegate.deviceButtons.count == 3)
    precondition(delegate.deviceButtons.keys.filter { !$0.isEnabled }.count == 1)
    try render(delegate.settings?.contentView, name: "settings-devices")
    delegate.menuDidClose(menu); precondition(menu.items.first?.view == nil)
    delegate.about?.close(); delegate.settings?.close()
    precondition(delegate.about == nil && delegate.settings == nil && delegate.settingsFeedback == nil)
    print("UI_CHECKS=PASS; ASSERTIONS=43; PREVIEWS=SYNTHETIC; MENU_PREVIEW=STRUCTURE_NOT_OS_SCREENSHOT")
}
