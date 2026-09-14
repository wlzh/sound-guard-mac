import AppKit
import ApplicationServices
import ServiceManagement
import GuardCore

extension AppDelegate {
    func toggle(_ title: String, on: Bool, action: Selector) -> NSSwitch {
        let control = NSSwitch(); control.state = on ? .on : .off; control.target = self; control.action = action
        control.setAccessibilityLabel(title); return control
    }
    @objc func showGeneralSettings() { selectedSettingsPage = 0; showSettings() }
    @objc func showDeviceSettings() { selectedSettingsPage = 1; showSettings() }
    @objc func selectSettingsPage(_ sender: NSSegmentedControl) { selectedSettingsPage = sender.selectedSegment; rebuildSettings() }
    @objc func showSettings() {
        if settings == nil { settings = window("声音守卫设置", width: 580, height: 650) }
        rebuildSettings(); present(settings!)
    }
    func rebuildSettings() {
        guard let window = settings else { return }
        minutesField = nil; recoveryDurationField = nil; recoveryUnitPopup = nil
        deviceButtons.removeAll(); deviceNames.removeAll()
        let root = NativeSurface(frame: window.contentView!.bounds); root.autoresizingMask = [.width, .height]
        let heading = UI.stack([
            UI.image(BrandAssets.icon(size: 48), size: 48),
            UI.stack([UI.label("声音守卫", size: 20, weight: .semibold), UI.label("闲置自动归零，开启由你决定。", size: 12, color: .secondaryLabelColor)], spacing: 4)
        ], vertical: false, spacing: 12)
        let tabs = NSSegmentedControl(labels: ["常规", "设备"], trackingMode: .selectOne, target: self, action: #selector(selectSettingsPage(_:)))
        tabs.selectedSegment = selectedSettingsPage; tabs.segmentStyle = .rounded
        tabs.setWidth(110, forSegment: 0); tabs.setWidth(110, forSegment: 1)
        tabs.setAccessibilityLabel("设置分类")
        let scroll = NSScrollView(); scroll.drawsBackground = false; scroll.hasVerticalScroller = true
        let footer = UI.label("未经你点击确认，声音守卫不会恢复音量。", size: 12, color: .secondaryLabelColor, centered: true)
        settingsFeedback = footer
        for view in [heading, tabs, scroll, footer] { view.translatesAutoresizingMaskIntoConstraints = false; root.addSubview(view) }
        NSLayoutConstraint.activate([
            heading.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 28),
            heading.topAnchor.constraint(equalTo: root.topAnchor, constant: 24),
            heading.trailingAnchor.constraint(lessThanOrEqualTo: root.trailingAnchor, constant: -28),
            tabs.centerXAnchor.constraint(equalTo: root.centerXAnchor), tabs.topAnchor.constraint(equalTo: heading.bottomAnchor, constant: 20),
            scroll.topAnchor.constraint(equalTo: tabs.bottomAnchor, constant: 22),
            scroll.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 28),
            scroll.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -28),
            scroll.bottomAnchor.constraint(equalTo: footer.topAnchor, constant: -18),
            footer.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 28),
            footer.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -28),
            footer.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -22)
        ])
        window.contentView = root; root.layoutSubtreeIfNeeded()
        let page = selectedSettingsPage == 0 ? generalSettingsPage() : deviceSettingsPage()
        let document = SettingsDocument(frame: NSRect(x: 0, y: 0, width: 524, height: scroll.contentSize.height))
        page.translatesAutoresizingMaskIntoConstraints = false; document.addSubview(page)
        NSLayoutConstraint.activate([page.leadingAnchor.constraint(equalTo: document.leadingAnchor), page.topAnchor.constraint(equalTo: document.topAnchor), page.widthAnchor.constraint(equalToConstant: 524)])
        scroll.documentView = document; document.layoutSubtreeIfNeeded()
        document.setFrameSize(NSSize(width: 524, height: max(scroll.contentSize.height, page.fittingSize.height)))
    }
    func generalSettingsPage() -> NSStackView {
        let p = controller.preferences
        let enable = UI.row(title: "自动保护", detail: "输出音量非零时，检测播放是否空闲。", control: toggle("自动保护", on: p.enabled, action: #selector(changeEnabled(_:))))
        let field = NSTextField(string: String(p.minutes)); field.alignment = .center
        field.widthAnchor.constraint(equalToConstant: 48).isActive = true; field.setAccessibilityLabel("空闲分钟数，1 至 120")
        minutesField = field
        let input = UI.stack([field, UI.label("分钟", size: 12), NSButton(title: "应用", target: self, action: #selector(applyMinutes))], vertical: false, spacing: 7)
        let delay = UI.row(title: "空闲时长", detail: "停止播放后等待 1–120 分钟。", control: input)
        let signal = UI.row(title: "静音流也计时", detail: "进一步识别持续输出、但内容全为静音的音频流。", control: toggle("静音流也计时", on: p.detectSilentStream, action: #selector(changeSignal(_:))))
        let recovery = UI.row(title: "播放时提示恢复", detail: "仅在声音守卫自动归零后，发现新的播放活动时提示。", control: toggle("播放时提示恢复", on: p.recoveryPromptEnabled, action: #selector(changeRecoveryPrompt(_:))))
        let useMinutes = p.recoveryPromptSeconds >= 60 && p.recoveryPromptSeconds % 60 == 0
        let recoveryField = NSTextField(string: String(useMinutes ? p.recoveryPromptSeconds / 60 : p.recoveryPromptSeconds))
        recoveryField.alignment = .center; recoveryField.widthAnchor.constraint(equalToConstant: 48).isActive = true
        recoveryField.setAccessibilityLabel("恢复提示倒计时时长")
        let unit = NSPopUpButton(); unit.addItems(withTitles: ["秒", "分钟"]); unit.selectItem(at: useMinutes ? 1 : 0)
        let recoveryInput = UI.stack([recoveryField, unit, NSButton(title: "应用", target: self, action: #selector(applyRecoveryDuration))], vertical: false, spacing: 7)
        recoveryDurationField = recoveryField; recoveryUnitPopup = unit
        let recoveryDelay = UI.row(title: "提示停留", detail: "5 秒至 10 分钟；超时关闭，下次播放仍可提醒。", control: recoveryInput)
        let permissionButton = NSButton(title: "权限设置…", target: self, action: #selector(openAccessibilitySettings))
        permissionButton.isEnabled = p.recoveryPromptEnabled
        let permissionDetail = !p.recoveryPromptEnabled ? "功能关闭时不申请辅助功能权限。" : PlaybackScreenLocator.trusted ? "辅助功能已授权，优先显示在播放 App 所在屏幕。" : "未授权时回退到鼠标所在屏幕，不影响自动归零。"
        let permission = UI.row(title: "定位播放窗口", detail: permissionDetail, control: permissionButton)
        let loginStatus = SMAppService.mainApp.status
        let login = UI.row(title: "登录时启动", detail: loginStatus == .requiresApproval ? "等待系统批准，请检查登录项。" : "登录后在菜单栏提供保护。", control: toggle("登录时启动", on: loginStatus == .enabled || loginStatus == .requiresApproval, action: #selector(changeLogin(_:))))
        return UI.stack([
            UI.section("自动归零"), UI.group([enable, delay]),
            UI.section("进阶检测"), UI.group([signal]),
            UI.label("默认关闭。开启后读取系统音频信号，需要相应权限并增加运行开销。若同时开启恢复提醒，自动归零后会继续分析信号，区分静音流与真正有声；否则归零后停止检测。", size: 12, color: .secondaryLabelColor),
            UI.section("音量恢复提醒"), UI.group([recovery, recoveryDelay, permission]),
            UI.label("此功能默认关闭。开启后，只有由声音守卫自动归零时才保存本次原音量；手动归零不提示。恢复前会再次核对设备和音量。", size: 12, color: .secondaryLabelColor),
            UI.section("启动"), UI.group([login])
        ], spacing: 12)
    }
    @objc func changeRecoveryPrompt(_ sender: NSSwitch) {
        if sender.state == .on {
            let alert = UI.alert(message: "开启播放恢复提醒？", informative: "自动归零后，默认模式保留播放事件监听；若已开启静音流检测，则继续分析信号以避免静音误报。检测到新的播放时显示确认窗口，只有点击恢复按钮才会提高音量。为定位播放 App 所在显示器，下一步会请求辅助功能权限；拒绝后改用鼠标所在显示器，自动归零不受影响。")
            alert.addButton(withTitle: "开启并继续"); alert.addButton(withTitle: "取消")
            guard alert.runModal() == .alertFirstButtonReturn else { sender.state = .off; return }
        }
        var p = controller.preferences; p.recoveryPromptEnabled = sender.state == .on; save(p)
        if sender.state == .on, !PlaybackScreenLocator.trusted { PlaybackScreenLocator.requestPermission() }
        recoveryPresenter.close(); rebuildSettings()
    }
    @objc func applyRecoveryDuration() {
        guard let raw = recoveryDurationField?.stringValue, let amount = Int(raw) else {
            showError("请输入有效的整数时长"); return
        }
        let seconds: Int
        if recoveryUnitPopup?.indexOfSelectedItem == 1 {
            let multiplied = amount.multipliedReportingOverflow(by: 60)
            guard !multiplied.overflow else { showError("请输入 5 秒至 10 分钟"); return }
            seconds = multiplied.partialValue
        } else { seconds = amount }
        guard (5...600).contains(seconds) else { showError("请输入 5 秒至 10 分钟"); return }
        var p = controller.preferences; p.recoveryPromptSeconds = seconds; save(p)
        settingsFeedback?.stringValue = "已保存，恢复提示停留 \(seconds) 秒。"
    }
    @objc func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
    func deviceSettingsPage() -> NSStackView {
        let p = controller.preferences
        let builtIn = UI.row(title: "系统内建扬声器", detail: "默认保护，不包含耳机插孔。", control: toggle("保护系统内建扬声器", on: p.protectBuiltIn, action: #selector(changeBuiltIn(_:))))
        var rows: [NSView] = []; var seen = Set<String>()
        do {
            let devices = try previewDevices ?? audio.devices()
            for device in devices where !device.builtInSpeaker {
                seen.insert(device.selectionID); deviceNames[device.selectionID] = device.name
                let selected = p.selectedDevices[device.selectionID] != nil
                let control = checkbox("", on: selected, action: #selector(changeDevice(_:)))
                control.setAccessibilityLabel("保护 " + device.name)
                control.isEnabled = device.controllable || selected; deviceButtons[control] = device.selectionID
                let detail = !device.controllable ? "不支持软件音量调节" : device.id == displayDevice?.id ? "当前输出设备" : selected ? "已加入保护，切换为当前输出时生效" : "未加入保护"
                rows.append(UI.row(title: device.name, detail: detail, control: control))
            }
            for (key, name) in p.selectedDevices.sorted(by: { $0.value < $1.value }) where !seen.contains(key) {
                deviceNames[key] = name
                let control = checkbox("", on: true, action: #selector(changeDevice(_:)))
                control.setAccessibilityLabel("移除离线设备 " + name); deviceButtons[control] = key
                rows.append(UI.row(title: name, detail: "离线或路由已改变，可取消选择", control: control))
            }
        } catch { rows.append(UI.label("设备列表读取失败：" + error.localizedDescription, size: 12, color: .secondaryLabelColor)) }
        if rows.isEmpty { rows.append(UI.label("暂无其他输出设备。连接耳机或音箱后，刷新列表。", size: 12, color: .secondaryLabelColor)) }
        let refresh = NSButton(title: "刷新设备列表", target: self, action: #selector(refreshSettings))
        let current = displayDevice.map { "当前输出：" + $0.name } ?? "当前没有输出设备"
        return UI.stack([
            UI.label(current, size: 13, weight: .medium),
            UI.label("只保护当前系统默认输出，不切换设备、不修改闲置设备的音量。", size: 12, color: .secondaryLabelColor),
            UI.section("内建输出"), UI.group([builtIn]), UI.section("其他设备"), UI.group(rows), refresh
        ], spacing: 12)
    }
}
