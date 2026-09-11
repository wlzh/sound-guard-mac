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
    delegate.settings = delegate.window("声音守卫设置", width: 580, height: 650)
    delegate.rebuildSettings()
    precondition(delegate.minutesField?.stringValue == "5")
    delegate.showAbout(); precondition(delegate.about?.contentView?.subviews.isEmpty == false)
    let menu = NSMenu(); delegate.menuWillOpen(menu)
    precondition(menu.items.contains { $0.title == "自动保护" && $0.state == .on })
    precondition(menu.items.contains { $0.title == "静音流也计时" && $0.state == .off })
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
    try render(delegate.about?.contentView, name: "about")
    let preview = NativeSurface(frame: NSRect(x: 0, y: 0, width: 316, height: 378))
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
        let surface = NativeSurface(frame: NSRect(x: 0, y: 0, width: 316, height: 84))
        surface.appearance = NSAppearance(named: appearance)
        let header = UI.menuHeader(headline: "音量已归零", detail: "MacBook Pro扬声器", volume: "0%")
        UI.pin(header, in: surface, padding: 0); surface.layoutSubtreeIfNeeded()
        let brand = header.subviews.compactMap { $0 as? NSStackView }.first!
        let brandText = brand.arrangedSubviews.compactMap { $0 as? NSTextField }.first!
        precondition(header.frame.height == 84 && !brandText.isHidden && brandText.frame.width > 40)
        let fields = header.subviews.compactMap { $0 as? NSTextField }
        precondition(fields.contains { $0.stringValue == "0%" && $0.alignment == .right && abs($0.alignmentRect(forFrame: $0.frame).maxX - 302) < 1 })
        try render(surface, name: "menu-header-" + suffix)
    }
    let longName = String(repeating: "很长的输出设备名称", count: 12)
    let compact = UI.menuHeader(headline: "保护需要检查", detail: longName)
    let host = NativeSurface(frame: NSRect(x: 0, y: 0, width: 316, height: 84))
    UI.pin(compact, in: host, padding: 0); host.layoutSubtreeIfNeeded()
    let details = compact.subviews.compactMap { $0 as? NSTextField }.first { $0.stringValue == longName }!
    precondition(details.toolTip == longName && details.maximumNumberOfLines == 1)
    precondition(compact.frame.width == 316 && details.alignmentRect(forFrame: details.frame).maxX <= 302)
    delegate.selectedSettingsPage = 1; delegate.rebuildSettings()
    precondition(delegate.minutesField == nil && delegate.deviceButtons.count == 3)
    precondition(delegate.deviceButtons.keys.filter { !$0.isEnabled }.count == 1)
    try render(delegate.settings?.contentView, name: "settings-devices")
    delegate.menuDidClose(menu); precondition(menu.items.first?.view == nil)
    delegate.about?.close(); delegate.settings?.close()
    precondition(delegate.about == nil && delegate.settings == nil && delegate.settingsFeedback == nil)
    print("UI_CHECKS=PASS; ASSERTIONS=18; PREVIEWS=SYNTHETIC; MENU_PREVIEW=STRUCTURE_NOT_OS_SCREENSHOT")
}
