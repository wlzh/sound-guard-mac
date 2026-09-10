import AppKit
import GuardCore

extension AppDelegate {
    func menuWillOpen(_ menu: NSMenu) {
        menu.removeAllItems(); menu.autoenablesItems = false
        let header = NSMenuItem(); header.isEnabled = false
        let device = displayDevice
        var detail = device.map { $0.name + ($0.controllable ? " · \(Int($0.volume * 100))%" : "") } ?? "连接输出设备后自动核对"
        if case .fault(let message) = displayState { detail = message }
        header.view = UI.menuHeader(headline: GuardPresentation.headline(displayState, now: ProcessInfo.processInfo.systemUptime), detail: detail)
        menu.addItem(header); menu.addItem(.separator())
        item("自动保护", #selector(toggleEnabled), in: menu).state = controller.preferences.enabled ? .on : .off
        let zero = item("立即归零", #selector(zeroNow), in: menu)
        zero.isEnabled = device.map { controller.preferences.includes($0) && $0.controllable && $0.volume > 0 } ?? false
        let delay = NSMenuItem(title: "空闲时长：\(controller.preferences.minutes) 分钟", action: nil, keyEquivalent: "")
        let options = NSMenu(); options.autoenablesItems = false
        for minutes in [1, 3, 5, 10, 15, 30, 60, 120] {
            let choice = item("\(minutes) 分钟", #selector(selectDelay(_:)), in: options)
            choice.tag = minutes; choice.state = controller.preferences.minutes == minutes ? .on : .off
        }
        options.addItem(.separator()); item("自定义…", #selector(showGeneralSettings), in: options)
        delay.submenu = options; menu.addItem(delay)
        item("静音流也计时", #selector(toggleSignalFromMenu), in: menu).state = controller.preferences.detectSilentStream ? .on : .off
        item("保护设备…", #selector(showDeviceSettings), in: menu)
        item("重新核对", #selector(retry), in: menu)
        menu.addItem(.separator())
        item("设置…", #selector(showSettings), in: menu, key: ",")
        item("关于声音守卫…", #selector(showAbout), in: menu)
        let help = NSMenuItem(title: "帮助与开源", action: nil, keyEquivalent: "")
        let links = NSMenu()
        item("使用文档", #selector(openGuide), in: links)
        item("版本记录", #selector(openReleases), in: links)
        item("GitHub 源代码", #selector(openRepository), in: links)
        help.submenu = links; menu.addItem(help)
        menu.addItem(.separator()); item("退出声音守卫", #selector(quit), in: menu, key: "q")
    }
    func menuDidClose(_ menu: NSMenu) { menu.items.first?.view = nil }
    @discardableResult func item(_ title: String, _ action: Selector, in menu: NSMenu, key: String = "") -> NSMenuItem {
        let entry = NSMenuItem(title: title, action: action, keyEquivalent: key)
        entry.target = self; menu.addItem(entry); return entry
    }
    @objc func selectDelay(_ sender: NSMenuItem) {
        guard (1...120).contains(sender.tag) else { return }
        var p = controller.preferences; p.minutes = sender.tag; save(p)
        minutesField?.stringValue = String(p.minutes)
    }
    @objc func toggleSignalFromMenu() {
        let control = NSSwitch(); control.state = controller.preferences.detectSilentStream ? .off : .on
        changeSignal(control)
    }
    @objc func openReleases() { NSWorkspace.shared.open(URL(string: repository + "/releases")!) }
}
